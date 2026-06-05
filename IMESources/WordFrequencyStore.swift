import Foundation

/// Learns the Hangul words the user actually types and answers prefix
/// queries for the prediction feature (안녕 → 하세요).
///
/// Privacy contract (PRIVACY.md):
///   - KOREAN UNITS ONLY: a unit is learned only if every character is a
///     complete Hangul syllable (가-힣) and it is 2–7 syllables long —
///     the length cap keeps spaceless sentences out of the store.
///   - Disk gets words + counts ONLY. lastUsed stays in memory (recency
///     tie-breaks reset per session). Units seen once are never persisted.
///   - Local only: a single JSON file under
///     ~/Library/Application Support/HaneulKeyboard/. No network anywhere.
///   - Erasable: deleteAll() removes the file; Settings exposes it, and the
///     controller wires `onExternalClearRequest` so a pending deletion
///     request is honored before ANY write, not just on activation.
///
/// Threading: all state is main-thread-confined (IME handle() runs on
/// main). File writes are serialized on `saveQueue`; snapshots are taken on
/// main and handed over, so the two never share mutable state.
///
/// Tuning constants live in `Policy` — adjust as 조건식 arrive.
final class WordFrequencyStore {
    struct Policy {
        /// Units shorter/longer than this (in syllables) are not learned.
        /// Upper bound 7: real Korean words rarely exceed it, spaceless
        /// sentences almost always do.
        var learnableLength: ClosedRange<Int> = 2...7
        /// A unit must have been committed this many times before it is
        /// ever suggested (filters typos and one-offs).
        var minCountToSuggest: Int = 3
        /// ...and this many times before it is ever written to disk.
        var minCountToPersist: Int = 2
        /// The typed prefix must be at least this many syllables.
        var minPrefixLength: Int = 1
        /// Entry cap; lowest-scored entries are pruned on overflow.
        var maxEntries: Int = 50_000
        /// Debounce for async saves after a learn event.
        var saveDelaySeconds: TimeInterval = 5
    }

    /// On disk: count only. lastUsed is in-memory recency state — never
    /// persisted (PRIVACY.md discloses words + frequency, nothing else).
    struct Entry: Codable {
        var count: Int
        var lastUsed: Date

        private enum CodingKeys: String, CodingKey { case count }

        init(count: Int, lastUsed: Date) {
            self.count = count
            self.lastUsed = lastUsed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            count = try container.decode(Int.self, forKey: .count)
            lastUsed = .distantPast
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(count, forKey: .count)
        }
    }

    var policy = Policy()

    /// Wired by the controller to the `haneul.clearLearnedData` defaults
    /// flag. Returns true exactly once per pending request (and resets the
    /// flag). Checked before EVERY write so a deletion can never be undone
    /// by an in-flight save.
    var onExternalClearRequest: (() -> Bool)?

    private var entries: [String: Entry] = [:]
    /// Sorted snapshot of keys for binary-search prefix ranges. Updated by
    /// insertion on new words (count bumps don't change key order), fully
    /// rebuilt only after load/prune/deleteAll.
    private var sortedWords: [String] = []
    private var sortedDirty = false
    /// True when something changed since the last persisted snapshot.
    private var persistDirty = false

    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "haneul.wordstore.save", qos: .utility)
    private var savePending = false

    /// Default on-disk location (shared with SettingsView's
    /// "학습 데이터 삭제" and UninstallManager).
    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HaneulKeyboard/word_frequency.json")
    }

    init(fileURL: URL = WordFrequencyStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - Learning

    /// Records one committed unit. Silently ignores anything that is not a
    /// pure Hangul unit of learnable length.
    func learn(_ word: String, now: Date = Date()) {
        guard isLearnable(word) else { return }
        if var entry = entries[word] {
            entry.count += 1
            entry.lastUsed = now
            entries[word] = entry
        } else {
            entries[word] = Entry(count: 1, lastUsed: now)
            insertSorted(word)
        }
        persistDirty = true
        pruneIfNeeded()
        scheduleSave()
    }

    /// Pure Hangul syllables only (가-힣), within learnable length.
    func isLearnable(_ word: String) -> Bool {
        let scalars = word.unicodeScalars
        guard policy.learnableLength.contains(word.count) else { return false }
        return !scalars.isEmpty && scalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }

    // MARK: - Suggesting

    /// Best completion for the typed prefix: highest count wins, recency
    /// breaks ties. Returns the FULL word (caller derives the remainder).
    /// Never returns the prefix itself.
    func suggest(prefix: String) -> String? {
        guard prefix.count >= policy.minPrefixLength else { return nil }
        guard prefix.unicodeScalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) }) else { return nil }

        rebuildSortedIfNeeded()
        var best: (word: String, entry: Entry)?
        for word in wordsWithPrefix(prefix) where word != prefix {
            guard let entry = entries[word], entry.count >= policy.minCountToSuggest else { continue }
            if let current = best {
                if (entry.count, entry.lastUsed.timeIntervalSinceReferenceDate)
                    > (current.entry.count, current.entry.lastUsed.timeIntervalSinceReferenceDate) {
                    best = (word, entry)
                }
            } else {
                best = (word, entry)
            }
        }
        return best?.word
    }

    /// Binary search for the contiguous sorted range sharing the prefix.
    private func wordsWithPrefix(_ prefix: String) -> ArraySlice<String> {
        let start = lowerBound(of: prefix)
        var end = start
        while end < sortedWords.count, sortedWords[end].hasPrefix(prefix) { end += 1 }
        return sortedWords[start..<end]
    }

    private func lowerBound(of word: String) -> Int {
        var lo = 0, hi = sortedWords.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedWords[mid] < word { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func insertSorted(_ word: String) {
        if sortedDirty { return } // full rebuild pending anyway
        sortedWords.insert(word, at: lowerBound(of: word))
    }

    private func rebuildSortedIfNeeded() {
        guard sortedDirty else { return }
        sortedWords = entries.keys.sorted()
        sortedDirty = false
    }

    private func pruneIfNeeded() {
        guard entries.count > policy.maxEntries else { return }
        // Drop the bottom 10% by (count, lastUsed).
        let sorted = entries.sorted {
            ($0.value.count, $0.value.lastUsed.timeIntervalSinceReferenceDate)
                < ($1.value.count, $1.value.lastUsed.timeIntervalSinceReferenceDate)
        }
        for (word, _) in sorted.prefix(entries.count / 10) {
            entries.removeValue(forKey: word)
        }
        sortedDirty = true
    }

    // MARK: - Persistence (serialized, dirty-guarded, atomic)

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            // Never let the next save silently destroy the evidence of a
            // corrupt store — move it aside and start empty.
            let aside = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return
        }
        entries = decoded
        sortedDirty = true
    }

    /// Honors a pending external deletion request. Returns false if one was
    /// consumed — callers must then skip the write they were about to do.
    @discardableResult
    func consumeClearRequestIfAny() -> Bool {
        if onExternalClearRequest?() == true {
            deleteAll()
            return false
        }
        return true
    }

    private func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        saveQueue.asyncAfter(deadline: .now() + policy.saveDelaySeconds) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.savePending = false
                guard self.persistDirty, self.consumeClearRequestIfAny() else { return }
                self.persistDirty = false
                let snapshot = self.entries
                self.saveQueue.async { self.write(snapshot) }
            }
        }
    }

    /// Synchronous save — used on deactivate so data survives IME shutdown.
    /// No-op when nothing changed (deactivate fires on every app switch).
    func saveNow() {
        guard persistDirty, consumeClearRequestIfAny() else { return }
        persistDirty = false
        let snapshot = entries
        // sync onto the serial save queue: ordered after any in-flight
        // debounced write, and completed before the IME can be torn down.
        saveQueue.sync { write(snapshot) }
    }

    private func write(_ snapshot: [String: Entry]) {
        // One-off units never reach disk (PRIVACY.md).
        let persistable = snapshot.filter { $0.value.count >= policy.minCountToPersist }
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        if persistable.isEmpty && !exists { return } // never create an empty footprint

        guard let data = try? JSONEncoder().encode(persistable) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Unique temp per write + rename: atomic promotion, and concurrent
        // writers (if any ever appear) can't tear each other's temp file.
        let tmp = dir.appendingPathComponent(".word_frequency-\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: - Erasure

    func deleteAll() {
        entries = [:]
        sortedWords = []
        sortedDirty = false
        persistDirty = false // suppress any pending debounced write
        try? FileManager.default.removeItem(at: fileURL)
    }

    // Test hooks
    var entryCount: Int { entries.count }
    func count(of word: String) -> Int { entries[word]?.count ?? 0 }
}

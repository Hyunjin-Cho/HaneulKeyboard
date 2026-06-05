import Foundation

/// Abstraction over the IMK client so the composer stays testable without
/// InputMethodKit (HaneulInputController wraps IMKTextInput in an adapter).
protocol ComposerClient {
    /// Insert finalized text at the cursor (replaces any marked text).
    func insertText(_ text: String)
    /// Show composition-in-progress text, cursor pinned at the end.
    /// An empty string clears the marked text.
    func setMarkedText(_ text: String)
}

/// Stateful Hangul word composer driven by 2-set jamo input.
///
/// Completed syllables accumulate into a word-level buffer (shown as marked
/// text) instead of committing eagerly. The whole word commits at a boundary:
/// space/punctuation/digit, modifier shortcut, focus change, or deactivate.
/// At that point, if the composed word is broken as Korean and the raw
/// keystrokes form a known English word (e.g. 메ㅔㅣㄷ ← "apple"), the
/// original keystrokes are committed instead — see EnglishDetector.
final class KoreanComposer {
    /// Gates the English auto-correction at word commit. The word-level
    /// buffering itself is always on.
    var autoEnglishEnabled = true

    /// True when the most recent non-empty commit was English (ASCII
    /// letters). Feeds EnglishDetector's context rule (사용자 조건 2·5:
    /// "I want to ..."에서 새→to). The controller resets it on boundaries
    /// that end the English run (enter/punctuation/focus change).
    private(set) var lastCommitWasEnglish = false

    func resetEnglishContext() {
        lastCommitWasEnglish = false
    }

    private var buffer = SyllableBuffer()
    /// Completed units (syllables or standalone jamo) of the current word,
    /// each paired with the keystrokes that produced it.
    private var word: [(text: String, keys: [Character])] = []
    /// Keystrokes that produced the current in-flight syllable buffer.
    private var pendingKeys: [Character] = []

    /// Safety cap — a run this long without a boundary is not a word. Spill
    /// it as Hangul rather than growing the marked text without bound.
    private let maxWordUnits = 40

    func handleInput(_ input: String, client: ComposerClient) -> Bool {
        guard let scalar = input.unicodeScalars.first else { return false }
        let character = Character(scalar)

        guard let jamo = KeyboardLayout2Set.jamo(for: character) else {
            commit(to: client, convertEnglish: true)
            return false
        }

        switch jamo {
        case .consonant(let c):
            appendConsonant(c)
        case .vowel(let v):
            appendVowel(v)
        }
        pendingKeys.append(character)

        if word.count >= maxWordUnits {
            let hangul = wordText()
            if !hangul.isEmpty { client.insertText(hangul) }
            word = []
            lastCommitWasEnglish = false // spill emits Hangul — breaks English context
        }

        refreshMarkedText(client: client)
        return true
    }

    /// Word boundary: commit the buffered word once. Returns the text that
    /// was actually inserted (callers use it to feed word learning).
    ///
    /// `convertEnglish` is true only for ACTIVE boundaries — a space,
    /// punctuation, digit, or Enter the user actually typed. Passive
    /// boundaries (focus change, mouse click, input-source switch, modifier
    /// shortcuts) must commit exactly the marked text the user saw on
    /// screen, never something different.
    @discardableResult
    func commit(to client: ComposerClient, convertEnglish: Bool = false) -> String {
        stashBuffer()
        defer { word = [] }

        let hangul = wordText()
        guard !hangul.isEmpty else {
            client.setMarkedText("")
            return ""
        }

        let committed: String
        let keys = word.flatMap(\.keys)
        let units = word.map(\.text)
        // Conversion may only fire when EVERY unit carries the keys that
        // produced it — an accepted suggestion's units have empty keys, and
        // converting then would commit text that differs from (and drops
        // part of) the marked text the user saw.
        if convertEnglish, autoEnglishEnabled,
           word.allSatisfy({ !$0.keys.isEmpty }),
           EnglishDetector.shouldConvert(
               units: units,
               keys: keys,
               previousWordWasEnglish: lastCommitWasEnglish
           ) {
            committed = String(keys)
        } else {
            committed = hangul
        }
        // English context for the NEXT word is carried only by words that are
        // English on their own structural evidence (real English words) —
        // never by a clean-Hangul word that converted SOLELY because of
        // context (새→to). Otherwise a single English word would chain-convert
        // a whole run of common Korean monosyllables (해/내/애).
        let isAscii = committed.allSatisfy { $0.isASCII && $0.isLetter }
        lastCommitWasEnglish = isAscii &&
            EnglishDetector.shouldConvert(units: units, keys: keys, previousWordWasEnglish: false)
        client.insertText(committed)
        client.setMarkedText("")
        return committed
    }

    /// Current composition as displayed (word so far + in-flight syllable).
    /// The prediction layer uses this as the prefix to complete.
    func currentPreview() -> String {
        return wordText() + buffer.previewString()
    }

    /// Replaces the in-progress composition with an accepted suggestion (the
    /// FULL word). It stays marked — the user commits it like any other word
    /// (space/enter), so all boundary logic stays uniform.
    ///
    /// Stored per-syllable so backspace peels one syllable at a time, like
    /// any other composed word. The units carry empty keys, which commit()
    /// treats as "never English-convert this word" — even if the user keeps
    /// typing wrong-layout English after accepting.
    func acceptSuggestion(_ fullWord: String, client: ComposerClient) {
        buffer.reset()
        pendingKeys = []
        word = fullWord.map { (String($0), [Character]()) }
        refreshMarkedText(client: client)
    }

    /// Peels one jamo from the in-flight syllable, or one whole unit from the
    /// word buffer. Returns true if the composer absorbed the backspace;
    /// false means everything was empty and the system should perform a
    /// normal delete on the text behind the cursor.
    func deleteBackward(client: ComposerClient) -> Bool {
        if !buffer.isEmpty {
            peelJamo()
            if !pendingKeys.isEmpty { pendingKeys.removeLast() }
            refreshMarkedText(client: client)
            return true
        }

        if !word.isEmpty {
            word.removeLast()
            refreshMarkedText(client: client)
            return true
        }

        return false
    }

    // MARK: - State transitions

    private func appendConsonant(_ c: Consonant) {
        if buffer.medial == nil {
            if buffer.initial != nil {
                stashBuffer()
            }
            buffer.initial = c
            return
        }

        // Bare vowel (no initial) followed by a consonant — e.g. English
        // typed in the wrong layout. Start a new unit; attaching the
        // consonant as a final would silently drop it, since a syllable
        // block can't assemble without an initial.
        if buffer.initial == nil {
            stashBuffer()
            buffer.initial = c
            return
        }

        if buffer.final == nil {
            if c.finalIndex != nil {
                buffer.final = .single(c)
            } else {
                stashBuffer()
                buffer.initial = c
            }
            return
        }

        if case let .single(prev) = buffer.final,
           CompoundFinal.index(first: prev, second: c) != nil {
            buffer.final = .compound(first: prev, second: c)
            return
        }

        stashBuffer()
        buffer.initial = c
    }

    private func appendVowel(_ v: Vowel) {
        if let final = buffer.final {
            // 도깨비불: the final consonant carries into the next syllable.
            // Its key is always the most recent one in pendingKeys.
            let (committedFinal, carry) = splitFinal(final)
            let committed = SyllableBuffer(
                initial: buffer.initial,
                medial: buffer.medial,
                final: committedFinal
            )
            let carryKey = pendingKeys.last
            stash(committed, keys: Array(pendingKeys.dropLast()))
            buffer = SyllableBuffer(initial: carry, medial: v, final: nil)
            pendingKeys = carryKey.map { [$0] } ?? []
            return
        }

        if let existing = buffer.medial {
            if let combined = Vowel.combine(existing, v) {
                buffer.medial = combined
            } else {
                stashBuffer()
                buffer.medial = v
            }
            return
        }

        buffer.medial = v
    }

    private func splitFinal(_ final: SyllableBuffer.Final) -> (commit: SyllableBuffer.Final?, carry: Consonant) {
        switch final {
        case .single(let c):
            return (nil, c)
        case .compound(let first, let second):
            return (.single(first), second)
        }
    }

    /// Inverse of Vowel.combine for compound vowels — returns the base vowel
    /// that the user "started with" before adding the modifier.
    private func decomposeVowel(_ v: Vowel) -> Vowel? {
        switch v {
        case .wa, .wae, .oe: return .o
        case .wo, .we, .wi:  return .u
        case .ui:            return .eu
        default:             return nil
        }
    }

    /// One backspace = one jamo off the in-flight syllable.
    private func peelJamo() {
        if let final = buffer.final {
            switch final {
            case .compound(let first, _):
                buffer.final = .single(first)
            case .single:
                buffer.final = nil
            }
            return
        }

        if let medial = buffer.medial {
            buffer.medial = decomposeVowel(medial)
            return
        }

        if buffer.initial != nil {
            buffer.initial = nil
        }
    }

    // MARK: - Word buffer

    private func stashBuffer() {
        if !buffer.isEmpty {
            stash(buffer, keys: pendingKeys)
        }
        buffer.reset()
        pendingKeys = []
    }

    private func stash(_ syllable: SyllableBuffer, keys: [Character]) {
        let text = syllable.assembled()
        if !text.isEmpty {
            word.append((text, keys))
        }
    }

    private func wordText() -> String {
        return word.map(\.text).joined()
    }

    // MARK: - Output

    private func refreshMarkedText(client: ComposerClient) {
        client.setMarkedText(wordText() + buffer.previewString())
    }
}

// MARK: - Buffer

struct SyllableBuffer {
    enum Final {
        case single(Consonant)
        case compound(first: Consonant, second: Consonant)
    }

    var initial: Consonant?
    var medial: Vowel?
    var final: Final?

    var isEmpty: Bool {
        return initial == nil && medial == nil && final == nil
    }

    mutating func reset() {
        initial = nil
        medial = nil
        final = nil
    }

    func previewString() -> String {
        return assembled()
    }

    func assembled() -> String {
        if let initial, let medial {
            let finalIdx: Int
            switch final {
            case .none:
                finalIdx = 0
            case .single(let c):
                finalIdx = c.finalIndex ?? 0
            case .compound(let a, let b):
                finalIdx = CompoundFinal.index(first: a, second: b) ?? 0
            }
            let code = 0xAC00 + (initial.initialIndex * 21 + medial.medialIndex) * 28 + finalIdx
            if let scalar = UnicodeScalar(code) {
                return String(scalar)
            }
            return ""
        }

        if let initial {
            return String(initial.compatibility)
        }
        if let medial {
            return String(medial.compatibility)
        }
        return ""
    }
}

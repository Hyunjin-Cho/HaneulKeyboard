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

    /// The most recent commit, when it was English (lowercased; nil = the
    /// last commit was Korean or context was reset). Feeds EnglishDetector's
    /// context rules — the WORD itself matters now (whitelistTriggers:
    /// "want"+새→to fires, "github"+새 stays Korean). The controller resets
    /// it on boundaries that end the English run.
    private(set) var lastEnglishWord: String?

    /// 직전에 영어로 변환된 단어 — (변환 전 한글, 변환 후 영어). shift+space로
    /// 방금 변환을 한글로 되돌릴 때 쓴다(㉠ 직후만). 다음 입력(자모/백스페이스)
    /// 이 들어오면 nil로 리셋 = "변환 직후, 다음 글자 치기 전"에만 유효.
    private(set) var lastConversion: (hangul: String, english: String)?

    var lastCommitWasEnglish: Bool { lastEnglishWord != nil }

    func resetEnglishContext() {
        lastEnglishWord = nil
    }

    /// shift+space 되돌리기가 lastConversion을 소비한 뒤 호출 — 재되돌리기 방지.
    func consumeLastConversion() {
        lastConversion = nil
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
        lastConversion = nil // 새 글자 입력 = 되돌리기 기회 끝

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
            lastEnglishWord = nil // spill emits Hangul — breaks English context
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
               previousEnglishWord: lastEnglishWord
           ) {
            committed = String(keys)
        } else {
            committed = hangul
        }
        // English context chains through every CONVERTED word ("that was
        // great" — was must arm great), EXCEPT clean-Hangul whitelist hits
        // (새→to): those exist only because of context and must not start
        // chains of their own (a run of 새/무 homographs would otherwise
        // cascade). Korean commits always break the run.
        let isAscii = !committed.isEmpty && committed.allSatisfy { $0.isASCII && $0.isLetter }
        if isAscii {
            let wordLower = String(keys.compactMap { $0.lowercased().first })
            let cleanHangul = !units.contains { unit in
                unit.unicodeScalars.contains { (0x3131...0x3163).contains($0.value) }
            }
            let whitelistOnly = EnglishDetector.shortWords.contains(wordLower) && cleanHangul
            lastEnglishWord = whitelistOnly ? nil : wordLower
            // 방금 영어로 변환됨 — shift+space 즉시 되돌리기용(㉠ 직후만).
            lastConversion = (hangul: hangul, english: committed)
        } else {
            lastEnglishWord = nil
            lastConversion = nil
        }
        client.insertText(committed)
        client.setMarkedText("")
        return committed
    }

    /// Peels one jamo from the in-flight syllable, or one whole unit from the
    /// word buffer. Returns true if the composer absorbed the backspace;
    /// false means everything was empty and the system should perform a
    /// normal delete on the text behind the cursor.
    func deleteBackward(client: ComposerClient) -> Bool {
        lastConversion = nil // 백스페이스 = 되돌리기 기회 끝
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

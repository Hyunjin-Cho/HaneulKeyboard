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
        }

        refreshMarkedText(client: client)
        return true
    }

    /// Word boundary: commit the buffered word once.
    ///
    /// `convertEnglish` is true only for ACTIVE boundaries — a space,
    /// punctuation, digit, or Enter the user actually typed. Passive
    /// boundaries (focus change, mouse click, input-source switch, modifier
    /// shortcuts) must commit exactly the marked text the user saw on
    /// screen, never something different.
    func commit(to client: ComposerClient, convertEnglish: Bool = false) {
        stashBuffer()
        defer { word = [] }

        let hangul = wordText()
        guard !hangul.isEmpty else {
            client.setMarkedText("")
            return
        }

        let keys = word.flatMap(\.keys)
        if convertEnglish, autoEnglishEnabled,
           EnglishDetector.shouldConvert(units: word.map(\.text), keys: keys) {
            client.insertText(String(keys))
        } else {
            client.insertText(hangul)
        }
        client.setMarkedText("")
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

import Cocoa
import InputMethodKit

/// Stateful Hangul syllable composer driven by 2-set jamo input.
final class KoreanComposer {
    private var buffer = SyllableBuffer()

    func handleInput(_ input: String, client: IMKTextInput) -> Bool {
        guard let scalar = input.unicodeScalars.first else { return false }
        let character = Character(scalar)

        guard let jamo = KeyboardLayout2Set.jamo(for: character) else {
            flushBuffer(to: client)
            return false
        }

        switch jamo {
        case .consonant(let c):
            appendConsonant(c, client: client)
        case .vowel(let v):
            appendVowel(v, client: client)
        }

        updateMarkedText(client: client)
        return true
    }

    func commit(to client: IMKTextInput) {
        flushBuffer(to: client)
    }

    /// Peels one jamo from the in-flight syllable. Returns true if the buffer
    /// absorbed the backspace; false means the buffer was empty and the system
    /// should perform a normal delete on the text behind the cursor.
    func deleteBackward(client: IMKTextInput) -> Bool {
        if buffer.isEmpty { return false }

        if let final = buffer.final {
            switch final {
            case .compound(let first, _):
                buffer.final = .single(first)
            case .single:
                buffer.final = nil
            }
            updateMarkedText(client: client)
            return true
        }

        if let medial = buffer.medial {
            if let decomposed = decomposeVowel(medial) {
                buffer.medial = decomposed
            } else {
                buffer.medial = nil
            }
            if buffer.isEmpty {
                clearMarkedText(client: client)
            } else {
                updateMarkedText(client: client)
            }
            return true
        }

        if buffer.initial != nil {
            buffer.initial = nil
            clearMarkedText(client: client)
            return true
        }

        return false
    }

    // MARK: - State transitions

    private func appendConsonant(_ c: Consonant, client: IMKTextInput) {
        if buffer.medial == nil {
            if buffer.initial != nil {
                flushBuffer(to: client)
            }
            buffer.initial = c
            return
        }

        if buffer.final == nil {
            if c.finalIndex != nil {
                buffer.final = .single(c)
            } else {
                flushBuffer(to: client)
                buffer.initial = c
            }
            return
        }

        if case let .single(prev) = buffer.final,
           CompoundFinal.index(first: prev, second: c) != nil {
            buffer.final = .compound(first: prev, second: c)
            return
        }

        flushBuffer(to: client)
        buffer.initial = c
    }

    private func appendVowel(_ v: Vowel, client: IMKTextInput) {
        if let final = buffer.final {
            let (committedFinal, carry) = splitFinal(final)
            let committed = SyllableBuffer(
                initial: buffer.initial,
                medial: buffer.medial,
                final: committedFinal
            )
            insertAssembled(committed, client: client)
            buffer = SyllableBuffer(initial: carry, medial: v, final: nil)
            return
        }

        if let existing = buffer.medial {
            if let combined = Vowel.combine(existing, v) {
                buffer.medial = combined
            } else {
                flushBuffer(to: client)
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

    // MARK: - Output

    private func updateMarkedText(client: IMKTextInput) {
        let preview = buffer.previewString()
        client.setMarkedText(
            preview as NSString,
            selectionRange: NSRange(location: (preview as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func clearMarkedText(client: IMKTextInput) {
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func flushBuffer(to client: IMKTextInput) {
        if !buffer.isEmpty {
            insertAssembled(buffer, client: client)
            buffer.reset()
        }
        clearMarkedText(client: client)
    }

    private func insertAssembled(_ buffer: SyllableBuffer, client: IMKTextInput) {
        let text = buffer.assembled()
        if !text.isEmpty {
            client.insertText(
                text,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
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

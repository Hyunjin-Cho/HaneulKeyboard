import Foundation

/// Standard Korean 2-set keyboard layout (두벌식 표준 / Standard 2-set).
///
/// Maps a typed character (with Shift baked in) to a jamo identity. Returns
/// nil for keys with no Hangul mapping — those should pass through unchanged.
enum KeyboardLayout2Set {
    enum Jamo {
        case consonant(Consonant)
        case vowel(Vowel)
    }

    /// Look up the jamo by the typed character (used as primary path).
    static func jamo(for character: Character) -> Jamo? {
        return table[character]
    }

    /// Look up the jamo by physical key code (used as fallback when
    /// `charactersIgnoringModifiers` returns nil on macOS 26+).
    ///
    /// The key-code → character mapping assumes the keyboard has been
    /// overridden to ABC (US) layout. Key codes 0–49 are the standard
    /// ANSI letter keys; they map to the same physical positions
    /// regardless of active layout or modifier keys.
    static func characterForKeyCode(_ keyCode: Int, shifted: Bool) -> Character? {
        guard let pair = keyCodeTable[keyCode] else { return nil }
        return shifted ? pair.1 : pair.0
    }

    /// Key-code → (lowercase, uppercase) for standard ABC letter keys.
    private static let keyCodeTable: [Int: (Character, Character)] = [
        0:  ("a", "A"),   11: ("b", "B"),   8:  ("c", "C"),
        2:  ("d", "D"),   14: ("e", "E"),   3:  ("f", "F"),
        5:  ("g", "G"),   4:  ("h", "H"),   34: ("i", "I"),
        38: ("j", "J"),   40: ("k", "K"),   37: ("l", "L"),
        46: ("m", "M"),   45: ("n", "N"),   31: ("o", "O"),
        35: ("p", "P"),   12: ("q", "Q"),   15: ("r", "R"),
        1:  ("s", "S"),   17: ("t", "T"),   32: ("u", "U"),
        9:  ("v", "V"),   13: ("w", "W"),   7:  ("x", "X"),
        16: ("y", "Y"),   6:  ("z", "Z"),
    ]

    private static let table: [Character: Jamo] = [
        // Top row consonants
        "q": .consonant(.bieup),       "Q": .consonant(.ssangBieup),
        "w": .consonant(.jieut),       "W": .consonant(.ssangJieut),
        "e": .consonant(.digeut),      "E": .consonant(.ssangDigeut),
        "r": .consonant(.giyeok),      "R": .consonant(.ssangGiyeok),
        "t": .consonant(.siot),        "T": .consonant(.ssangSiot),

        // Top row vowels — Shift on y/u/i is a no-op in standard 2-set.
        // o/p are special: Shift = compound vowel (ㅐ→ㅒ, ㅔ→ㅖ).
        "y": .vowel(.yo),              "Y": .vowel(.yo),
        "u": .vowel(.yeo),             "U": .vowel(.yeo),
        "i": .vowel(.ya),              "I": .vowel(.ya),
        "o": .vowel(.ae),              "O": .vowel(.yae),
        "p": .vowel(.e),               "P": .vowel(.ye),

        // Home row consonants — Shift on these has no extra geminate (쌍자음) in standard 2-set.
        "a": .consonant(.mieum),       "A": .consonant(.mieum),
        "s": .consonant(.nieun),       "S": .consonant(.nieun),
        "d": .consonant(.ieung),       "D": .consonant(.ieung),
        "f": .consonant(.rieul),       "F": .consonant(.rieul),
        "g": .consonant(.hieut),       "G": .consonant(.hieut),

        // Home row vowels — Shift is a no-op.
        "h": .vowel(.o),               "H": .vowel(.o),
        "j": .vowel(.eo),              "J": .vowel(.eo),
        "k": .vowel(.a),               "K": .vowel(.a),
        "l": .vowel(.i),               "L": .vowel(.i),

        // Bottom row consonants — Shift is a no-op.
        "z": .consonant(.kieuk),       "Z": .consonant(.kieuk),
        "x": .consonant(.tieut),       "X": .consonant(.tieut),
        "c": .consonant(.chieut),      "C": .consonant(.chieut),
        "v": .consonant(.pieup),       "V": .consonant(.pieup),

        // Bottom row vowels — Shift is a no-op.
        "b": .vowel(.yu),              "B": .vowel(.yu),
        "n": .vowel(.u),               "N": .vowel(.u),
        "m": .vowel(.eu),              "M": .vowel(.eu),
    ]
}

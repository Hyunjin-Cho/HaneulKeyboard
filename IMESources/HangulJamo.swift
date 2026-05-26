import Foundation

/// Korean consonants in lookup form. Ordered to match the Hangul Jamo
/// initial-consonant table (U+1100 block — 0=ㄱ ... 18=ㅎ).
enum Consonant: Int, CaseIterable {
    case giyeok = 0       // ㄱ
    case ssangGiyeok      // ㄲ
    case nieun            // ㄴ
    case digeut           // ㄷ
    case ssangDigeut      // ㄸ
    case rieul            // ㄹ
    case mieum            // ㅁ
    case bieup            // ㅂ
    case ssangBieup       // ㅃ
    case siot             // ㅅ
    case ssangSiot        // ㅆ
    case ieung            // ㅇ
    case jieut            // ㅈ
    case ssangJieut       // ㅉ
    case chieut           // ㅊ
    case kieuk            // ㅋ
    case tieut            // ㅌ
    case pieup            // ㅍ
    case hieut            // ㅎ

    /// 0-based index into the initial table (same as rawValue, just clarifying).
    var initialIndex: Int { rawValue }

    /// 1..27 index into the final (jongseong) table, or nil if this consonant
    /// has no final form (ㄸㅃㅉ).
    var finalIndex: Int? {
        switch self {
        case .giyeok:       return 1
        case .ssangGiyeok:  return 2
        case .nieun:        return 4
        case .digeut:       return 7
        case .rieul:        return 8
        case .mieum:        return 16
        case .bieup:        return 17
        case .siot:         return 19
        case .ssangSiot:    return 20
        case .ieung:        return 21
        case .jieut:        return 22
        case .chieut:       return 23
        case .kieuk:        return 24
        case .tieut:        return 25
        case .pieup:        return 26
        case .hieut:        return 27
        case .ssangDigeut, .ssangBieup, .ssangJieut: return nil
        }
    }

    /// Display character from the compatibility-jamo block (U+3131-U+314E).
    var compatibility: Character {
        switch self {
        case .giyeok:       return "ㄱ"
        case .ssangGiyeok:  return "ㄲ"
        case .nieun:        return "ㄴ"
        case .digeut:       return "ㄷ"
        case .ssangDigeut:  return "ㄸ"
        case .rieul:        return "ㄹ"
        case .mieum:        return "ㅁ"
        case .bieup:        return "ㅂ"
        case .ssangBieup:   return "ㅃ"
        case .siot:         return "ㅅ"
        case .ssangSiot:    return "ㅆ"
        case .ieung:        return "ㅇ"
        case .jieut:        return "ㅈ"
        case .ssangJieut:   return "ㅉ"
        case .chieut:       return "ㅊ"
        case .kieuk:        return "ㅋ"
        case .tieut:        return "ㅌ"
        case .pieup:        return "ㅍ"
        case .hieut:        return "ㅎ"
        }
    }
}

/// Korean vowels. Ordered to match the medial-vowel table (0=ㅏ ... 20=ㅣ).
enum Vowel: Int, CaseIterable {
    case a = 0    // ㅏ
    case ae       // ㅐ
    case ya       // ㅑ
    case yae      // ㅒ
    case eo       // ㅓ
    case e        // ㅔ
    case yeo      // ㅕ
    case ye       // ㅖ
    case o        // ㅗ
    case wa       // ㅘ
    case wae      // ㅙ
    case oe       // ㅚ
    case yo       // ㅛ
    case u        // ㅜ
    case wo       // ㅝ
    case we       // ㅞ
    case wi       // ㅟ
    case yu       // ㅠ
    case eu       // ㅡ
    case ui       // ㅢ
    case i        // ㅣ

    var medialIndex: Int { rawValue }

    var compatibility: Character {
        switch self {
        case .a:   return "ㅏ"
        case .ae:  return "ㅐ"
        case .ya:  return "ㅑ"
        case .yae: return "ㅒ"
        case .eo:  return "ㅓ"
        case .e:   return "ㅔ"
        case .yeo: return "ㅕ"
        case .ye:  return "ㅖ"
        case .o:   return "ㅗ"
        case .wa:  return "ㅘ"
        case .wae: return "ㅙ"
        case .oe:  return "ㅚ"
        case .yo:  return "ㅛ"
        case .u:   return "ㅜ"
        case .wo:  return "ㅝ"
        case .we:  return "ㅞ"
        case .wi:  return "ㅟ"
        case .yu:  return "ㅠ"
        case .eu:  return "ㅡ"
        case .ui:  return "ㅢ"
        case .i:   return "ㅣ"
        }
    }

    /// Vowel produced by combining two simple vowels (e.g., ㅗ+ㅏ → ㅘ).
    /// Returns nil if the pair is not a recognized compound.
    static func combine(_ first: Vowel, _ second: Vowel) -> Vowel? {
        switch (first, second) {
        case (.o, .a):    return .wa
        case (.o, .ae):   return .wae
        case (.o, .i):    return .oe
        case (.u, .eo):   return .wo
        case (.u, .e):    return .we
        case (.u, .i):    return .wi
        case (.eu, .i):   return .ui
        default:          return nil
        }
    }
}

/// Compound-final (이중종성 / double-jongseong) lookup: (first, second) → final-table index.
enum CompoundFinal {
    static func index(first: Consonant, second: Consonant) -> Int? {
        switch (first, second) {
        case (.giyeok, .siot):    return 3   // ㄳ
        case (.nieun, .jieut):    return 5   // ㄵ
        case (.nieun, .hieut):    return 6   // ㄶ
        case (.rieul, .giyeok):   return 9   // ㄺ
        case (.rieul, .mieum):    return 10  // ㄻ
        case (.rieul, .bieup):    return 11  // ㄼ
        case (.rieul, .siot):     return 12  // ㄽ
        case (.rieul, .tieut):    return 13  // ㄾ
        case (.rieul, .pieup):    return 14  // ㄿ
        case (.rieul, .hieut):    return 15  // ㅀ
        case (.bieup, .siot):     return 18  // ㅄ
        default:                  return nil
        }
    }
}

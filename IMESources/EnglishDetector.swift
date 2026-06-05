import Foundation

/// Decides, at word-commit time, whether the word typed in Korean mode was
/// actually an English word typed without switching layouts (메ㅔㅣㄷ ← "apple").
///
/// Conservative by design — conversion only fires when ALL of these hold:
///   1. at least 3 keystrokes (2-letter dictionary words like "hi"/"re"
///      collide with everyday jamo slang: ㅗㅑ, ㅐㅏ, ㅂㄱ, ㅢ...),
///   2. the keystrokes are not a single repeated key (ㅋㅋㅋ / ㅠㅠ / zzz),
///   3. at least one key maps to a Korean vowel — jamo initialisms
///      (ㅎㄷㄷ, ㅁㅊㄷ, ㄴㅇㄱ) are consonant-keys-only, while real
///      wrong-layout English essentially always touches a vowel key,
///   4. not a vowel-consonant-vowel palindrome (kaomoji: ㅡㅁㅡ, ㅜㅁㅜ, ㅠㅁㅠ),
///   5. the composed result contains standalone jamo, i.e. it is already
///      broken as Korean (valid Hangul is never touched), and
///   6. the raw keystrokes spell a known English word (exact hit or a light
///      plural/past/-ing inflection of one).
///
/// No data is stored or learned; the wordlist is read-only reference data.
enum EnglishDetector {
    /// Wordlist sources, merged in order. Overridable for tests — must be
    /// set before the first `shouldConvert` call (the set loads lazily once).
    /// `/usr/share/dict/words` ships with macOS but is a 1934 vintage list,
    /// so a bundled supplement covers modern/tech vocabulary.
    static var wordlistPaths: [String] = {
        var paths = ["/usr/share/dict/words"]
        if let bundled = Bundle.main.path(forResource: "english_supplement", ofType: "txt") {
            paths.append(bundled)
        }
        return paths
    }()

    static func shouldConvert(units: [String], keys: [Character]) -> Bool {
        guard keys.count >= 3 else { return false }

        let lowered = keys.compactMap { $0.lowercased().first }
        if Set(lowered).count == 1 { return false }

        guard lowered.contains(where: mapsToVowel) else { return false }

        if lowered.count == 3, lowered[0] == lowered[2],
           mapsToVowel(lowered[0]), !mapsToVowel(lowered[1]) {
            return false
        }

        guard units.contains(where: containsStandaloneJamo) else { return false }

        return matchesEnglishWord(String(lowered))
    }

    /// Call early, off the typing path, so the wordlist is warm before the
    /// first word boundary needs it.
    static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = words }
    }

    private static func mapsToVowel(_ key: Character) -> Bool {
        if case .vowel = KeyboardLayout2Set.jamo(for: key) { return true }
        return false
    }

    /// Compatibility-jamo block (U+3131–U+3163): a scalar here means an
    /// unattached consonant/vowel — impossible inside intended Hangul words.
    private static func containsStandaloneJamo(_ unit: String) -> Bool {
        return unit.unicodeScalars.contains { (0x3131...0x3163).contains($0.value) }
    }

    /// Exact wordlist hit, or a light inflection fallback so that
    /// "apples"/"wanted"/"typing" convert when their stems are known.
    private static func matchesEnglishWord(_ w: String) -> Bool {
        if words.contains(w) { return true }

        var stems: [String] = []
        if w.hasSuffix("ies") { stems.append(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("es") { stems.append(String(w.dropLast(2))) }
        if w.hasSuffix("s") { stems.append(String(w.dropLast(1))) }
        if w.hasSuffix("ed") {
            let stem = String(w.dropLast(2))
            stems.append(stem)            // wanted → want
            stems.append(stem + "e")      // saved → save (hmm: sav+e)
            stems.append(dedoubled(stem)) // stopped → stop
        }
        if w.hasSuffix("ing") {
            let stem = String(w.dropLast(3))
            stems.append(stem)            // reading → read
            stems.append(stem + "e")      // typing → type
            stems.append(dedoubled(stem)) // running → run
        }
        return stems.contains { $0.count >= 3 && words.contains($0) }
    }

    /// stopp → stop, runn → run
    private static func dedoubled(_ s: String) -> String {
        let chars = Array(s)
        guard chars.count >= 2, chars[chars.count - 1] == chars[chars.count - 2] else { return s }
        return String(chars.dropLast())
    }

    private static let words: Set<String> = {
        var set = Set<String>()
        set.reserveCapacity(250_000)
        for path in wordlistPaths {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n") {
                // Skip capitalized entries: web2 proper nouns/abbreviations
                // (Mam, Bab, Td...) would otherwise hijack jamo sequences.
                // Also skips comment lines in the supplement.
                guard let first = line.first, first.isLowercase else { continue }
                let word = line.trimmingCharacters(in: .whitespaces)
                if word.count >= 3, word.allSatisfy({ $0.isASCII && $0.isLetter }) {
                    set.insert(word.lowercased())
                }
            }
        }
        return set
    }()
}

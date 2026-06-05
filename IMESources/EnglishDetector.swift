import Foundation
import CoreFoundation

/// Decides, at word-commit time, whether the word typed in Korean mode was
/// actually an English word typed without switching layouts (메ㅔㅣㄷ ← "apple").
///
/// CORE PRINCIPLE (validated by adversarial review): cleanly composed,
/// real-Korean-shaped Hangul is indistinguishable from genuine Korean by
/// structure alone — 며새(auto) and 모든(ahems) look identical to the code.
/// So clean Hangul may convert ONLY via narrow, low-collision channels:
///   - a CURATED common-English wordlist (R5), never raw /usr/share/dict, or
///   - an explicit English typing context (R2), whitelist-gated.
/// Everything broken-as-Korean (standalone jamo, non-existent syllables) is
/// safe to match against the full dictionary, because the breakage itself
/// proves it was never valid Korean.
///
/// Rules (all behind shared guards — same-key runs ㅋㅋㅋ/ㅠㅠ, V-C-V
/// kaomoji ㅡㅁㅡ):
///   MAIN — standalone jamo + ≥3 keys + vowel key + dict hit (메ㅔㅣㄷ←apple,
///          and broken proper nouns ㅡㅐㄱ무←moran via the bundled list).
///   R1   — starts with a standalone VOWEL (조건 1: 자음보다 모음이 먼저 =
///          한국어 불가, ㅑ→i). shortWords (excl. context-only) or dict.
///   R3   — contains a syllable not in KS X 1001 완성형 (조건 3: 솓←the).
///          EUC-KR encodability = membership; no data file needed.
///   R5   — ≥6 keys AND a CURATED common-English hit (조건 8·11: 퍄녀미←
///          visual, 두샤시드둣←entitlement). Curated list only, so obscure
///          web2 collisions (야구인=dirndls, 힘찬=glacks) never fire.
///   R2   — previous committed word was English (조건 2·5: 새→to, ㅁ→a).
///          The only rule converting clean Hangul on context — whitelist
///          ONLY, since web2 collides with 좀/책/형/곧.
///
/// No data is stored or learned; wordlists are read-only reference data.
enum EnglishDetector {
    /// Wordlist sources, merged in order. Overridable for tests — must be
    /// set before the first lookup (the sets load lazily once).
    /// `/usr/share/dict/words` is the broad list (broken-as-Korean rules);
    /// the rest are CURATED supplements (also the only source for R5).
    static var wordlistPaths: [String] = {
        var paths = ["/usr/share/dict/words"]
        if let bundled = Bundle.main.path(forResource: "english_supplement", ofType: "txt") {
            paths.append(bundled)
        }
        return paths
    }()

    /// The broad dictionary path — entries here are NOT trusted for the
    /// clean-Hangul R5 rule (full of obscure collisions with real Korean).
    static var broadDictPath = "/usr/share/dict/words"

    /// High-frequency English words allowed below the 3-key minimum, via
    /// R1 (vowel-first) and R2 (English context). Hand-curated.
    ///
    /// EXCLUDED on purpose — their 2-set Hangul homographs are ultra-common
    /// standalone Korean words, so auto-converting them after an English
    /// word destroys real Korean more often than it helps:
    ///   go→해, so→내, do→애 (해/내/애 are top-frequency). 새(to)/무(an) are
    /// kept because the user explicitly requested them (조건 2·5).
    static let shortWords: Set<String> = [
        "i", "a", "an", "to", "of", "in", "on", "at", "it", "is", "am",
        "as", "be", "by", "he", "we", "me", "my", "no",
        "up", "us", "or", "if", "ok", "id", "tv", "pc", "md", "ml", "ui",
        "os",
    ]

    /// shortWords whose Hangul forms are everyday jamo slang (ㅢ=ml, ㅐㅏ=ok):
    /// convertible ONLY in English context (R2), never standalone.
    static let contextOnlyShortWords: Set<String> = ["ml", "ok"]

    static func shouldConvert(
        units: [String],
        keys: [Character],
        previousWordWasEnglish: Bool = false
    ) -> Bool {
        guard !keys.isEmpty else { return false }

        let lowered = keys.compactMap { $0.lowercased().first }
        // Emotive runs (ㅋㅋㅋ, ㅠㅠ, zzz) are intentional — never convert.
        // (2+ keys only: a single key stays eligible for R1, ㅑ→i.)
        if lowered.count >= 2, Set(lowered).count == 1 { return false }
        // Kaomoji faces: vowel-consonant-vowel palindrome (ㅡㅁㅡ, ㅜㅁㅜ).
        if lowered.count == 3, lowered[0] == lowered[2],
           mapsToVowel(lowered[0]), !mapsToVowel(lowered[1]) {
            return false
        }

        let word = String(lowered)
        let isContextShortWord = shortWords.contains(word)
        let isShortWord = isContextShortWord && !contextOnlyShortWords.contains(word)
        let isDictWord = lowered.count >= 3 && matchesEnglishWord(word)
        let isCommonWord = lowered.count >= 6 && commonWords.contains(word)

        // MAIN: broken-as-Korean + structural guards + broad dictionary.
        if units.contains(where: containsStandaloneJamo),
           lowered.count >= 3,
           lowered.contains(where: mapsToVowel),
           isDictWord {
            return true
        }

        // R1 — 조건 1: a standalone vowel before any consonant is impossible
        // Korean (ㅑ→i). Broad dict is safe here: vowel-first already
        // excludes real Korean.
        if startsWithStandaloneVowel(units), isShortWord || isDictWord {
            return true
        }

        // R3 — 조건 3: a syllable that doesn't exist in used Korean (솓).
        if units.contains(where: containsImplausibleSyllable), isShortWord || isDictWord {
            return true
        }

        // R5 — 조건 8·11: long, cleanly composed, CURATED common English
        // (visual/entitlement). Curated-only so 야구인/힘찬/소개차 are safe.
        if isCommonWord {
            return true
        }

        // R2 — 조건 2·5: high-frequency word after an English word
        // (새→to). Whitelist ONLY (incl. ml/ok) — broad dict would destroy
        // 좀/책/형/곧 here.
        if previousWordWasEnglish, isContextShortWord {
            return true
        }

        return false
    }

    /// Call early, off the typing path, so wordlists are warm before the
    /// first word boundary needs them.
    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            _ = words
            _ = commonWords
        }
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

    /// First scalar of the first unit is a standalone VOWEL (ㅏ–ㅣ,
    /// U+314F–U+3163): Korean words always start with a consonant.
    private static func startsWithStandaloneVowel(_ units: [String]) -> Bool {
        guard let first = units.first?.unicodeScalars.first else { return false }
        return (0x314F...0x3163).contains(first.value)
    }

    /// Modern Korean slang syllables that live outside KS X 1001 but ARE
    /// intentionally typed — must not be treated as "implausible" by R3.
    private static let knownNonKSXSlang: Set<Character> = ["햏"] // DCInside 아햏햏/햏자

    /// Syllables (가-힣) outside KS X 1001 완성형 (the 2,350 syllables chosen
    /// to cover used Korean) don't occur in real words — 솓, unlike 솥/솟.
    /// EUC-KR encodability IS KS X 1001 membership, so no data file needed.
    private static func containsImplausibleSyllable(_ unit: String) -> Bool {
        return unit.contains { ch in
            guard let scalar = ch.unicodeScalars.first,
                  (0xAC00...0xD7A3).contains(scalar.value) else { return false }
            if knownNonKSXSlang.contains(ch) { return false }
            return !isInKSX1001(ch)
        }
    }

    private static var ksx1001Cache: [Character: Bool] = [:]
    private static let eucKR = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    /// Main-thread confined (detector runs inside the IME's key handling).
    private static func isInKSX1001(_ syllable: Character) -> Bool {
        if let cached = ksx1001Cache[syllable] { return cached }
        let contained = String(syllable).data(using: eucKR) != nil
        ksx1001Cache[syllable] = contained
        return contained
    }

    /// Broad-dictionary hit (web2 + supplements) with a light inflection
    /// fallback. Used only by rules already gated on broken-as-Korean
    /// evidence (MAIN/R1/R3), where false positives are structurally bounded.
    private static func matchesEnglishWord(_ w: String) -> Bool {
        if words.contains(w) { return true }

        var stems: [String] = []
        if w.hasSuffix("ies") { stems.append(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("es") { stems.append(String(w.dropLast(2))) }
        if w.hasSuffix("s") { stems.append(String(w.dropLast(1))) }
        if w.hasSuffix("ed") {
            let stem = String(w.dropLast(2))
            stems.append(stem)            // wanted → want
            stems.append(stem + "e")      // saved → save
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

    /// Broad list: web2 + all supplements. For broken-as-Korean rules only.
    private static let words: Set<String> = loadWords(from: wordlistPaths)

    /// Curated list: supplements ONLY (web2 excluded). The clean-Hangul R5
    /// rule trusts this exclusively — exact match, no inflection — so obscure
    /// web2 entries can never hijack a real Korean word.
    private static let commonWords: Set<String> =
        loadWords(from: wordlistPaths.filter { $0 != broadDictPath })

    private static func loadWords(from paths: [String]) -> Set<String> {
        var set = Set<String>()
        set.reserveCapacity(250_000)
        for path in paths {
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
    }
}

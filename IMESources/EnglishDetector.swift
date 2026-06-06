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
    /// Korean-homograph entries (새=to, 무=an, ㅁ=a, 내=so, 랙=for) are
    /// included but TRIGGER-GATED via koreanHomographShortWords — they fire
    /// only right after whitelistTriggers words (v3.1, 사용자 명시 요청).
    /// go(해)/do(애) remain EXCLUDED: 해/애 are top-frequency standalone
    /// Korean and were not requested.
    static let shortWords: Set<String> = [
        "i", "a", "an", "to", "of", "in", "on", "at", "it", "is", "am",
        "as", "be", "by", "he", "we", "me", "my", "no",
        "up", "us", "or", "if", "ok", "id", "tv", "pc", "md", "ml", "ui",
        "os", "so", "for",
    ]

    /// shortWords whose Hangul forms are everyday jamo slang (ㅢ=ml, ㅐㅏ=ok):
    /// convertible ONLY in English context (R2), never standalone.
    static let contextOnlyShortWords: Set<String> = ["ml", "ok"]

    /// 자음 초성체 슬랭 보호 목록 — 한국어 사전(완성 한글만)에는 없지만
    /// 의도적으로 치는 표현들. 영어 문맥 뒤에서도 절대 변환하지 않는다
    /// (ㅎㄷㄷ가 "gee"로 깨지는 것 방지). 한글 조합 결과 기준.
    /// (ㅢ는 넣지 않는다 — R2 화이트리스트의 ml이 의도된 변환이라 우선.)
    static let protectedSlang: Set<String> = [
        "ㅎㄷㄷ", "ㅁㅊ", "ㅂㅅ", "ㅅㅂ", "ㅇㅈ", "ㄹㅇ", "ㄱㅅ", "ㅈㅅ",
        "ㄷㄷ", "ㅎㄹ", "ㅁㅈ", "ㅇㅇ", "ㄴㄴ", "ㄱㄱ", "ㅂㅂ", "ㅇㅋ",
        "ㄴㅇㄱ", "ㅁㅊㄷ", "ㅇㄱㄹㅇ", "ㅈㄴ", "ㄲㅈ", "ㅊㅋ", "ㅊㅊ",
        "ㅎㅇ", "ㅂㄱ", "ㄷㅊ", "ㄱㄷ", "ㅇㄷ", "ㅁㄴㅇㄹ", "ㅗㅜㅑ", "ㅗㅑ",
    ]

    /// 화이트리스트 중 한글형이 "흔한 실존 한국어"인 항목(새=to, 무=an,
    /// ㅁ=a, 내=so, 랙=for) — 이들은 아무 영어 단어 뒤가 아니라, 영어
    /// 기능어/동사(whitelistTriggers) 직후에만 발동한다. "GitHub 새 기능"
    /// 의 새를 지키면서 "want to"/"thank you so much for"는 살리는 정밀화.
    static let koreanHomographShortWords: Set<String> = ["to", "an", "a", "so", "for"]

    /// 새→to/무→an/내→so/랙→for를 발동시키는 직전 영어 단어들.
    static let whitelistTriggers: Set<String> = [
        "want", "wants", "wanted", "need", "needs", "needed",
        "have", "has", "had", "how", "is", "was", "are", "were",
        "be", "been", "being", "going", "get", "gets", "used",
        "trying", "like", "likes", "liked", "about", "make", "makes",
        "supposed", "ought", "such", "what", "not", "of",
        "you", "thank", "thanks", "much", "very", "too",
        "looking", "waiting", "asking", "time",
    ]

    /// 한글형이 "희귀 한자어 표제어"라 veto에 막히는 고빈도 영어 단어 —
    /// 영어 문맥에서는 영어 의도가 압도적이라 veto를 우회한다.
    /// (when=조두, then=소두, than=소무, also=미내, form=래그, works=재간,
    /// down=애주 — 전부 일상에서 안 쓰는 한자어.)
    /// 의도적 제외(흔한 한국어 우선): did=양, got=햇, god=행, end=둥,
    /// work=재가, rock=개차, for=랙.
    static let contextOverrideEnglish: Set<String> = [
        "when", "then", "than", "also", "form", "works", "down",
    ]

    static func shouldConvert(
        units: [String],
        keys: [Character],
        previousWordWasEnglish: Bool = false,
        previousEnglishWord: String? = nil
    ) -> Bool {
        guard !keys.isEmpty else { return false }
        let prevEnglish = previousWordWasEnglish || previousEnglishWord != nil

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
        let hangul = units.joined()

        // R2-화이트리스트 (조건 2·5, 사용자 명시): veto보다 먼저 평가.
        // 단, 한글형이 흔한 한국어인 항목(새=to/무=an/ㅁ=a)은 트리거
        // 단어(want/need/how...) 직후에만 — "GitHub 새 기능" 보호.
        if prevEnglish, isContextShortWord, !protectedSlang.contains(hangul) {
            if koreanHomographShortWords.contains(word) {
                if let prev = previousEnglishWord, whitelistTriggers.contains(prev) {
                    return true
                }
            } else {
                return true
            }
        }
        // 희귀 한자어와만 충돌하는 고빈도 영어(when/then/than...)도 veto 우회.
        if prevEnglish, contextOverrideEnglish.contains(word) {
            return true
        }

        // ★ 한국어 사전 veto (v3): 조합 결과가 실존 한국어 단어(우리말샘
        // 67.7만)면 어떤 룰로도 변환하지 않는다. 며새(사전에 없음)는
        // 통과해 영어 후보가 되고, 모든/랙/좀/책(있음)은 절대 안전.
        if KoreanDictionary.contains(hangul) {
            return false
        }
        // 초성체 슬랭도 동급 보호 (사전엔 완성 한글만 있어서 별도 목록).
        if protectedSlang.contains(hangul) {
            return false
        }

        // MAIN: broken-as-Korean + structural guards + broad dictionary.
        if units.contains(where: containsStandaloneJamo),
           lowered.count >= 3,
           lowered.contains(where: mapsToVowel),
           isDictWord {
            return true
        }

        // R-자음열 — 사용자 조건 (2026-06-06): standalone 자음만 4개 이상
        // 이고 영어 사전에 있으면 무맥락에서도 영어 (great=ㅎㄱㄷㅁㅅ —
        // 문장 첫 단어라 문맥이 없어도 잡아야 함). 초성체 슬랭은
        // ①protectedSlang(상단 차단) ②사전 게이트(ㅇㄱㄹㅇ=drfd는 영어
        // 단어가 아님)의 이중 방어. 3자(was/are)는 문맥 룰(R2x) 관할.
        if units.count >= 4,
           !lowered.contains(where: mapsToVowel),
           units.allSatisfy({ $0.unicodeScalars.allSatisfy { (0x3131...0x314E).contains($0.value) } }),
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

        // 조건 10(모음 반복)은 별도 룰이 필요 없다: 떠 있는 모음도 "깨진
        // 자모"라 MAIN이 (모음 + 영어 사전 일치)로 잡는다. mini=ㅡㅑㅜㅑ(사전
        // 등재 → MAIN), kpop=ㅏㅔㅐㅔ. 반대로 ㅗㅜㅑ(hni)·ㅜㅡㅜ(nmn)처럼
        // 영어로 말이 안 되는 모음 나열은 사전에 없으니 자동으로 한글로 남는다.
        // (사전 없이 모음 3개를 무조건 변환하면 이런 슬랭/이모티콘이 깨졌음.)

        // R2-확장 (v3, 리뷰로 정밀화) — 영어 문맥에서의 추가 변환.
        // 3중 가드 (활용형/구어가 표제어 사전에 없어 veto를 빠져나가는
        // 것에 대한 구조적 방어 — 해준=gowns, 했=goT, 걍=rid 클래스):
        //   ① Shift 키 포함 금지 — 쌍자음(ㅆㄲㄸㅃㅉ)/ㅒㅖ를 일부러 쳤다는
        //     건 한국어 의도의 구조적 증거 (했=goT, 쟤가=wOrk 전멸)
        //   ② 단음절 한글 금지 — 한 음절이 영어 의도일 가능성은 화이트
        //     리스트가 이미 처리 (걍/믿/닫 보호)
        //   ③ 멀쩡한 한글(깨진 자모 없음)은 curated 사전(exact)만 —
        //     broad web2의 꼬리 단어(gowns/glacks/throck/cork)가 절대
        //     활용형·조사결합형을 건드릴 수 없게.
        //   how [are] you → ㅁㄱㄷ(깨짐, broad OK) → are
        //   the [auto]    → 며새(clean, curated 등재) → auto
        if prevEnglish {
            let hasShiftKey = keys.contains { $0.isUppercase }
            let brokenAsKorean = units.contains(where: containsStandaloneJamo)
                || startsWithStandaloneVowel(units)
                || units.contains(where: containsImplausibleSyllable)
            if !hasShiftKey {
                if brokenAsKorean, isDictWord {
                    return true
                }
                if !brokenAsKorean, units.count >= 2, lowered.count >= 3,
                   commonWords.contains(word) {
                    return true
                }
            }
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

    /// mmap + 바이트 스캔 (KoreanDictionary와 동일 이유 — 임시 버퍼가
    /// malloc 캐시에 상주하는 것 방지). 필터는 기존과 동일: 첫 글자가
    /// ASCII 소문자인 줄만(고유명사/주석 제외), 3자+, ASCII 알파벳만.
    private static func loadWords(from paths: [String]) -> Set<String> {
        var set = Set<String>()
        set.reserveCapacity(250_000)
        let newline = UInt8(ascii: "\n")
        for path in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                let bytes = buf.bindMemory(to: UInt8.self)
                var start = 0
                func consume(_ range: Range<Int>) {
                    guard range.count >= 3 else { return }
                    let first = bytes[range.lowerBound]
                    guard first >= 0x61, first <= 0x7A else { return } // a-z
                    for i in range where !((bytes[i] >= 0x61 && bytes[i] <= 0x7A)
                        || (bytes[i] >= 0x41 && bytes[i] <= 0x5A)) {
                        return // 비알파벳 포함 줄 스킵
                    }
                    let word = String(decoding: bytes[range], as: UTF8.self).lowercased()
                    set.insert(word)
                }
                for i in 0..<bytes.count where bytes[i] == newline {
                    consume(start..<i)
                    start = i + 1
                }
                if start < bytes.count { consume(start..<bytes.count) }
            }
        }
        return set
    }
}

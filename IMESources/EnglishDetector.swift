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
    /// ALL paths together form the BROAD set (broken-as-Korean rules only);
    /// the subset registered in `curatedPaths` additionally feeds the
    /// CURATED set (the only source clean-Hangul rules R5/R2-clean trust).
    /// Bundle files not shipped yet are skipped naturally (path nil).
    static var wordlistPaths: [String] = {
        var paths = ["/usr/share/dict/words"]
        // 번들 사전 5종 — 역할 분담:
        //   english_supplement  : curated + broad (수작업 현대어/기술어)
        //   english_common      : curated + broad (NGSL 고빈도 일상어)
        //   english_modern      : broad 전용 (SCOWL 70/US — web2에 없는 현대어)
        //   english_names       : broad 전용 (Census/SSA 인명)
        //   english_names_extra : broad 전용 (수작업 유명인)
        for name in ["english_supplement", "english_common", "english_modern",
                     "english_names", "english_names_extra"] {
            if let bundled = Bundle.main.path(forResource: name, ofType: "txt") {
                paths.append(bundled)
            }
        }
        return paths
    }()

    /// CURATED 경로 화이트리스트 — fail-safe 교체 (기존 `broadDictPath`
    /// "제외" 방식 → "명시 등록" 방식). clean-Hangul 룰(R5/R2-clean)은
    /// 여기 등록된 파일만 신뢰한다. 새 사전 파일을 추가하며 등록을
    /// 깜빡하면 broad 전용(깨진 한글 룰만, 저위험)으로 떨어진다 — 실수가
    /// 과변환이 아니라 미변환 쪽으로 새는 구조. 인명(english_names*)·현대어
    /// (english_modern)는 의도적 미등록: 롱테일이라 clean 한글 충돌 검증이
    /// 불가능하다 (NGSL 2,786개만 전수 검역을 통과해 curated 자격).
    static var curatedPaths: Set<String> = {
        var set = Set<String>()
        for name in ["english_supplement", "english_common"] {
            if let bundled = Bundle.main.path(forResource: name, ofType: "txt") {
                set.insert(bundled)
            }
        }
        return set
    }()

    /// High-frequency English words allowed below the 3-key minimum, via
    /// R1 (vowel-first) and R2 (English context). Hand-curated.
    ///
    /// Korean-homograph entries (새=to, 무=an, ㅁ=a, 내=so) are included but
    /// TRIGGER-GATED via koreanHomographShortWords — they fire only right
    /// after whitelistTriggers words (v3.1, 사용자 명시 요청). for(랙) was
    /// un-gated 2026-06-19 — it now fires after ANY English word.
    /// go(해)/do(애) remain EXCLUDED: 해/애 are top-frequency standalone
    /// Korean and were not requested.
    ///
    /// ⚠️ 불변식: shortWords/contextOverrideEnglish에 단어 추가 = veto 우회
    /// 채널 확장. 추가 전 그 단어의 한글형이 우리말샘에 등재돼 있는지 반드시
    /// 확인할 것(`scripts/audit_wordlist.sh`로 검증 가능) — 등재어면
    /// koreanHomographShortWords 게이트(트리거 직후만 발동)를 강제해야 한다.
    /// 미등재 한글형(뭉=and)이면 일반 shortWords로 충분하다.
    static let shortWords: Set<String> = [
        "i", "a", "an", "to", "of", "in", "on", "at", "it", "is", "am",
        "as", "be", "by", "he", "we", "me", "my", "no",
        "up", "us", "or", "if", "ok", "id", "tv", "pc", "md", "ml", "ui",
        "os", "so", "for",
        // 모음먼저+자음 약어 (한국어 조합 불가 = 영어 신호): lg=ㅣㅎ, ls=ㅣㄴ,
        // pd=ㅔㅇ. R1(모음 시작) 게이트로 변환 (2026-06-19). 흔한 약어만
        // 명시 — 무조건 패턴은 한국어 충돌 위험이라 보수적으로 목록 관리.
        "lg", "ls", "pd",
        // and(뭉): 우리말샘 미등재 + clean 1음절이라 어떤 구조 룰에도 도달
        // 못 하던 구멍. 무맥락 단독·영어 사이·영어 뒤 모두 변환된다
        // (2026-06-19 standaloneShortWords로 항상 변환 — 아래 정의).
        "and",
    ]

    /// 무맥락 단독에서도 변환하는 1음절 비단어 화이트리스트 (and=뭉).
    /// 한국어에 단독으로 쓰이지 않는 단어라 veto 통과 시 좌우 문맥과
    /// 무관하게 변환한다("salt 뭉 pepper", "jane 뭉 john", 문장 첫 "뭉 ").
    /// R5(멀쩡한 한글 2음절+)가 못 잡는 1음절 구멍을 메운다 — 임의의
    /// 1음절 전체가 아니라 *명시 목록*이라, 걍(rid) 등 1음절 슬랭은
    /// 여기 없으므로 veto 미등재여도 그대로 한글 유지(보호).
    static let standaloneShortWords: Set<String> = ["and"]

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

    /// (2026-06-19) 트리거 게이트 완전 제거 — 새(to)/무(an)/내(so)/ㅁ(a)/
    /// 랙(for)을 포함한 shortWords는 "직전 단어가 영어면 무조건" 변환한다
    /// (사용자 결정). "내 책"·"새 기능"·"무엇"은 앞이 한글이라 prevEnglish=
    /// false로 자동 보호되고, "render 내(나의)"류 영어+한국어 혼용만 드물게
    /// 오변환 → shift+space 되돌리기로 커버. homograph 모호성은 "뒤 단어"를
    /// 모르는 한 원리적으로 완벽 구분 불가이며, 되돌리기가 최종 안전망이다.

    /// 검역 프로브 호환용 — WordlistAudit의 trigger 시나리오가 참조한다.
    /// (게이트가 사라져 변환 판정엔 더 이상 쓰이지 않음.)
    static let whitelistTriggers: Set<String> = [
        "want", "wants", "wanted", "need", "needs", "needed",
        "have", "has", "had", "how", "is", "was", "are", "were",
        "be", "been", "being", "going", "get", "gets", "used",
        "trying", "like", "likes", "liked", "about", "make", "makes",
        "supposed", "ought", "such", "what", "not", "of",
        "you", "thank", "thanks", "much", "very", "too",
        "looking", "waiting", "asking", "time",
    ]

    /// 해(go)/애(do) — 한국어 최빈어(태양·하다·아이)라 무조건 변환은 위험.
    /// go/do가 영어에서 자연스럽게 따라오는 단어(인칭대명사 주어·to·조동사)
    /// 직후에만 변환한다(2026-06-19, 사용자 보수 결정). "I go"·"to go"·"let do"
    /// 는 살리고 "render 해(하다)"·"오늘 해(태양)"는 앞이 트리거가 아니라 보호.
    static let goDoWords: Set<String> = ["go", "do"]
    static let goDoTriggers: Set<String> = [
        "i", "you", "he", "she", "it", "we", "they",
        "to", "let", "will", "would", "can", "could", "should",
        "must", "may", "might", "gonna", "gotta", "don't", "didn't",
        "won't", "can't", "just",
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
        let hangul = units.joined()
        // "한국어로서 깨짐" 구조 판정 — R5(무맥락 clean 게이트)와 R2-확장이 공유.
        let brokenAsKorean = units.contains(where: containsStandaloneJamo)
            || startsWithStandaloneVowel(units)
            || units.contains(where: containsImplausibleSyllable)

        // R2-화이트리스트 (조건 2·5): 직전 단어가 영어면 shortWords를 변환.
        // (2026-06-19) 트리거 게이트 제거 — 새/무/내/ㅁ/랙도 "앞 영어면 무조건".
        // 한국어 용법(내 책/새 기능)은 앞이 한글이라 prevEnglish=false로 보호.
        // protectedSlang(초성체)만 제외하고, veto보다 먼저 평가한다.
        if prevEnglish, isContextShortWord, !protectedSlang.contains(hangul) {
            return true
        }
        // 희귀 한자어와만 충돌하는 고빈도 영어(when/then/than...)도 veto 우회.
        if prevEnglish, contextOverrideEnglish.contains(word) {
            return true
        }
        // 해(go)/애(do) — 트리거(주어·to·조동사) 직후에만 변환(veto 우회).
        // "I 해"→"I go", "to 애"→"to do"; "render 해"·"오늘 해"는 보호.
        if prevEnglish, goDoWords.contains(word),
           let prev = previousEnglishWord, goDoTriggers.contains(prev) {
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

        // 무맥락 단독 화이트리스트 (and=뭉): veto 통과한 1음절 비단어를 좌우
        // 문맥 무관하게 변환. R5(2음절+)가 못 잡는 1음절 구멍 — 명시 목록
        // 이라 걍 등 다른 1음절 슬랭은 건드리지 않는다.
        if standaloneShortWords.contains(word) {
            return true
        }

        // MAIN: broken-as-Korean + structural guards + broad dictionary.
        if units.contains(where: containsStandaloneJamo),
           lowered.count >= 3,
           lowered.contains(where: mapsToVowel),
           isDictWord {
            return true
        }

        // R-자음열 — standalone 자음만 + 영어 사전. 4개+는 broad(great=
        // ㅎㄱㄷㅁㅅ; 자음 4+면 우연 충돌 적어 안전), 3개는 curated만
        // (was/are류 broad 꼬리 차단 — red=ㄱㄷㅇ는 NGSL에 있음. 2026-06-19
        // 사용자 요청으로 3자 확장). ㅋㅋㅋ는 보호막이, 초성체(ㅇㄱㄹ=drf)는
        // protectedSlang + "영어단어 아님" 사전 게이트가 이중 방어.
        if !lowered.contains(where: mapsToVowel),
           units.allSatisfy({ $0.unicodeScalars.allSatisfy { (0x3131...0x314E).contains($0.value) } }) {
            if units.count >= 4, isDictWord { return true }
            if units.count == 3, commonWords.contains(word) { return true }
        }

        // ㅑ 1음절 — 1음절에 ㅑ(중성)가 들어가면 한국어 뜻일 확률 거의 0
        // (먕=aid, 먁=air). veto가 위에서 향/양/약/야/샷 등 진짜 단어를 이미
        // 걸렀으므로(우리말샘 1음절 ㅑ 29개), 미등재 ㅑ 1음절 + 영어 사전이면
        // 변환. 걍(rid)도 변환되나 shift+space 되돌리기로 커버(2026-06-19).
        if units.count == 1, isDictWord, hasMedialYa(units[0]) {
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

        // R5 — cleanly composed Hangul + CURATED common English, 무맥락.
        // (2026-06-19) "6키+" 제한 → "멀쩡한 한글 2음절+"로 완화. veto가 위에서
        // 실존 한국어를 이미 걸렀으므로, 도달한 clean 한글은 한국어가 아니다
        // → curated(supplement+NGSL) exact면 변환 (챠쇼→city, 재깅→world,
        // 퍄녀미→visual). curated-only라 broad 꼬리단어(야구인=dirndls,
        // 힘찬=glacks)는 commonWords에 없어 차단. ★ 2음절 가드 = 1음절 슬랭
        // (걍=rid 등 우리말샘 미등재) 보호 — 검역(2026-06-19): NGSL 62개 무맥락
        // 후보 중 걍이 유일한 진짜 한국어로 확인.
        if !brokenAsKorean, units.count >= 2, commonWords.contains(word) {
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

    /// 음절의 중성이 ㅑ(medial index 2)인지 — ㅑ 1음절 영어 변환 룰용.
    private static func hasMedialYa(_ syllable: String) -> Bool {
        guard let scalar = syllable.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return false }
        return (Int(scalar.value) - 0xAC00) / 28 % 21 == 2
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

    /// Curated list: curatedPaths-registered files ONLY (web2와 인명 파일
    /// 제외). The clean-Hangul R5 rule trusts this exclusively — exact
    /// match, no inflection — so obscure broad entries can never hijack a
    /// real Korean word.
    private static let commonWords: Set<String> =
        loadWords(from: wordlistPaths.filter { curatedPaths.contains($0) })

    /// mmap + 바이트 스캔 (KoreanDictionary와 동일 이유 — 임시 버퍼가
    /// malloc 캐시에 상주하는 것 방지). 필터는 기존과 동일: 첫 글자가
    /// ASCII 소문자인 줄만(고유명사/주석 제외), 3자+, ASCII 알파벳만.
    private static func loadWords(from paths: [String]) -> Set<String> {
        var set = Set<String>()
        set.reserveCapacity(320_000) // web2 소문자 ~21만 + 번들 5종 ~10.3만 = ~31.3만 (리해시 0회)
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

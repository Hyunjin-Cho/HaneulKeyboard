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
///          한국어 불가, ㅑ→i). shortWords or dict.
///   R3   — contains a syllable not in KS X 1001 완성형 (조건 3: 솓←the).
///          EUC-KR encodability = membership; no data file needed.
///   R5   — ≥2 Hangul syllables AND a CURATED common-English hit (조건 8·11: 퍄녀미←
///          visual, 두샤시드둣←entitlement). Curated list only, so obscure
///          web2 collisions (야구인=dirndls, 힘찬=glacks) never fire.
///   R2   — previous committed word was English (조건 2·5: 새→to, ㅁ→a).
///          The only rule converting clean Hangul on context — whitelist
///          ONLY, since web2 collides with 좀/책/형/곧.
///
/// No data is stored or learned; wordlists are read-only reference data.
enum EnglishDetector {
    // 전체 입력 규칙과 초기 조건의 현재 반영 상태: docs/input-conversion-rules.md.
    /// 2026-11-07 (#175) 오너 결정: broad를 Set에 펼치지 않는다. 해시 표만 8.6MB로 입력기 메모리의 3/4을 차지했다.
    /// 원인은 파일 위치가 아니라 전부 펼치는 방식이라, 시스템 web2는 그 자리에서 매핑해 찾고(`SystemWordFile`)
    /// 번들 사전 6종은 정렬 표 하나로 합쳐 찾는다(`SortedWordTable`). 저장소와 앱에 web2 낱말은 들어가지 않는다.
    /// Overridable for tests — must be set before the first lookup (loads lazily once).
    nonisolated(unsafe) static var bundledTablePath: String? =
        Bundle.main.path(forResource: "english_bundled", ofType: "txt")

    /// 시스템 낱말 파일. 없으면 web2 없이 돈다. Overridable for tests.
    nonisolated(unsafe) static var systemWordsPath: String? = "/usr/share/dict/words"

    /// Set으로 읽는 파일들. Overridable for tests — must be set before the first lookup.
    /// `curatedPaths`에 등록된 파일은 CURATED set(clean-Hangul 룰 R5/R2-clean이 믿는 유일한 출처)이 되고,
    /// 나머지는 broad에 더해진다. 배포본에는 curated 둘뿐이다. 나머지는 테스트 픽스처와 검역 후보를 얹는 통로다.
    /// 번들 사전 6종 — 역할 분담:
    ///   english_supplement  : curated + broad (수작업 현대어/기술어)
    ///   english_common      : curated + broad (NGSL 고빈도 일상어)
    ///   english_modern      : broad 전용 (SCOWL 70/US — web2에 없는 현대어)
    ///   english_names       : broad 전용 (Census/SSA 인명)
    ///   english_names_extra : broad 전용 (수작업 이름·생명체·제품·기술 보충어)
    ///   english_sports_geo  : broad 전용 (북미·유럽 지명 + 9리그 축구 클럽·
    ///                         선수 + 약어. GeoNames CC-BY + Wikidata CC0.
    ///                         검역 Tier A/B=0 → clean 충돌 없음, broad 전용)
    ///
    /// (review-0712 P3-5) 이 목록의 **정본은 `dict_work/dict_manifest.tsv`**다.
    /// 2026-11-07 (#175)부터 런타임은 표(`english_bundled.txt`)와 curated 둘만 번들에서 읽고, 이 이름 목록은 테스트가 manifest와 대조하는 데 쓴다.
    /// manifest와 어긋나면 `scripts/run_ime_tests.sh`가 실패한다. 사전을
    /// 추가·제거할 땐 manifest를 먼저 고치고 scripts/build_english_table.py를 돌릴 것.
    static let bundledWordlistNames = [
        "english_supplement", "english_common", "english_modern",
        "english_names", "english_names_extra", "english_sports_geo",
    ]

    /// 위 중 curated 역할(= clean-Hangul 룰이 신뢰하는) 사전 이름.
    static let curatedWordlistNames = ["english_supplement", "english_common"]

    nonisolated(unsafe) static var wordlistPaths: [String] =
        curatedWordlistNames.compactMap { Bundle.main.path(forResource: $0, ofType: "txt") }

    /// CURATED 경로 화이트리스트 — fail-safe 교체 (기존 `broadDictPath`
    /// "제외" 방식 → "명시 등록" 방식). clean-Hangul 룰(R5/R2-clean)은
    /// 여기 등록된 파일만 신뢰한다. 새 사전 파일을 추가하며 등록을
    /// 깜빡하면 broad 전용(깨진 한글 룰만, 저위험)으로 떨어진다 — 실수가
    /// 과변환이 아니라 미변환 쪽으로 새는 구조. 인명(english_names*)·현대어
    /// (english_modern)는 의도적 미등록: 롱테일이라 clean 한글 충돌 검증이
    /// 불가능하다 (NGSL 2,786개만 전수 검역을 통과해 curated 자격).
    nonisolated(unsafe) static var curatedPaths: Set<String> = {
        var set = Set<String>()
        for name in curatedWordlistNames {
            if let bundled = Bundle.main.path(forResource: name, ofType: "txt") {
                set.insert(bundled)
            }
        }
        return set
    }()

    /// High-frequency English words allowed below the 3-key minimum, via
    /// R1 (vowel-first) and R2 (English context). Hand-curated.
    ///
    /// (2026-06-19) homograph(새=to, 무=an, ㅁ=a, 내=so, 랙=for)의 트리거
    /// 게이트는 전부 제거됨 — 직전 단어가 영어면 무조건 변환(R2-화이트리스트).
    /// 한국어 용법(내 책/새 기능)은 앞이 한글이라 prevEnglish=false로 보호되고,
    /// 오변환은 shift+space 되돌리기가 최종 안전망. (해=go/애=do만 최빈어라
    /// goDoTriggers로 별도 보수 처리.)
    /// go(해)/do(애) remain EXCLUDED: 해/애 are top-frequency standalone
    /// Korean and were not requested.
    ///
    /// ⚠️ 불변식: veto보다 위에서 평가되는 목록에 단어를 추가하는 것은 전부
    /// "veto 우회 채널 확장"이다 — shortWords · standaloneShortWords ·
    /// consonantPairShortWords · S/C/T 등급 3종(standaloneOverrideEnglish /
    /// contextOverrideEnglish / triggerOverrideEnglish). 추가 전 그 단어의
    /// 한글형이 우리말샘에 등재돼 있는지, 실제로 한국어로 치는 말인지 확인할 것
    /// (`scripts/audit_wordlist.sh`). 흔한 한국어일수록 오변환이 잦아
    /// shift+space 되돌리기 의존도가 커지니 신중히. (2026-09-19 #33 갱신)
    static let shortWords: Set<String> = [
        "i", "a", "an", "to", "of", "in", "on", "at", "it", "is", "am",
        "as", "be", "by", "he", "we", "me", "my", "no",
        "up", "us", "or", "if", "ok", "id", "tv", "pc", "md", "ml", "ui",
        "os", "so", "for",
        // 모음먼저+자음 약어 (한국어 조합 불가 = 영어 신호): lg=ㅣㅎ, ls=ㅣㄴ,
        // pd=ㅔㅇ. R1(모음 시작) 게이트로 변환 (2026-06-19). 흔한 약어만
        // 명시 — 무조건 패턴은 한국어 충돌 위험이라 보수적으로 목록 관리.
        "lg", "ls", "pd",
        // 2026-09-23 (#70) pr=ㅔㄱ 추가 — 오너 지정(풀 리퀘스트·홍보). pd와 같은 R1 경로이고,
        // 2글자라 사전 파일로는 못 넣는다(isDictWord는 3글자 이상만 본다).
        "pr",
        // 2026-11-01 (#109) 수학 약어 — 오너 지정(A안). 모두 모음으로 시작하는 2글자라
        // pd·pr과 같은 R1 경로다: ln=ㅣㅜ, pi=ㅔㅑ, mu=ㅡㅕ, nu=ㅜㅕ. 우리말샘 미등재·
        // 초성체 슬랭 목록에 없음을 검역으로 확인했다(dict_work/2026-11-01-dict106-*).
        "ln", "pi", "mu", "nu",
        // 2026-11-07 (#194) pm(ㅔㅡ): 오후. 그 전에는 단위(피코미터) 경로로 소문자 pm만 바뀌어 PM·Pm(ㅖㅡ)이 그대로 남았다.
        "pm",
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
    static let standaloneShortWords: Set<String> = [
        "and",
        // 약어(컴퓨터·스포츠) — "전부-자모"(ㄷㄴㅊ=esc, ㅕㄹㅊ=ufc, ㅔㄴㅎ=psg)나
        // 짧은 형태라 사전·일반 규칙으로는 안 잡힌다. 무맥락 화이트리스트로 직접
        // 변환(2026-06-20). veto(위) 후 평가라 — 한글형이 자모거나 우리말샘
        // 미등재면 통과해 변환된다.
        "esc", "ctrl", "alt", "var", "ufc", "psg", "mcp", "ime",
        // gpt(헷): 1음절 clean·veto 통과라 R5(2음절+ 가드)가 못 잡던 구멍.
        // 무맥락 단독으로도 변환 (대문자 "Gpt"는 firstConsonantShift도 커버).
        "gpt",
        // who(좨): gpt와 같은 구멍 — veto 미등재인데 R5의 "2음절+" 가드에 걸려
        // 어떤 경로로도 안 잡혔다 (#33, 2026-09-19). 좨는 한국어에서 단독으로
        // 쓰이지 않으므로 앞뒤가 한글이든 영어든 문맥과 무관하게 변환한다 —
        // 한글 문장 한가운데 "좨"를 칠 이유가 없다는 게 근거다.
        "who",
        // 2026-09-23 (#70) dmg(읗): 오너 지정 — macOS 디스크 이미지. gpt=헷과 같은 구멍
        // (clean 1음절·우리말샘 미등재 → R5 "2음절+" 가드에 막혀 사전만으로는 미도달).
        // 읗은 히읗(ㅎ의 이름) 안에서만 쓰이고 단독으로 칠 일이 없다 — 판정은 단어 단위라
        // 히읗은 그대로 한글이다. d·m·g는 Shift가 자모를 안 바꾸는 키라 DMG도 같은 경로.
        "dmg",
        // 2026-11-01 (#109) 수학 약어 — 오너 지정(A안). gpt=헷·dmg=읗과 같은 구멍
        // (멀쩡한 1음절·우리말샘 미등재 → R5 "2음절+" 가드에 막혀 사전만으로는 미도달).
        // abs=뮨, xi=탸. veto 뒤에서 평가하므로 실존 한국어(cot=챗 등)는 넣지 않았다.
        // 자음 3개 초성형(gcd·det·arg·std·csc)은 초성체와 겹칠 수 있어 오너가 제외했다.
        // 2026-11-07 (#174) 오너 결정: cos=챈을 뺐다. 채다의 활용형이라 "눈치 챈 사람"이 "눈치 cos 사람"으로 깨졌다.
        // 영어 문맥(contextOverrideEnglish)과 개인 사전으로는 계속 쓴다.
        "abs", "xi",
        // 2026-11-07 (#194) am(므): 오너 지정 — 오전. 2글자에서 멀쩡한 한글이 되는 꼴(so=내)은 원칙상 안 넣지만 오너가 정한 예외다.
        // 므는 우리말샘 미등재이고 므다도 없다. veto 뒤에서 평가하고, 표제어 므로·므흣은 단어 전체 판정이 먼저 지킨다.
        "am",
    ]

    /// 자음으로 시작하는 **2글자** 영단어 — 무맥락 단독 변환 화이트리스트
    /// (#33, 2026-09-19). we=ㅈㄷ·at=ㅁㅅ·as=ㅁㄴ는 모음 키가 하나도 없어
    /// R1(모음 시작)·R3(비KSX 음절) 어느 구조 룰에도 닿지 않고, 사전 로더가
    /// 2글자 줄을 버리므로(loadWords의 `range.count >= 3`) 사전으로도 넣을 수
    /// 없다 — 코드 목록이 유일한 통로다. 평가 위치는 R-자음열 분기 안이라
    /// veto·protectedSlang(ㅇㅇ/ㄴㄴ/ㄱㄱ/ㅂㅂ)을 이미 통과한 뒤다.
    /// a=ㅁ는 넣지 않는다 — 낱자 ㅁ는 오타·초성체와 구분이 불가능해 문맥 전용
    /// (shortWords)으로 남긴다.
    /// 2026-09-20 (#39) ev=ㄷㅍ 추가: 전기차(EV)는 오너 지정 단어이고 ㄷㅍ는
    /// protectedSlang에 없다. 나머지 2글자 후보 53개(gs·vc·fx·cs·cd …)는 we/at/as
    /// 정책과 묶어 오너 결정 대기 — 목록은 #39 검토 기록에.
    static let consonantPairShortWords: Set<String> = ["we", "at", "as", "ev"]

    // 2026-11-07 오너 결정(#194): contextOnlyShortWords를 없앴다. 마지막으로 남았던 ok(ㅐㅏ)를 단독으로도 바꾼다.
    // 그 전에는 "ㅐㅏ는 흔한 자모 슬랭"이라고 적어 막았지만 오너가 "이런 건 쓰지 않는다"고 정정했다.
    // 2026-11-01 (#106)에 뺀 ml(ㅢ)과 같은 R1(모음 시작) 경로다. 반복 키 이모티콘 mm(ㅡㅡ)·cc(ㅊㅊ)는 공통 가드가 계속 막는다.

    /// 자음 초성체 슬랭 보호 목록 — 한국어 사전(완성 한글만)에는 없지만
    /// 의도적으로 치는 표현들. 영어 문맥 뒤에서도 절대 변환하지 않는다
    /// (ㅎㄷㄷ가 "gee"로 깨지는 것 방지). 한글 조합 결과 기준.
    /// (ㅢ는 넣지 않는다 — ml이 의도된 변환이다. 2026-11-01 #106부터 단독으로도 변환.)
    static let protectedSlang: Set<String> = [
        "ㅎㄷㄷ", "ㅁㅊ", "ㅂㅅ", "ㅅㅂ", "ㅇㅈ", "ㄹㅇ", "ㄱㅅ", "ㅈㅅ",
        "ㄷㄷ", "ㅎㄹ", "ㅁㅈ", "ㅇㅇ", "ㄴㄴ", "ㄱㄱ", "ㅂㅂ", "ㅇㅋ",
        "ㄴㅇㄱ", "ㅁㅊㄷ", "ㅇㄱㄹㅇ", "ㅈㄴ", "ㄲㅈ", "ㅊㅋ", "ㅊㅊ",
        "ㅎㅇ", "ㅂㄱ", "ㄷㅊ", "ㄱㄷ", "ㅇㄷ", "ㅁㄴㅇㄹ", "ㅗㅜㅑ", "ㅗㅑ",
        // 2026-11-07 (#174) 오너 결정: 초성체 ㄱㄱㅅ(rrt)·ㄴㄱ(sr)과 자음 얼굴 ㅇㅁㅇ(dad)·ㅁㅇㅁ(ada)·ㅈㅁㅈㅁ(wawa)·ㅁㅇㅁㅇ(adad).
        // Title·ALLCAPS(Dad·DAD)는 첫 자음 Shift 경로가 veto보다 먼저 받으므로 그대로 변환된다.
        "ㄱㄱㅅ", "ㄴㄱ", "ㅇㅁㅇ", "ㅁㅇㅁ", "ㅈㅁㅈㅁ", "ㅁㅇㅁㅇ",
    ]

    /// 2026-11-07 (#174) 오너 결정(리뷰 B안): 무맥락에서 이 1음절 뒤에 ㅠㅜㅡ만 이어지면 변환하지 않는다.
    /// "어떻게 해ㅠ"가 "어떻게 gob", "네ㅜ"가 "spn"이 되는 사고가 채팅에서 흔한 꼴이었다.
    /// 깨진 한글이라도 이 꼴은 우는 표정이 붙은 한국어다. 앞말을 고빈도 음절로 좁혀 잃는 영어를 줄였고,
    /// 영어 문맥(the son, I won)은 그대로 변환한다.
    static let sadTailHeads: Set<String> = [
        "해", "개", "걔", "내", "네", "애", "얘", "새", "재", "쟤", "야", "여", "아",
        "어", "오", "우", "으", "이", "그", "저", "나", "너", "뭐", "왜", "예", "응",
    ]

    /// 2026-11-07 오너 결정(리뷰 F-1의 개별 검토): curated 약어 wlb·rnb·thb·epb의 한글형. 무맥락에서만 막는다.
    /// 음절 단위로 넓히지 않고 오너가 정한 네 꼴만 적는다. 그날 broad에 같은 음절 + ㅠㅜㅡ 꼴의 다른 낱말은 없었다.
    static let sadTailExactForms: Set<String> = ["지ㅠ", "구ㅠ", "소ㅠ", "데ㅠ"]

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

    // ═══ veto 우회 정책 등급 S/C/T (#33, 2026-09-19) ════════════════════
    // 아래 ★한국어 veto는 "멀쩡한 한글은 영어로 바꾸지 않는다"는 최후 방어선
    // 이지만, 한글형이 **아무도 안 쓰는 표제어**라는 이유만으로 고빈도 영어가
    // 통째로 막히는 부작용이 있었다. 실측(2026-09-19): curated 2,999개 중 13개가
    // veto와 충돌하고, 그중 6개(work=재가, end=둥, god=행, rock=개차, goal=해미,
    // fps=렌)는 **어떤 경로로도 변환 불가**였다.
    //
    // 기준은 하나 — "그 한글형을 한국어로 실제 얼마나 치는가". 그 빈도에 따라
    // veto 우회 강도를 셋으로 나눈다. 세 등급 모두 veto보다 **위**에서 평가한다.
    //   S(단독)   거의 안 쓰는 한글형 → 문맥 없이 변환
    //   C(문맥)   드물지만 0은 아님   → 직전 단어가 영어일 때만
    //   T(트리거) 흔한 한국어         → "영어가 확실한" 특정 단어 뒤에서만
    //
    // T 등급을 따로 둔 이유: god=행·did=양은 한국어에서 흔해서(3행 4열, 데이터
    // 양) C로 풀면 "render 양이 → render did이" 같은 영한 혼용 사고가 난다.
    // 앞 단어까지 보고 나서야 "이건 영어다"라고 단정할 수 있다.

    /// S(단독) — 한글형이 사실상 안 쓰이는 희귀어. 문맥과 무관하게 변환한다.
    /// work=재가(재가를 받다·재가 요양 — 격식 한자어), rock=개차, goal=해미,
    /// fps=렌: 전부 일상 타이핑에서 나올 일이 없는 말이다.
    /// 가드 2개 —
    ///   ① 키에 Shift가 없을 것: 쌍자음/ㅒㅖ를 일부러 쳤다는 건 한국어 의도의
    ///     구조적 증거다(wOrk=쟤가 보호). 대문자로 친 Work/WORK는 한글형이
    ///     째가/쨰까라 veto에 걸리지도 않아 R5가 알아서 잡는다.
    ///   ② 2음절 이상 또는 키 3개 이상: fps=렌처럼 1음절이어도 키 3개면 허용.
    ///     2키 이하 1음절을 S로 올리면 오타·초성체와 구분이 불가능해진다.
    /// 2026-09-20 (#39) ros=갠 추가: 1음절 clean·우리말샘 미등재라 veto는 통과하지만
    /// R5의 "2음절+" 가드에 막혀 사전만으로는 어떤 경로로도 안 잡히던 구멍(and·gpt·who와
    /// 같은 부류). standaloneShortWords가 아니라 여기인 이유 — 그 목록은 소문자화된
    /// word만 보고 Shift 가드가 없어 rOs=걘(걔는)까지 ros로 깨졌다(2026-11-07 #174부터 그 목록도
    /// 혼합 Shift를 막는다). S 등급은 QWERTOP Shift 가드로 걘을 지키고, 키 3개라 가드 ②도 통과한다. 남는 위험은 "비 갠 뒤"의
    /// 갠(개다 활용형) — work=재가와 같은 판단으로 Shift+Space 되돌리기에 맡긴다.
    /// 같은 부류(1음절 clean 미도달)가 #39 검역에 26개 더 있었지만(eps=덴·apt=멧·
    /// tbd=슝 …) 오너 지정인 ros만 올렸다 — 나머지는 오너 결정 대기.
    static let standaloneOverrideEnglish: Set<String> = [
        "work", "rock", "goal", "fps",
        "ros",
    ]

    /// C(문맥) — 한글형이 희귀 한자어이거나 혼자서는 잘 안 쓰는 말.
    /// 직전 단어가 영어일 때만 veto를 우회한다.
    /// (when=조두, then=소두, than=소무, also=미내, form=래그, works=재간,
    /// down=애주 — 전부 일상에서 안 쓰는 한자어.)
    /// 2026-09-19 (#33) 추가: got=햇(햇감자처럼 접두사로 붙어 단독 커밋이 드묾),
    /// end=둥(하는 둥 마는 둥 — 의존명사라 앞말 없이 혼자 오지 않는다).
    /// 2026-11-07 (#174) 오너 결정: cos=챈을 단독 목록에서 여기로 옮겼다. 앞이 영어일 때만 변환한다.
    static let contextOverrideEnglish: Set<String> = [
        "when", "then", "than", "also", "form", "works", "down",
        "got", "end", "cos",
    ]

    /// T(트리거) — 한글형이 흔한 한국어라 "직전 영어 단어가 이것일 때만" 영어로
    /// 본다. go(해)/do(애)가 원래 이 방식이었고(2026-06-19), #33에서 표로
    /// 일반화하며 god(행)·did(양)를 같은 구조로 흡수했다.
    ///   god=행 : 3행 4열·행 번호로 흔하다 → 감탄사 관용구(my/oh/thank…) 뒤에서만
    ///   did=양 : 데이터 양·양이 많다로 흔하다 → 의문사·주어·조동사 뒤에서만
    /// "render 행"·"render 양"처럼 트리거가 아닌 영어 뒤에서는 그대로 보호된다.
    static let triggerOverrideEnglish: [String: Set<String>] = [
        "go": goDoTriggers,
        "do": goDoTriggers,
        "god": ["my", "oh", "thank", "good", "dear"],
        "did": [
            "i", "you", "he", "she", "it", "we", "they", "who", "never",
            "have", "has", "had", "what", "why", "how", "where", "when", "that",
        ],
    ]

    /// 해(go)/애(do) — 한국어 최빈어(태양·하다·아이)라 무조건 변환은 위험.
    /// go/do가 영어에서 자연스럽게 따라오는 단어(인칭대명사 주어·to·조동사)
    /// 직후에만 변환한다(2026-06-19, 사용자 보수 결정). "I go"·"to go"·"let do"
    /// 는 살리고 "render 해(하다)"·"오늘 해(태양)"는 앞이 트리거가 아니라 보호.
    /// (2026-09-19 #33: 판정은 위 triggerOverrideEnglish 표로 옮겼다. 이 집합
    /// 자체는 KoreanComposer의 whitelistOnly 예외가 직접 참조하므로 — "want to
    /// go"의 to가 다음 단어에 문맥을 넘기는 규칙 — 이름 그대로 유지한다.)
    static let goDoTriggers: Set<String> = [
        "i", "you", "he", "she", "it", "we", "they",
        "to", "let", "will", "would", "can", "could", "should",
        "must", "may", "might", "gonna", "gotta", "don't", "didn't",
        "won't", "can't", "just",
    ]

    static func shouldConvert(
        units: [String],
        keys: [Character],
        previousEnglishWord: String? = nil,
        dictionaryCompoundsEnabled: Bool = false,
        blockedCompoundWords: Set<String> = []
    ) -> Bool {
        guard !keys.isEmpty else { return false }
        // (H-10) 한국어 veto 사전이 로드 안 됐으면 자동변환을 끈다(fail-closed)
        // — 사전이 비면 모든 한글이 veto를 통과해 영어로 오변환될 수 있다.
        guard KoreanDictionary.isLoaded else { return false }
        let prevEnglish = previousEnglishWord != nil

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
        let isShortWord = shortWords.contains(word)
        let isDictWord = lowered.count >= 3 && matchesEnglishWord(word)
        let hangul = units.joined()
        // "한국어로서 깨짐" 구조 판정 — R5(무맥락 clean 게이트)와 R2-확장이 공유.
        let brokenAsKorean = units.contains(where: containsStandaloneJamo)
            || startsWithStandaloneVowel(units)
            || units.contains(where: containsImplausibleSyllable)
        // 두벌식에서 다른 자모를 내는 Shift만 한국어 입력 의도로 센다.
        // R2도 이 가드를 공유해야 sO(냬)를 소문자 so(내)와 혼동하지 않는다.
        let hasShiftKey = keys.contains { $0.isUppercase && "QWERTOP".contains($0) }
        // 2026-10-06 (#75): wOrk(쟤가)는 의미 있는 내부 Shift를 포함한다.
        // Title Case/ALL CAPS는 유지하되 S/C/T에서 막힌 혼합 대소문자가
        // R5를 통해 한국어 보호를 우회하지 않게 한다(worK의 K는 자모 변화 없음).
        // 2026-11-07 (#174) 오너 결정: 같은 기준을 R3·첫 자음 Shift·단독 목록·자음열에도 쓴다.
        // 떄문(EOans)·옛(DPt)·헸(gpT)·ㅁㅆ(aT) 같은 Shift 오타와 실존어가 영어 조각으로 바뀌었다.
        // MAIN에는 넣지 않는다 — iPhone·macOS·YouTube·sRGB 같은 영어 표기가 그 경로로 온다.
        // 2026-11-07 오너 결정(리뷰 E174-P3-1): 등록된 단위 기호와 대소문자까지 같으면 차단하지 않는다(GPa=혬).
        // sr·ton은 이 조건이 아니라 슬랭 보호와 끝 모음 판정에서 막히므로 그대로다.
        let titleCase = keys.first?.isUppercase == true && keys.dropFirst().allSatisfy(\.isLowercase)
        let conventionalCase = titleCase || keys.allSatisfy(\.isUppercase)
        let englishCasing = !hasShiftKey || conventionalCase || MeasurementUnits.contains(String(keys))

        // R2-화이트리스트 (조건 2·5): 직전 단어가 영어면 shortWords를 변환.
        // (2026-06-19) 트리거 게이트 제거 — 새/무/내/ㅁ/랙도 "앞 영어면 무조건".
        // 한국어 용법(내 책/새 기능)은 앞이 한글이라 prevEnglish=false로 보호.
        // 초성체·의미 있는 Shift는 보호하고, veto보다 먼저 평가한다.
        if prevEnglish, isShortWord, !hasShiftKey, !protectedSlang.contains(hangul) {
            return true
        }
        // ── veto 우회 정책 등급 S/C/T (#33, 2026-09-19) — 셋 다 veto보다 위 ──
        // 공통 가드: Shift 키가 하나라도 있으면 세 등급 모두 발동하지 않는다.
        // 쌍자음(ㅆㄲㄸㅃㅉ)·ㅒㅖ를 일부러 쳤다는 건 한국어 의도의 구조적 증거이며
        // (v3 리뷰 가드 ①과 같은 근거), 등급 판정이 veto보다 위에 있는 만큼
        // 여기서 막지 못하면 실존 한국어가 그대로 영어가 된다.
        // 🚨 2026-09-19: got을 C 등급에 넣자마자 "commit goT"의 **했**이 got으로
        // 깨졌다(테스트가 잡음). 그래서 가드를 S 전용이 아니라 셋 공통으로 둔다.
        // 🚨 2026-09-19 리뷰(H-3): "대문자 = Shift = 한국어 의도"는 두벌식에서 Shift가 실제로
        // 다른 자모를 내는 키(Q W E R T → 쌍자음, O P → ㅒ ㅖ)에만 성립한다. 나머지 키는
        // Shift가 no-op이라(KeyboardLayout2Set 주석 참조) 화면의 한글이 소문자와 완전히 같다 —
        // 그런데 초판 가드가 모든 대문자를 막아 "i Go"·"to Do"·"go dowN"이 종전과 달리
        // 보호되는 회귀가 났다. 자모가 바뀌는 7키의 대문자만 Shift 증거로 센다.
        // S(단독): 한글형이 사실상 안 쓰이는 희귀어 → 문맥 무관 변환.
        // 비슬랭 + 2음절↑ 또는 키 3개↑ (선언부 가드 설명 참조).
        if !hasShiftKey, standaloneOverrideEnglish.contains(word),
           !protectedSlang.contains(hangul),
           units.count >= 2 || keys.count >= 3 {
            return true
        }
        // C(문맥): 희귀 한자어와만 충돌하는 고빈도 영어(when/then/than/got/end).
        if prevEnglish, !hasShiftKey, contextOverrideEnglish.contains(word) {
            return true
        }
        // T(트리거): 흔한 한국어와 동형이라 지정된 영어 단어 뒤에서만 변환.
        // "I 해"→"I go", "to 애"→"to do", "my 행"→"god", "you 양"→"did";
        // "render 해"·"오늘 해"·"render 행"·"render 양"은 트리거가 아니라 보호.
        if !hasShiftKey, let prev = previousEnglishWord,
           let triggers = triggerOverrideEnglish[word], triggers.contains(prev) {
            return true
        }

        // 첫 자음 shift = 명시적 영어 의도 (fps→Fps). asdfgzxcv 자리는 shift가
        // no-op(쌍자음 안 남)이라 한국어 의도로 굳이 shift 칠 이유가 없다 →
        // 영어 신호로 본다. qwert(쌍자음 ㅃㅉㄸㄲㅆ 자리)는 제외 — 쌍자음
        // 입력 의도와 구분 불가하므로. 영어 사전(broad) 일치 시 veto를
        // 우회한다: fps=렌처럼 1음절·실존 한글이라 일반 룰이 못 잡는 약어 구제.
        // (2026-09-19 #33) 소문자로 친 "fps"(렌)는 이제 위 S 등급이 veto보다
        // 먼저 잡는다 — 종전엔 veto가 보호해 미변환이었다.
        // 오변환은 shift+space 되돌리기가 최종 안전망. (대문자는 keyDown으로
        // 들어오므로 flagsChanged 구독 불필요 — 쌍자음 깨짐 위험 없음.)
        if let first = keys.first, first.isUppercase,
           "ASDFGZXCV".contains(first), isDictWord, englishCasing {
            return true
        }
        // 2026-11-07 (#174) 오너 결정: 문장 첫 The. T는 쌍자음 키라 위 분기에 못 오고, 쏟은 멀쩡한 1음절이라 R5에도 안 닿고,
        // 쏟다가 표제어라 아래 X다 veto에 걸렸다. 키열이 정확히 The일 때만 변환하므로 the·THE·쏟은(Thedms)은 그대로다.
        // 조사 분리의 앞말로는 쓰지 않는다(EnglishParticleSplitter.prefixDecision) — 쏟는이 The는이 되면 안 된다.
        if isSentenceStartThe(keys) {
            return true
        }

        // ★ 한국어 사전 veto (v3): 조합 결과가 실존 한국어 단어(우리말샘
        // 67.7만)면 어떤 룰로도 변환하지 않는다. 며새(사전에 없음)는
        // 통과해 영어 후보가 되고, 모든/랙/좀/책(있음)은 절대 안전.
        if KoreanDictionary.contains(hangul) {
            return false
        }
        // 2026-11-06 (#152): 표제어에는 기본형만 있어 어간은 빠진다. 얕(얕다)이 사전에 없어 영어 이름 dix로 넘어가
        // "얕은" + Space가 "dix은"으로 확정됐다. X다가 표제어면 X는 우리말 어간이다.
        // 활용형 98만 개 전수에서 확정 오변환을 낸 어간이 이 기준으로 전부 막힌다. 잃는 영어는 epfl(데리)·dix(얕) 둘이다.
        if KoreanDictionary.contains(hangul + "다") {
            return false
        }
        // 초성체 슬랭도 동급 보호 (사전엔 완성 한글만 있어서 별도 목록).
        if protectedSlang.contains(hangul) {
            return false
        }
        // 2026-11-07 (#174) 오너 결정: 해ㅠ·네ㅜ류. MAIN만이 아니라 단위 경로(새ㅜ=ton)도 함께 막도록 여기서 거른다.
        // 영어 문맥이 있거나 숫자 뒤 단위(10 ton)이면 이 판정에 오지 않거나 통과하고, Son·Don은 첫 자음 Shift가 위에서 받는다.
        if !prevEnglish, isSadTail(units) || sadTailExactForms.contains(hangul) {
            return false
        }

        // #24 · 2026-10-14: 의미를 추측하거나 철자를 고치지 않는다. 전체 기존 사전
        // 판정은 그대로 우선한다. 새 경로는 깨진 한글 + 정확 curated 단어 두 개뿐이다.
        // clean 한글/의미 있는 Shift/짧은 조각/복수 분해는 포기하고, veto를 우회하지 않는다.
        if dictionaryCompoundsEnabled, !isDictWord, brokenAsKorean, !hasShiftKey,
           dictionaryCompoundParts(word, blockedWords: blockedCompoundWords) != nil {
            return true
        }

        // #82: 명시된 단위만 추가한다. 반복/얼굴 자모·한국어 veto·슬랭은 위에서
        // 이미 보호했다. ㅚ(hl/hL)처럼 한 자모로 합쳐진 표기는 이 경로로 바꾸지 않는다.
        // (2026-11-01 #106: ml/mL=ㅢ은 이 경로가 아니라 아래 R1의 shortWords로 변환한다.)
        // cm=츠는 검역한 비단어 예외, 다른 멀쩡한 1음절은 숫자 수량 조건을 요구한다.
        if MeasurementUnits.contains(String(keys)), keys.count >= 2,
           (brokenAsKorean && units.count >= 2) || String(keys) == "cm" {
            return true
        }

        // 무맥락 단독 화이트리스트 (and=뭉): veto 통과한 1음절 비단어를 좌우
        // 문맥 무관하게 변환. R5(2음절+)가 못 잡는 1음절 구멍 — 명시 목록
        // 이라 걍 등 다른 1음절 슬랭은 건드리지 않는다.
        if standaloneShortWords.contains(word), englishCasing {
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
        if englishCasing, !lowered.contains(where: mapsToVowel),
           units.allSatisfy({ $0.unicodeScalars.allSatisfy { (0x3131...0x314E).contains($0.value) } }) {
            if units.count >= 4, isDictWord { return true }
            if units.count == 3, commonWords.contains(word) { return true }
            // 자음 2개(we=ㅈㄷ, at=ㅁㅅ, as=ㅁㄴ)는 사전으로 못 넣어 코드 목록만이
            // 통로다 (#33, 2026-09-19 — 선언부 consonantPairShortWords 참조).
            if units.count == 2, consonantPairShortWords.contains(word) { return true }
        }

        // ㅑ 1음절 — 1음절에 ㅑ(중성)가 들어가면 한국어 뜻일 확률 거의 0
        // (먕=aid, 먁=air). veto가 향/양/약/야/샷 등 진짜 단어를 이미 걸렀고
        // (우리말샘 1음절 ㅑ 29개), 미등재 ㅑ 1음절 + 영어 사전이면 변환.
        // ★ (M3) R5(clean)는 curated만 신뢰하지만 여기는 의도적으로 broad
        // (isDictWord) 예외 — "1음절+ㅑ"는 한국어가 거의 없어 broad가 안전.
        // 걍(rid) 등 미등재 슬랭은 변환되나 shift+space 되돌리기로 커버.
        // 2026-11-07 (#174) 오너 결정: 의미 있는 Shift가 있으면 막는다. 썅(Tid)·쨩(Wid)·곘(rPT)·얐(diT)가 영어로 바뀌었다.
        if units.count == 1, isDictWord, hasMedialYa(units[0]), !hasShiftKey {
            return true
        }

        // R1 — 조건 1: a standalone vowel before any consonant is impossible
        // Korean (ㅑ→i). Broad dict is safe here: vowel-first already
        // excludes real Korean.
        if startsWithStandaloneVowel(units), isShortWord || isDictWord {
            return true
        }

        // R3 — 조건 3: a syllable that doesn't exist in used Korean (솓).
        if units.contains(where: containsImplausibleSyllable), isShortWord || isDictWord, englishCasing {
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
        if !brokenAsKorean, units.count >= 2, englishCasing, commonWords.contains(word) {
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
            // 여기는 종전대로 **모든** 대문자를 Shift 증거로 본다(v3 리뷰 가드 ① — 활용형 방어는
            // 보수적으로). 위 등급 가드(QWERTOP 한정)와 기준이 다른 것은 의도다.
            let anyUppercase = keys.contains { $0.isUppercase }
            if !anyUppercase {
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
            _ = bundledTable
            _ = systemWords
            _ = extraBroadWords
            _ = commonWords
        }
    }

    /// #14: 외부 원문은 명시 사전 전체 일치/닫힌 축약형만 문맥의 근거가 된다.
    /// inflection fallback이나 복합어 추론, 오타 유사도는 여기에 사용하지 않는다.
    static func isExplicitEnglishContextWord(_ word: String) -> Bool {
        shortWords.contains(word) || isBroadWord(word) || Contractions.words.contains(word)
    }

    /// #24: 두 조각은 각각 4~24글자, 전체 8~48글자이며 curated에 정확히 등재돼야 한다.
    /// broad 전용 이름/형태 변형은 제외한다. curated에 있는 브랜드 이름은 정확 일치 시 허용한다.
    /// 둘 이상으로 쪼갤 수 있으면 모호하므로 포기한다.
    static func dictionaryCompoundParts(
        _ word: String, blockedWords: Set<String> = []
    ) -> (first: String, second: String)? {
        let bytes = Array(word.utf8)
        guard (8...48).contains(bytes.count),
              bytes.allSatisfy({ (0x61...0x7A).contains($0) }) else { return nil }
        var found: (first: String, second: String)?
        let firstSplit = max(4, bytes.count - 24)
        let lastSplit = min(24, bytes.count - 4)
        guard firstSplit <= lastSplit else { return nil }
        for split in firstSplit...lastSplit {
            let first = String(decoding: bytes[..<split], as: UTF8.self)
            let second = String(decoding: bytes[split...], as: UTF8.self)
            guard commonWords.contains(first), commonWords.contains(second) else { continue }
            if found != nil { return nil }
            found = (first, second)
        }
        guard let found, !blockedWords.contains(word),
              !blockedWords.contains(found.first), !blockedWords.contains(found.second) else { return nil }
        // 개인 금지는 영어뿐 아니라 자판 한글형도 받는다. 구성 단어 금지를 합성해 지킨다.
        if !blockedWords.isEmpty {
            for part in [found.first, found.second] {
                if let hangul = ManualToggle.keysToHangul(part), blockedWords.contains(hangul) {
                    return nil
                }
            }
        }
        return found
    }

    /// 2026-11-07 (#174): 문장 첫 The 예외의 키열.
    static func isSentenceStartThe(_ keys: [Character]) -> Bool {
        keys == ["T", "h", "e"]
    }

    /// 2026-11-07 (#174): `sadTailHeads`의 1음절 뒤에 ㅠㅜㅡ만 이어지는 꼴인가 (해ㅠ·개ㅠㅠ·네ㅜ).
    private static func isSadTail(_ units: [String]) -> Bool {
        guard units.count >= 2, sadTailHeads.contains(units[0]) else { return false }
        return units.dropFirst().allSatisfy { $0 == "ㅠ" || $0 == "ㅜ" || $0 == "ㅡ" }
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

    nonisolated(unsafe) private static var ksx1001Cache: [Character: Bool] = [:]
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
        if isBroadWord(w) { return true }

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
        return stems.contains { $0.count >= 3 && isBroadWord($0) }
    }

    /// stopp → stop, runn → run
    private static func dedoubled(_ s: String) -> String {
        let chars = Array(s)
        guard chars.count >= 2, chars[chars.count - 1] == chars[chars.count - 2] else { return s }
        return String(chars.dropLast())
    }

    /// Broad lookup: 번들 표 + 시스템 web2 + curated + 표 밖의 파일. For broken-as-Korean rules only.
    /// 모든 낱말이 ASCII 소문자라 바이트 비교와 Set<String>의 유니코드 동치 비교는 답이 같다.
    private static func isBroadWord(_ w: String) -> Bool {
        if let bundledTable, bundledTable.contains(Array(w.utf8)) { return true }
        if let systemWords, systemWords.contains(w) { return true }
        return commonWords.contains(w) || extraBroadWords.contains(w)
    }

    /// 온전한 파일일 때만 쓴다. 틀어진 표로 조회가 조용히 빗나가느니 표 없이 동작하는 편이 안전하다.
    private static let bundledTable: SortedWordTable? =
        bundledTablePath.flatMap { SortedWordTable(path: $0) }.flatMap { $0.isComplete ? $0 : nil }

    private static let systemWords: SystemWordFile? = systemWordsPath.flatMap { SystemWordFile(path: $0) }

    /// wordlistPaths 중 curated가 아닌 파일. 배포본에서는 비어 있다.
    private static let extraBroadWords: Set<String> =
        loadWords(from: wordlistPaths.filter { !curatedPaths.contains($0) }, expectedCapacity: 0)

    /// Curated list: curatedPaths-registered files ONLY (web2와 인명 파일
    /// 제외). The clean-Hangul R5 rule trusts this exclusively — exact
    /// match, no inflection — so obscure broad entries can never hijack a
    /// real Korean word.
    private static let commonWords: Set<String> =
        loadWords(
            from: wordlistPaths.filter { curatedPaths.contains($0) },
            expectedCapacity: 4_000
        )

    /// mmap + 바이트 스캔 (KoreanDictionary와 동일 이유 — 임시 버퍼가
    /// malloc 캐시에 상주하는 것 방지). 필터는 `isWordLine` 하나다.
    static func loadWords(
        from paths: [String],
        expectedCapacity: Int
    ) -> Set<String> {
        var set = Set<String>()
        set.reserveCapacity(expectedCapacity)
        for path in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            insertWords(of: data, into: &set)
        }
        return set
    }

    /// 낱말 파일의 줄 필터: 3자 이상, 첫 글자가 ASCII 소문자(고유명사/주석 제외), ASCII 알파벳만. 비교는 소문자화해서 한다.
    /// Set 로더와 `SystemWordFile`이 이 함수를 함께 써서 판정이 갈라지지 않게 한다.
    @inline(__always)
    fileprivate static func isWordLine(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Bool {
        guard range.count >= 3 else { return false }
        let first = bytes[range.lowerBound]
        guard first >= 0x61, first <= 0x7A else { return false }
        for i in range where !((bytes[i] >= 0x61 && bytes[i] <= 0x7A) || (bytes[i] >= 0x41 && bytes[i] <= 0x5A)) {
            return false
        }
        return true
    }

    fileprivate static func insertWords(of data: Data, into set: inout Set<String>) {
        let newline = UInt8(ascii: "\n")
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            var start = 0
            func consume(_ range: Range<Int>) {
                guard isWordLine(bytes, range) else { return }
                set.insert(String(decoding: bytes[range], as: UTF8.self).lowercased())
            }
            for i in 0..<bytes.count where bytes[i] == newline {
                consume(start..<i)
                start = i + 1
            }
            if start < bytes.count { consume(start..<bytes.count) }
        }
    }
}

/// 2026-11-07 (#175) 오너 결정: 시스템 낱말 파일을 펼치지 않고 매핑한 채 찾는다. 답은 언제나 그 파일을 `loadWords`로 펼친 Set과 같다.
///
/// 파일은 대소문자 무시 순이지만 보장이 아니다(macOS 판마다 다를 수 있다). 그래서 초기화 때 한 번 훑어 직접 확인한다.
///   - 대상은 `isWordLine`을 통과한 줄뿐이다. March처럼 대문자로 시작하는 줄은 답이 될 수 없어 순서를 따지지 않는다.
///   - 앞줄보다 작은 대상 줄(2026-11-07 이 Mac: plies 뒤의 pliers 1곳)은 작은 Set에 따로 둔다. 나머지는 정렬돼 있으므로 성긴 색인으로 찾는다.
///   - 어긋난 낱말이 `maxStrayWords`를 넘거나 색인 사이가 `maxGapBytes`를 넘으면 정렬 파일로 보지 않고 Set으로 펼친다.
///     메모리만 늘고 답은 같다. 빈 파일·CRLF(모든 줄이 필터에서 탈락)·잘린 파일도 같은 필터를 타므로 답이 Set과 같다.
///
/// 매핑한 페이지는 깨끗한 페이지라 phys_footprint에 들지 않고, 초기화(utility 큐)에서 전부 한 번 읽어 올라와 있다.
/// 파일은 봉인된 시스템 볼륨에 있어 입력기가 도는 동안 제자리에서 바뀌지 않는다.
/// 메모리가 모자라 페이지가 내려간 뒤에는 조회가 파일을 다시 읽는다. 압축 파일이라 비어 있는 페이지 첫 접근이 50~800µs 걸린다(2026-11-07 실측).
/// 그래서 색인 줄의 앞 8글자를 메모리에 두어 이진 탐색이 파일을 건드리지 않게 하고, 조회 한 번이 읽는 곳을 색인 사이 한 구간으로 줄였다.
final class SystemWordFile {
    /// 대상 줄 몇 개마다 색인을 둘지. 이 Mac의 web2에서 색인 약 6,600개(26KB), 간격 평균 약 380B다.
    private static let anchorStride = 32
    /// 어긋난 낱말 상한. Set<String> 4,096칸은 약 0.13MB로 펼친 Set(8.6MB)에 견줘 작다.
    /// 이보다 많으면 파일이 정렬돼 있다고 보기 어렵고, 펼쳐도 답은 같으니 더 버틸 이유가 없다.
    static let maxStrayWords = 4_096
    /// 조회 한 번이 훑는 길이의 상한. 키 입력 경로라 대상이 아닌 줄이 길게 이어지는 파일은 받지 않는다.
    static let maxGapBytes = 64 * 1024

    private let data: Data
    private let anchors: [UInt32]
    /// `anchors`와 같은 순서의 앞 8글자(소문자, 큰 자리부터, 모자라면 0). 낱말 순서와 대소 관계가 같다.
    private let anchorPrefixes: [UInt64]
    private let strayWords: Set<String>
    private let expanded: Set<String>?
    /// 정렬 파일로 쓰지 못해 Set으로 펼쳤는가.
    var isExpanded: Bool { expanded != nil }
    var strayCount: Int { strayWords.count }

    convenience init?(path: String) {
        guard let mapped = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
        self.init(data: mapped)
    }

    init(data given: Data) {
        var marks: [UInt32] = []
        var prefixes: [UInt64] = []
        var stray = Set<String>()
        var usable = given.count < Int(UInt32.max)
        if usable {
            marks.reserveCapacity(given.count / (Self.anchorStride * 8) + 16)
            prefixes.reserveCapacity(marks.capacity)
            given.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let bytes = raw.bindMemory(to: UInt8.self)
                let newline = UInt8(ascii: "\n")
                var cursor = 0
                var ordered = 0
                var previous: Range<Int>? = nil
                scan: while cursor < bytes.count {
                    var end = cursor
                    while end < bytes.count, bytes[end] != newline { end += 1 }
                    let line = cursor..<end
                    if EnglishDetector.isWordLine(bytes, line) {
                        if let previous, Self.compareLowered(bytes, line, previous) < 0 {
                            stray.insert(String(decoding: bytes[line], as: UTF8.self).lowercased())
                            if stray.count > Self.maxStrayWords { usable = false; break scan }
                        } else {
                            if ordered % Self.anchorStride == 0 {
                                if let last = marks.last, cursor - Int(last) > Self.maxGapBytes { usable = false; break scan }
                                marks.append(UInt32(cursor))
                                prefixes.append(Self.prefix(bytes[line]))
                            }
                            ordered += 1
                            previous = line
                        }
                    }
                    cursor = end + 1
                }
                if let last = marks.last, bytes.count - Int(last) > Self.maxGapBytes { usable = false }
            }
        }
        if usable {
            data = given
            anchors = marks
            anchorPrefixes = prefixes
            strayWords = stray
            expanded = nil
        } else {
            var set = Set<String>()
            EnglishDetector.insertWords(of: given, into: &set)
            data = Data()
            anchors = []
            anchorPrefixes = []
            strayWords = []
            expanded = set
        }
    }

    func contains(_ word: String) -> Bool {
        if let expanded { return expanded.contains(word) }
        if strayWords.contains(word) { return true }
        var key = word
        return key.withUTF8 { key in
            // 파일의 대상 줄은 소문자화하면 전부 a-z다. 그 밖의 글자가 든 말은 답이 될 수 없다.
            guard key.count >= 3, key.allSatisfy({ $0 >= 0x61 && $0 <= 0x7A }) else { return false }
            return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
                lookup(raw.bindMemory(to: UInt8.self), key)
            }
        }
    }

    private func lookup(_ bytes: UnsafeBufferPointer<UInt8>, _ key: UnsafeBufferPointer<UInt8>) -> Bool {
        let newline = UInt8(ascii: "\n")
        func lineEnd(_ start: Int) -> Int {
            var end = start
            while end < bytes.count, bytes[end] != newline { end += 1 }
            return end
        }
        // anchors[lo]는 key 이상인 첫 색인이다. 답은 그 줄이거나 바로 앞 색인과의 사이에 있다.
        // 앞 8글자가 다르면 파일을 읽지 않고 정한다.
        let keyPrefix = Self.prefix(key[...])
        var lo = 0, hi = anchors.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let order: Int
            if anchorPrefixes[mid] != keyPrefix {
                order = anchorPrefixes[mid] < keyPrefix ? -1 : 1
            } else {
                let start = Int(anchors[mid])
                order = Self.compareLowered(bytes, start..<lineEnd(start), key)
            }
            if order < 0 { lo = mid + 1 } else { hi = mid }
        }
        if lo < anchors.count, anchorPrefixes[lo] == keyPrefix {
            let start = Int(anchors[lo])
            if Self.compareLowered(bytes, start..<lineEnd(start), key) == 0 { return true }
        }
        guard lo > 0 else { return false }
        var cursor = Int(anchors[lo - 1])
        let stop = lo < anchors.count ? Int(anchors[lo]) : bytes.count
        while cursor < stop {
            let end = lineEnd(cursor)
            if Self.matches(bytes, cursor..<end, key) { return true }
            cursor = end + 1
        }
        return false
    }

    /// 앞 8글자를 큰 자리부터 담는다. 대상 줄은 알파벳뿐이라 0x20을 켜면 소문자가 되고, key는 이미 소문자다.
    @inline(__always)
    private static func prefix(_ text: Slice<UnsafeBufferPointer<UInt8>>) -> UInt64 {
        var value: UInt64 = 0
        var taken = 0
        for byte in text.prefix(8) {
            value = value << 8 | UInt64(byte | 0x20)
            taken += 1
        }
        return taken == 8 ? value : value << UInt64((8 - taken) * 8)
    }

    /// 대상 줄과 key가 같은가. March는 첫 글자가 대문자라 march의 답이 아니다(loadWords가 건너뛴다). marCh는 답이다.
    @inline(__always)
    private static func matches(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>, _ key: UnsafeBufferPointer<UInt8>) -> Bool {
        guard line.count == key.count, bytes[line.lowerBound] == key[0] else { return false }
        var k = 1
        var i = line.lowerBound + 1
        while i < line.upperBound {
            let b = bytes[i]
            guard b == key[k] || b == key[k] - 0x20 else { return false }
            i += 1
            k += 1
        }
        return true
    }

    /// 대상 줄끼리, 또는 대상 줄과 소문자 key의 사전순 비교. 대상 줄은 알파벳뿐이라 0x20을 켜면 소문자가 된다.
    @inline(__always)
    private static func compareLowered(_ bytes: UnsafeBufferPointer<UInt8>, _ a: Range<Int>, _ b: Range<Int>) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n {
            let x = bytes[a.lowerBound + i] | 0x20, y = bytes[b.lowerBound + i] | 0x20
            if x != y { return x < y ? -1 : 1 }
            i += 1
        }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    @inline(__always)
    private static func compareLowered(_ bytes: UnsafeBufferPointer<UInt8>, _ a: Range<Int>, _ key: UnsafeBufferPointer<UInt8>) -> Int {
        let n = min(a.count, key.count)
        var i = 0
        while i < n {
            let x = bytes[a.lowerBound + i] | 0x20, y = key[i]
            if x != y { return x < y ? -1 : 1 }
            i += 1
        }
        return a.count == key.count ? 0 : (a.count < key.count ? -1 : 1)
    }
}

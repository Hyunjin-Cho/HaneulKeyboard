import Foundation

// Standalone test harness for the IME composition core. Runs without Xcode:
//   scripts/run_ime_tests.sh
// Compiles HangulJamo + KeyboardLayout2Set + KoreanComposer + EnglishDetector
// (all Foundation-only) together with this file and executes main().

// MARK: - Fake client

final class FakeClient: ComposerClient {
    var inserted: [String] = []
    var marked: String = ""

    func insertText(_ text: String) {
        inserted.append(text)
    }

    func setMarkedText(_ text: String) {
        marked = text
    }

    var committedText: String { inserted.joined() }
}

// MARK: - Tiny assertion runner

var failures = 0
var passes = 0

func expect(_ actual: String, _ expected: String, _ label: String) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(label): expected \"\(expected)\", got \"\(actual)\"")
    }
}

func expect(_ actual: Bool, _ expected: Bool, _ label: String) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(label): expected \(expected), got \(actual)")
    }
}

func expect(_ actual: Int, _ expected: Int, _ label: String) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(label): expected \(expected), got \(actual)")
    }
}

// MARK: - Helpers

/// Feeds each character through the composer as typed keys, then commits at
/// an ACTIVE boundary (as if the user pressed Space).
func type(_ keys: String, autoEnglish: Bool = true) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    composer.autoEnglishEnabled = autoEnglish
    for ch in keys {
        _ = composer.handleInput(String(ch), client: client)
    }
    composer.commit(to: client, convertEnglish: true)
    return client
}

/// Same, but commits at a PASSIVE boundary (focus change, mouse click,
/// CapsLock switch) — must always commit the marked text as displayed.
func typePassive(_ keys: String) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    for ch in keys {
        _ = composer.handleInput(String(ch), client: client)
    }
    composer.commit(to: client)
    return client
}

/// Types words separated by space boundaries through ONE composer, so the
/// English-context rule (직전 단어가 영어) can carry across words.
func typeWords(_ words: [String]) -> [String] {
    let client = FakeClient()
    let composer = KoreanComposer()
    var committed: [String] = []
    for w in words {
        for ch in w { _ = composer.handleInput(String(ch), client: client) }
        committed.append(composer.commit(to: client, convertEnglish: true))
    }
    return committed
}

// MARK: - Tests

@main
struct ComposerTests {
    static func main() {
        // Wordlist: system dict + a temp supplement (no app bundle here).
        // Must be set before the first shouldConvert call (lazy load).
        let supplementPath = NSTemporaryDirectory() + "haneul_test_supplement.txt"
        try? "google\ngithub\n".write(toFile: supplementPath, atomically: true, encoding: .utf8)
        // 실제 번들 보충 사전도 포함 (xcode/kpop 등) — 테스트는 repo 루트에서 실행됨
        EnglishDetector.wordlistPaths = [
            "/usr/share/dict/words",
            "Resources/IM/english_supplement.txt",
            supplementPath,
        ]
        // v3 한국어 veto 사전 (우리말샘 추출본, repo 루트 기준)
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"

        // Hangul composition (regression — must match pre-word-buffer behavior)
        expect(type("dkssud").committedText, "안녕", "basic 안녕")
        expect(type("dkssudgktpdy").committedText, "안녕하세요", "안녕하세요")
        expect(type("gksk").committedText, "하나", "도깨비불 carry 하나")
        expect(type("Rk").committedText, "까", "쌍자음 까")
        expect(type("ghk").committedText, "화", "compound vowel 화")
        expect(type("dhks").committedText, "완", "compound vowel with final 완")
        expect(type("dlfrrh").committedText, "읽고", "compound final 읽고")

        // Backspace: peel in-flight jamo
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dks" { _ = composer.handleInput(String(ch), client: client) } // 안
            _ = composer.deleteBackward(client: client) // peel ㄴ → 아
            expect(client.marked, "아", "backspace peels final")
            _ = composer.handleInput("s", client: client) // 안
            composer.commit(to: client)
            expect(client.committedText, "안", "retype after peel")
        }

        // Backspace: through the word buffer down to empty
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) } // 안녕
            expect(client.marked, "안녕", "word-level marked text")
            _ = composer.deleteBackward(client: client) // 녕 → 녀
            expect(client.marked, "안녀", "peel into in-flight syllable")
            _ = composer.deleteBackward(client: client) // 녀 → ㄴ
            _ = composer.deleteBackward(client: client) // ㄴ → (empty in-flight)
            expect(client.marked, "안", "in-flight fully peeled")
            _ = composer.deleteBackward(client: client) // word unit 안 removed
            expect(client.marked, "", "word unit removed")
            expect(composer.deleteBackward(client: client), false, "empty → system handles")
            composer.commit(to: client)
            expect(client.committedText, "", "nothing left to commit")
        }

        // Wrong-layout English auto-correction
        expect(type("apple").committedText, "apple", "apple converts (메ㅔㅣㄷ → apple)")
        expect(type("hello").committedText, "hello", "hello converts (ㅗ디ㅣㅐ → hello)")
        expect(type("google").committedText, "google", "supplement wordlist hit")
        expect(type("apple", autoEnglish: false).committedText, "메ㅔㅣㄷ", "toggle off keeps hangul")
        expect(type("zzz").committedText, "ㅋㅋㅋ", "emotive ㅋㅋㅋ untouched")
        expect(type("bb").committedText, "ㅠㅠ", "emotive ㅠㅠ untouched")
        expect(type("dkssud").committedText, "안녕", "valid hangul never converted")
        expect(type("Apple").committedText, "Apple", "case preserved on conversion")

        // Bare-vowel + consonant fix (was silent data loss: ㄷ vanished)
        expect(type("le", autoEnglish: false).committedText, "ㅣㄷ", "consonant after bare vowel survives")

        // Backspace inside a wrong-layout word still converts correctly
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "applw" { _ = composer.handleInput(String(ch), client: client) } // typo: w
            _ = composer.deleteBackward(client: client) // remove ㅈ (w)
            _ = composer.handleInput("e", client: client) // correct: e
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "apple", "backspace correction mid-word")
        }

        // Jamo slang / kaomoji must NEVER convert (review findings)
        expect(type("gee").committedText, "ㅎㄷㄷ", "consonant-only slang ㅎㄷㄷ untouched")
        expect(type("aw").committedText, "ㅁㅈ", "2-key slang ㅁㅈ untouched")
        expect(type("hi").committedText, "ㅗㅑ", "2-key vowel slang ㅗㅑ untouched")
        // ㅢ(ml)/ㅐㅏ(ok)는 흔한 자모 슬랭 → 무맥락 유지, 영어 문맥서만 변환
        expect(type("ml").committedText, "ㅢ", "ml: 무맥락 슬랭 ㅢ 보호")
        expect(type("ok").committedText, "ㅐㅏ", "ok: 무맥락 슬랭 ㅐㅏ 보호")
        expect(typeWords(["want", "ml"]).last ?? "", "ml", "ml: 영어 문맥서만 변환")
        // (the composer assembles these as ㅡ므/ㅜ무/ㅠ뮤 — same as Apple's
        // IME; the point is the V-C-V palindrome guard blocks conversion)
        expect(type("mam").committedText, "ㅡ므", "kaomoji keys mam not converted")
        expect(type("nan").committedText, "ㅜ무", "kaomoji keys nan not converted")
        expect(type("bab").committedText, "ㅠ뮤", "kaomoji keys bab not converted")
        expect(type("sdr").committedText, "ㄴㅇㄱ", "ㄴㅇㄱ untouched")

        // 3-key English with vowels still converts
        expect(type("you").committedText, "you", "3-key you converts")
        expect(type("man").committedText, "man", "non-palindrome man converts")

        // Inflected English converts via suffix fallback ("apples"/"typing"
        // are not in the 1934 dict; their stems are)
        expect(type("apples").committedText, "apples", "plural apples converts")
        expect(type("typing").committedText, "typing", "typing converts (-ing → +e stem)")

        // PASSIVE boundaries (click, CapsLock, app switch) never convert —
        // they must commit exactly the marked text the user saw.
        expect(typePassive("apple").committedText, "메ㅔㅣㄷ", "passive boundary commits as displayed")
        expect(typePassive("dkssud").committedText, "안녕", "passive boundary commits hangul")

        // ── 영타 v2: 사용자 조건식 (2026-06-06) ──

        // 조건 1: 자음보다 모음이 먼저 = 잘못된 한국어
        expect(type("i").committedText, "i", "조건1: ㅑ → i")
        expect(type("md").committedText, "md", "조건1: ㅡㅇ → md")
        expect(type("email").committedText, "email", "조건1: 모음시작 email")

        // 조건 7: 조합 안 되는 모음 연속 = 영어 / 복모음은 한글
        expect(type("ui").committedText, "ui", "조건7: ㅕㅑ → ui")
        expect(type("dml").committedText, "의", "조건7 예외: 의")
        expect(type("dhk").committedText, "와", "조건7 예외: 와")
        expect(type("dho").committedText, "왜", "조건7 예외: 왜")

        // 조건 2·5: 직전 단어가 영어면 새→to, ㅁ→a, 무→an
        expect(typeWords(["want", "to"]).joined(separator: " "), "want to", "조건2: 영어 뒤 새 → to")
        expect(type("to").committedText, "새", "조건2: 문맥 없으면 새 유지")
        expect(typeWords(["want", "a"]).last ?? "", "a", "조건5: 영어 뒤 ㅁ → a")
        expect(type("a").committedText, "ㅁ", "조건5: 문맥 없으면 ㅁ 유지")
        expect(typeWords(["want", "an"]).last ?? "", "an", "조건5: 영어 뒤 무 → an")
        expect(
            typeWords(["i", "want", "to", "make", "a", "keyboard"]).joined(separator: " "),
            "i want to make a keyboard",
            "조건2: 문장 전체"
        )

        // 문맥 리셋: 마침표/엔터/클릭 뒤에는 영어 문맥이 끊긴다
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "want" { _ = composer.handleInput(String(ch), client: client) }
            _ = composer.commit(to: client, convertEnglish: true) // "want"
            composer.resetEnglishContext() // controller가 비공백 경계에서 호출
            for ch in "to" { _ = composer.handleInput(String(ch), client: client) }
            expect(composer.commit(to: client, convertEnglish: true), "새", "문맥 리셋 후 새 유지")
        }

        // 조건 3: 한국어에 실존하지 않는 음절 (솓 ∉ KS X 1001)
        expect(type("the").committedText, "the", "조건3: 솓 → the")

        // 조건 6: 자음 연속 = 영어 / ㄺ·ㄼ·ㅀ 받침 조합은 한글
        expect(type("xcode").committedText, "xcode", "조건6: ㅌ챙ㄷ → xcode")
        expect(type("rmfrek").committedText, "긁다", "조건6 예외: ㄺ 받침")
        expect(type("Wkfqek").committedText, "짧다", "조건6 예외: ㄼ 받침")
        expect(type("tlfgek").committedText, "싫다", "조건6 예외: ㅀ 받침")

        // 조건 9 + 추가 사전
        expect(type("kpop").committedText, "kpop", "조건9: kpop")
        expect(type("opus").committedText, "opus", "opus")
        expect(type("readme").committedText, "readme", "조건4: readme")

        // 조건 10(모음 반복): 떠 있는 모음 + 영어 단어 → MAIN이 변환
        expect(type("mini").committedText, "mini", "조건10: ㅡㅑㅜㅑ → mini (사전 등재)")
        expect(type("you").committedText, "you", "조건10: ㅛㅐㅕ → you")
        // 보호: 영어로 말 안 되는 모음 나열은 사전에 없어 한글 유지
        expect(type("hni").committedText, "ㅗㅜㅑ", "보호: ㅗㅜㅑ 슬랭 (hni는 영어 아님)")
        expect(type("nmn").committedText, "ㅜㅡㅜ", "보호: ㅜㅡㅜ 우는 이모티콘")
        expect(type("hmh").committedText, "ㅗㅡㅗ", "보호: ㅗㅡㅗ 이모티콘")
        // 보호: 자음 슬랭·정상 조합
        expect(type("drfddla").committedText, "ㅇㄱㄹㅇ임", "보호: 자음 슬랭")
        expect(type("dhksrjsk").committedText, "완거나", "보호: 정상 조합")

        // R2는 화이트리스트 전용 (web2 확장은 좀/책/형 파괴 → 되돌림).
        // 흔한 한국어 보호: 영어 뒤라도 clean Hangul 단어는 안 건드림.
        expect(typeWords(["good", "wha"]).last ?? "", "좀", "R2 보호: good 뒤 좀 유지")
        expect(typeWords(["want", "gud"]).last ?? "", "형", "R2 보호: want 뒤 형 유지")
        expect(typeWords(["really", "cor"]).last ?? "", "책", "R2 보호: really 뒤 책 유지")
        // 한계 명시: 문장 첫 clean 단어(며새=auto)는 문맥이 없어 유지
        expect(
            typeWords(["auto", "mode", "on"]).joined(separator: " "),
            "며새 mode on",
            "한계: 문장 첫 clean 단어 며새는 유지 (mode/on은 변환)"
        )

        // ── v3: 한국어 사전 veto + R2 사전 확장 (실기기 실패 케이스) ──
        // 자음-only 영단어: 영어 문맥에서 변환 (사전 veto 통과 — 한글 아님)
        expect(typeWords(["how", "are"]).last ?? "", "are", "v3: how 뒤 ㅁㄱㄷ → are")
        expect(typeWords(["how", "great"]).last ?? "", "great", "v3: ㅎㄱㄷㅁㅅ → great")
        expect(typeWords(["wallet", "was"]).last ?? "", "was", "v3: ㅈㅁㄴ → was")
        // clean 한글이지만 사전에 없는 단어: 영어 문맥에서 변환
        expect(typeWords(["the", "auto"]).last ?? "", "auto", "v3: 며새(사전 없음) → auto")
        // 실존 한국어는 영어 문맥에서도 절대 보호 (veto)
        expect(typeWords(["good", "wha"]).last ?? "", "좀", "v3 veto: 좀 보호")
        expect(typeWords(["really", "cor"]).last ?? "", "책", "v3 veto: 책 보호")
        expect(typeWords(["want", "gud"]).last ?? "", "형", "v3 veto: 형 보호")
        // (v3.1: 사용자 요청으로 뒤집힘 — 랙도 영어 문맥에선 for로)
        expect(typeWords(["thanks", "for"]).last ?? "", "for", "v3.1: thanks 뒤 랙 → for")
        // 초성체 슬랭은 영어 문맥에서도 보호 (보호 목록)
        expect(typeWords(["lol", "gee"]).last ?? "", "ㅎㄷㄷ", "v3 슬랭: ㅎㄷㄷ 보호")
        expect(typeWords(["lol", "ace"]).last ?? "", "ㅁㅊㄷ", "v3 슬랭: ㅁㅊㄷ 보호")
        // 사용자 명시 화이트리스트(새→to)는 veto보다 우선
        expect(typeWords(["want", "to"]).last ?? "", "to", "v3: 새→to 유지 (명시 조건)")
        // 무맥락은 여전히 보수적 (문장 첫 며새는 유지)
        expect(type("auto").committedText, "며새", "v3: 무맥락 며새 유지")

        // R2 호모그래프 보호 (라운드2): 해/내/애는 영어 뒤에서도 한글 유지
        expect(typeWords(["apple", "go"]).last ?? "", "해", "R2 보호: apple 뒤 해 유지 (go 아님)")
        expect(typeWords(["apple", "so"]).last ?? "", "내", "R2 보호: apple 뒤 내 유지 (so 아님)")
        expect(typeWords(["apple", "do"]).last ?? "", "애", "R2 보호: apple 뒤 애 유지 (do 아님)")
        // 체이닝 방지: 새→to(문맥-only)는 다음 단어에 영어 문맥을 넘기지 않음
        expect(
            typeWords(["want", "to", "go"]).joined(separator: " "),
            "want to 해",
            "체이닝 방지: 새→to 뒤 해는 유지"
        )
        // R2x 체이닝: 구조적 변환(was)은 다음 단어(great)에 문맥을 넘김
        expect(
            typeWords(["that", "was", "great"]).joined(separator: " "),
            "that was great",
            "체이닝: was → great 연쇄"
        )
        // 화이트리스트 트리거: want 뒤 새→to는 되고, github 뒤 새는 유지
        expect(typeWords(["github", "to"]).last ?? "", "새", "트리거: github 뒤 새 유지")

        // ── v3 리뷰 회귀: 활용형/구어 보호 3중 가드 ──
        expect(typeWords(["commit", "goT"]).last ?? "", "했", "Shift 가드: 했 보호")
        expect(typeWords(["game", "wuT"]).last ?? "", "졌", "Shift 가드: 졌 보호")
        expect(typeWords(["the", "rid"]).last ?? "", "걍", "단음절 가드: 걍 보호")
        expect(typeWords(["merge", "gowns"]).last ?? "", "해준", "curated 가드: 해준 보호")
        expect(typeWords(["really", "glacks"]).last ?? "", "힘찬", "curated 가드: 힘찬 보호")
        expect(typeWords(["the", "throck"]).last ?? "", "소개차", "curated 가드: 소개차 보호")
        // veto 우회 override: 희귀 한자어 동형 고빈도 영어
        expect(typeWords(["more", "than"]).last ?? "", "than", "override: 소무 → than")
        expect(typeWords(["back", "when"]).last ?? "", "when", "override: 조두 → when")
        // override 의도적 제외: 흔한 한국어 우선
        expect(typeWords(["what", "did"]).last ?? "", "양", "override 제외: 양 보호")

        // ── v3.1: 실기기 후속 3건 (2026-06-06) ──
        // 자음열 4+ 무맥락 변환 (great이 문장 첫 단어여도)
        expect(type("great").committedText, "great", "v3.1: 무맥락 ㅎㄱㄷㅁㅅ → great")
        // 단 3자(was/are)는 여전히 문맥 필요 — 초성체 보호 우선
        expect(type("was").committedText, "ㅈㅁㄴ", "v3.1: 무맥락 3자는 유지")
        // 4자+ 자음 슬랭은 사전 게이트로 보호
        expect(type("drfd").committedText, "ㅇㄱㄹㅇ", "v3.1: ㅇㄱㄹㅇ 보호")
        expect(type("asdf").committedText, "ㅁㄴㅇㄹ", "v3.1: ㅁㄴㅇㄹ 보호")
        // 내→so, 랙→for (트리거 뒤에서만)
        expect(
            typeWords(["thank", "you", "so", "much", "for", "helping", "me"]).joined(separator: " "),
            "thank you so much for helping me",
            "v3.1: 사용자 실패 문장 풀 변환"
        )
        expect(typeWords(["apple", "so"]).last ?? "", "내", "v3.1: 비트리거(apple) 뒤 내 보호")
        // R3 슬랭 보호: 햏(아햏햏 문화)은 변환 안 됨
        expect(type("gog").committedText, "햏", "R3 보호: 햏 → gog 아님")

        // 조건 11: 멀쩡히 조합된 한글이어도 키가 긴 영어 단어면 영어 (curated only)
        expect(type("entitlement").committedText, "entitlement", "조건11: 두샤시드둣 → entitlement")
        expect(type("visual").committedText, "visual", "조건8/11: 퍄녀미 → visual")
        // 조건 11 가드: 진짜 긴 한국어는 안 건드림 (키 시퀀스가 영어가 아님)
        expect(type("rkatkgkqslek").committedText, "감사합니다", "조건11 가드: 감사합니다 유지")
        expect(type("tkfkdgo").committedText, "사랑해", "조건11 가드: 사랑해 유지")

        // 조건 10: 깨진 자모 고유명사는 MAIN(사전)이 잡음 — moran은 supplement
        expect(type("moran").committedText, "moran", "조건10: ㅡㅐㄱ무 → moran")

        // 슬랭 보호 (R4 제거): 초성체+음절 슬랭은 사전에 없어 변환 안 됨
        expect(type("drfddla").committedText, "ㅇㄱㄹㅇ임", "슬랭 보호: ㅇㄱㄹㅇ임")
        expect(type("dkzzzfd").committedText, "앜ㅋㅋㄹㅇ", "슬랭 보호: 아ㅋㅋㄹㅇ")
        expect(type("gjffdzz").committedText, "헐ㄹㅇㅋㅋ", "슬랭 보호: 헐ㄹㅇㅋㅋ")
        expect(type("sdranjdi").committedText, "ㄴㅇㄱ뭐야", "슬랭 보호: ㄴㅇㄱ뭐야")

        // 백스페이스 후 재변환 루프 방지: 영어 문맥은 커밋텍스트 삭제 시 끊김
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "want" { _ = composer.handleInput(String(ch), client: client) }
            _ = composer.commit(to: client, convertEnglish: true) // want, 문맥 ON
            composer.resetEnglishContext()                         // controller가 backspace 시 호출
            for ch in "to" { _ = composer.handleInput(String(ch), client: client) }
            expect(composer.commit(to: client, convertEnglish: true), "새", "백스페이스 리셋 후 새 유지")
        }

        // 보호 유지: 영어 문맥이 일반 한글을 건드리면 안 됨
        expect(typeWords(["apple", "rkwk"]).last ?? "", "가자", "문맥 룰이 일반 한글 안 건드림")
        expect(typeWords(["lol", "bb"]).last ?? "", "ㅠㅠ", "문맥 + 동일키 ㅠㅠ 보호")

        // Detector unit tests
        expect(EnglishDetector.shouldConvert(units: ["메", "ㅔ", "ㅣ", "ㄷ"], keys: Array("apple")), true, "detector: apple")
        expect(EnglishDetector.shouldConvert(units: ["안", "녕"], keys: Array("dkssud")), false, "detector: no broken jamo")
        expect(EnglishDetector.shouldConvert(units: ["ㅠ", "ㅠ"], keys: Array("bb")), false, "detector: same-key run")
        expect(EnglishDetector.shouldConvert(units: ["ㄴ", "ㅇ", "ㄱ"], keys: Array("sdr")), false, "detector: not a word")
        expect(EnglishDetector.shouldConvert(units: ["ㄷ"], keys: Array("e")), false, "detector: single key")

        // ── WordFrequencyStore (prediction) ──
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory() + "haneul_test_store/word_frequency.json")
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        let store = WordFrequencyStore(fileURL: storeURL)

        // Below threshold (3): no suggestion yet
        store.learn("안녕하세요")
        store.learn("안녕하세요")
        expect(store.suggest(prefix: "안녕") == nil, true, "store: below threshold")
        store.learn("안녕하세요")
        expect(store.suggest(prefix: "안녕") ?? "", "안녕하세요", "store: suggests after 3 commits")
        expect(store.suggest(prefix: "안녕하세") ?? "", "안녕하세요", "store: longer prefix")
        expect(store.suggest(prefix: "안녕하세요") == nil, true, "store: never suggests the prefix itself")

        // Frequency wins
        for _ in 0..<5 { store.learn("안녕히가세요") }
        expect(store.suggest(prefix: "안녕") ?? "", "안녕히가세요", "store: higher frequency wins")

        // Korean-only learning
        store.learn("apple")
        store.learn("안녕ㅋ")
        store.learn("한")          // 1 syllable — below learnable length
        store.learn("오늘저녁에치킨먹을래") // 10 syllables — spaceless sentence, over cap
        expect(store.count(of: "apple"), 0, "store: never learns English")
        expect(store.count(of: "안녕ㅋ"), 0, "store: never learns jamo-mixed")
        expect(store.count(of: "한"), 0, "store: never learns 1-syllable words")
        expect(store.count(of: "오늘저녁에치킨먹을래"), 0, "store: never learns spaceless sentences (>7 syllables)")

        // Non-hangul prefixes never suggest
        expect(store.suggest(prefix: "안녕ㅎ") == nil, true, "store: jamo prefix → no suggestion")
        expect(store.suggest(prefix: "ap") == nil, true, "store: ascii prefix → no suggestion")

        // Persistence roundtrip — and privacy: count==1 units never reach disk
        store.learn("일회성단어")
        store.saveNow()
        let reloaded = WordFrequencyStore(fileURL: storeURL)
        expect(reloaded.count(of: "안녕하세요"), 3, "store: persistence roundtrip")
        expect(reloaded.count(of: "일회성단어"), 0, "store: one-off units never persisted")
        expect(reloaded.suggest(prefix: "안녕") ?? "", "안녕히가세요", "store: suggest after reload")

        // Disk contains only words + counts — no timestamps (PRIVACY.md)
        if let raw = try? String(contentsOf: storeURL, encoding: .utf8) {
            expect(raw.contains("lastUsed"), false, "store: lastUsed never persisted")
        } else {
            expect(false, true, "store: file readable after saveNow")
        }

        // Clean store never creates a file footprint
        let emptyURL = URL(fileURLWithPath: NSTemporaryDirectory() + "haneul_test_store/empty.json")
        let emptyStore = WordFrequencyStore(fileURL: emptyURL)
        emptyStore.saveNow()
        expect(FileManager.default.fileExists(atPath: emptyURL.path), false, "store: no file when nothing learned")

        // deleteAll erases memory + file
        reloaded.deleteAll()
        expect(reloaded.suggest(prefix: "안녕") == nil, true, "store: deleteAll clears suggestions")
        expect(FileManager.default.fileExists(atPath: storeURL.path), false, "store: deleteAll removes file")

        // ── Composer suggestion acceptance (Tab) ──
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) } // 안녕
            expect(composer.currentPreview(), "안녕", "composer: currentPreview")
            composer.acceptSuggestion("안녕하세요", client: client)
            expect(client.marked, "안녕하세요", "composer: accepted suggestion is marked")
            let committed = composer.commit(to: client, convertEnglish: true)
            expect(committed, "안녕하세요", "composer: commit returns accepted word")
            expect(client.committedText, "안녕하세요", "composer: accepted word inserted")
        }

        // Regression (review finding): accepted word + wrong-layout continuation
        // must commit EXACTLY the marked text — never English-convert away
        // the accepted Hangul.
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) }
            composer.acceptSuggestion("안녕하세요", client: client)
            for ch in "mail" { _ = composer.handleInput(String(ch), client: client) }
            let marked = client.marked
            let committed = composer.commit(to: client, convertEnglish: true)
            expect(committed, marked, "regression: commit equals marked text after accept")
            expect(committed.contains("안녕하세요"), true, "regression: accepted word survives conversion")
        }

        // Regression (review finding): backspace after accept peels ONE
        // syllable, not the whole word.
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) }
            composer.acceptSuggestion("안녕하세요", client: client)
            _ = composer.deleteBackward(client: client)
            expect(client.marked, "안녕하세", "regression: backspace peels one syllable after accept")
        }

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

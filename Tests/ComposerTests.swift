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

/// 2026-09-19 (#34): 컨트롤러(`HaneulInputController.handle`)의 키 분배를 그대로
/// 흉내 낸다. `type()`은 모든 키를 `handleInput`에 밀어 넣지만 실제 컨트롤러는
/// `'`를 먼저 `handleApostrophe`로 보내고(단어 내부 문자), 흡수되지 않은
/// 비자모만 active boundary로 처리한다 — 축약형은 이 경로로만 재현된다.
func typeKeyViaController(_ ch: Character, composer: KoreanComposer, client: FakeClient) {
    if Contractions.isApostrophe(ch), composer.handleApostrophe(ch, client: client) { return }
    if KeyboardLayout2Set.jamo(for: ch) != nil {
        _ = composer.handleInput(String(ch), client: client)
        return
    }
    // 흡수되지 않은 비자모 = active boundary. 컨트롤러는 false를 돌려주고
    // 클라이언트가 그 글자를 직접 넣으므로 여기서도 똑같이 기록한다.
    composer.commit(to: client, convertEnglish: true)
    client.insertText(String(ch))
}

/// 위 경로로 한 단어를 치고 active boundary(스페이스)에서 커밋한다.
func typeViaController(_ keys: String, autoEnglish: Bool = true) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    composer.autoEnglishEnabled = autoEnglish
    for ch in keys { typeKeyViaController(ch, composer: composer, client: client) }
    composer.commit(to: client, convertEnglish: true)
    return client
}

/// `typeWords`의 컨트롤러 경로 버전 — 영어 문맥이 축약형을 거쳐 이어지는지 본다.
func typeWordsViaController(_ words: [String]) -> [String] {
    let client = FakeClient()
    let composer = KoreanComposer()
    var committed: [String] = []
    for w in words {
        for ch in w { typeKeyViaController(ch, composer: composer, client: client) }
        committed.append(composer.commit(to: client, convertEnglish: true))
    }
    return committed
}

func runDictionaryProbe(_ wordlistPath: String, _ label: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--probe-kdict", wordlistPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        failures += 1
        print("FAIL \(label): probe launch failed: \(error)")
        return false
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus != 0 {
        failures += 1
        print("FAIL \(label): probe exit \(process.terminationStatus), output=\(output)")
        return false
    }
    return output == "true"
}

// MARK: - 사전 manifest (review-0712 P3-5)

/// `dict_work/dict_manifest.tsv` 한 줄 — 번들 영어 사전 하나의 계약.
struct DictManifestEntry {
    let name: String
    let role: String        // "curated" (curated+broad) | "broad" (broad 전용)
    let minWords: Int
    let sampleWord: String

    var path: String { "Resources/IM/\(name).txt" }
}

/// 런타임(`EnglishDetector`)·이 테스트·검역(`audit_wordlist.sh`)이 공유하는
/// 사전 목록의 **정본**. 예전엔 세 군데가 각자 목록을 들고 있어서
/// `english_sports_geo.txt`(28,360줄)가 런타임에만 있고 테스트·검역에서는
/// 빠져도 아무도 몰랐다. 이제 어긋나면 이 파일의 assertion이 실패한다.
enum DictManifest {
    static let path = "dict_work/dict_manifest.tsv"

    static func load() -> [DictManifestEntry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var entries: [DictManifestEntry] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let cols = line.split(separator: "\t").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4, let minWords = Int(cols[2]) else { continue }
            entries.append(DictManifestEntry(
                name: cols[0], role: cols[1], minWords: minWords, sampleWord: cols[3]
            ))
        }
        return entries
    }
}

// MARK: - Tests

@main
struct ComposerTests {
    static func main() {
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--probe-kdict" {
            KoreanDictionary.wordlistPath = CommandLine.arguments[2]
            print(KoreanDictionary.isLoaded ? "true" : "false")
            return
        }

        // Wordlist: system dict + a temp supplement (no app bundle here).
        // Must be set before the first shouldConvert call (lazy load).
        let supplementPath = NSTemporaryDirectory() + "haneul_test_supplement.txt"
        try? "google\ngithub\n".write(toFile: supplementPath, atomically: true, encoding: .utf8)
        // curatedPaths 격리 검증용 names 픽스처 (broad 전용 — curated 미등록):
        //   goawor(햄잭, clean 6키, 우리말샘 미등재) — R5/R2-clean 절대 금지
        //   zvinci(ㅋ퍄ㅜ챠, 깨짐)                  — MAIN 변환 OK (broad 로드 증명)
        let namesFixturePath = NSTemporaryDirectory() + "haneul_test_names_fixture.txt"
        try? "goawor\nzvinci\n".write(toFile: namesFixturePath, atomically: true, encoding: .utf8)

        // ── 배포 영어 사전 리소스 ──
        // 아래 파일은 모두 필수 번들 리소스이며, 후반에서 존재와
        // 대표 단어를 assertion으로 검증한다.
        let pendingCommon = "Resources/IM/english_common.txt"
        let pendingModern = "Resources/IM/english_modern.txt" // SCOWL — broad 전용
        let pendingNames = "Resources/IM/english_names.txt"
        let pendingNamesExtra = "Resources/IM/english_names_extra.txt"
        let hasCommon = FileManager.default.fileExists(atPath: pendingCommon)
        let hasModern = FileManager.default.fileExists(atPath: pendingModern)
        let hasNames = FileManager.default.fileExists(atPath: pendingNames)
        let hasNamesExtra = FileManager.default.fileExists(atPath: pendingNamesExtra)

        // 실제 번들 사전도 포함 — 테스트는 repo 루트에서 실행됨.
        // (review-0712 P3-5) 목록을 여기 하드코딩하지 않고 정본 manifest에서
        // 읽는다. 예전엔 english_sports_geo.txt가 런타임에만 있고 여기엔 없어서,
        // 28,360줄짜리 사전이 통째로 빠져도 테스트가 통과했다.
        let manifestEntries = DictManifest.load()
        var wordlists = [
            "/usr/share/dict/words",
            supplementPath,
            namesFixturePath, // broad 전용 — 아래 curated에 미등록 (의도)
        ]
        // 화이트리스트 방식(fail-safe): curated로 신뢰할 경로만 명시 등록.
        var curated: Set<String> = [supplementPath]
        for entry in manifestEntries
        where FileManager.default.fileExists(atPath: entry.path) {
            wordlists.append(entry.path)
            if entry.role == "curated" { curated.insert(entry.path) }
        }
        EnglishDetector.wordlistPaths = wordlists
        EnglishDetector.curatedPaths = curated
        // v3 한국어 veto 사전 (우리말샘 추출본, repo 루트 기준)
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"

        let dictGoodPath = NSTemporaryDirectory() + "haneul_kdict_good.txt"
        let dictNoHeaderPath = NSTemporaryDirectory() + "haneul_kdict_no_header.txt"
        let dictMismatchPath = NSTemporaryDirectory() + "haneul_kdict_mismatch.txt"
        try? "# count: 2\n# fixture\n가\n나\n가\n".write(
            toFile: dictGoodPath,
            atomically: true,
            encoding: .utf8
        )
        try? "# fixture\n가\n나\n가\n".write(
            toFile: dictNoHeaderPath,
            atomically: true,
            encoding: .utf8
        )
        try? "# count: 3\n# fixture\n가\n나\n가\n".write(
            toFile: dictMismatchPath,
            atomically: true,
            encoding: .utf8
        )
        expect(runDictionaryProbe(dictGoodPath, "kdict: header OK"), true, "kdict: header OK")
        expect(runDictionaryProbe(dictNoHeaderPath, "kdict: no header"), false, "kdict: no header")
        expect(runDictionaryProbe(dictMismatchPath, "kdict: count mismatch"), false, "kdict: count mismatch")
        expect(
            runDictionaryProbe("Resources/IM/korean_words.txt", "kdict: production wordlist"),
            true,
            "kdict: production wordlist"
        )

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

        // ── AI·게임 산업 단어 (#18) — english_supplement.txt 등재분 ──
        // broad/curated 어느 룰로 잡히든 무맥락 변환돼야 한다.
        expect(type("gemini").committedText, "gemini", "AI: gemini")
        expect(type("deepseek").committedText, "deepseek", "AI: deepseek")
        expect(type("qwen").committedText, "qwen", "AI: qwen")
        expect(type("nemotron").committedText, "nemotron", "AI: nemotron")
        expect(type("llm").committedText, "llm", "AI: llm")
        expect(type("rag").committedText, "rag", "AI: rag (자음열, curated)")
        expect(type("dlss").committedText, "dlss", "게임: dlss")
        expect(type("fsr").committedText, "fsr", "게임: fsr (자음열, curated)")
        expect(type("rtx").committedText, "rtx", "게임: rtx (자음열, curated)")
        expect(type("geforce").committedText, "geforce", "게임: geforce")
        expect(type("vsync").committedText, "vsync", "게임: vsync")
        // gpt(헷): 1음절 약어 화이트리스트로 무맥락 변환
        expect(type("gpt").committedText, "gpt", "gpt 무맥락 변환(standaloneShortWords)")
        // fps: 첫 자음 shift(Fps)는 영어 의도 → 변환(대소문자 보존). 소문자
        // (렌)는 우리말샘 등재라 veto가 보호했으나, 2026-09-19 (#33) S 등급이
        // veto 위에서 잡아 이제 소문자도 변환된다(렌은 일상에서 안 쓰는 말).
        expect(type("Fps").committedText, "Fps", "fps 첫자음shift 변환")
        expect(type("fps").committedText, "fps", "fps 소문자도 S 등급으로 변환 (#33)")
        expect(type("Dlss").committedText, "Dlss", "Dlss 첫자음shift(asdfgzxcv)")
        // qwert 자리(Q=쌍비읍)는 첫자음shift 제외 — 쌍자음 입력 의도 보호
        expect(type("Qfc").committedText, "ㅃㄹㅊ", "qwert 첫자(Q)는 첫자음shift 제외")
        // 한국어 미손상 — 추가 단어가 실존 한국어를 영어로 오변환하지 않는다
        expect(type("rkrh").committedText, "가고", "한국어 가고 보존")
        expect(type("Rk").committedText, "까", "쌍자음 까 보존(첫자음shift 무영향)")

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
        // (2026-06-19) 무맥락 clean 변환 완화 — 며새(auto)도 변환됨
        // (veto통과 + curated + 2음절+). 문장 첫 단어도 영어로.
        expect(
            typeWords(["auto", "mode", "on"]).joined(separator: " "),
            "auto mode on",
            "무맥락 완화: 며새→auto (문장 첫 단어 포함)"
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
        // (2026-06-19) 무맥락 며새→auto 변환 (veto통과 + curated + 2음절+)
        expect(type("auto").committedText, "auto", "무맥락 완화: 며새→auto")

        // R2 호모그래프 보호 (라운드2): 해/내/애는 영어 뒤에서도 한글 유지
        expect(typeWords(["apple", "go"]).last ?? "", "해", "R2 보호: apple 뒤 해 유지 (go 아님)")
        expect(typeWords(["apple", "so"]).last ?? "", "so", "앞 영어: apple 뒤 내 → so (게이트 제거)")
        expect(typeWords(["apple", "do"]).last ?? "", "애", "R2 보호: apple 뒤 애 유지 (do 아님)")
        // (H2) to는 goDoTriggers라 문맥을 넘긴다 → "want to go" (해도 변환됨)
        expect(
            typeWords(["want", "to", "go"]).joined(separator: " "),
            "want to go",
            "H2: want to go — to가 문맥 넘겨 go 변환"
        )
        // R2x 체이닝: 구조적 변환(was)은 다음 단어(great)에 문맥을 넘김
        expect(
            typeWords(["that", "was", "great"]).joined(separator: " "),
            "that was great",
            "체이닝: was → great 연쇄"
        )
        // 앞 영어면 무조건(게이트 제거 2026-06-19): want·github 둘 다 영어 뒤라 새→to
        expect(typeWords(["github", "to"]).last ?? "", "to", "앞 영어: github 뒤 새 → to")

        // ── v3 리뷰 회귀: 활용형/구어 보호 3중 가드 ──
        expect(typeWords(["commit", "goT"]).last ?? "", "했", "Shift 가드: 했 보호")
        expect(typeWords(["game", "wuT"]).last ?? "", "졌", "Shift 가드: 졌 보호")
        expect(typeWords(["the", "rid"]).last ?? "", "rid", "ㅑ 1음절: 걍→rid (the 뒤, 되돌리기 커버)")
        expect(typeWords(["merge", "gowns"]).last ?? "", "해준", "curated 가드: 해준 보호")
        expect(typeWords(["really", "glacks"]).last ?? "", "힘찬", "curated 가드: 힘찬 보호")
        expect(typeWords(["the", "throck"]).last ?? "", "소개차", "curated 가드: 소개차 보호")
        // veto 우회 override: 희귀 한자어 동형 고빈도 영어
        expect(typeWords(["more", "than"]).last ?? "", "than", "override: 소무 → than")
        expect(typeWords(["back", "when"]).last ?? "", "when", "override: 조두 → when")
        // 2026-09-19 (#33): did=양은 T(트리거) 등급 — what/I 같은 트리거 뒤에서만.
        // 트리거가 아닌 영어 뒤("render 양이")는 그대로 보호된다.
        expect(typeWords(["what", "did"]).last ?? "", "did", "T등급: what 양 → did")
        expect(typeWords(["render", "did"]).last ?? "", "양", "T등급: render 양 보호(데이터 양)")

        // ═══ veto 우회 정책 등급 S/C/T (#33, 2026-09-19) ═══
        // 실측: curated 2,999개 중 veto 충돌 13개(완전 차단 6). 공식이 아니라 단어별
        // 등급으로 푼다. 오변환 보호(Shift·트리거 밖·단독)를 변환과 같은 무게로 못 박는다.
        // ── S 단독: 한글형이 사실상 안 쓰이는 희귀어 ──
        expect(type("work").committedText, "work", "S등급: 재가 → work (단독)")
        expect(typeWords(["i", "work"]).last ?? "", "work", "S등급: 문맥에서도 work")
        expect(type("rock").committedText, "rock", "S등급: 개차 → rock")
        expect(type("goal").committedText, "goal", "S등급: 해미 → goal")
        expect(type("Work").committedText, "Work", "S등급: 대문자는 기존대로 변환(째가는 veto 미등재)")
        expect(typeWords(["commit", "goT"]).last ?? "", "했", "등급 공통 가드: Shift(했)는 한국어 의도 → 보호")
        // 리뷰 H-3 회귀 방지: Shift가 자모를 안 바꾸는 키(asdfgzxcv·hjkl·ynuim·b)의 대문자는
        // 화면 한글이 소문자와 같으므로 가드 대상이 아니다 — 종전(23c9e33) 동작과 동일해야 한다.
        expect(typeWords(["i", "Go"]).last ?? "", "Go", "가드 범위: i Go → Go (G는 Shift no-op)")
        expect(typeWords(["want", "to", "Do"]).last ?? "", "Do", "가드 범위: to Do → Do")
        expect(typeWords(["i", "go", "dowN"]).last ?? "", "dowN", "가드 범위: (i go) dowN → dowN — 해는 트리거 뒤에서만 영어가 되므로 앞에 i를 둔다")
        expect(type("worK").committedText, "worK", "가드 범위: worK는 work와 같은 한글(재가) → S 등급 변환")
        expect(type("goaL").committedText, "goaL", "가드 범위: goaL도 S 등급 변환")
        // ── C 문맥: 직전 단어가 영어일 때만 ──
        expect(typeWords(["the", "end"]).last ?? "", "end", "C등급: the 둥 → end")
        expect(type("end").committedText, "둥", "C등급: 단독 둥은 보호")
        expect(typeWords(["you", "got"]).last ?? "", "got", "C등급: you 햇 → got")
        expect(type("got").committedText, "햇", "C등급: 단독 햇은 보호")
        expect(typeWords(["more", "than"]).last ?? "", "than", "C등급: 기존 7개 유지(소무 → than)")
        // ── T 트리거: 흔한 한국어라 지정 단어 뒤에서만 ──
        expect(typeWords(["my", "god"]).last ?? "", "god", "T등급: my 행 → god")
        expect(typeWords(["thank", "god"]).last ?? "", "god", "T등급: thank 행 → god")
        expect(typeWords(["render", "god"]).last ?? "", "행", "T등급: render 행 보호(3행 4열)")
        expect(type("god").committedText, "행", "T등급: 단독 행 보호")
        expect(typeWords(["i", "did"]).last ?? "", "did", "T등급: I 양 → did")
        expect(type("did").committedText, "양", "T등급: 단독 양 보호")
        expect(typeWords(["i", "go"]).last ?? "", "go", "T등급: goDo 흡수 후에도 I 해 → go")
        expect(typeWords(["want", "to", "do"]).last ?? "", "do", "T등급: want to 애 → do 유지(to는 문맥 뒤에서만 영어)")
        expect(typeWords(["render", "go"]).last ?? "", "해", "T등급: render 해 보호 유지")
        // ── 구멍 ①: 굴절형이 curated에 없던 문제 ──
        expect(type("was").committedText, "was", "굴절형: ㅈㅁㄴ → was (curated 등재)")
        expect(type("are").committedText, "are", "굴절형: ㅁㄱㄷ → are")
        expect(typeWords(["how", "are", "you"]).joined(separator: " "), "how are you", "굴절형: how are you 전부 변환")
        // ── 구멍 ②: 자음 시작 2글자 단독 ──
        expect(type("we").committedText, "we", "2글자: ㅈㄷ → we")
        expect(type("at").committedText, "at", "2글자: ㅁㅅ → at")
        expect(type("as").committedText, "as", "2글자: ㅁㄴ → as")
        expect(type("a").committedText, "ㅁ", "2글자: ㅁ 단독은 보호(문맥 전용)")
        expect(type("dd").committedText, "ㅇㅇ", "2글자: 초성체 ㅇㅇ 보호(동일키)")
        expect(type("sd").committedText, "ㄴㅇ", "2글자: 목록에 없는 자음쌍은 유지")
        // ── 구멍 ③: who=좨 1음절 가드 ──
        expect(type("who").committedText, "who", "who: 좨 → who")
        expect(typeWords(["who", "are", "you"]).joined(separator: " "), "who are you", "who: 문맥 체인")
        // ── #35 산업군 단어 (astra 등) ──
        expect(type("astra").committedText, "astra", "#35: ㅁㄴㅅㄱㅁ → astra")
        expect(type("matchmove").committedText, "matchmove", "#35 VFX: matchmove")
        expect(type("nukex").committedText, "nukex", "#35 VFX: nukex")
        expect(type("openexr").committedText, "openexr", "#35 VFX: openexr")
        expect(type("comfyui").committedText, "comfyui", "#35 AI: comfyui")
        expect(type("openrouter").committedText, "openrouter", "#35 AI: openrouter")
        expect(type("roto").committedText, "개새", "#35 VFX: roto는 veto(개새 표제어·구어 슬랭) 보호 — 사전 추가 대상 아님")
        // ── #39 산업군 사전 2차 (2026-09-20) — 개발·금융/크립토·게임·자동차·로보틱스·브랜드/복합어 ──
        // 후보 2,933 → 이미 변환 636 제외 → 검역 후 등재(english_supplement.txt #39 섹션).
        // 구조 예외는 ros·ev 둘뿐(EnglishDetector 선언부 주석 참조).
        expect(type("ros").committedText, "ros", "#39: 갠 → ros (S 등급 — 1음절 clean·veto 미등재라 사전만으론 미도달)")
        expect(type("rOs").committedText, "걘", "#39: rOs=걘(걔는)은 QWERTOP Shift 가드로 보호")
        expect(type("ev").committedText, "ev", "#39: ㄷㅍ → ev (consonantPairShortWords)")
        expect(type("slam").committedText, "slam", "#39 로보틱스: 니므 → slam (R5·supplement)")
        expect(type("etf").committedText, "etf", "#39 금융: ㄷㅅㄹ → etf (R-자음열 3·curated)")
        expect(type("sudo").committedText, "sudo", "#39 개발: 녀애 → sudo (R5)")
        expect(type("kubernetes").committedText, "kubernetes", "#39 개발: kubernetes")
        expect(type("opencv").committedText, "opencv", "#39 복합어: opencv")
        expect(type("macbookpro").committedText, "macbookpro", "#39 복합어: macbookpro")
        expect(type("kpi").committedText, "kpi", "#39 금융: ㅏㅔㅑ → kpi")
        expect(type("btc").committedText, "btc", "#39 크립토: ㅠㅅㅊ → btc")
        expect(type("xbox").committedText, "xbox", "#39 게임: xbox")
        expect(type("ioniq").committedText, "ioniq", "#39 자동차: ioniq")
        // 제외 확인 — 검역에서 걸러 supplement에 넣지 않은 것들은 종전 동작 그대로.
        expect(type("bnb").committedText, "ㅠㅜㅠ", "#39 제외: bnb=ㅠㅜㅠ 우는 이모티콘")
        expect(type("trd").committedText, "ㅅㄱㅇ", "#39 제외: trd=ㅅㄱㅇ 초성체(수고요)")
        expect(type("pvp").committedText, "ㅔ페", "#39 제외: pvp=ㅔ페 카오모지 팰린드롬 가드라 등재해도 변환 불가")
        expect(type("dns").committedText, "운", "#39 제외: dns=운 우리말샘 등재(veto) — 등급 판정은 미결")
        // ── #49 산업군 사전 3차 (2026-09-20) — 의료·교육·여행·K-pop/엔터·헬스/식음료·소비자IT·마케팅/직장·디자인/사진 + 게임 타이틀 붙여쓰기 ──
        // 후보 3,544 → 이미 변환 762 제외 → 검역 후 2,731 등재. 코드 예외 없음(전부 사전 등재만).
        // 단일어 타이틀(overwatch 등)은 원래 되고, 두 단어 이상 붙인 고유명사가 이번 대상.
        expect(type("leagueoflegends").committedText, "leagueoflegends", "#49 게임: 붙여쓴 타이틀 leagueoflegends")
        expect(type("finalfantasy").committedText, "finalfantasy", "#49 게임: finalfantasy")
        expect(type("mariokart").committedText, "mariokart", "#49 게임: mariokart")
        expect(type("koreanair").committedText, "koreanair", "#49 여행: koreanair")
        expect(type("incheon").committedText, "incheon", "#49 여행: incheon")
        expect(type("aespa").committedText, "aespa", "#49 K-pop: aespa")
        expect(type("jimin").committedText, "jimin", "#49 K-pop: 멤버 예명 jimin")
        expect(type("opic").committedText, "opic", "#49 교육: opic")
        expect(type("ozempic").committedText, "ozempic", "#49 의료: ozempic")
        expect(type("americano").committedText, "americano", "#49 식음료: americano")
        expect(type("usbc").committedText, "usbc", "#49 소비자IT: usbc")
        expect(type("crm").committedText, "crm", "#49 마케팅: ㅊㄱㅡ → crm")
        expect(type("figjam").committedText, "figjam", "#49 디자인: 랴허므 → figjam (R5·Tier A 통과)")
        // 제외 확인 — 검역에서 걸러 넣지 않은 것들은 종전 동작 그대로.
        expect(type("nmn").committedText, "ㅜㅡㅜ", "#49 제외: nmn=ㅜㅡㅜ 우는 얼굴 카오모지")
        expect(type("totk").committedText, "새사", "#49 제외: totk=새사 우리말샘 등재(veto)")
        expect(type("gpa").committedText, "헴", "#49 제외: gpa=헴 우리말샘 등재(veto)")

        // ── v3.1: 실기기 후속 3건 (2026-06-06) ──
        // 자음열 4+ 무맥락 변환 (great이 문장 첫 단어여도)
        expect(type("great").committedText, "great", "v3.1: 무맥락 ㅎㄱㄷㅁㅅ → great")
        // 단 3자는 curated에 있을 때만 — broad 전용(vat=ㅍㅁㅅ)은 초성체 보호 우선.
        // (2026-09-19 #33: was/are는 curated에 등재돼 이제 무맥락 변환된다 — 아래 정책 절)
        expect(type("vat").committedText, "ㅍㅁㅅ", "v3.1: 무맥락 3자(broad 전용)는 유지")
        // 4자+ 자음 슬랭은 사전 게이트로 보호
        expect(type("drfd").committedText, "ㅇㄱㄹㅇ", "v3.1: ㅇㄱㄹㅇ 보호")
        expect(type("asdf").committedText, "ㅁㄴㅇㄹ", "v3.1: ㅁㄴㅇㄹ 보호")
        // 내→so, 랙→for (트리거 뒤에서만)
        expect(
            typeWords(["thank", "you", "so", "much", "for", "helping", "me"]).joined(separator: " "),
            "thank you so much for helping me",
            "v3.1: 사용자 실패 문장 풀 변환"
        )
        expect(typeWords(["apple", "so"]).last ?? "", "so", "앞 영어: apple 뒤 내 → so")
        // R3 슬랭 보호: 햏(아햏햏 문화)은 변환 안 됨
        expect(type("gog").committedText, "햏", "R3 보호: 햏 → gog 아님")

        // ── 사전 확장 1단계 (2026-06-10): and + curated 화이트리스트 격리 ──
        // and(뭉): 우리말샘 미등재 + clean 1음절 = 어떤 룰에도 도달 못 하던
        // 구멍. shortWords 등재로 영어 문맥에서만 변환, 무맥락은 보수 유지.
        expect(typeWords(["apples", "and"]).joined(separator: " "), "apples and", "and: 영어 뒤 뭉 → and")
        expect(type("and").committedText, "and", "and: 무맥락 뭉→and (1음절 화이트리스트)")
        expect(type("andcl").committedText, "뭉치", "and: 뭉치 veto 보호")
        expect(typeWords(["want", "andcl"]).last ?? "", "뭉치", "and: 영어 문맥서도 뭉치 보호")
        expect(type("andzmf").committedText, "뭉클", "and: 뭉클 veto 보호")
        // and는 트리거 게이트 없음(뭉이 실존 한국어가 아니라서) — 비트리거
        // 영어(apples) 뒤에서도 발동. 단 화이트리스트-only 변환이므로 다음
        // 단어에 영어 문맥을 넘기지 않는다 (KoreanComposer whitelistOnly).
        expect(
            typeWords(["apples", "and", "vat"]).joined(separator: " "),
            "apples and ㅍㅁㅅ",
            "and: 문맥 비전달 (뒤 vat는 ㅍㅁㅅ 유지 — 2026-09-19 was가 curated에 들어가 예시 교체)"
        )

        // curatedPaths 격리 보증: broad 전용 파일(names 픽스처)의 clean 6키+
        // 단어는 R5(무맥락)·R2-clean(문맥) 어디서도 변환되지 않는다.
        expect(type("goawor").committedText, "햄잭", "격리: broad 전용 goawor(햄잭) 무맥락 유지")
        expect(typeWords(["the", "goawor"]).last ?? "", "햄잭", "격리: broad 전용 goawor 문맥서도 유지")
        // 같은 픽스처의 깨진 단어는 MAIN으로 변환 — broad 로드 자체는 증명
        expect(type("zvinci").committedText, "zvinci", "격리: 같은 픽스처 zvinci(깨짐)는 MAIN 변환")

        // ═══ 배포 필수 영어 사전·대표 단어 검증 ═══
        // 사전 파일과 대표 단어는 배포 계약이므로 누락 시 테스트를 실패시킨다.
        func wordsInFile(_ path: String) -> Set<String> {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
            return Set(
                content.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            )
        }
        expect(hasCommon, true, "배포 필수 리소스: english_common.txt 존재")
        expect(hasModern, true, "배포 필수 리소스: english_modern.txt 존재")
        expect(hasNames, true, "배포 필수 리소스: english_names.txt 존재")
        expect(hasNamesExtra, true, "배포 필수 리소스: english_names_extra.txt 존재")

        // ── 사전 manifest 정합성 (review-0712 P3-5) ──
        // 런타임·테스트·검역이 같은 목록을 보는지 확인한다. manifest만 고치면
        // 세 곳이 함께 따라오고, 어긋나면 여기서 걸린다.
        expect(manifestEntries.isEmpty, false, "manifest: \(DictManifest.path) 로드")
        expect(
            manifestEntries.map(\.name).joined(separator: ","),
            EnglishDetector.bundledWordlistNames.joined(separator: ","),
            "manifest: 런타임 wordlistPaths 목록과 일치"
        )
        expect(
            manifestEntries.filter { $0.role == "curated" }.map(\.name).joined(separator: ","),
            EnglishDetector.curatedWordlistNames.joined(separator: ","),
            "manifest: 런타임 curated 역할과 일치"
        )
        for entry in manifestEntries {
            let words = wordsInFile(entry.path)
            expect(words.isEmpty, false, "manifest: \(entry.name).txt 존재·비어있지 않음")
            expect(
                words.count >= entry.minWords, true,
                "manifest: \(entry.name) 최소 \(entry.minWords)단어 (실제 \(words.count))"
            )
            expect(
                words.contains(entry.sampleWord), true,
                "manifest: \(entry.name) 대표어 '\(entry.sampleWord)'"
            )
            // ── 2026-09-20 (#41, 리뷰 F-3): 로더가 못 싣는 줄·중복 줄 금지 ──
            // EnglishDetector.loadWords는 비알파벳이 섞인 줄을 조용히 버리고(mp3·mp4가
            // 그렇게 영원히 무효였다) Set이라 중복(email·keyboard)도 조용히 삼킨다.
            // "등재했으니 변환된다"는 착각과 검역 수치 어긋남을 막기 위해 모든 번들
            // 사전의 비주석·비공백 줄이 로더 필터(소문자 a-z만, 3자+ — audit_wordlist.sh의
            // 정규화 ^[a-z]{3,}$와 같은 기준)를 만족하고 중복이 없어야 한다.
            let rawLines = (try? String(contentsOfFile: entry.path, encoding: .utf8))?
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") } ?? []
            let malformed = rawLines.filter { line in
                line.count < 3 || !line.unicodeScalars.allSatisfy { (0x61...0x7A).contains($0.value) }
            }
            expect(
                malformed.count, 0,
                "manifest: \(entry.name) 로더가 못 싣는 줄 0개 (실제 \(malformed.prefix(5)))"
            )
            expect(
                rawLines.count - words.count, 0,
                "manifest: \(entry.name) 중복 줄 0개 (실제 \(rawLines.count - words.count))"
            )
        }
        if hasCommon {
            let commonSet = wordsInFile(pendingCommon)
            // city(챠쇼)/with(쟈소): clean 한글 — 문맥(R2-clean)도, 무맥락도
            // 변환 (2026-06-19 R5 "멀쩡한 한글 2음절+" 완화).
            for (keys, hangul) in [("city", "챠쇼"), ("with", "쟈소")] {
                if commonSet.contains(keys) {
                    expect(typeWords(["the", keys]).last ?? "", keys, "the 뒤 \(hangul) → \(keys)")
                    expect(type(keys).committedText, keys, "무맥락 완화: \(hangul)→\(keys) (2음절+)")
                } else {
                    expect(false, true, "english_common 대표 단어: \(keys)")
                }
            }
        } else {
            // 필수 리소스 누락은 위 assertion에서 실패한다.
        }
        // playlist(ㅔㅣ묘ㅣㅑㄴㅅ)·selfie: 깨진 형 현대어 — NGSL엔 없고
        // SCOWL(english_modern, broad 전용)이 관할. 합집합으로 확인.
        if hasCommon || hasModern {
            // supplement 포함: dedup 파이프라인이 supplement 기존재 단어를
            // modern에서 제거하므로(selfie), 합집합으로 검증한다.
            let modernUnion = wordsInFile(pendingCommon)
                .union(wordsInFile(pendingModern))
                .union(wordsInFile("Resources/IM/english_supplement.txt"))
            for w in ["playlist", "selfie"] {
                if modernUnion.contains(w) {
                    expect(type(w).committedText, w, "\(w)(깨짐, 현대어) 무맥락 변환")
                } else {
                    expect(false, true, "현대 영어 대표 단어: \(w)")
                }
            }
        } else {
            // 필수 리소스 누락은 위 assertion에서 실패한다.
        }
        if hasNamesExtra {
            let extraSet = wordsInFile(pendingNamesExtra)
            // davinci(ㅇㅁ퍄ㅜ챠)/ronaldo(개ㅜ미애): 깨진 인명 — 무맥락 MAIN 변환
            for name in ["davinci", "ronaldo"] {
                if extraSet.contains(name) {
                    expect(type(name).committedText, name, "\(name)(깨짐 인명) 무맥락 변환")
                } else {
                    expect(false, true, "english_names_extra 대표 인명: \(name)")
                }
            }
        } else {
            // 필수 리소스 누락은 위 assertion에서 실패한다.
        }
        if hasNames {
            let namesSet = wordsInFile(pendingNames)
            // garcia(ㅎㅁㄱ챰): 깨진 성씨 — 무맥락 MAIN 변환 (Census top-10)
            if namesSet.contains("garcia") {
                expect(type("garcia").committedText, "garcia", "garcia(깨짐 성씨) 무맥락 변환")
            } else {
                expect(false, true, "english_names 대표 성씨: garcia")
            }
        } else {
            // 필수 리소스 누락은 위 assertion에서 실패한다.
        }

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

        // for(랙) un-gated (2026-06-19): 아무 영어 단어 뒤 → for 무조건
        expect(EnglishDetector.shouldConvert(units: ["랙"], keys: Array("for"), previousEnglishWord: "good"), true, "for: good 뒤 변환")
        expect(EnglishDetector.shouldConvert(units: ["랙"], keys: Array("for"), previousEnglishWord: "greeting"), true, "for: greeting 뒤 변환")
        expect(EnglishDetector.shouldConvert(units: ["랙"], keys: Array("for"), previousEnglishWord: "you"), true, "for: you 뒤(기존도 유지)")
        expect(EnglishDetector.shouldConvert(units: ["랙"], keys: Array("for"), previousEnglishWord: nil), false, "for: 무맥락은 랙 유지(한글 뒤·문장 첫)")
        // 앞 영어면 무조건(게이트 제거 2026-06-19): github·want 둘 다 영어 뒤라 변환
        expect(EnglishDetector.shouldConvert(units: ["새"], keys: Array("to"), previousEnglishWord: "github"), true, "to: github 뒤 새 → to (앞 영어)")
        expect(EnglishDetector.shouldConvert(units: ["새"], keys: Array("to"), previousEnglishWord: "want"), true, "to: want 뒤 변환")

        // 무맥락 멀쩡한 한글 변환 완화 (2026-06-19): veto통과 + curated + 2음절+
        expect(EnglishDetector.shouldConvert(units: ["챠","쇼"], keys: Array("city")), true, "무맥락: 챠쇼→city")
        expect(EnglishDetector.shouldConvert(units: ["재","깅"], keys: Array("world")), true, "무맥락: 재깅→world")
        expect(EnglishDetector.shouldConvert(units: ["퍄","녀","미"], keys: Array("visual")), true, "무맥락: 퍄녀미→visual(기존 R5 회귀)")
        expect(EnglishDetector.shouldConvert(units: ["걍"], keys: Array("rid")), true, "무맥락: 걍→rid (ㅑ 1음절, 되돌리기 커버)")
        expect(EnglishDetector.shouldConvert(units: ["모","든"], keys: Array("ahems")), false, "무맥락: 모든 veto 보호")

        // and(뭉) 무맥락 단독 변환 (2026-06-19 standaloneShortWords) — 1음절 구멍
        expect(EnglishDetector.shouldConvert(units: ["뭉"], keys: Array("and")), true, "무맥락: 뭉→and 단독")
        expect(EnglishDetector.shouldConvert(units: ["뭉"], keys: Array("and"), previousEnglishWord: "jane"), true, "영어 사이: jane 뭉 → and")
        // 걍(rid)은 standaloneShortWords 아니지만 ㅑ 1음절 룰로 변환됨(되돌리기 커버)
        expect(EnglishDetector.shouldConvert(units: ["걍"], keys: Array("rid")), true, "걍→rid (ㅑ 1음절)")

        // shift+space 되돌리기용 lastConversion 기록·리셋 (2026-06-19, ㉠ 직후만)
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "and" { _ = composer.handleInput(String(ch), client: client) } // 뭉
            _ = composer.commit(to: client, convertEnglish: true) // 뭉 → and
            expect(composer.lastConversion?.hangul ?? "", "뭉", "되돌리기: lastConversion 한글=뭉")
            expect(composer.lastConversion?.english ?? "", "and", "되돌리기: lastConversion 영어=and")
            _ = composer.handleInput("d", client: client) // 다음 글자 입력 → 리셋
            expect(composer.lastConversion == nil, true, "되돌리기: 다음 입력 시 lastConversion 리셋")
        }
        // 한국어로 commit되면 lastConversion 안 남음 (되돌릴 영어가 없음)
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) } // 안녕
            _ = composer.commit(to: client, convertEnglish: true) // 한글 그대로
            expect(composer.lastConversion == nil, true, "되돌리기: 한글 commit은 기록 안 함")
        }

        // B·C·D (2026-06-19): red 자음3 + ㅑ1음절 + cyan
        expect(EnglishDetector.shouldConvert(units: ["ㄱ","ㄷ","ㅇ"], keys: Array("red")), true, "자음3: ㄱㄷㅇ→red")
        expect(EnglishDetector.shouldConvert(units: ["먕"], keys: Array("aid")), true, "ㅑ1음절: 먕→aid")
        expect(EnglishDetector.shouldConvert(units: ["먁"], keys: Array("air")), true, "ㅑ1음절: 먁→air")
        expect(EnglishDetector.shouldConvert(units: ["향"], keys: Array("gid")), false, "ㅑ1음절: 향(veto) 보호")
        expect(EnglishDetector.shouldConvert(units: ["쵸","무"], keys: Array("cyan")), true, "무맥락: 쵸무→cyan")

        // 해(go)/애(do) 트리거 게이트 + 모음먼저+자음 약어 (2026-06-19)
        expect(EnglishDetector.shouldConvert(units: ["해"], keys: Array("go"), previousEnglishWord: "i"), true, "go: I 뒤 해→go")
        expect(EnglishDetector.shouldConvert(units: ["해"], keys: Array("go"), previousEnglishWord: "to"), true, "go: to 뒤 해→go")
        expect(EnglishDetector.shouldConvert(units: ["애"], keys: Array("do"), previousEnglishWord: "let"), true, "do: let 뒤 애→do")
        expect(EnglishDetector.shouldConvert(units: ["해"], keys: Array("go"), previousEnglishWord: "render"), false, "go: render(비트리거) 뒤 해 보호")
        expect(EnglishDetector.shouldConvert(units: ["해"], keys: Array("go")), false, "go: 무맥락 해 보호")
        expect(EnglishDetector.shouldConvert(units: ["ㅣ","ㅎ"], keys: Array("lg")), true, "모음먼저+자음: ㅣㅎ→lg")
        expect(EnglishDetector.shouldConvert(units: ["ㅔ","ㅇ"], keys: Array("pd")), true, "모음먼저+자음: ㅔㅇ→pd")

        // (M1) shift+space 되돌리기 좌표 로직 단위테스트 (순수함수 resolveToggle)
        let t1 = KoreanComposer.resolveToggle(before: "and ", english: "and", hangul: "뭉", atDocStart: true)
        expect(t1?.text ?? "", "뭉", "resolveToggle: and→뭉 토글")
        expect((t1?.replaceLen ?? -1) == 3 && (t1?.offsetFromEnd ?? -1) == 4, true, "resolveToggle: 교체 3글자·커서서 4")
        expect(KoreanComposer.resolveToggle(before: "brand ", english: "and", hangul: "뭉", atDocStart: true) == nil, true, "resolveToggle: brand의 끝 and = 좌측경계 위반 nil")
        expect(KoreanComposer.resolveToggle(before: "뭉 ", english: "and", hangul: "뭉", atDocStart: true)?.text ?? "", "and", "resolveToggle: 뭉→and 역토글")
        expect(KoreanComposer.resolveToggle(before: "xyz ", english: "and", hangul: "뭉", atDocStart: true) == nil, true, "resolveToggle: 매칭 실패 nil")
        expect(KoreanComposer.resolveToggle(before: "and ", english: "and", hangul: "뭉", atDocStart: false) == nil, true, "resolveToggle: 읽기경계 붙음+문서시작 아님 → 안전 nil")
        expect(KoreanComposer.resolveToggle(before: "go and ", english: "and", hangul: "뭉", atDocStart: false)?.text ?? "", "뭉", "resolveToggle: 'go and ' 공백경계 → 뭉")
        // (낱자모 끝 버그, 2026-06-20) hangul이 낱자모로 끝나는 단어(apple→"메ㅔㅣㄷ",
        // verona 등)도 양방향 토글돼야 한다 — isWordChar가 완성형(가–힣)만 인정하던
        // 탓에 trailing이 낱자모 "ㅔㅣㄷ"를 먹어 길이 매칭이 깨졌다(apple·verona는
        // 스페이스가 샜고, tough·google은 완성형 끝이라 멀쩡했다).
        expect(KoreanComposer.resolveToggle(before: "apple ", english: "apple", hangul: "메ㅔㅣㄷ", atDocStart: true)?.text ?? "", "메ㅔㅣㄷ", "resolveToggle: apple→메ㅔㅣㄷ 정토글(낱자모 끝)")
        expect(KoreanComposer.resolveToggle(before: "메ㅔㅣㄷ ", english: "apple", hangul: "메ㅔㅣㄷ", atDocStart: true)?.text ?? "", "apple", "resolveToggle: 메ㅔㅣㄷ→apple 역토글(낱자모 끝 — 이게 버그였음)")
        expect((KoreanComposer.resolveToggle(before: "메ㅔㅣㄷ ", english: "apple", hangul: "메ㅔㅣㄷ", atDocStart: true)?.offsetFromEnd ?? -1) == 5, true, "resolveToggle: 메ㅔㅣㄷ 역토글 커서 오프셋 5(낱자모4+공백1)")

        // (T1/T2, #30) 터미널류 되돌리기 불가 판정 — 아래 수치는 진단 빌드 실측값이다
        // (Chrome: selLoc 4↔5·읽기 정상 / Terminal.app: selLoc 80 고정·읽기 정상이나
        // 교체 무시 / Ghostty: selLoc 0·attributedSubstring nil).
        expect(KoreanComposer.toggleUnsupported(cursorLocation: 0, didReadText: false), true, "toggleUnsupported: Ghostty(커서0+읽기nil) → 미지원")
        expect(KoreanComposer.toggleUnsupported(cursorLocation: 0, didReadText: true), true, "toggleUnsupported: 변환 직후인데 커서가 문서 맨 앞 = 거짓 보고 → 미지원")
        expect(KoreanComposer.toggleUnsupported(cursorLocation: 80, didReadText: false), true, "toggleUnsupported: 커서는 알지만 앞 글자를 못 읽음 → 미지원")
        expect(KoreanComposer.toggleUnsupported(cursorLocation: 80, didReadText: true), false, "toggleUnsupported: Terminal.app/Chrome(읽기 정상) → 여기선 지원으로 보고 교체까지 시도")
        expect(KoreanComposer.toggleUnsupported(cursorLocation: 5, didReadText: true), false, "toggleUnsupported: Chrome 정상 케이스")

        expect(KoreanComposer.toggleWasRejected(textAtReplacement: "spoon", previousText: "spoon"), true, "toggleWasRejected: Terminal.app — 교체 자리에 옛 글자 그대로 → 거부")
        expect(KoreanComposer.toggleWasRejected(textAtReplacement: "묘ㅐㅜ", previousText: "spoon"), false, "toggleWasRejected: Chrome — 새 글자로 바뀜 → 반영됨")
        expect(KoreanComposer.toggleWasRejected(textAtReplacement: nil, previousText: "spoon"), false, "toggleWasRejected: 재확인을 못 읽으면 판정 불가 → 성공 취급(정상 앱 회귀 방지)")
        expect(KoreanComposer.toggleWasRejected(textAtReplacement: "", previousText: "spoon"), false, "toggleWasRejected: 빈 문자열은 옛 글자와 다름 → 거부 아님")

        // 약어 무맥락 변환 (standaloneShortWords, 2026-06-20)
        expect(EnglishDetector.shouldConvert(units: ["ㄷ","ㄴ","ㅊ"], keys: Array("esc")), true, "약어: esc(ㄷㄴㅊ)")
        expect(EnglishDetector.shouldConvert(units: ["ㅕ","ㄹ","ㅊ"], keys: Array("ufc")), true, "약어: ufc(ㅕㄹㅊ)")
        expect(EnglishDetector.shouldConvert(units: ["ㅔ","ㄴ","ㅎ"], keys: Array("psg")), true, "약어: psg(ㅔㄴㅎ)")
        expect(EnglishDetector.shouldConvert(units: ["ㅍ","ㅁ","ㄱ"], keys: Array("var")), true, "약어: var(ㅍㅁㄱ)")

        // ═══ 설치·제거 결정 로직 (review-0712 P3-8) ═══
        // 파일을 실제로 옮기거나 지우지 않고 "무엇을 결정하는가"만 검증한다.
        // 리뷰가 잡은 P2 두 건이 바로 이 판단들에서 났는데, 예전엔 컴파일만
        // 되고 행동 테스트가 없어서 213개 통과 상태로 숨어 있었다.

        // ── 앱 이동: 목적지는 항상 고정 이름 (P2-1) ──
        expect(
            AppMoveDecision.destinationURL().path, "/Applications/HaneulKeyboard.app",
            "앱 이동: 목적지 파일명 고정"
        )
        expect(
            AppMoveDecision.destinationURL(applicationsDir: "/tmp/apps").path,
            "/tmp/apps/HaneulKeyboard.app", "앱 이동: 목적지 디렉터리 반영"
        )

        // ── 앱 이동: 이미 제자리인가 ──
        expect(
            AppMoveDecision.isAlreadyInPlace(bundlePath: "/Applications/HaneulKeyboard.app"),
            true, "앱 이동: /Applications 안이면 이동 안 함"
        )
        expect(
            AppMoveDecision.isAlreadyInPlace(bundlePath: "/Applications/Renamed.app"),
            true, "앱 이동: /Applications 안이면 이름이 달라도 이동 안 함"
        )
        expect(
            AppMoveDecision.isAlreadyInPlace(bundlePath: "/Users/x/Downloads/HaneulKeyboard.app"),
            false, "앱 이동: 다운로드 폴더는 이동 대상"
        )
        expect(
            AppMoveDecision.isAlreadyInPlace(
                bundlePath: "/private/var/folders/ab/AppTranslocation/X/d/HaneulKeyboard.app"
            ),
            false, "앱 이동: translocated 임시본은 이동 대상"
        )
        expect(
            AppMoveDecision.isAlreadyInPlace(bundlePath: "/ApplicationsBackup/HaneulKeyboard.app"),
            false, "앱 이동: /ApplicationsBackup은 제자리가 아님(접두어 함정)"
        )

        // ── 앱 이동: 목적지를 덮어써도 되는가 (P2-1 회귀 방지) ──
        expect(
            AppMoveDecision.canReplaceDestination(
                destinationBundleID: "com.hyunjincho.haneulkeyboard", isSameTeamSigned: true
            ),
            true, "앱 이동: 우리 앱 + 같은 Team → 교체 허용"
        )
        expect(
            AppMoveDecision.canReplaceDestination(
                destinationBundleID: "com.someone.other", isSameTeamSigned: true
            ),
            false, "앱 이동: 관계없는 앱은 서명이 유효해도 교체 금지"
        )
        expect(
            AppMoveDecision.canReplaceDestination(
                destinationBundleID: "com.hyunjincho.haneulkeyboard", isSameTeamSigned: false
            ),
            false, "앱 이동: bundle ID가 같아도 Team이 다르면 교체 금지"
        )
        expect(
            AppMoveDecision.canReplaceDestination(destinationBundleID: nil, isSameTeamSigned: true),
            false, "앱 이동: bundle ID를 못 읽으면 교체 금지"
        )

        // ── 전체 제거: 메인 앱을 지워도 되는가 (P2-2 회귀 방지) ──
        expect(
            UninstallDecision.shouldRemoveMainApp(removedIMEBundle: true),
            true, "제거: IME 삭제 성공 → 메인 앱도 삭제"
        )
        expect(
            UninstallDecision.shouldRemoveMainApp(removedIMEBundle: false),
            false, "제거: IME 삭제 실패 → 메인 앱 보존(재시도 수단)"
        )

        // ── 전체 제거: 결과 판정과 문구 ──
        func outcome(
            killed: Bool = true, ime: Bool = true, mainApp: Bool = true, kept: Bool = false,
            ls: Bool = true, defaults: Bool = true, picker: Bool = false
        ) -> UninstallOutcome {
            UninstallOutcome(
                killedProcess: killed, removedIMEBundle: ime, removedMainApp: mainApp,
                keptMainAppForRetry: kept, unregisteredLS: ls,
                clearedUserDefaults: defaults, stillEnabledInPicker: picker
            )
        }

        let allOK = outcome()
        expect(allOK.fullyRemoved, true, "제거 결과: 전 단계 성공이면 fullyRemoved")
        expect(allOK.statusText.contains("완료."), true, "제거 결과: 완료 문구")

        // 관리자 암호창 취소 → IME가 남음 → 메인 앱 보존 + 재시도 안내
        let adminCancelled = outcome(ime: false, mainApp: false, kept: true)
        expect(adminCancelled.fullyRemoved, false, "제거 결과: IME 삭제 실패면 완료 아님")
        expect(
            adminCancelled.statusText.contains("다시 실행"), true,
            "제거 결과: 재시도 안내 문구"
        )
        expect(
            adminCancelled.statusText.contains("건너뜀(재시도용 보존)"), true,
            "제거 결과: 메인 앱 보존을 그대로 표시"
        )
        expect(
            adminCancelled.statusText.contains("완료."), false,
            "제거 결과: 실패했는데 완료라고 말하지 않음"
        )

        // 입력 소스가 picker에 남아있음 → 시스템 설정 안내
        let stillEnabled = outcome(picker: true)
        expect(stillEnabled.fullyRemoved, false, "제거 결과: picker에 남으면 완료 아님")
        expect(
            stillEnabled.statusText.contains("시스템 설정"), true,
            "제거 결과: picker 정리 안내"
        )

        // LaunchServices 등록 해제 실패 → 부분 실패로 정직하게 보고
        let lsFailed = outcome(ls: false)
        expect(lsFailed.fullyRemoved, false, "제거 결과: LS 등록 해제 실패면 완료 아님")
        expect(
            lsFailed.statusText.contains("완료."), false,
            "제거 결과: LS 실패 시 완료 문구 없음"
        )
        expect(
            lsFailed.statusText.contains("일부 단계가 실패"), true,
            "제거 결과: 부분 실패 안내"
        )

        // 설정 초기화 실패도 동일하게 완료로 처리하지 않는다
        let defaultsFailed = outcome(defaults: false)
        expect(defaultsFailed.fullyRemoved, false, "제거 결과: 설정 초기화 실패면 완료 아님")

        // ═══ 앱 삭제 ↔ IME 연동: 자기 정리 판단 (#32, 2026-09-19) ═══
        // 파일을 지우지 않고 "지워도 되는가"만 검증한다. 오탐(앱이 살아 있는데 IME가
        // 사라짐)이 가장 나쁜 결과라 보수적인 쪽으로 못 박는다.

        // ── 휴지통 판정: 구성요소 정확 일치 ──
        expect(OrphanDecision.isInTrash("/Users/x/.Trash/HaneulKeyboard.app"), true, "연동: ~/.Trash 안")
        expect(OrphanDecision.isInTrash("/Volumes/Ext/.Trashes/501/HaneulKeyboard.app"), true, "연동: 외장 .Trashes 안")
        expect(OrphanDecision.isInTrash("/Applications/HaneulKeyboard.app"), false, "연동: /Applications는 휴지통 아님")
        expect(OrphanDecision.isInTrash("/Users/x/Trash-like/HaneulKeyboard.app"), false, "연동: 비슷한 폴더명(접두어 함정)은 휴지통 아님")
        expect(OrphanDecision.isInTrash("/Users/x/.Trash"), true, "연동: 휴지통 자체")

        // ── 관찰 요약: 실재하는 경로만 센다 ──
        let liveApp = "/Applications/HaneulKeyboard.app"
        let trashedApp = "/Users/x/.Trash/HaneulKeyboard.app"
        let stale = "/Users/x/Downloads/HaneulKeyboard.app"   // LS 캐시엔 있지만 디스크엔 없음
        expect(
            OrphanDecision.classify(candidatePaths: [stale, trashedApp, liveApp]) { $0 != stale } == .present,
            true, "연동: 휴지통 밖 복사본이 하나라도 살아 있으면 present (업데이트 중 옛 번들이 휴지통에 있어도)"
        )
        expect(
            OrphanDecision.classify(candidatePaths: [stale, trashedApp]) { $0 != stale } == .trashed,
            true, "연동: 살아 있는 게 휴지통 사본뿐이면 trashed"
        )
        expect(
            OrphanDecision.classify(candidatePaths: [stale, liveApp]) { _ in false } == .missing,
            true, "연동: 아무것도 실재하지 않으면 missing (LS 캐시 잔재는 무시)"
        )
        expect(
            OrphanDecision.classify(candidatePaths: []) { _ in true } == .missing,
            true, "연동: 후보 자체가 없으면 missing"
        )

        // ── 휴지통 사본 인정: bundle ID + 기록된 inode ──
        expect(OrphanDecision.acceptsTrashedCopy(bundleIDMatches: true, recordedFileID: 42, candidateFileID: 42), true, "연동: 같은 inode의 우리 앱 사본은 인정")
        expect(OrphanDecision.acceptsTrashedCopy(bundleIDMatches: true, recordedFileID: 42, candidateFileID: 7), false, "연동: inode가 다른 옛 버전 사본은 무시(리뷰 H-1)")
        expect(OrphanDecision.acceptsTrashedCopy(bundleIDMatches: true, recordedFileID: nil, candidateFileID: 7), true, "연동: 기록이 없으면 bundle ID만으로 인정")
        expect(OrphanDecision.acceptsTrashedCopy(bundleIDMatches: false, recordedFileID: nil, candidateFileID: nil), false, "연동: bundle ID가 다르면 이름이 같아도 무시")

        // ── 2026-09-20 (#47, 리뷰 F-1): LaunchServices 후보의 휴지통 경로도 같은 inode 검사를 거친다 ──
        let oldTrashedCopy = "/Users/x/.Trash/HaneulKeyboard 옛버전.app"   // inode 불일치 → accept false
        let filtered = OrphanDecision.filterTrashedCandidates([liveApp, trashedApp, oldTrashedCopy]) { $0 == trashedApp }
        expect(filtered.joined(separator: "|"), [liveApp, trashedApp].joined(separator: "|"), "연동: 휴지통 밖은 그대로, 휴지통 안은 accept 통과분만 남는다")
        expect(
            OrphanDecision.filterTrashedCandidates([liveApp, oldTrashedCopy]) { _ in false }.joined(separator: "|"),
            liveApp, "연동: accept가 전부 거부해도 휴지통 밖 경로는 영향 없음"
        )
        expect(
            OrphanDecision.classify(candidatePaths: OrphanDecision.filterTrashedCandidates([stale, oldTrashedCopy]) { _ in false }) { $0 != stale } == .missing,
            true, "연동: 기각된 옛 사본만 남으면 trashed(2분)가 아니라 missing(30분 유예)"
        )
        expect(
            OrphanDecision.classify(candidatePaths: OrphanDecision.filterTrashedCandidates([stale, trashedApp]) { $0 == trashedApp }) { $0 != stale } == .trashed,
            true, "연동: inode가 맞는 휴지통 사본은 종전대로 trashed"
        )

        // ── 정리 실행 판단: 어떤 관찰도 한 번으로는 정리하지 않는다 (리뷰 B-1) ──
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func decide(_ p: OrphanDecision.AppPresence, prev: Date?, after: TimeInterval) -> Bool {
            OrphanDecision.shouldSelfRemove(current: p, previousAbsentAt: prev, now: t0.addingTimeInterval(after),
                                            trashedInterval: 120, missingInterval: 1800)
        }
        expect(decide(.present, prev: t0, after: 9_999), false, "연동: present면 이전 관찰과 무관하게 정리 안 함")
        expect(decide(.trashed, prev: nil, after: 0), false, "연동: 휴지통 첫 관찰은 대기(제자리에 놓기 유예)")
        expect(decide(.trashed, prev: t0, after: 119), false, "연동: 휴지통 두 번째가 유예 미만이면 대기")
        expect(decide(.trashed, prev: t0, after: 120), true, "연동: 휴지통 두 번째가 유예 이상이면 정리")
        expect(decide(.missing, prev: nil, after: 0), false, "연동: missing 첫 관찰은 대기(앱 교체·볼륨 마운트 오탐 방지)")
        expect(decide(.missing, prev: t0, after: 1799), false, "연동: missing 두 번째가 간격 미만이면 아직 대기")
        expect(decide(.missing, prev: t0, after: 1800), true, "연동: missing 두 번째가 간격 이상이면 정리")
        expect(decide(.missing, prev: t0, after: 120), false, "연동: 휴지통을 비워 missing이 되면 긴 유예를 다시 요구")
        expect(decide(.trashed, prev: t0, after: 120), true, "연동: missing 뒤 trashed로 바뀌어도 부재 관찰은 이어 센다")

        // ── 번들 삭제 허용 범위: 사용자 도메인만 ──
        let userIM = "/Users/x/Library/Input Methods"
        expect(
            OrphanDecision.mayDeleteBundle(bundlePath: "/Users/x/Library/Input Methods/HaneulKeyboardIM.app", userInputMethodsDir: userIM),
            true, "연동: ~/Library/Input Methods 설치본은 삭제 가능"
        )
        expect(
            OrphanDecision.mayDeleteBundle(bundlePath: "/Library/Input Methods/HaneulKeyboardIM.app", userInputMethodsDir: userIM),
            false, "연동: 시스템 도메인(root 소유)은 삭제 대신 비활성만"
        )
        expect(
            OrphanDecision.mayDeleteBundle(bundlePath: "/Users/x/Library/Input Methods2/HaneulKeyboardIM.app", userInputMethodsDir: userIM),
            false, "연동: 접두어 함정 폴더는 삭제 불가"
        )
        expect(
            OrphanDecision.mayDeleteBundle(bundlePath: "/Users/x/Library/Developer/Xcode/DerivedData/X/Build/Products/Release/HaneulKeyboardIM.app", userInputMethodsDir: userIM),
            false, "연동: 개발 빌드 경로는 삭제 불가"
        )


        // ── 2026-09-19 (#34) 아포스트로피 축약형 ────────────────────────
        // 예전엔 `'`(keyCode 39)가 active boundary였다: `ㅑ`만 i로 변환되고
        // `'`가 삽입된 뒤 `m`은 `ㅡ` 한 글자로 남아 화면에 `i'ㅡ`가 됐다
        // (하네스 실측 32개 전부 실패). 이제 조합 중의 `'`는 단어 내부 문자로
        // 흡수되고(handleApostrophe), 커밋 때 통째로 판정된다.

        // (a) 축약형 소사전 — 목록 전체를 실제 키 시뮬레이션으로 검증.
        let contractionCases = [
            "i'm", "i'll", "i've", "i'd",
            "you're", "you'll", "you've", "you'd",
            "we're", "we'll", "we've", "we'd",
            "they're", "they'll", "they've", "they'd",
            "he's", "he'll", "he'd",
            "she's", "she'll", "she'd",
            "it's", "it'll", "it'd",
            "isn't", "aren't", "wasn't", "weren't",
            "don't", "doesn't", "didn't",
            "can't", "couldn't", "won't", "wouldn't", "shouldn't",
            "hasn't", "haven't", "hadn't",
            "mustn't", "needn't", "shan't", "ain't",
            "that's", "that'll", "that'd",
            "what's", "what'll",
            "who's", "who'll",
            "there's", "there'll",
            "here's", "where's", "how's", "when's", "why's",
            "let's",
            "o'clock", "y'all", "ma'am",
        ]
        for w in contractionCases {
            expect(typeViaController(w).committedText, w, "축약형: \(w)")
        }
        // 소사전에 단어를 추가하고 테스트를 빼먹는 일이 없게 개수를 맞물려 둔다.
        expect(
            contractionCases.count, Contractions.words.count,
            "축약형: 테스트 표가 소사전 전 항목을 덮는지"
        )

        // 대소문자는 keys를 그대로 커밋하므로 자동 보존된다.
        expect(typeViaController("I'm").committedText, "I'm", "축약형: 대문자 I'm")
        expect(typeViaController("Don't").committedText, "Don't", "축약형: 대문자 Don't")
        expect(typeViaController("It's").committedText, "It's", "축약형: 대문자 It's")
        // U+2019(’)로 올라오는 레이아웃도 같은 판정 — 출력은 친 글자 그대로.
        expect(
            typeViaController("i\u{2019}m").committedText, "i\u{2019}m",
            "축약형: U+2019 아포스트로피도 인식"
        )

        // (b) base가 기존 규칙으로 변환 + 허용 접미 → 통째로 변환.
        expect(typeViaController("apple's").committedText, "apple's", "축약형: 소유격 apple's")
        expect(typeViaController("world's").committedText, "world's", "축약형: 소유격 world's")
        expect(typeViaController("today's").committedText, "today's", "축약형: 소유격 today's")
        expect(typeViaController("github's").committedText, "github's", "축약형: 소유격 github's")
        expect(typeViaController("i'").committedText, "i'", "축약형: 빈 접미 `ㅑ'` → i'")
        expect(typeViaController("you'").committedText, "you'", "축약형: 빈 접미 you'")
        // 2026-09-19 (#34): 닫는 따옴표로 끝난 영어는 문맥을 끊는다 — `'apple' 내`의 내가 so로 안 바뀜.
        // (여는 따옴표는 클라이언트가 직접 넣으므로 커밋 목록엔 apple'·내만 남는다)
        // 헬퍼는 키열을 받는다: so=내. 여는 따옴표는 클라이언트가 직접 넣으므로 커밋 목록엔 apple'·내만 남는다.
        expect(typeWordsViaController(["'apple'", "so"]).joined(separator: " "), "apple' 내", "축약형: 닫는 따옴표 뒤 한국어 보호(문맥 단절)")
        expect(typeWordsViaController(["apple", "so"]).joined(separator: " "), "apple so", "축약형: (대조) 따옴표 없는 영어 뒤에는 문맥 변환 유지")
        // ⚠️ john's는 변환되지 않는다 — web2에는 대문자 "John"만 있고
        // EnglishDetector.loadWords가 "소문자로 시작하는 줄"만 싣기 때문에 base
        // "john"이 사전에 없다. 축약형 로직이 아니라 base 사전의 한계이고,
        // `'`가 경계였던 예전과 결과가 같다(회귀 아님).
        expect(
            typeViaController("john's").committedText, "ㅓㅐㅗㅜ'ㄴ",
            "축약형: base가 사전에 없으면(john) 한글 유지"
        )

        // (c) 한국어 보호 — 두 관문을 모두 통과 못 해 친 그대로 남는다.
        expect(typeViaController("'dkssud").committedText, "'안녕", "축약형 보호: 여는 따옴표 '안녕")
        expect(
            typeViaController("dkssud'gktpdy").committedText, "안녕'하세요",
            "축약형 보호: 안녕'하세요"
        )
        expect(typeViaController("tkfkd'dl").committedText, "사랑'이", "축약형 보호: 사랑'이")
        expect(
            typeViaController("dkssud's").committedText, "안녕'ㄴ",
            "축약형 보호: 한글 base는 허용 접미라도 변환 안 함"
        )
        expect(
            typeViaController("apple'gktpdy").committedText, "apple'하세요",
            "축약형: 접미가 한국어면 base만 변환하고 뒤는 친 그대로"
        )
        expect(
            typeViaController("i'm'").committedText, "i'm'",
            "축약형: 두 번째 '는 경계 — i'm 커밋 후 ' 통과"
        )
        expect(
            typeViaController("i'm", autoEnglish: false).committedText, "ㅑ'ㅡ",
            "축약형: 자동변환을 끄면 한글 그대로"
        )

        // marked text / Backspace / passive 커밋
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            typeKeyViaController("i", composer: composer, client: client)
            typeKeyViaController("'", composer: composer, client: client)
            expect(client.marked, "ㅑ'", "축약형: 조합 중 '가 marked text에 보임")
            expect(composer.deleteBackward(client: client), true, "축약형: Backspace를 composer가 흡수")
            expect(client.marked, "ㅑ", "축약형: Backspace가 ' 유닛을 통째로 삭제")
            typeKeyViaController("'", composer: composer, client: client)
            expect(client.marked, "ㅑ'", "축약형: 지운 뒤 '를 다시 넣을 수 있음(상태 플래그가 아님)")
            typeKeyViaController("m", composer: composer, client: client)
            expect(client.marked, "ㅑ'ㅡ", "축약형: ' 뒤로도 조합이 이어짐")
            composer.commit(to: client) // passive = 클릭/포커스 이동
            expect(client.committedText, "ㅑ'ㅡ", "축약형: passive 커밋은 보이는 그대로")
        }

        // 영어 문맥이 축약형을 통해 이어진다
        expect(
            typeWordsViaController(["i'm", "ok"]).joined(separator: " "), "i'm ok",
            "축약형 문맥: i'm 뒤 ㅐㅏ(ok, contextOnly)가 영어로"
        )
        expect(
            typeWordsViaController(["apple", "don't", "go"]).joined(separator: " "),
            "apple don't go",
            "축약형 문맥: don't가 goDoTriggers로 이어져 해→go"
        )
        // 2026-09-20 (#44, 리뷰 F-6): 곱은 아포스트로피(U+2019)로 친 축약형도 같은 문맥 —
        // lastEnglishWord가 정규화되지 않으면 `don’t`가 goDoTriggers(직선 따옴표)와 어긋나
        // 해가 그대로 남았다. 출력은 친 글자(’) 그대로여야 한다.
        expect(
            typeWordsViaController(["apple", "don\u{2019}t", "go"]).joined(separator: " "),
            "apple don\u{2019}t go",
            "축약형 문맥: U+2019 don’t 뒤에서도 해→go (lastEnglishWord 정규화)"
        )
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "don\u{2019}t" { typeKeyViaController(ch, composer: composer, client: client) }
            expect(composer.commit(to: client, convertEnglish: true), "don\u{2019}t", "축약형 U+2019: 커밋 텍스트는 친 글자 그대로")
            expect(composer.lastEnglishWord ?? "", "don't", "축약형 U+2019: lastEnglishWord는 정규화(직선 따옴표)")
            expect(composer.lastConversion?.english ?? "", "don\u{2019}t", "축약형 U+2019: lastConversion.english는 친 글자 그대로")
        }

        // shift+space 되돌리기 기록
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "i'm" { typeKeyViaController(ch, composer: composer, client: client) }
            expect(composer.commit(to: client, convertEnglish: true), "i'm", "축약형: 커밋 텍스트 i'm")
            expect(composer.lastConversion?.hangul ?? "", "ㅑ'ㅡ", "축약형 되돌리기: lastConversion 한글")
            expect(composer.lastConversion?.english ?? "", "i'm", "축약형 되돌리기: lastConversion 영어")
            expect(composer.lastEnglishWord ?? "", "i'm", "축약형 문맥: lastEnglishWord=i'm(소문자 전체)")
        }

        // 되돌리기 좌표 로직 (순수함수 resolveToggle) — `'`가 낀 단어도 통째로
        let ct1 = KoreanComposer.resolveToggle(
            before: "i'm ", english: "i'm", hangul: "ㅑ'ㅡ", atDocStart: true)
        expect(ct1?.text ?? "", "ㅑ'ㅡ", "축약형 되돌리기: i'm → ㅑ'ㅡ")
        expect(
            (ct1?.replaceLen ?? -1) == 3 && (ct1?.offsetFromEnd ?? -1) == 4, true,
            "축약형 되돌리기: 교체 3글자·커서서 4"
        )
        expect(
            KoreanComposer.resolveToggle(
                before: "ㅑ'ㅡ ", english: "i'm", hangul: "ㅑ'ㅡ", atDocStart: true)?.text ?? "",
            "i'm", "축약형 되돌리기: ㅑ'ㅡ → i'm 역토글"
        )
        expect(
            KoreanComposer.resolveToggle(
                before: "go i'm ", english: "i'm", hangul: "ㅑ'ㅡ", atDocStart: false)?.text ?? "",
            "ㅑ'ㅡ", "축약형 되돌리기: 앞에 단어가 있어도 좌측경계 통과"
        )
        // ⚠️ 알려진 한계: `i'`처럼 `'`로 끝나는 변환은 되돌릴 수 없다.
        // resolveToggle의 isWordChar가 `'`를 단어 문자로 보지 않아 trailing으로
        // 먹히고 매칭이 실패한다 → nil(안전한 포기: 컨트롤러가 손대지 않는다).
        // `'`를 단어 문자에 넣으면 `'and `(여는 따옴표 뒤 단어)의 토글이 죽으므로
        // 일부러 그대로 둔다.
        expect(
            KoreanComposer.resolveToggle(
                before: "i' ", english: "i'", hangul: "ㅑ'", atDocStart: true) == nil,
            true, "축약형 되돌리기: `'`로 끝나면 안전하게 포기(nil)"
        )

        // Contractions 순수함수
        expect(Contractions.isApostrophe("'"), true, "Contractions: U+0027")
        expect(Contractions.isApostrophe("\u{2019}"), true, "Contractions: U+2019")
        expect(Contractions.isApostrophe("\""), false, "Contractions: 큰따옴표는 아님")
        expect(
            Contractions.normalizedKey(Array("I\u{2019}M")), "i'm",
            "Contractions: 조회용 정규화(대문자+U+2019)"
        )
        let splitDont = Contractions.split(Array("don't"))
        expect(String(splitDont?.base ?? []), "don", "Contractions: base 분리")
        expect(String(splitDont?.suffix ?? []), "t", "Contractions: suffix 분리")
        expect(Contractions.split(Array("apple")) == nil, true, "Contractions: '가 없으면 nil")
        expect(Contractions.matchesDictionary(Array("Don't")), true, "Contractions: 소사전 대소문자 무시")
        expect(Contractions.matchesDictionary(Array("don'x")), false, "Contractions: 소사전 미등재")
        expect(Contractions.hasAllowedSuffix(Array("apple's")), true, "Contractions: 허용 접미 s")
        expect(Contractions.hasAllowedSuffix(Array("i'")), true, "Contractions: 빈 접미 허용")
        expect(Contractions.hasAllowedSuffix(Array("apple'xyz")), false, "Contractions: 허용 안 된 접미")

        // MARK: 되돌리기 키 선택 (#54, 2026-09-21) — RevertKey 순수 매칭
        // 수정자 비트는 NSEvent.ModifierFlags의 SDK 값을 여기 **직접** 적는다(2026-09-21 Xcode 27
        // SDK 실측: capsLock 1<<16 · shift 1<<17 · control 1<<18 · option 1<<19 · command 1<<20 ·
        // function 1<<23 · deviceIndependentFlagsMask 0xFFFF0000). RevertKey.Modifiers 상수가
        // SDK와 어긋나면 여기서 잡힌다 — 테스트 하네스는 AppKit을 못 불러 상수를 직접 못 읽는다.
        let mCapsLock: UInt = 0x10000
        let mShift: UInt = 0x20000
        let mControl: UInt = 0x40000
        let mOption: UInt = 0x80000
        let mCommand: UInt = 0x100000
        let mFunction: UInt = 0x800000
        expect(
            RevertKey.Modifiers.capsLock.rawValue == mCapsLock
                && RevertKey.Modifiers.shift.rawValue == mShift
                && RevertKey.Modifiers.control.rawValue == mControl
                && RevertKey.Modifiers.option.rawValue == mOption
                && RevertKey.Modifiers.command.rawValue == mCommand
                && RevertKey.Modifiers.function.rawValue == mFunction
                && RevertKey.Modifiers.deviceIndependentMask.rawValue == 0xFFFF_0000,
            true, "RevertKey: 수정자 비트 = NSEvent.ModifierFlags SDK 값"
        )
        expect(RevertKey.spaceKeyCode == 49, true, "RevertKey: Space 키코드 49")
        expect(RevertKey.defaultsKey, "haneul.revertKey", "RevertKey: 저장 키 이름")
        expect(RevertKey.allCases.count, 4, "RevertKey: 고정 후보 4종")
        expect(
            RevertKey.allCases.contains { $0.requiredModifiers == [.control] }, false,
            "RevertKey: Ctrl+Space는 후보에 없다(macOS 입력 소스 전환 키)"
        )
        expect(RevertKey.default == .shiftSpace, true, "RevertKey: 기본값 Shift+Space")
        expect(RevertKey.resolve(rawValue: nil) == .shiftSpace, true, "RevertKey: 저장값 없음 → 기본값")
        expect(RevertKey.resolve(rawValue: "") == .shiftSpace, true, "RevertKey: 빈 문자열 → 기본값")
        expect(RevertKey.resolve(rawValue: "controlSpace") == .shiftSpace, true, "RevertKey: 모르는 값 → 기본값")
        expect(RevertKey.resolve(rawValue: "ShiftSpace") == .shiftSpace, true, "RevertKey: 대소문자 틀린 값 → 기본값(rawValue 정확 일치)")
        expect(RevertKey.resolve(rawValue: "optionSpace") == .optionSpace, true, "RevertKey: optionSpace 해석")
        expect(RevertKey.resolve(rawValue: "controlShiftSpace") == .controlShiftSpace, true, "RevertKey: controlShiftSpace 해석")
        expect(RevertKey.resolve(rawValue: "optionShiftSpace") == .optionShiftSpace, true, "RevertKey: optionShiftSpace 해석")
        for key in RevertKey.allCases {
            expect(RevertKey.resolve(rawValue: key.rawValue) == key, true, "RevertKey: rawValue 왕복 \(key.rawValue)")
            expect(key.displayName.isEmpty, false, "RevertKey: 표시 이름 있음 \(key.rawValue)")
        }

        let space: UInt16 = 49
        let combos: [(key: RevertKey, mods: UInt, name: String)] = [
            (.shiftSpace, mShift, "Shift+Space"),
            (.optionSpace, mOption, "Option+Space"),
            (.controlShiftSpace, mControl | mShift, "Ctrl+Shift+Space"),
            (.optionShiftSpace, mOption | mShift, "Option+Shift+Space"),
        ]
        for combo in combos {
            let key = combo.key, mods = combo.mods, name = combo.name
            expect(key.matches(keyCode: space, modifierFlagsRaw: mods), true, "RevertKey \(name): 정확 일치")
            expect(key.matches(keyCode: space, modifierFlagsRaw: mods | mCapsLock), true, "RevertKey \(name): capsLock 무시(한글 모드)")
            expect(key.matches(keyCode: space, modifierFlagsRaw: mods | mFunction), true, "RevertKey \(name): function 무시")
            expect(key.matches(keyCode: space, modifierFlagsRaw: mods | mCapsLock | mFunction | 0x0102), true, "RevertKey \(name): 장치별 하위 16비트 무시")
            expect(key.matches(keyCode: space, modifierFlagsRaw: mods | mCommand), false, "RevertKey \(name): Command가 더 붙으면 아님")
            expect(key.matches(keyCode: 0, modifierFlagsRaw: mods), false, "RevertKey \(name): Space 아닌 키(A)")
            expect(key.matches(keyCode: 36, modifierFlagsRaw: mods), false, "RevertKey \(name): Space 아닌 키(Return)")
            expect(key.matches(keyCode: space, modifierFlagsRaw: 0), false, "RevertKey \(name): 수정자 없는 Space")
            expect(key.matches(keyCode: space, modifierFlagsRaw: mCapsLock), false, "RevertKey \(name): capsLock만 붙은 Space")
            for other in combos where other.key != key {
                expect(key.matches(keyCode: space, modifierFlagsRaw: other.mods), false, "RevertKey \(name): \(other.name) 조합은 아님")
            }
        }

        // MARK: 앱별 자동 변환 끄기 (#54, 2026-09-21) — AutoConvertPolicy 순수 판정
        let disabledApps = ["com.apple.Terminal", "com.mitchellh.ghostty"]
        expect(AutoConvertPolicy.disabledAppsKey, "haneul.disabledAppBundleIDs", "앱별 끄기: 저장 키 이름")
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: "com.apple.Terminal"),
            false, "앱별 끄기: 목록에 있는 앱 → 변환 안 함"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: "com.mitchellh.ghostty"),
            false, "앱별 끄기: 목록 두 번째 앱도 → 변환 안 함"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: "com.apple.TextEdit"),
            true, "앱별 끄기: 목록에 없는 앱 → 변환"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: nil),
            true, "앱별 끄기: bundle ID 못 얻음(nil) → 켜짐"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: ""),
            true, "앱별 끄기: 빈 bundle ID → 켜짐"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: [], clientBundleID: "com.apple.Terminal"),
            true, "앱별 끄기: 목록 비면 변환"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: false, disabledIDs: [], clientBundleID: "com.apple.TextEdit"),
            false, "앱별 끄기: 전역 off → 무조건 변환 안 함"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: false, disabledIDs: disabledApps, clientBundleID: nil),
            false, "앱별 끄기: 전역 off + nil → 변환 안 함(전역이 우선)"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: "COM.APPLE.TERMINAL"),
            false, "앱별 끄기: 대소문자 무시"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: [" com.apple.Terminal "], clientBundleID: "com.apple.Terminal"),
            false, "앱별 끄기: 목록 항목의 앞뒤 공백 무시"
        )
        expect(
            AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledApps, clientBundleID: "com.apple.Terminal2"),
            true, "앱별 끄기: 접두어 함정 아님(정확 일치)"
        )
        expect(
            AutoConvertPolicy.adding("com.apple.Safari", to: disabledApps).joined(separator: ","),
            "com.apple.Terminal,com.mitchellh.ghostty,com.apple.Safari", "앱별 끄기: 추가는 끝에, 순서 유지"
        )
        expect(AutoConvertPolicy.adding("com.apple.Terminal", to: disabledApps).count, 2, "앱별 끄기: 중복 추가 안 됨")
        expect(AutoConvertPolicy.adding(" COM.apple.terminal ", to: disabledApps).count, 2, "앱별 끄기: 공백·대소문자 다른 중복도 안 됨")
        expect(AutoConvertPolicy.adding("  ", to: disabledApps).count, 2, "앱별 끄기: 빈 값 추가 무시")
        expect(AutoConvertPolicy.adding(" com.apple.Safari ", to: []).joined(separator: ","), "com.apple.Safari", "앱별 끄기: 추가 시 공백 정리")
        expect(
            AutoConvertPolicy.removing("com.apple.Terminal", from: disabledApps).joined(separator: ","),
            "com.mitchellh.ghostty", "앱별 끄기: 제거"
        )
        expect(
            AutoConvertPolicy.removing("COM.MITCHELLH.GHOSTTY", from: disabledApps).joined(separator: ","),
            "com.apple.Terminal", "앱별 끄기: 제거도 대소문자 무시"
        )
        expect(AutoConvertPolicy.removing("com.example.none", from: disabledApps).count, 2, "앱별 끄기: 없는 항목 제거는 그대로")
        expect(AutoConvertPolicy.removing("", from: disabledApps).count, 2, "앱별 끄기: 빈 값 제거는 그대로")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

import AppKit

/// #87 · 2026-10-12: 순수 세션 정책과 실제 조합 코어의 경계 연동 검사.
/// OS가 IMK의 false 반환을 실제 앱에 전달하는 과정은 설치 후 실기 검사 대상이다.
private final class SlashTextClient: ComposerClient {
    var committed = ""
    var marked = ""
    var visible: String { committed + marked }
    func insertText(_ text: String) { committed += text; marked = "" }
    func setMarkedText(_ text: String) { marked = text }
}

@main enum SlashEnglishTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            guard value else { fatalError(message) }
            checks += 1
        }
        func step(_ session: inout SlashEnglishSession, _ text: String?, key: UInt16 = 0,
                  flags: NSEvent.ModifierFlags = [], enabled: Bool = true) -> SlashEnglishSession.Action {
            session.process(characters: text, keyCode: key, modifierFlagsRaw: flags.rawValue, enabled: enabled)
        }

        let suiteName = "com.hyunjincho.haneulkeyboard.slash-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        check(SlashEnglishSession.defaultEnabled, "사용자 승인 기본 ON")
        check(SlashEnglishSession.isEnabled(in: defaults), "미저장 값은 ON")
        defaults.set(false, forKey: SlashEnglishSession.defaultsKey)
        check(!SlashEnglishSession.isEnabled(in: UserDefaults(suiteName: suiteName)!), "OFF 재로드")
        defaults.set(true, forKey: SlashEnglishSession.defaultsKey)
        check(SlashEnglishSession.isEnabled(in: UserDefaults(suiteName: suiteName)!), "ON 재로드")
        defaults.set(false, forKey: "haneul.autoEnglishEnabled")
        defaults.set(["example.app"], forKey: AutoConvertPolicy.disabledAppsKey)
        check(SlashEnglishSession.isEnabled(in: defaults), "자동 변환·앱별 예외와 독립")

        var session = SlashEnglishSession()
        check(step(&session, "h") == .composeKorean, "슬래시 전 한글 경로")
        check(step(&session, "/", key: 44) == .begin, "슬래시 시작")
        for letter in "help" {
            check(step(&session, String(letter)) == .passThrough, "/help 즉시 전달")
            check(session.isActive, "영문 유지")
        }
        let nonEnding: [(String?, UInt16, NSEvent.ModifierFlags)] = [
            ("\r", 36, []), ("\t", 48, []), ("\u{1b}", 53, []),
            ("?", 44, .shift), ("/", 44, []), (".", 47, []), ("1", 18, []),
            ("\u{7f}", 51, []), ("\u{7f}", 51, .command),
            (" ", 49, .shift), (" ", 49, .option), (" ", 49, [.control, .shift]),
            ("a", 0, .command), ("c", 8, .control), ("é", 14, .option),
            (nil, 123, [.function, .numericPad])
        ]
        for (text, key, flags) in nonEnding {
            check(step(&session, text, key: key, flags: flags) == .passThrough, "Space 외 키 전달: \(key)")
            check(session.isActive, "Space 외에는 종료하지 않음: \(key)")
        }
        check(step(&session, " ", key: 49) == .end, "일반 Space 종료·전달")
        check(!session.isActive, "일반 Space 직후 한글 상태")
        check(step(&session, "g") == .composeKorean, "다음 키부터 한글")
        check(step(&session, "/", enabled: false) == .composeKorean, "OFF에서 시작 금지")
        _ = step(&session, "/")
        check(step(&session, "h", enabled: false) == .composeKorean && !session.isActive, "입력 중 OFF 즉시 초기화")
        check(step(&session, "h", enabled: true) == .composeKorean, "ON 복귀 때 과거 상태 복원 금지")
        for reason in ["입력 대상 교체", "입력 소스 비활성화", "입력 소스 활성화", "secure input", "호스트 세션 종료"] {
            _ = step(&session, "/")
            session.reset()
            check(!session.isActive && step(&session, "h") == .composeKorean, reason)
        }

        // 실제 AppKit 상수로 수정자 조합을 전수 확인한다. 하위 장치 비트·CapsLock·Fn은
        // 일반 Space를 막지 않고, Shift/Ctrl/Option/Cmd는 시작·종료 조건에 각각 적용한다.
        let flagBits: [NSEvent.ModifierFlags] = [.capsLock, .shift, .control, .option, .command, .function, .numericPad]
        for mask in 0..<(1 << flagBits.count) {
            var flags: NSEvent.ModifierFlags = []
            for bit in flagBits.indices where mask & (1 << bit) != 0 { flags.formUnion(flagBits[bit]) }
            session.reset()
            let action = step(&session, "/", key: 44, flags: flags)
            let shortcut = !flags.intersection([.control, .option, .command]).isEmpty
            check(action == (shortcut ? .composeKorean : .begin), "슬래시 수정자 조합 \(mask)")
            session.reset()
            _ = step(&session, "/")
            let modifiedSpace = !flags.intersection([.shift, .control, .option, .command]).isEmpty
            check(step(&session, " ", key: 49, flags: flags) == (modifiedSpace ? .passThrough : .end),
                  "Space 수정자 조합 \(mask)")
        }
        for text in ["?", "／", "\\", "", "//"] {
            session.reset()
            check(step(&session, text, key: 44) == .composeKorean, "실제 슬래시 문자만 시작")
        }
        session.reset()
        _ = step(&session, "/")
        check(step(&session, " ", key: 0) == .passThrough, "물리 Space 아닌 문자로 종료 금지")
        check(step(&session, "\u{a0}", key: 49) == .passThrough, "특수 공백으로 종료 금지")
        for key: UInt16 in [44, 75] {
            session.reset()
            check(step(&session, nil, key: key) == .begin, "문자 누락 Slash/키패드 fallback")
            check(step(&session, nil, key: 49, flags: .shift) == .passThrough, "문자 누락 Shift+Space 유지")
            check(step(&session, nil, key: 49) == .end, "문자 누락 일반 Space 종료")
            check(step(&session, nil, key: key, flags: .shift) == .composeKorean, "문자 누락 Shift 슬래시 추측 금지")
            check(step(&session, nil, key: key, flags: .command) == .composeKorean, "문자 누락 Command 슬래시 보존")
        }

        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + EnglishDetector.bundledWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" })
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"

        // 실제 KoreanComposer를 사용해 slash 앞 기존 구두점 정책과 영문 뒤 한글 복귀를 검증.
        // 앱의 일반 입력은 insertText로 모사하며 IMK 서버를 대신했다고 주장하지 않는다.
        let beginnings: [(String?, UInt16, NSEvent.ModifierFlags)] = [
            ("/", 44, []), ("/", 44, .function), (nil, 44, []),
            (nil, 44, .function), (nil, 75, .numericPad)
        ]
        for globalEnabled in [true, false] {
            for disabled in [false, true] {
                for (slashText, slashKey, slashFlags) in beginnings {
                    let composer = KoreanComposer()
                    let client = SlashTextClient()
                    var run = SlashEnglishSession()
                    composer.autoEnglishEnabled = AutoConvertPolicy.allowed(globalEnabled: globalEnabled,
                        disabledIDs: disabled ? ["example.app"] : [], clientBundleID: "example.app")
                    for key in "banana" { _ = composer.handleInput(String(key), client: client) }
                    let beforeSlash = client.visible
                    check(step(&run, slashText, key: slashKey, flags: slashFlags) == .begin,
                          "조합 중 Fn·문자 누락 slash도 단어 시작 제한 없음")
                    composer.commit(to: client, convertEnglish: true)
                    composer.completeBoundary("/")
                    check(composer.lastConversion == nil && !composer.lastCommitWasEnglish,
                          "slash 경계는 이전 변환·영어 문맥 초기화")
                    client.insertText("/")
                    let expectedPrefix = globalEnabled && !disabled ? "banana" : beforeSlash
                    check(client.visible == expectedPrefix + "/", "슬래시 앞 기존 자동 변환 정책")
                    for key in "help" {
                        check(step(&run, String(key)) == .passThrough, "auto OFF·앱별 예외에서도 영어 전달")
                        client.insertText(String(key))
                    }
                    check(client.visible == expectedPrefix + "/help" && client.marked.isEmpty, "즉시 영문, 조합 없음")
                    check(step(&run, " ", key: 49) == .end, "연동 일반 Space 종료")
                    composer.resetEnglishContext()
                    client.insertText(" ")
                    check(step(&run, "g") == .composeKorean, "연동 한글 복귀")
                    _ = composer.handleInput("g", client: client)
                    check(client.visible == expectedPrefix + "/help ㅎ", "공백 한 번 + 다음 한글")
                }
            }
        }
        for personalBlock in [true, false] {
            let composer = KoreanComposer()
            let client = SlashTextClient()
            for key in "banana" { _ = composer.handleInput(String(key), client: client) }
            let original = client.visible
            defaults.set(personalBlock ? ["banana"] : [], forKey: PersonalDictionary.Keys.block)
            composer.personalDictionary = PersonalDictionary.load(from: defaults)
            composer.commit(to: client, convertEnglish: true)
            composer.completeBoundary("/")
            check(client.visible == (personalBlock ? original : "banana"), "slash 앞 개인 사전 재로드 정책")
        }
        print("SlashEnglishTests: \(checks) passed, 0 failed")
    }
}

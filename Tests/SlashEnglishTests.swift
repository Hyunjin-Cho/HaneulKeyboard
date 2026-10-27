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
                  flags: NSEvent.ModifierFlags = [], enabled: Bool = true,
                  context: SlashEnglishSession.Context? = nil) -> SlashEnglishSession.Action {
            session.process(characters: text, keyCode: key, modifierFlagsRaw: flags.rawValue,
                            enabled: enabled, context: context)
        }
        func context(_ location: Int, length: Int = 0, text: String? = "/",
                     marked: NSRange = NSRange(location: NSNotFound, length: 0)) -> SlashEnglishSession.Context {
            SlashEnglishSession.Context(selection: NSRange(location: location, length: length),
                                        markedRange: marked, triggerText: text)
        }
        func start(_ session: inout SlashEnglishSession, at location: Int) {
            session.reset()
            check(step(&session, "/", key: 44) == .begin, "삭제 검사 세션 시작")
            check(session.captureTrigger(in: NSRange(location: location, length: 0),
                                         markedRange: NSRange(location: NSNotFound, length: 0)),
                  "확정 뒤 slash 위치 캡처")
            check(session.triggerRange == NSRange(location: location, length: 1), "UTF16 한 글자만 추적")
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

        // 2026-10-20 빌드90: 시작 `/`를 실제로 지우는 이벤트만 종료한다.
        // 입력/삭제 자체는 호스트가 처리하고 다음 한글은 실제 조합기로 확인한다.
        for prefix in ["", "앞🙂 ", "이미 확정한 문장 "] {
            for suffix in ["", "abc"] {
                var run = SlashEnglishSession()
                let client = SlashTextClient()
                let composer = KoreanComposer()
                client.committed = prefix
                let anchor = (prefix as NSString).length
                start(&run, at: anchor)
                client.insertText("/")
                for key in suffix {
                    check(step(&run, String(key), context: context((client.visible as NSString).length)) == .passThrough,
                          "slash 뒤 영문은 직접 입력")
                    client.insertText(String(key))
                }
                for remaining in stride(from: suffix.count, through: 0, by: -1) {
                    let action = step(&run, "\u{7f}", key: 51,
                                      context: context((client.visible as NSString).length))
                    check(action == (remaining == 0 ? .end : .passThrough), "시작 slash를 지우는 순간만 종료")
                    client.committed.removeLast()
                }
                check(client.visible == prefix, "slash와 뒷글자 삭제가 앞 문장을 보존")
                check(!run.isActive && run.triggerRange == nil, "삭제 뒤 세션과 시작 위치 초기화")
                check(step(&run, "g") == .composeKorean, "slash 전체 삭제 뒤 다음 키는 한글")
                _ = composer.handleInput("g", client: client)
                check(client.visible == prefix + "ㅎ", "삭제 후 실제 한글 조합")
            }
        }

        // 앞의 한글 조합이 영어로 확정되면 길이가 바뀐다. 캡처는 확정된 커서 기준이다.
        do {
            var run = SlashEnglishSession()
            let client = SlashTextClient(); let composer = KoreanComposer()
            for key in "banana" { _ = composer.handleInput(String(key), client: client) }
            check(step(&run, "/") == .begin, "앞 조합이 있는 slash 시작")
            _ = composer.commit(to: client, convertEnglish: true)
            composer.completeBoundary("/")
            check(client.visible == "banana", "앞 조합의 활성 경계 확정")
            check(run.captureTrigger(in: NSRange(location: (client.visible as NSString).length, length: 0),
                                     markedRange: NSRange(location: NSNotFound, length: 0)),
                  "길이 변경 뒤 시작 위치 캡처")
            client.insertText("/")
            check(step(&run, "\u{7f}", key: 51, context: context(7)) == .end,
                  "확정 길이가 바뀌어도 slash 삭제 감지")
        }

        for flags: NSEvent.ModifierFlags in [[], .shift, .capsLock] {
            start(&session, at: 3)
            check(step(&session, "\u{7f}", key: 51, flags: flags, context: context(4)) == .end,
                  "문자 삭제 방향을 바꾸지 않는 수정자는 종료 허용")
        }
        start(&session, at: 3)
        check(step(&session, nil, key: 117, flags: [.function, .numericPad], context: context(3)) == .end,
              "forwardDelete로 시작 slash 삭제")

        for flags: NSEvent.ModifierFlags in [[], .command, .option] {
            start(&session, at: 3)
            check(step(&session, "a", key: 0, flags: .command, context: context(7)) == .passThrough,
                  "Cmd+A 자체는 앱에 전달")
            check(step(&session, "\u{7f}", key: 51, flags: flags, context: context(0, length: 7)) == .end,
                  "선택 범위에 slash가 있으면 선택 삭제 종료")
            check(step(&session, "g") == .composeKorean, "선택 삭제 뒤 한글 복귀")
        }
        start(&session, at: 3)
        check(step(&session, "\u{7f}", key: 51, context: context(4, length: 3)) == .passThrough,
              "slash 다음 글자만 선택 삭제하면 유지")
        for location in [7, 6, 4, 3, 2, 3, 4] {
            check(step(&session, nil, key: 123, flags: [.function, .numericPad],
                       context: context(location)) == .passThrough && session.isActive,
                  "좌우 이동 자체는 임시 영어를 종료하지 않음")
        }
        for flags: NSEvent.ModifierFlags in [.command, .option, .control, .function] {
            start(&session, at: 0)
            check(step(&session, "\u{7f}", key: 51, flags: flags, context: context(1)) == .passThrough,
                  "선택 없는 단어·줄·방향 변경 삭제 범위는 추측하지 않음")
            check(step(&session, "g", context: context(0, text: "")) == .composeKorean,
                  "수정자 삭제 뒤 기호가 없다고 확인되면 현재 키부터 복귀")
        }

        // The first plain Backspace directly after '/' does not need substring
        // support. Later edits still require the original verified geometry.
        for capture in [true, false] {
            var run = SlashEnglishSession()
            check(step(&run, "/", key: 44) == .begin,"immediate fallback start")
            if capture {
                check(run.captureTrigger(in: NSRange(location: 0, length: 0),
                                         markedRange: NSRange(location: NSNotFound, length: 0)),
                      "immediate fallback captured caret")
            }
            check(step(&run, "\u{7f}", key: 51,
                       context: capture ? context(1,text:nil) : nil) == .end,
                  "immediate slash deletion without host readback")
            check(!run.isActive && run.triggerRange == nil,"immediate fallback clears state")
            check(step(&run, "g") == .composeKorean,"immediate fallback resumes Korean")
        }
        for triggerText: String? in ["/", nil, ""] {
            var run = SlashEnglishSession(); start(&run,at:0)
            check(step(&run,"\u{7f}",key:51,
                       context:context(NSNotFound,text:triggerText)) == .end,
                  "selection support lost after slash still permits immediate plain deletion")
            check(!run.isActive && step(&run,"g") == .composeKorean,
                  "lost selection deletion returns to Korean without retaining a trigger")
        }
        for key: UInt16 in [0,123] {
            var run = SlashEnglishSession(); start(&run,at:0)
            _ = step(&run,key == 0 ? "a" : nil,key:key)
            check(step(&run,"\u{7f}",key:51,context:context(1,text:nil)) == .passThrough,
                  "intervening text or navigation invalidates immediate fallback")
            check(step(&run,"\u{7f}",key:51,context:context(NSNotFound,text:nil)) == .passThrough,
                  "unavailable geometry cannot revive an expired immediate fallback")
        }
        start(&session,at:0)
        check(step(&session,"\u{7f}",key:51,
                   context:context(NSNotFound,text:nil,marked:NSRange(location:0,length:1))) == .passThrough,
              "an active marked range blocks lost-selection fallback")
        for flags: NSEvent.ModifierFlags in [.command,.option,.control,.function] {
            var run = SlashEnglishSession(); _ = step(&run,"/")
            check(step(&run,"\u{7f}",key:51,flags:flags) == .passThrough,
                  "unknown host does not guess modified deletion")
        }
        start(&session,at:0)
        check(step(&session,"\u{7f}",key:51,context:context(7,text:nil)) == .passThrough,
              "readable caret away from slash blocks immediate fallback")
        for (delimiter,key,flags): (String,UInt16,NSEvent.ModifierFlags) in [
            (")",29,.shift),("]",30,[]),("}",30,.shift)
        ] {
            for text: String? in [delimiter,nil] {
                var run = SlashEnglishSession(); _ = step(&run,"/")
                check(step(&run,text,key:key,flags:flags) == .end,"closing delimiter ends slash")
                check(step(&run,"g") == .composeKorean,"closing delimiter resumes Korean")
            }
        }
        var actualCharacters = SlashEnglishSession(); _ = step(&actualCharacters,"/")
        check(step(&actualCharacters,"0",key:29,flags:.shift) == .passThrough,
              "actual characters override physical closing-parenthesis fallback")
        for flags: NSEvent.ModifierFlags in [.command,.option,.control] {
            var run = SlashEnglishSession(); _ = step(&run,"/")
            check(step(&run,")",key:29,flags:flags) == .passThrough,"modified parenthesis stays a host shortcut")
        }

        let unavailable = [
            context(-1, text: ""),
            context(Int.max - 1, length: 2, text: ""),
            context(1, length: -1, text: ""),
            context(1, text: "", marked: NSRange(location: 0, length: 1)),
            context(1, text: "", marked: NSRange(location: -1, length: 0)),
        ]
        for snapshot in unavailable {
            start(&session, at: 0)
            check(step(&session, "\u{7f}", key: 51, context: snapshot) == .passThrough && session.isActive,
                  "조회 불가·불완전 범위는 삭제를 확정하지 않음")
            check(step(&session, " ", key: 49, context: snapshot) == .end && session.triggerRange == nil,
                  "조회 불가여도 기존 일반 Space 종료 유지")
        }
        for text in ["", "x"] {
            start(&session, at: 0)
            check(step(&session, "g", context: context(0, text: text)) == .composeKorean,
                  "시작 기호 소실을 확인하면 현재 입력부터 한글")
            check(!session.isActive && session.triggerRange == nil, "기호 소실은 추적 상태도 삭제")
        }
        start(&session, at: 0)
        check(step(&session, "/", context: context(0, text: "")) == .begin && session.triggerRange == nil,
              "옛 slash 삭제 뒤 새 slash는 새 세션으로 시작")
        session.reset()
        check(!session.captureTrigger(in: NSRange(location: 0, length: 0),
                                      markedRange: NSRange(location: NSNotFound, length: 0)),
              "RPC 도중 reset된 세션은 늦은 캡처로 되살리지 않음")
        check(!session.isActive && session.triggerRange == nil, "캡처는 시작 동작이 아님")
        for snapshot in [context(NSNotFound), context(1, marked: NSRange(location: 0, length: 1))] {
            _ = step(&session, "/")
            check(!session.captureTrigger(in: snapshot.selection, markedRange: snapshot.markedRange)
                    && session.isActive && session.triggerRange == nil,
                  "캡처 불가 호스트는 기존 정책으로 유지")
            session.reset()
        }
        start(&session, at: 0)
        check(step(&session, "g", enabled: false, context: context(1)) == .composeKorean
                && session.triggerRange == nil, "설정 OFF도 시작 위치를 초기화")

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

import Foundation

// 2026-11-07 (#174): 리뷰 english-dict F-1~F-12, input-core F-17 회귀 검사.
// 고치기 전에 실패하는 것을 확인했고, 대조군(정상 동작)도 함께 지킨다.
func runEnglishRulesTests() {
    func hangul(_ keys: String) -> String { ManualToggle.keysToHangul(keys)! }
    func staysKorean(_ keys: [String], _ label: String) {
        for key in keys { expect(type(key).committedText, hangul(key), "\(label): \(key)") }
    }
    func converts(_ keys: [String], _ label: String) {
        for key in keys { expect(type(key).committedText, key, "\(label): \(key)") }
    }
    func afterThe(_ key: String) -> String { typeWords(["the", key]).last ?? "" }

    // ── F-1 오너 결정(B안): 자주 쓰는 1음절 + ㅠㅜㅡ는 무맥락에서 한글로 남긴다.
    staysKorean(["gob", "gon", "sob", "son", "rob", "robb", "rObb", "dOb", "don", "ton", "won", "spn"], "F-1 우는 표정 끝")
    for (keys, expected) in [("gob", "해ㅠ"), ("son", "내ㅜ"), ("robb", "개ㅠㅠ"), ("spn", "네ㅜ")] {
        expect(type(keys).committedText, expected, "F-1 화면 그대로: \(keys)")
    }
    expect(type("gobdp").committedText, "해ㅠ에", "F-1 조사 앞에서도 한글")
    // 단위 경로로도 새지 않지만 숫자 뒤 단위와 Title Case는 영어 표기다.
    expect(typeViaController("10ton ").committedText, "10ton ", "F-1 숫자 뒤 단위는 유지")
    expect(typeViaController("10 ton ").committedText, "10 ton ", "F-1 숫자 뒤 띄운 단위는 유지")
    converts(["Son", "Don", "Gob"], "F-1 첫 자음 Shift는 유지")
    // 영어 문맥에서는 계속 변환한다.
    for key in ["son", "won", "don", "rob", "sob", "gob"] {
        expect(afterThe(key), key, "F-1 영어 문맥은 변환: the \(key)")
    }
    expect(typeWords(["I", "won"]).last ?? "", "won", "F-1 영어 문맥은 변환: I won")
    // 목록 밖 음절과 ㅠㅜㅡ가 아닌 끝은 좁게 막기의 범위 밖이다(B안). 깨진 영어 대조군도 지킨다.
    converts(["throb", "run", "fun", "sun", "gun", "apron", "cotton", "skeleton", "wisdom", "dkk", "apple"], "F-1 대조군 변환")
    staysKorean(["dkssud", "go", "ro"], "F-1 대조군 한글")

    // 2026-11-07 오너 결정: curated 약어 4개의 한글형만 무맥락에서 막는다. 앞 음절이 같은 다른 영어는 건드리지 않는다.
    for (keys, form) in [("wlb", "지ㅠ"), ("rnb", "구ㅠ"), ("thb", "소ㅠ"), ("epb", "데ㅠ")] {
        expect(type(keys).committedText, form, "약어 4개 무맥락 한글: \(keys)")
        expect(afterThe(keys), keys, "약어 4개 영어 문맥은 변환: \(keys)")
    }
    converts(["WLB", "Wlb", "RNB", "Rnb", "THB", "Thb", "EPB", "Epb"], "약어 4개 Title·ALLCAPS 유지")

    // ── F-2 오너 결정: 초성체·자음 얼굴 6개는 문맥과 무관하게 보호, 자음열의 혼합 대소문자는 막는다.
    for (keys, face) in [("rrt", "ㄱㄱㅅ"), ("sr", "ㄴㄱ"), ("dad", "ㅇㅁㅇ"), ("ada", "ㅁㅇㅁ"),
                         ("wawa", "ㅈㅁㅈㅁ"), ("adad", "ㅁㅇㅁㅇ")] {
        expect(type(keys).committedText, face, "F-2 보호: \(face)")
        expect(afterThe(keys), face, "F-2 영어 문맥에서도 보호: \(face)")
    }
    staysKorean(["aT", "wE", "rrT"], "F-2 자음열 혼합 Shift")
    // 단위 sr은 숫자 뒤에서만 쓴다.
    expect(typeViaController("100sr ").committedText, "100sr ", "F-2 숫자 뒤 sr은 유지")
    expect(typeViaController("100 sr ").committedText, "100 sr ", "F-2 숫자 뒤 띄운 sr은 유지")
    // 일반 소문자 자음열·Title·ALLCAPS는 그대로다.
    converts(["wtf", "ddr", "cd", "as", "Dad", "DAD", "Ada", "ADA", "Wawa", "WAWA", "RRT", "Rrt", "AT", "At", "WE", "We", "EV", "Ev", "AS", "WTF", "DDR"], "F-2 대조군")
    staysKorean(["zz", "gg"], "F-2 대조군 슬랭")

    // ── F-3 오너 결정: R3·첫 자음 Shift·단독 목록의 혼합 Shift, ㅑ 1음절의 Shift를 막는다.
    staysKorean(["EOans", "gOT", "EOs", "sPark"], "F-3 R3 혼합 Shift")
    expect(type("EOansdp").committedText, "떄문에", "F-3 떄문에는 그대로")
    expect(type("DPt").committedText, "옛", "F-3 Shift를 먼저 눌러도 옛은 옛")
    staysKorean(["Tid", "Wid", "rPT", "diT"], "F-3 ㅑ 1음절 Shift")
    staysKorean(["gpT", "alT", "imE", "mcP"], "F-3 단독 목록·혼합 Shift")
    converts(["Apple", "APPLE", "iPhone", "macOS", "GitHub", "YouTube", "Entry", "Title", "WORK", "Work",
              "Spark", "SPARK", "spArk", "TTArtisan", "TaylorMade", "WhatsApp", "sRGB",
              "Fps", "FPS", "FpS", "Gpt", "GPT", "Esc", "ESC", "Mcp", "MCP", "Dmg", "DMG", "Abs", "ABS", "Xi", "XI"], "F-3 대조군")
    staysKorean(["eoans", "dPt", "spaRk"], "F-3 대조군 한글")
    // Shift 없는 ㅑ 1음절은 종전대로다.
    expect(type("aid").committedText, "aid", "F-3 대조군 aid(먕)")
    // 2026-11-07 오너 결정(리뷰 E174-P3-1): 등록된 단위 기호와 대소문자까지 같으면 혼합 Shift 차단을 건너뛴다.
    expect(type("GPa").committedText, "GPa", "단위 GPa 단독")
    expect(typeViaController("100GPa ").committedText, "100GPa ", "단위 GPa 숫자 뒤")
    expect(typeViaController("100 GPa ").committedText, "100 GPa ", "단위 GPa 숫자 뒤 띄움")
    expect(type("gPa").committedText, hangul("gPa"), "단위 표기와 다른 대소문자는 막는다")
    expect(type("gpa").committedText, hangul("gpa"), "gpa는 표제어 veto")
    expect(type("sr").committedText, "ㄴㄱ", "단위 sr 단독은 오너 결정대로 막힌다")
    expect(type("ton").committedText, "새ㅜ", "단위 ton 단독은 오너 결정대로 막힌다")

    // ── F-4: 변환 추가는 Shift로 다른 자모가 된 혼합 대소문자까지 강제하지 않는다.
    let forced = PersonalDictionary(force: ["got", "work", "won", "r2d2", "openai"], block: [])
    for (keys, expected) in [("got", "got"), ("Got", "Got"), ("GOT", "GOT"), ("goT", "했"), ("work", "work"), ("wOrk", "쟤가"), ("won", "won"), ("wOn", "쟤ㅜ")] {
        expect(typeWithPersonalDictionary(keys, forced).client.committedText, expected, "F-4 force: \(keys)")
    }
    expect(forced.decision(word: "goT", hangul: "했") == nil, true, "F-4 혼합은 의견 없음")
    expect(forced.decision(word: "Got", hangul: "햇") == .forceConvert, true, "F-4 Title은 force")
    expect(forced.decision(word: "GOT", hangul: "햇") == .forceConvert, true, "F-4 ALLCAPS는 force")
    expect(forced.decision(word: "R2D2", hangul: "x") == .forceConvert, true, "F-4 숫자 낀 ALLCAPS는 force")
    expect(forced.decision(word: "r2D2", hangul: "x") == .forceConvert, true, "F-4 숫자 든 이름은 한국어로 칠 일이 없다")
    expect(forced.decision(word: "OPENAI", hangul: "x") == .forceConvert, true, "F-4 ALLCAPS Shift 키")
    expect(forced.decision(word: "Openai", hangul: "x") == .forceConvert, true, "F-4 Title Shift 키")
    expect(PersonalDictionary(force: ["vismo"]).decision(word: "ViSmO", hangul: "x") == nil, true, "F-4 O는 자모가 바뀌는 Shift")
    expect(PersonalDictionary(force: ["github"]).decision(word: "GitHub", hangul: "x") == .forceConvert, true, "F-4 자모가 안 바뀌는 대문자는 force")
    expect(PersonalDictionary(force: ["got"], block: ["got"]).decision(word: "goT", hangul: "했") == .block, true, "F-4 금지는 대소문자 무관")
    expect(typeViaControllerWithPersonalDictionary("goT's", forced).committedText, "했'ㄴ", "F-4 축약형 경로도 같은 기준")

    // ── 2026-11-07 오너 결정(리뷰 E174-P2-1): 등록한 대소문자를 보존해 그 키열 그대로 치면 Shift 가드를 건너뛴다.
    let cased = ["QuickTime", "TeamViewer", "QuickBooks", "TopazAI"]
    let registered = PersonalDictionary(forceList: cased + ["got", "work", "won"], blockList: [])
    for word in cased {
        expect(typeWithPersonalDictionary(word, registered).client.committedText, word, "등록 표기 그대로: \(word)")
        expect(typeWithPersonalDictionary(word, registered).composer.lastConversion?.english ?? "", word, "등록 표기 되돌리기 쌍: \(word)")
        expect(typeWithPersonalDictionary(word.lowercased(), registered).client.committedText, word.lowercased(), "등록 표기 소문자 입력: \(word)")
        expect(typeWithPersonalDictionary(word.uppercased(), registered).client.committedText, word.uppercased(), "등록 표기 ALLCAPS 입력: \(word)")
        expect(typeWithPersonalDictionary(word, .empty).client.committedText, hangul(word), "등록 안 하면 한글: \(word)")
    }
    for (keys, form) in [("goT", "했"), ("wOrk", "쟤가"), ("wOn", "쟤ㅜ")] {
        expect(typeWithPersonalDictionary(keys, registered).client.committedText, form, "소문자 등록의 혼합 Shift는 계속 막는다: \(keys)")
    }
    expect(registered.decision(word: "quickTime", hangul: "x") == nil, true, "등록과 다른 혼합 대소문자는 force가 아니다")
    expect(typeWithPersonalDictionary("QuickTimedms", registered).client.committedText, "QuickTime은", "등록 표기 + 조사")
    expect(typeWithPersonalDictionary("QuickTime", PersonalDictionary(forceList: cased, blockList: ["quicktime"])).client.committedText,
           hangul("QuickTime"), "금지가 등록 표기보다 우선")
    expect(typeWithPersonalDictionary("QuickTime", PersonalDictionary(forceList: cased, blockList: [hangul("QuickTime")])).client.committedText,
           hangul("QuickTime"), "한글 표기 금지도 우선")
    expect(typeViaControllerWithPersonalDictionary("Y'KnOw", PersonalDictionary(forceList: ["Y\u{2019}KnOw"], blockList: [])).committedText,
           "Y'KnOw", "곱은 따옴표로 등록해도 같은 표기")
    // 옛 항목: 소문자 목록은 동작이 그대로다. 등록 표기 집합이 비어 전과 같은 값이 된다.
    let old = PersonalDictionary(forceList: ["got", "work", "apple"], blockList: ["banana"])
    expect(old == PersonalDictionary(force: ["got", "work", "apple"], block: ["banana"]), true, "옛 항목은 전과 같은 값")
    for (word, want) in [("got", true), ("Got", true), ("GOT", true), ("goT", false), ("wOrk", false), ("apple", true), ("Apple", true)] {
        expect(old.decision(word: word, hangul: "x") == .forceConvert, want, "옛 항목 판정: \(word)")
    }
    // 예전 빌드는 같은 목록을 소문자로 정규화해 읽으므로 새 항목을 만나도 깨지지 않는다.
    expect(PersonalDictionary.normalizedForceEntry("QuickTime") ?? "", "quicktime", "옛 정규화 규칙은 그대로")
    // 목록 편집: 설정 앱이 쓰는 순수 함수.
    expect(PersonalDictionary.forceEntries(["banana", "apple"]).joined(separator: ","), "apple,banana", "옛 항목 표시는 그대로")
    expect(PersonalDictionary.forceEntries(["QuickTime", "apple"]).joined(separator: ","), "apple,QuickTime", "새 항목은 등록한 표기로 표시, 정렬은 대소문자 무시")
    expect(PersonalDictionary.forceEntries(["quicktime", "QuickTime", "QUICKTIME", " apple ", "apple", "", "한글"]).joined(separator: ","),
           "apple,QuickTime", "같은 낱말은 한 줄, 먼저 나온 대문자 표기, 잘못된 항목은 버림")
    expect(PersonalDictionary.addingForceEntry(" QuickTime ", to: ["apple"])?.joined(separator: ",") ?? "", "apple,QuickTime", "추가: 표기 보존")
    expect(PersonalDictionary.addingForceEntry("QuickTime", to: ["apple", "quicktime"])?.joined(separator: ",") ?? "", "apple,QuickTime", "중복: 새로 친 표기로 바꾼다")
    expect(PersonalDictionary.addingForceEntry("quicktime", to: ["QuickTime"])?.joined(separator: ",") ?? "", "quicktime", "중복: 소문자로 다시 치면 소문자")
    expect(PersonalDictionary.addingForceEntry("apple", to: ["apple"])?.joined(separator: ",") ?? "", "apple", "중복: 같은 표기는 그대로")
    expect(PersonalDictionary.addingForceEntry("한글", to: ["apple"]) == nil, true, "추가: 규칙에 안 맞으면 거절")
    expect(PersonalDictionary.addingForceEntry("'", to: []) == nil, true, "추가: 글자 없는 항목 거절")
    expect(PersonalDictionary.addingForceEntry("\u{212A}elvin", to: [])?.joined(separator: ",") ?? "", "kelvin", "소문자화로만 ASCII가 되면 소문자로 저장")
    expect(PersonalDictionary.removingForceEntry("QuickTime", from: ["apple", "QuickTime"]).joined(separator: ","), "apple", "삭제: 등록 표기")
    expect(PersonalDictionary.removingForceEntry("apple", from: ["apple", "QuickTime"]).joined(separator: ","), "QuickTime", "삭제: 옛 항목")

    // ── F-5: 줄 끝 CR·빈 줄이 있는 파일은 온전한 파일로 받지 않는다(fail-closed).
    func table(_ text: String) -> SortedWordTable { SortedWordTable(data: Data(text.utf8)) }
    expect(table("# count: 2\n가\r\n나\r\n").isComplete, false, "F-5 CRLF 본문")
    expect(table("# count: 2\n가\n나\r").isComplete, false, "F-5 끝 줄 CR")
    expect(table("# count: 2\n가\n\n나\n").isComplete, false, "F-5 중간 빈 줄")
    expect(table("# count: 2\n\n가\n나\n").isComplete, false, "F-5 첫 줄 빈 줄")
    expect(table("# count: 2\n가\n나\n\n").isComplete, false, "F-5 끝 빈 줄")
    let spaced = (0..<200).map { String(format: "w%03d", $0) }
    var anchored = spaced; anchored.insert("", at: 64)
    expect(table("# count: 200\n" + anchored.joined(separator: "\n") + "\n").isComplete, false, "F-5 앵커 자리 빈 줄")
    expect(table("# count: 200\n" + spaced.joined(separator: "\n") + "\n").isComplete, true, "F-5 대조군 정상 파일")
    expect(table("# count: 2\n가\n나").isComplete, true, "F-5 대조군 끝 줄바꿈 없음")
    expect(KoreanDictionary.isLoaded, true, "F-5 대조군 배포 사전")

    // ── F-6: 배포 사전 ∩ 제외 목록의 새 겹침을 잡는다. 현재 겹침은 기준선 파일이 고정한다.
    runExclusionOverlapCheck()
    runEnglishTableTests()

    // ── F-7 오너 결정: 약어 7개는 curated에서 broad로 내렸다. 멀쩡한 한글은 지키고 깨진 꼴은 계속 변환한다.
    staysKorean(["ansi", "goty", "emtek", "totp", "algo", "rhel", "gorm", "Emtek", "Totp", "Rhel", "RHEL"], "F-7 멀쩡한 한글")
    for key in ["ansi", "goty", "emtek", "totp", "algo", "rhel", "gorm"] {
        expect(afterThe(key), hangul(key), "F-7 영어 문맥도 curated만 믿는다: \(key)")
    }
    converts(["Ansi", "ANSI", "Goty", "GOTY", "EMTEK", "TOTP", "Algo", "ALGO", "Gorm", "GORM"], "F-7 깨진 꼴·첫 자음 Shift 유지")
    staysKorean(["ansidp"], "F-7 조사 앞")
    converts(["dirty", "duty", "disk", "sharp", "coal", "town", "audi"], "F-7 일반 영어는 건드리지 않는다")

    // ── F-8 오너 결정: cos는 단독 목록에서 뺐다. 영어 문맥과 개인 사전으로는 계속 쓴다.
    expect(type("cos").committedText, "챈", "F-8 눈치 챈")
    expect(typeWords([ManualToggle.hangulToKeys("눈치")!, "cos", ManualToggle.hangulToKeys("사람")!]).joined(separator: " "),
           "눈치 챈 사람", "F-8 문장")
    expect(type("cosrk").committedText, "챈가", "F-8 조사 앞")
    expect(afterThe("cos"), "cos", "F-8 영어 문맥은 변환")
    expect(typeWithPersonalDictionary("cos", PersonalDictionary(force: ["cos"])).client.committedText, "cos", "F-8 개인 사전")
    converts(["Cos", "COS", "abs", "xi", "arccos"], "F-8 대조군")

    // ── F-9: 어떤 조사 끝으로 끊어도 앞부분이 표제어이면 분리를 포기한다.
    for (keys, word) in [("qnapfkddms", "부메랑은"), ("qnapfkdeh", "부메랑도"), ("qnapfkdaks", "부메랑만")] {
        expect(type(keys).committedText, word, "F-9 표제어+조사: \(word)")
        expect(EnglishParticleSplitter.split(keys: Array(keys), hangul: word, personalDictionary: .empty) == nil, true, "F-9 분리 포기: \(word)")
    }
    expect(type("qnapfkd").committedText, "부메랑", "F-9 대조군 부메랑")
    expect(type("qnap").committedText, "qnap", "F-9 대조군 qnap")
    expect(type("qnapdp").committedText, "qnap에", "F-9 대조군 qnap에")
    expect(type("githubdp").committedText, "github에", "F-9 대조군 github에")
    // 개인 사전에 의견이 있으면 예외다. 금지는 한글로 남기고, 사용자가 직접 추가한 앞말은 종전대로 분리한다.
    expect(typeWithPersonalDictionary("qnapfkddms", PersonalDictionary(block: ["qnap"])).client.committedText, "부메랑은", "F-9 금지 우선")
    expect(typeWithPersonalDictionary("qnapfkddms", PersonalDictionary(force: ["qnap"])).client.committedText, "qnap랑은", "F-9 추가한 앞말 우선")

    // ── F-12 오너 결정: 키열이 정확히 The일 때만 veto 위에서 변환한다.
    expect(type("The").committedText, "The", "F-12 The")
    expect(typeViaController("The ").committedText, "The ", "F-12 The Space")
    expect(typeWords(["The", "apple"]).joined(separator: " "), "The apple", "F-12 문장 첫 The")
    expect(typeWords(["The", "got"]).last ?? "", "got", "F-12 The는 영어 문맥을 넘긴다")
    expect(typeWithPersonalDictionary("The", .empty).composer.lastConversion?.hangul ?? "", "쏟", "F-12 되돌릴 원문")
    expect(type("The", autoEnglish: false).committedText, "쏟", "F-12 자동 변환 OFF")
    expect(typePassive("The").committedText, "쏟", "F-12 수동 경계")
    for blocked in ["the", "쏟"] {
        expect(typeWithPersonalDictionary("The", PersonalDictionary(block: [blocked])).client.committedText, "쏟", "F-12 개인 금지: \(blocked)")
    }
    converts(["the", "THE", "They"], "F-12 대조군 변환")
    // 쏟다 활용형은 그대로다. The가 조사 분리의 앞말로 인정되면 쏟는 → The는 사고가 난다.
    staysKorean(["Tht", "Thesms", "Thedms", "Thedmf", "Thedk", "Thesmsep", "Them", "Thdms"], "F-12 다른 키열")
    for keys in ["Thesms", "Thedms", "Thedmf", "Thefh", "Thetj"] {
        let client = FakeClient(); let composer = KoreanComposer()
        for key in keys {
            _ = composer.handleInput(String(key), client: client)
            expect(client.marked.contains { $0.isASCII && $0.isLetter }, false, "F-12 입력 중에도 영어 없음: \(keys)")
        }
    }
    // 사전이 온전하지 않으면 이 예외도 꺼진다(공통 fail-closed는 shouldConvert 맨 앞).
    expect(EnglishDetector.shouldConvert(units: ["쏟"], keys: Array("The")), true, "F-12 판정기")
    expect(EnglishDetector.shouldConvert(units: ["쏟"], keys: Array("the")), false, "F-12 다른 대소문자는 예외 아님")

    // ── input-core F-17: 원본 배열이 같으면 정규화를 다시 하지 않고, 바뀌면 바로 반영한다.
    // 2026-11-13 (#226, 리뷰 install-update-F-5): 고정 이름 도메인. UUID 이름은 실행마다 빈 plist를 ~/Library/Preferences에 남겼다(151개). 시작할 때도 비운다.
    let suite = "local.synthetic.haneul-personal-dict"
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    if let defaults = UserDefaults(suiteName: suite) {
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["Vismo", " apple "], forKey: PersonalDictionary.Keys.force)
        defaults.set(["BANANA", "ㅠ무무"], forKey: PersonalDictionary.Keys.block)
        let first = PersonalDictionary.load(from: defaults)
        expect(first.force == ["vismo", "apple"] && first.block == ["banana", "ㅠ무무"], true, "F-17 정규화 결과")
        let builds = PersonalDictionary.loadBuildCount
        for _ in 0..<100 { expect(PersonalDictionary.load(from: defaults) == first, true, "F-17 재사용 결과") }
        expect(PersonalDictionary.loadBuildCount, builds, "F-17 같은 배열은 재정규화 안 함")
        defaults.set(["vismo"], forKey: PersonalDictionary.Keys.force)
        let forceChanged = PersonalDictionary.load(from: defaults)
        expect(forceChanged.force == ["vismo"], true, "F-17 추가 목록 변경 즉시 반영")
        expect(PersonalDictionary.loadBuildCount, builds + 1, "F-17 바뀌면 다시 만든다")
        defaults.set(["cherry"], forKey: PersonalDictionary.Keys.block)
        expect(PersonalDictionary.load(from: defaults).block == ["cherry"], true, "F-17 금지 목록 변경 즉시 반영")
        defaults.removeObject(forKey: PersonalDictionary.Keys.force)
        defaults.removeObject(forKey: PersonalDictionary.Keys.block)
        expect(PersonalDictionary.load(from: defaults) == .empty, true, "F-17 키를 지우면 빈 사전")
        // 저장·읽기·삭제 왕복: 설정 앱이 쓰는 함수로 목록을 고쳐 저장하면 입력기 쪽 읽기에 바로 반영된다.
        var entries = PersonalDictionary.storedForceEntries(in: defaults)
        entries = PersonalDictionary.addingForceEntry("QuickTime", to: entries) ?? []
        defaults.set(entries, forKey: PersonalDictionary.Keys.force)
        expect(PersonalDictionary.storedForceEntries(in: defaults).joined(separator: ","), "QuickTime", "저장 왕복: 표기 보존")
        expect(PersonalDictionary.load(from: defaults).decision(word: "QuickTime", hangul: "x") == .forceConvert, true, "저장 왕복: 입력기 판정")
        entries = PersonalDictionary.removingForceEntry("QuickTime", from: entries)
        defaults.set(entries, forKey: PersonalDictionary.Keys.force)
        expect(PersonalDictionary.load(from: defaults).decision(word: "QuickTime", hangul: "x") == nil, true, "저장 왕복: 삭제 반영")
    } else {
        expect(false, true, "F-17 시험용 설정 도메인")
    }
}

/// 2026-11-07 (#175): 번들 표가 manifest의 사전과 정확히 같은가. 표에 web2 낱말이 들어가면 안 된다.
/// 사전을 고치고 scripts/build_english_table.py를 안 돌리면 여기서 실패한다.
func runEnglishTableTests() {
    let tablePath = "Resources/IM/english_bundled.txt"
    var expected = Set<String>()
    for entry in DictManifest.load() {
        expected.formUnion(EnglishDetector.loadWords(from: [entry.path], expectedCapacity: 0))
    }
    let tableText = (try? String(contentsOfFile: tablePath, encoding: .utf8)) ?? ""
    let body = tableText.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
    expect(body == expected.sorted(), true, "표: 번들 사전 합집합과 정확히 같다 (어긋나면 scripts/build_english_table.py)")
    let foreign = Set(body).subtracting(expected).sorted()
    expect(foreign.count, 0, "표 ⊆ 번들 사전 합집합: 번들 사전에 없는 낱말 \(foreign.prefix(10))")
    expect(FileManager.default.fileExists(atPath: "dict_work/web2_snapshot.txt"), false, "표: web2 사본을 저장소에 두지 않는다")
    guard let table = SortedWordTable(path: tablePath) else {
        expect(false, true, "표: 파일 열기")
        return
    }
    expect(table.isComplete, true, "표: 정렬·개수·줄 끝이 온전하다")
    expect(table.uniqueCount, expected.count, "표: 낱말 수")
    // 표본은 고르게 뽑는다. 전체 대조는 #175 머지 전 관문에서 돌렸고, 여기서는 조회 코드의 회귀만 잡는다.
    var missed: [String] = [], wrongHit: [String] = []
    for (index, word) in body.enumerated() where index % 53 == 0 {
        if !table.contains(Array(word.utf8)) { missed.append(word) }
        for near in [word + "q", String(word.dropLast()), word + word] where !expected.contains(near) {
            if table.contains(Array(near.utf8)) { wrongHit.append(near) }
        }
    }
    expect(missed.count, 0, "표: 있는 낱말 조회 \(missed.prefix(5))")
    expect(wrongHit.count, 0, "표: 없는 낱말 조회 \(wrongHit.prefix(5))")
    for entry in DictManifest.load() {
        expect(EnglishDetector.isExplicitEnglishContextWord(entry.sampleWord), true, "표: \(entry.name) 대표어 \(entry.sampleWord)")
    }
    expect(EnglishDetector.isExplicitEnglishContextWord("zzzzq"), false, "표: 없는 낱말")
    // 온전하지 않은 표는 쓰지 않는다. 변환이 줄어들 뿐 틀어진 조회로 새지 않는다.
    expect(runDictionaryProbe(tablePath, "표 탐침: 배포 표", flag: "--probe-bundled-table"), true, "표 탐침: 배포 표")
    let scratch = NSTemporaryDirectory() + "haneul-table-probe-\(ProcessInfo.processInfo.processIdentifier)"
    try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    let stale = scratch + "/stale.txt", unsorted = scratch + "/unsorted.txt", crlf = scratch + "/crlf.txt"
    try? "# count: 9\nplaylist\n".write(toFile: stale, atomically: true, encoding: .utf8)
    try? "# count: 2\nplaylist\napple\n".write(toFile: unsorted, atomically: true, encoding: .utf8)
    try? "# count: 2\napple\r\nplaylist\r\n".write(toFile: crlf, atomically: true, encoding: .utf8)
    for (path, label) in [(stale, "개수 불일치"), (unsorted, "정렬 깨짐"), (crlf, "CRLF"), (scratch + "/none.txt", "파일 없음")] {
        expect(runDictionaryProbe(path, "표 탐침: \(label)", flag: "--probe-bundled-table"), false, "표 탐침: \(label)이면 변환 안 함")
    }
    runSystemWordFileTests(scratch: scratch)
}

/// 2026-11-07 (#175): 시스템 파일을 펼치지 않고 찾아도 답이 `loadWords`로 펼친 Set과 같아야 한다. 파일이 달라져도 마찬가지다.
private func runSystemWordFileTests(scratch: String) {
    /// 시드 고정 뒤섞기. 언제나 같은 순서가 나온다.
    func shuffled(_ items: [String], seed: UInt64) -> [String] {
        var out = items, state = seed
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out.swapAt(i, Int((state >> 33) % UInt64(i + 1)))
        }
        return out
    }
    /// 3글자 이상 소문자 낱말 n개를 정렬된 채로 만든다.
    func sortedWords(_ n: Int) -> [String] {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return (0..<n).map { i in
            String([letters[(i / 17576) % 26], letters[(i / 676) % 26], letters[(i / 26) % 26], letters[i % 26]])
        }
    }
    let plain = sortedWords(3000)
    let fewStray = plain.enumerated().map { $0.offset == 1500 ? "zzzz" : $0.element } + ["aaab"]
    var moved = plain
    for (at, i) in stride(from: 31, to: 2900, by: 97).enumerated() { moved.swapAt(i, i + 1 + at % 3) }
    let capitalRun = (0..<9000).map { "Capital\($0)" }.joined(separator: "\n")
    /// 로더와 따로 적은 필터. `isWordLine`을 Set과 시스템 파일이 함께 쓰므로, 필터가 틀어지면 둘을 비교해서는 못 잡는다.
    func oracle(_ bytes: Data) -> Set<String> {
        var out = Set<String>()
        for line in bytes.split(separator: 0x0A) {
            let b = Array(line)
            guard b.count >= 3, (0x61...0x7A).contains(b[0]),
                  b.allSatisfy({ (0x61...0x7A).contains($0) || (0x41...0x5A).contains($0) }) else { continue }
            out.insert(String(decoding: b.map { $0 | 0x20 }, as: UTF8.self))
        }
        return out
    }
    let innerCaps = plain.map { String($0.prefix(1)) + $0.dropFirst().uppercased() }
    let sharedStem = sortedWords(800).map { "nonconformist" + $0 }
    // 어긋난 낱말이 상한을 넘지만 정렬된 줄 사이에 고르게 섞여 색인 간격은 좁다. 상한만이 이 파일을 Set으로 돌린다.
    let manyStrays = sortedWords(SystemWordFile.maxStrayWords + 200).flatMap { ["b" + $0, "a" + $0] }
    let cases: [(name: String, bytes: Data, expanded: Bool)] = [
        ("정렬", Data((plain.joined(separator: "\n") + "\n").utf8), false),
        ("끝 줄바꿈 없음", Data(plain.joined(separator: "\n").utf8), false),
        ("잘린 파일(낱말 중간)", Data((plain.joined(separator: "\n") + "\n").utf8).prefix(7000), false),
        ("대소문자 이웃(대문자 먼저)", Data("A\na\nAbc\nabc\nAbd\nabd\nMarch\nmarch\nMay\nmay\n".utf8), false),
        ("대소문자 이웃(소문자 먼저)", Data("abc\nAbc\nabd\nAbd\nmarch\nMarch\nmay\nMay\n".utf8), false),
        ("대문자만 있으면 답이 아니다", Data("Alpha\nBeta\nMarch\nZebra\n".utf8), false),
        ("안쪽 대문자", Data("aBc\nabD\nmArCh\nmay\nzEbRa\n".utf8), false),
        ("안쪽 대문자가 색인을 넘김", Data((innerCaps.joined(separator: "\n") + "\n").utf8), false),
        ("앞 8글자가 같은 낱말", Data((sharedStem.joined(separator: "\n") + "\n").utf8), false),
        ("앞 8글자가 같고 길이가 다름", Data("nonconfo\nnonconfoa\nnonconfoaa\nnonconfob\nnonconfor\nnonconform\nnonconformist\nnonconfot\n".utf8), false),
        ("같은 키 중복", Data("abc\nAbc\nabc\naBc\nabd\nabd\n".utf8), false),
        ("짧은 줄·알파벳 아닌 줄", Data("a\nab\nabc\nab1\nabd\nabe-f\nabg h\n\n\nJean-Pierre\ndon't\nabz\n".utf8), false),
        ("주석과 빈 줄", Data("# count: 3\n\nabc\n\n# note\nabd\n".utf8), false),
        ("UTF-8 밖 바이트와 NUL", { var d = Data("abc\n".utf8); d.append(contentsOf: [0xFF, 0xFE, 0x0A, 0x00, 0x61, 0x62, 0x63, 0x0A]); d.append(Data("abd\n".utf8)); return d }(), false),
        ("빈 파일", Data(), false),
        ("줄바꿈만", Data("\n\n\n".utf8), false),
        ("CRLF", Data((plain.prefix(500).joined(separator: "\r\n") + "\r\n").utf8), false),
        ("일부만 CRLF", Data("abc\r\nabd\nabe\r\nabf\n".utf8), false),
        ("어긋남 조금", Data((fewStray.joined(separator: "\n") + "\n").utf8), false),
        ("어긋남 색인 근처", Data((moved.joined(separator: "\n") + "\n").utf8), false),
        ("plies·pliers", Data("plier\nplies\npliers\nplight\n".utf8), false),
        ("거꾸로", Data((Array(plain.reversed()).joined(separator: "\n") + "\n").utf8), false),
        ("뒤섞음(상한 안)", Data((shuffled(plain, seed: 7).joined(separator: "\n") + "\n").utf8), false),
        ("어긋남이 상한을 넘고 고르게 섞임", Data((manyStrays.joined(separator: "\n") + "\n").utf8), true),
        ("뒤섞음(상한 넘음)", Data((shuffled(sortedWords(40_000), seed: 11).joined(separator: "\n") + "\n").utf8), true),
        ("앞줄 하나가 뒤를 전부 밀어냄", Data((["zzzz"] + sortedWords(20_000)).joined(separator: "\n").utf8), true),
        ("대상 아닌 줄이 길게 이어짐", Data(("abc\n" + capitalRun + "\nabd\n").utf8), true),
        // 2026-11-07 (#175, 독립 리뷰): 위 사례는 파일 끝 검사만 탄다. 가운데 간격도 조회 비용 상한(`maxGapBytes`)을 넘으면 펼쳐야 한다.
        ("대상 아닌 줄이 가운데에 길게 이어짐", Data((plain.prefix(100).joined(separator: "\n") + "\n" + capitalRun + "\n"
            + plain.dropFirst(100).joined(separator: "\n") + "\n").utf8), true),
    ]
    for item in cases {
        let path = scratch + "/system-\(item.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }).txt"
        try? item.bytes.write(to: URL(fileURLWithPath: path))
        let set = EnglishDetector.loadWords(from: [path], expectedCapacity: 0)
        expect(set == oracle(item.bytes), true, "로더 필터 == 따로 적은 필터: \(item.name)")
        guard let file = SystemWordFile(path: path) else {
            expect(false, true, "시스템 파일 열기: \(item.name)")
            continue
        }
        expect(file.isExpanded, item.expanded, "시스템 파일 방식: \(item.name)")
        var queries = Set(set)
        for word in set {
            queries.insert(word + "q")
            queries.insert(String(word.dropLast()))
            queries.insert(word.capitalized)
            queries.insert(word.uppercased())
            queries.insert(String(word.dropFirst()))
        }
        queries.formUnion(["", "a", "ab", "abc", "ABC", "aBc", "march", "March", "may", "abd", "plies", "pliers", "plier",
                           "don't", "ab1", "jean", "alpha", "zebra", "zebr", "capital1", "한글", "ab\r", "abc\r", "naïve", "\u{212A}elvin"])
        let wrong = queries.filter { file.contains($0) != set.contains($0) }.sorted()
        expect(wrong.count, 0, "시스템 파일 == Set: \(item.name) \(wrong.prefix(5))")
    }
    // 필터의 뜻을 낱낱이 고정한다. March는 답이 아니고 mArCh는 답이다. 3글자 미만·알파벳 밖은 답이 아니다.
    let meaning = SystemWordFile(data: Data("Abc\nabd\nab\nMarch\nmArCh\nZebra\nzEbra\nabe1\nabf-g\nabz\n".utf8))
    for (word, want) in [("abc", false), ("abd", true), ("ab", false), ("march", true), ("March", false), ("mArCh", false),
                         ("zebra", true), ("abe1", false), ("abe", false), ("abf", false), ("abz", true), ("", false)] {
        expect(meaning.contains(word), want, "필터의 뜻: \(word)")
    }
    let onlyCapital = SystemWordFile(data: Data("March\nZebra\n".utf8))
    expect(onlyCapital.contains("march"), false, "대문자로만 있으면 답이 아니다")
    // 대문자 줄이 찾는 구간 안에 있어도 답이 아니다.
    let capitalInside = SystemWordFile(data: Data("abc\nJohn\nzeta\n".utf8))
    expect(capitalInside.contains("john"), false, "구간 안의 대문자 줄은 답이 아니다")
    expect(capitalInside.contains("zeta"), true, "구간 안의 대상 줄은 답이다")
    expect(SystemWordFile(data: Data("plier\nplies\npliers\nplight\n".utf8)).strayCount, 1, "어긋난 낱말은 예외 Set으로")
    // 실제 시스템 파일. macOS가 바뀌어도 답이 같아야 하므로 어긋남 개수는 고정하지 않는다.
    let real = "/usr/share/dict/words"
    if let file = SystemWordFile(path: real) {
        let set = EnglishDetector.loadWords(from: [real], expectedCapacity: 0)
        var wrong: [String] = []
        for (index, word) in set.sorted().enumerated() where index % 11 == 0 {
            for query in [word, word + "q", String(word.dropLast()), word.capitalized] where file.contains(query) != set.contains(query) {
                wrong.append(query)
            }
        }
        expect(wrong.count, 0, "실제 시스템 파일 == Set \(wrong.prefix(5))")
        expect(file.isExpanded, false, "실제 시스템 파일은 펼치지 않는다")
    }
    expect(SystemWordFile(path: scratch + "/none.txt") == nil, true, "시스템 파일 없음")
    // 주입한 경로가 실제 판정까지 이어진다.
    let fixture = scratch + "/system-fixture.txt"
    try? "Zebra\nabc\nzythum\n".write(toFile: fixture, atomically: true, encoding: .utf8)
    expect(runDictionaryProbe(fixture, "시스템 탐침: 주입 파일", flag: "--probe-system-words"), true, "시스템 탐침: 주입 파일의 낱말은 변환")
    let without = scratch + "/system-without.txt"
    try? "abc\nzebra\n".write(toFile: without, atomically: true, encoding: .utf8)
    expect(runDictionaryProbe(without, "시스템 탐침: 낱말 없음", flag: "--probe-system-words"), false, "시스템 탐침: 없는 낱말은 변환 안 함")
    expect(runDictionaryProbe(scratch + "/none.txt", "시스템 탐침: 파일 없음", flag: "--probe-system-words"), false, "시스템 탐침: 파일이 없으면 web2 없이 돈다")
}

/// 2026-11-07 (#174, F-6): 배포 사전과 제외 목록의 겹침을 기준선 파일과 대조한다.
/// 기준선은 겹침의 기록일 뿐이다. 오너의 의도된 재등록인지는 여기서 판단하지 않는다.
private func runExclusionOverlapCheck() {
    let baselinePath = "dict_work/exclusion_overlap_baseline.tsv"
    func lines(_ path: String) -> [String] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
    guard FileManager.default.fileExists(atPath: baselinePath) else {
        expect(false, true, "F-6 기준선 파일: \(baselinePath)")
        return
    }
    let exclusions = ["exclusions.txt", "scowl_exclusions_alljamo4.txt"]
    var actual = Set<String>()
    for entry in DictManifest.load() {
        let words = Set(lines(entry.path))
        for name in exclusions {
            for word in lines("dict_work/\(name)") where words.contains(word) {
                actual.insert("\(entry.name)\t\(name)\t\(word)")
            }
        }
    }
    let baseline = Set(lines(baselinePath))
    let added = actual.subtracting(baseline).sorted()
    let stale = baseline.subtracting(actual).sorted()
    expect(added.count, 0, "F-6 제외 목록과 새로 겹친 단어 \(added.prefix(10)) — 탈락시킨 단어가 다시 들어왔는지 확인하고, 의도면 기준선에 사유와 함께 적는다")
    expect(stale.count, 0, "F-6 더는 겹치지 않는 기준선 줄 \(stale.prefix(10)) — 기준선에서 지운다")
}

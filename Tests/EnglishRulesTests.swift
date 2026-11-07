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
    let suite = "local.synthetic.haneul-personal-dict.\(UUID().uuidString)"
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

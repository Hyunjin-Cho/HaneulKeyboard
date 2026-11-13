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

    /// 2026-11-04: 조합이 없을 때 Backspace는 앱이 커서 앞 한 글자를 지운다(실제 호스트 동작 흉내).
    func hostDeleteBackward() {
        guard let index = inserted.lastIndex(where: { !$0.isEmpty }) else { return }
        inserted[index].removeLast()
    }
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
    if AlphanumericWords.isDigit(ch), composer.handleDigit(ch, client: client) { return }
    if KeyboardLayout2Set.jamo(for: ch) != nil {
        _ = composer.handleInput(String(ch), client: client)
        return
    }
    // 2026-11-04: 컨트롤러와 같이 — 붙잡지 않은 숫자·소수점은 앱에 바로 보내고 보낸 숫자열만 기억한다.
    let run: String? = AlphanumericWords.isDigit(ch) ? composer.digitRunAfterSending(ch)
        : ch == "." ? composer.pointRunAfterSending() : nil
    // 흡수되지 않은 비자모 = active boundary. 컨트롤러는 false를 돌려주고
    // 클라이언트가 그 글자를 직접 넣으므로 여기서도 똑같이 기록한다.
    composer.commit(to: client, convertEnglish: true)
    client.insertText(String(ch))
    composer.completeBoundary(ch)
    if AlphanumericWords.isDigit(ch) || ch == "." { composer.setSentDigits(run) }
}

/// 2026-11-04: 컨트롤러의 Backspace 경로 — 조합기가 못 지우면 앱이 지우고, 보낸 숫자열도 한 글자 줄인다.
@discardableResult
func deleteKeyViaController(composer: KoreanComposer, client: FakeClient) -> Bool {
    if composer.deleteBackward(client: client) { return true }
    client.hostDeleteBackward()
    let run = composer.digitRunAfterHostDelete()
    composer.resetEnglishContext()
    composer.setSentDigits(run)
    return false
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
        composer.completeBoundary(" ")
    }
    return committed
}

/// 2026-09-21 (#53): 개인 사전을 실은 composer로 한 단어를 친다. `type()`과 같되
/// `personalDictionary`를 미리 넣는다(컨트롤러가 활성 경계에서 defaults를 읽어 넘기는 자리).
func typeWithPersonalDictionary(
    _ keys: String, _ pd: PersonalDictionary, autoEnglish: Bool = true, passive: Bool = false
) -> (client: FakeClient, composer: KoreanComposer) {
    let client = FakeClient()
    let composer = KoreanComposer()
    composer.autoEnglishEnabled = autoEnglish
    composer.personalDictionary = pd
    for ch in keys { _ = composer.handleInput(String(ch), client: client) }
    composer.commit(to: client, convertEnglish: !passive)
    return (client, composer)
}

/// 위의 컨트롤러 경로 버전 — `'`가 낀 단어(축약형·소유격)를 개인 사전과 함께 본다.
func typeViaControllerWithPersonalDictionary(_ keys: String, _ pd: PersonalDictionary) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    composer.personalDictionary = pd
    for ch in keys { typeKeyViaController(ch, composer: composer, client: client) }
    composer.commit(to: client, convertEnglish: true)
    return client
}

func runDictionaryProbe(_ wordlistPath: String, _ label: String, flag: String = "--probe-kdict") -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = [flag, wordlistPath]
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

// #104 · 2026-10-28: spark is clean Hangul (넴가) but not a Korean headword.
// Register the exact English word without widening Korean veto or Shift rules.
func runSparkRegistrationTests() {
    expect(ManualToggle.keysToHangul("spark") ?? "", "넴가", "spark original two-set composition")
    expect(KoreanDictionary.contains("넴가"), false, "spark original is not a Korean headword")
    for keys in ["spark", "Spark", "SPARK", "spArk"] {
        expect(type(keys).committedText, keys, "spark exact English casing: \(keys)")
        expect(typeViaController(keys + " ").committedText, keys + " ", "spark active Space: \(keys)")
    }
    expect(type("spark", autoEnglish: false).committedText, "넴가", "spark global OFF")
    expect(typePassive("spark").committedText, "넴가", "spark passive boundary preserves marked text")
    for blocked in ["spark", "넴가"] {
        let result = typeWithPersonalDictionary("spark", PersonalDictionary(force: ["spark"], block: [blocked]))
        expect(result.client.committedText, "넴가", "spark personal block wins: \(blocked)")
        expect(result.composer.lastConversion == nil, true, "spark blocked conversion has no pair")
    }
    // 2026-11-07 (#174) 오너 결정: 비완성형 음절 경로(R3)도 혼합 Shift를 막는다. sPark는 이제 녬가로 남는다.
    for shifted in ["spaRk", "sPark"] {
        expect(type(shifted).committedText, ManualToggle.keysToHangul(shifted)!, "spark meaningful internal Shift protects Korean")
    }
    for word in ["학교", "사과", "선반", "세제", "장갑", "넥타이"] {
        expect(type(ManualToggle.hangulToKeys(word)!).committedText, word, "spark registration preserves Korean: \(word)")
    }
    expect(typeWords([ManualToggle.hangulToKeys("오늘")!, "spark"]).last ?? "", "spark", "spark also converts after Korean")
    expect(type("zqsparkzq").committedText, ManualToggle.keysToHangul("zqsparkzq")!, "spark does not register arbitrary containing strings")
    for particle in ["에", "밖에"] {
        expect(type("spark" + ManualToggle.hangulToKeys(particle)!).committedText, "spark" + particle, "spark with supported particle")
    }
    let result = typeWithPersonalDictionary("spark", .empty)
    expect(result.composer.lastConversion?.hangul ?? "", "넴가", "spark stores original Hangul")
    expect(result.composer.lastConversion?.english ?? "", "spark", "spark stores converted English")
    expect(KoreanComposer.resolveToggle(before: "spark ", english: "spark", hangul: "넴가", atDocStart: true)?.text ?? "", "넴가", "spark restores original Hangul")
    expect(KoreanComposer.resolveToggle(before: "넴가 ", english: "spark", hangul: "넴가", atDocStart: true)?.text ?? "", "spark", "spark reapplies saved conversion")
}

// #106 · 2026-11-01: owner-requested pele, kawaii, math terms and standalone ml.
// pele/max/mod were only capitalized in web2 (skipped as proper nouns); the
// others were in no list. Broken forms go to broad, clean theorem/curl to curated.
func runDict106Tests() {
    let broad: [(String, String)] = [
        ("pele", "ㅔ딛"), ("kawaii", "ㅏㅁㅈ먀ㅑ"), ("max", "ㅡㅁㅌ"), ("mod", "ㅡㅐㅇ"),
        ("ker", "ㅏㄷㄱ"), ("inf", "ㅑㅜㄹ"), ("sqrt", "ㄴㅂㄱㅅ"), ("cbrt", "츇"),
        ("cov", "챞"), ("arcsin", "ㅁㄱㅊ냐ㅜ"), ("arccos", "ㅁㄱㅊ챈"), ("arctan", "ㅁㄱㅊㅅ무"),
        ("laplacian", "ㅣ메ㅣㅁ챠무"),
    ]
    let curated: [(String, String)] = [("theorem", "소댁드"), ("curl", "쳐기")]
    for (word, hangul) in broad + curated {
        expect(ManualToggle.keysToHangul(word) ?? "", hangul, "#106 two-set composition: \(word)")
        expect(KoreanDictionary.contains(hangul), false, "#106 original is not a Korean headword: \(word)")
        expect(type(word).committedText, word, "#106 converts: \(word)")
        expect(typeViaController(word + " ").committedText, word + " ", "#106 active Space: \(word)")
        expect(type(word, autoEnglish: false).committedText, hangul, "#106 global OFF: \(word)")
        expect(typePassive(word).committedText, hangul, "#106 passive boundary keeps marked text: \(word)")
        let blocked = typeWithPersonalDictionary(word, PersonalDictionary(block: [word]))
        expect(blocked.client.committedText, hangul, "#106 personal block wins: \(word)")
        let result = typeWithPersonalDictionary(word, .empty)
        expect(result.composer.lastConversion?.hangul ?? "", hangul, "#106 stores original Hangul: \(word)")
        expect(KoreanComposer.resolveToggle(before: word + " ", english: word, hangul: hangul, atDocStart: true)?.text ?? "",
               hangul, "#106 Shift+Space restores original: \(word)")
    }
    // Title Case names keep the typed casing (M is a no-op Shift key in two-set).
    expect(type("Max").committedText, "Max", "#106 Title Case Max")
    expect(typeWords([ManualToggle.hangulToKeys("오늘")!, "pele"]).last ?? "", "pele", "#106 pele after Korean")
    expect(typeWords([ManualToggle.hangulToKeys("정말")!, "kawaii"]).last ?? "", "kawaii", "#106 kawaii after Korean")
    // Clean curated additions must not widen into nearby Korean.
    for word in ["쳐", "쳐서", "소대", "소댁", "학교", "사과"] {
        expect(type(ManualToggle.hangulToKeys(word)!).committedText, word, "#106 preserves Korean: \(word)")
    }
    // Not added: consonant-only 3-key forms (owner excluded, #109 A안), real Korean (veto),
    // 2-consonant pairs (pending the 2-letter policy). cos/abs/ln/pi moved to #109.
    for (keys, hangul) in [("gcd", "ㅎㅊㅇ"), ("det", "ㅇㄷㅅ"), ("std", "ㄴㅅㅇ"),
                           ("cot", "챗"), ("dy", "요"), ("dx", "ㅇㅌ")] {
        expect(type(keys).committedText, hangul, "#106 not added: \(keys)")
    }

    // Standalone ml (ㅢ) converts; mm(ㅡㅡ) stays an emoticon. ok(ㅐㅏ)도 2026-11-07 #194부터 단독 변환한다.
    for keys in ["ml", "mL"] {
        expect(type(keys).committedText, keys, "#106 standalone \(keys)")
        expect(typeViaController(keys + " ").committedText, keys + " ", "#106 standalone \(keys) Space")
        expect(type(keys, autoEnglish: false).committedText, "ㅢ", "#106 \(keys) global OFF")
        expect(typePassive(keys).committedText, "ㅢ", "#106 \(keys) passive boundary")
    }
    for blocked in ["ml", "ㅢ"] {
        expect(typeWithPersonalDictionary("ml", PersonalDictionary(block: [blocked])).client.committedText,
               "ㅢ", "#106 ml personal block: \(blocked)")
    }
    expect(KoreanComposer.resolveToggle(before: "ml ", english: "ml", hangul: "ㅢ", atDocStart: true)?.text ?? "",
           "ㅢ", "#106 ml Shift+Space restores ㅢ")
    expect(type("mm").committedText, "ㅡㅡ", "#106 mm emoticon stays")
    expect(type("dml").committedText, "의", "#106 의 stays Korean")
    expect(typeWords(["ml", ManualToggle.hangulToKeys("우유")!]).last ?? "", "우유", "#106 Korean after ml stays Korean")
}

// #109 · 2026-11-01: owner-chosen math abbreviations (A안). Two-letter vowel-first
// words go to shortWords (R1); clean one-syllable words go to standaloneShortWords.
/// 2026-11-06 (#154): 메뉴바 아이콘 켜고 끄기의 판단.
/// 2026-11-06 (#162): 한국어 사전을 Set에서 파일 매핑으로 바꾸며 정렬·색인 경계를 지킨다.
/// 2026-11-07 (#173): 입력 코어 리뷰 회귀 — 컨트롤러 없이 볼 수 있는 판정·조합 규칙. 컨트롤러 경로는 InputControllerSessionTests.
func runInputCoreReviewTests() {
    // F-3 (오너 결정 2026-11-07): 커서 뒤로 건너뛰는 글자는 같은 줄의 공백(스페이스·탭)과 ! ? . , ) ] } 와 따옴표(' " ’ ”)뿐이다.
    // 같은 날 루트 판단: 오너 결정의 "공백"에 NBSP(U+00A0)를 포함한다 — 크롬 계열 contenteditable이 줄 끝 공백을 NBSP로 줄 수 있다.
    let skippable = [" ", "\t", "\u{a0}", "!", "?", ".", ",", ")", "]", "}", "'", "\"", "’", "”",
                     "... ", "!!! ", "    ", "\t\t", "\u{a0}\u{a0}", " \u{a0}", ",\u{a0}", "), ", "\" ", "’ ", "”, ", String(repeating: " ", count: 40)]
    for trailing in skippable {
        let found = KoreanComposer.wordBeforeCursor(before: "안녕" + trailing, atDocStart: true)
        expect(found?.word ?? "", "안녕", "F-3 건너뜀: \(trailing.debugDescription)")
        expect(found?.trailing ?? -1, (trailing as NSString).length, "F-3 뒤 경계 길이: \(trailing.debugDescription)")
        let toggle = KoreanComposer.resolveToggle(before: "apple" + trailing, english: "apple", hangul: "메ㅔㅣㄷ", atDocStart: true)
        expect(toggle?.text ?? "", "메ㅔㅣㄷ", "F-3 저장 쌍도 같은 글자를 건너뜀: \(trailing.debugDescription)")
    }
    let blocking = ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}", "\n    ", "   \n", " \n ", " 🎬", "🎬 ", "🎬", " 漢字", "漢", "(", "[", "{", "{\n    ",
                    ":", ";", "-", "/", "<", ">", "\u{2003}", "\u{200b}", "\u{3000}", "é", "。", "、", "e\u{301}", "\u{fe0f}"]
    for tail in blocking {
        expect(KoreanComposer.wordBeforeCursor(before: "안녕" + tail, atDocStart: true) == nil, true,
               "F-3 멈춤: \(tail.debugDescription)")
        expect(KoreanComposer.resolveToggle(before: "apple" + tail, english: "apple", hangul: "메ㅔㅣㄷ", atDocStart: true) == nil, true,
               "F-3 저장 쌍도 멈춤: \(tail.debugDescription)")
    }
    expect(KoreanComposer.wordBeforeCursor(before: "func foo() {\n    ", atDocStart: true) == nil, true, "F-3 코드 다음 줄 들여쓰기")
    expect(KoreanComposer.wordBeforeCursor(before: "résumé", atDocStart: true) == nil, true, "F-3 악센트 글자 뒤")
    // 대조: 왼쪽 경계와 단어 찾기는 그대로다.
    expect(KoreanComposer.wordBeforeCursor(before: "func foo() ", atDocStart: true) == nil, true, "F-3 여는 괄호에서 멈춤: foo() 뒤")
    expect(KoreanComposer.wordBeforeCursor(before: "(foo) ", atDocStart: true)?.word ?? "", "foo", "F-3 대조: ) 뒤 공백은 건너뜀")
    expect(KoreanComposer.wordBeforeCursor(before: "🎬 안녕! ", atDocStart: false)?.word ?? "", "안녕", "F-3 대조: 앞쪽 이모지는 경계")
    expect(KoreanComposer.wordBeforeCursor(before: "(\"안녕\") ", atDocStart: true)?.word ?? "", "안녕", "F-3 대조: 닫는 따옴표·괄호")
    expect(KoreanComposer.wordBeforeCursor(before: "첫 줄\n안녕 ", atDocStart: false)?.word ?? "", "안녕", "F-3 대조: 같은 줄의 단어")
    expect(KoreanComposer.wordBeforeCursor(before: String(repeating: " ", count: 64), atDocStart: true) == nil, true, "F-3 대조: 공백뿐이면 nil")

    // F-12: 아포스트로피를 지우면 직전 음절이 다시 열린다(숫자와 같은 결과).
    func composed(_ script: String) -> (client: FakeClient, composer: KoreanComposer) {
        let client = FakeClient(), composer = KoreanComposer()
        for ch in script {
            if ch == "⌫" { deleteKeyViaController(composer: composer, client: client) }
            else { typeKeyViaController(ch, composer: composer, client: client) }
        }
        return (client, composer)
    }
    for (script, expected) in [("a2⌫k", "마"), ("a'⌫k", "마"), ("rks'⌫k", "가나"), ("rk'⌫s", "간"),
                               ("rks'⌫w", "갅"), ("i'⌫", "ㅑ"), ("dkssud'⌫s", "안녕ㄴ"),
                               ("rk'⌫'", "가'"), ("rk'⌫⌫", "ㄱ")] {
        expect(composed(script).client.marked, expected, "F-12 재개: \(script)")
    }
    // 대조: 숫자 유닛 뒤의 아포스트로피는 다시 열 음절이 없다.
    expect(composed("a2'⌫k").client.marked, "ㅁ2ㅏ", "F-12 대조: 앞이 숫자면 재개하지 않음")
    do { // 다시 연 뒤에도 키열이 그대로라 영타 변환이 된다.
        let (client, composer) = composed("apple'⌫")
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText, "apple", "F-12 재개 뒤 영타 변환 유지")
    }

    // F-13: 넘친 입력을 전부 지운 뒤의 새 단어는 넘침 표시를 물려받지 않는다.
    func spilled(_ composer: KoreanComposer, _ client: FakeClient) {
        for _ in 0..<45 { for ch in "rk" { typeKeyViaController(ch, composer: composer, client: client) } }
    }
    do {
        let client = FakeClient(), composer = KoreanComposer()
        spilled(composer, client)
        while composer.hasPendingComposition { _ = composer.deleteBackward(client: client) }
        for ch in "apple" { typeKeyViaController(ch, composer: composer, client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText.hasSuffix("apple"), true, "F-13 전부 지운 뒤 다음 단어 변환")
    }
    do { // 대조: 일부만 지우면 아직 긴 입력의 연속이라 변환하지 않는다.
        let client = FakeClient(), composer = KoreanComposer()
        spilled(composer, client)
        _ = composer.deleteBackward(client: client)
        for ch in "apple" { typeKeyViaController(ch, composer: composer, client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText.hasSuffix("메ㅔㅣㄷ"), true, "F-13 대조: 일부 삭제는 넘침 유지")
    }
    do { // 대조: 지우지 않고 이어 치면 변환하지 않고, 경계를 친 다음 단어는 변환한다.
        let client = FakeClient(), composer = KoreanComposer()
        spilled(composer, client)
        for ch in "apple" { typeKeyViaController(ch, composer: composer, client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText.hasSuffix("메ㅔㅣㄷ"), true, "F-13 대조: 넘침 뒤 이어 친 단어")
        for ch in "apple" { typeKeyViaController(ch, composer: composer, client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText.hasSuffix("apple"), true, "F-13 대조: 경계 뒤 단어는 변환")
    }
    do { // 숫자 넘침은 조합이 빈 채로 refresh한다 — 넘침 표시를 그 자리에서 지우면 뒤 숫자가 새 후보가 된다.
        let client = FakeClient(), composer = KoreanComposer()
        for ch in "a" + String(repeating: "2", count: 90) { typeKeyViaController(ch, composer: composer, client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(client.committedText, "ㅁ" + String(repeating: "2", count: 90), "F-13 대조: 숫자 넘침 유실 없음")
    }

    // F-4: 글자를 넣는 왕복 중 세션 콜백이 commit을 다시 불러도 한 번만 들어간다. 상태를 먼저 비우고 왕복한다.
    final class ReentrantClient: ComposerClient {
        var inserted: [String] = []
        var marked = ""
        var onInsert: (() -> Void)?
        func insertText(_ text: String) {
            inserted.append(text)
            let callback = onInsert
            onInsert = nil
            callback?()
        }
        func setMarkedText(_ text: String) { marked = text }
    }
    for (keys, convert, expected) in [("rk", true, "가"), ("rk", false, "가"), ("apple", true, "apple"),
                                      ("apple", false, "메ㅔㅣㄷ"), ("githubdp", true, "github에"),
                                      ("a24", true, "a24"), ("rk'", true, "가'")] {
        let client = ReentrantClient(), composer = KoreanComposer()
        for ch in keys {
            if Contractions.isApostrophe(ch) { _ = composer.handleApostrophe(ch, client: client) }
            else if AlphanumericWords.isDigit(ch) { _ = composer.handleDigit(ch, client: client) }
            else { _ = composer.handleInput(String(ch), client: client) }
        }
        var nested = "(없음)"
        client.onInsert = {
            nested = composer.commit(to: client)
            composer.resetEnglishContext()
        }
        expect(composer.commit(to: client, convertEnglish: convert), expected, "F-4 바깥 확정 \(keys) \(convert)")
        expect(client.inserted.joined(), expected, "F-4 글자가 한 번만 들어감 \(keys) \(convert)")
        expect(nested, "", "F-4 재진입 commit은 넣을 것이 없음 \(keys) \(convert)")
        expect(composer.hasPendingComposition, false, "F-4 조합이 남지 않음 \(keys) \(convert)")
        expect(composer.lastConversion == nil && composer.lastEnglishWord == nil, true,
               "F-4 재진입이 끝낸 세션의 쌍을 되살리지 않음 \(keys) \(convert)")
    }
    do { // 넘침 왕복 중 재진입: 내보내는 중인 단어를 다시 넣지 않는다.
        let client = ReentrantClient(), composer = KoreanComposer()
        for _ in 0..<45 {
            client.onInsert = { composer.commit(to: client) }
            for ch in "rk" { _ = composer.handleInput(String(ch), client: client) }
        }
        client.onInsert = nil
        composer.commit(to: client)
        expect(client.inserted.joined(), String(repeating: "가", count: 45), "F-4 넘침 재진입에도 글자가 늘지 않음")
    }
    do { // 대조: 재진입이 없으면 쌍·문맥을 평소대로 세운다.
        let client = ReentrantClient(), composer = KoreanComposer()
        for ch in "apple" { _ = composer.handleInput(String(ch), client: client) }
        expect(composer.commit(to: client, convertEnglish: true), "apple", "F-4 대조 확정")
        expect(composer.lastConversion?.hangul ?? "", "메ㅔㅣㄷ", "F-4 대조 쌍")
        expect(composer.lastEnglishWord ?? "", "apple", "F-4 대조 문맥")
    }

    // F-14: 키 이벤트에서 글자를 고르는 inputCharacter를 직접 시험한다.
    func input(_ ignoring: String?, _ characters: String?, keyCode: Int = 0, shifted: Bool = false) -> String {
        KeyboardLayout2Set.inputCharacter(charactersIgnoringModifiers: ignoring, characters: characters,
                                          keyCode: keyCode, shifted: shifted).map(String.init) ?? "nil"
    }
    for letter in "abcdefghijklmnopqrstuvwxyz" {
        let lower = String(letter), upper = lower.uppercased()
        expect(input(lower, lower), lower, "inputCharacter 소문자 \(lower)")
        expect(input(lower, upper, shifted: true), upper, "inputCharacter Shift \(lower)")
        expect(input(upper, upper, shifted: true), upper, "inputCharacter 대문자 + Shift \(lower)")
        expect(input(upper, upper), lower, "inputCharacter CapsLock형: Shift 없으면 소문자 \(lower)")
        expect(input("", lower), lower, "inputCharacter 빈 문자열이면 characters \(lower)")
        expect(input(nil, upper, shifted: true), upper, "inputCharacter nil이면 characters \(lower)")
    }
    for (code, lower) in [(0, "a"), (11, "b"), (15, "r"), (40, "k"), (46, "m"), (6, "z")] {
        expect(input(nil, nil, keyCode: code), lower, "inputCharacter 물리 키 \(code)")
        expect(input(nil, nil, keyCode: code, shifted: true), lower.uppercased(), "inputCharacter 물리 키 Shift \(code)")
    }
    for code in [18, 36, 48, 49, 53] { expect(input(nil, nil, keyCode: code), "nil", "inputCharacter 글자 키가 아닌 물리 키 \(code)") }
    expect(input("", "", keyCode: 0), "nil", "inputCharacter 빈 문자열은 물리 키로 넘기지 않음")
    expect(input("", "1", keyCode: 18), "nil", "inputCharacter characters가 숫자")
    expect(input(nil, "é", keyCode: 14), "nil", "inputCharacter characters가 비 ASCII")
    for text in ["1", "!", " ", "\r", "\t", "\u{1b}", "'", "/", "é", "ㅁ", "한", "😀"] {
        for shifted in [false, true] { expect(input(text, text, shifted: shifted), "nil", "inputCharacter 자모 아님 \(text.debugDescription) \(shifted)") }
    }
    // 2026-11-07 (#173, 독립 리뷰 A-P3-2): 대문자가 두 글자가 되는 문자는 Debug에서 트랩이 났다(Release는 nil).
    for text in ["ß", "ﬁ", "ŉ"] {
        for shifted in [false, true] {
            expect(input(text, text, shifted: shifted), "nil", "inputCharacter 대문자가 두 글자 \(text) \(shifted)")
            expect(input(nil, text, shifted: shifted), "nil", "inputCharacter 대문자가 두 글자(characters) \(text) \(shifted)")
        }
    }
}

/// 2026-11-12 (#224): 입력 코어 리뷰 2차 — 컨트롤러 없이 볼 수 있는 조합 규칙. 컨트롤러 경로는 InputControllerSessionTests.
func runInputCoreReview1112Tests() {
    func composed(_ script: String) -> (client: FakeClient, composer: KoreanComposer) {
        let client = FakeClient(), composer = KoreanComposer()
        for ch in script {
            if ch == "⌫" { deleteKeyViaController(composer: composer, client: client) }
            else { typeKeyViaController(ch, composer: composer, client: client) }
        }
        return (client, composer)
    }
    func hasLatin(_ text: String) -> Bool { text.contains { $0.isASCII && $0.isLetter } }

    // F-7: 숫자 뒤 낱말을 Backspace로 고친 뒤의 능동 경계는 보이던 한글 그대로다(숫자가 없을 때와 같다).
    for (script, shown) in [("6gksrmfk⌫", "6한그ㄹ"), ("3rksk⌫", "3가ㄴ"), ("1rs⌫k", "1ㄱㅏ"),
                            ("gksrmfk⌫", "한그ㄹ"), ("rksk⌫", "가ㄴ"), ("rs⌫k", "ㄱㅏ")] {
        let (client, composer) = composed(script)
        expect(client.committedText + client.marked, shown, "F-7 화면: \(script)")
        typeKeyViaController(" ", composer: composer, client: client)
        expect(client.committedText, shown + " ", "F-7 Space 뒤 보이던 그대로: \(script)")
        if let pair = composer.lastConversion {
            expect(shown.hasSuffix(pair.hangul), true, "F-7 되돌림 쌍의 한글도 보이던 그대로: \(script)")
        }
    }
    // 대조: 숫자 뒤 낱말의 변환·단위·영숫자 이름은 그대로다.
    for (script, expected) in [("10kg ", "10kg "), ("3d ", "3d "), ("10apple ", "10apple "), ("1dkssud ", "1안녕 "), ("a24 ", "a24 ")] {
        let (client, _) = composed(script)
        expect(client.committedText, expected, "F-7 대조: \(script)")
    }
    // 무작위: 숫자 + 자모 + Backspace를 섞어 Space로 확정한다. 영어로 바뀌지 않았으면 보이던 글자와 같아야 한다.
    var rng = SeededGenerator(state: 0x2026_1112_0224_F007)
    let letters = Array("abcdefghijklmnopqrstuvwxyzQWERTOP")
    var trials = 0, mismatches = 0, pairMismatches = 0
    var samples: [String] = []
    for _ in 0..<20_000 {
        var script = String(Character(String(Int.random(in: 0...9, using: &rng))))
        for _ in 0..<Int.random(in: 1...10, using: &rng) {
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.22 { script.append("⌫") }
            else if roll < 0.30 { script.append(Character(String(Int.random(in: 0...9, using: &rng)))) }
            else { script.append(letters.randomElement(using: &rng)!) }
        }
        let (client, composer) = composed(script)
        let shown = client.committedText + client.marked
        typeKeyViaController(" ", composer: composer, client: client)
        let committed = client.committedText
        trials += 1
        guard !hasLatin(shown) else { continue }   // 조사 미리보기(github에)는 문서에 적힌 다른 동작이다
        if !hasLatin(committed), committed != shown + " " {
            mismatches += 1
            if samples.count < 6 { samples.append("\(script.debugDescription): 화면 \(shown) → \(committed)") }
        }
        if let pair = composer.lastConversion, !shown.hasSuffix(pair.hangul) {
            pairMismatches += 1
            if samples.count < 6 { samples.append("쌍 \(script.debugDescription): 화면 \(shown) 쌍 \(pair.hangul)") }
        }
    }
    samples.forEach { print("F-7 무작위 표본: \($0)") }
    expect(trials, 20_000, "F-7 무작위: 시험 횟수")
    expect(mismatches == 0 && pairMismatches == 0, true, "F-7 무작위: 표본 없음")
    expect(mismatches, 0, "F-7 무작위: 영어로 안 바뀐 낱말은 보이던 그대로")
    expect(pairMismatches, 0, "F-7 무작위: 되돌림 쌍의 한글은 보이던 그대로")

    // F-6: 커서가 방금 넣은 자리 그대로라고 확인됐을 때만 왼쪽 경계를 묻지 않는다(기본값은 지금처럼 묻는다).
    for (before, english, hangul, expected) in [("안녕1apple ", "apple", "메ㅔㅣㄷ", "메ㅔㅣㄷ"), ("APIapple ", "apple", "메ㅔㅣㄷ", "메ㅔㅣㄷ"),
                                                ("버전2beta ", "beta", "ㅠㄷ싸", "ㅠㄷ싸"), ("안녕1메ㅔㅣㄷ ", "apple", "메ㅔㅣㄷ", "apple")] {
        let found = KoreanComposer.resolveToggle(before: before, english: english, hangul: hangul, atDocStart: true,
                                                 requireLeftBoundary: false)
        expect(found?.text ?? "", expected, "F-6 붙여 친 낱말 되돌리기: \(before)")
        expect(found?.replaceLen ?? -1, ((expected == hangul ? english : hangul) as NSString).length, "F-6 교체 길이: \(before)")
        expect(found?.offsetFromEnd ?? -1, ((expected == hangul ? english : hangul) as NSString).length + 1, "F-6 커서 오프셋: \(before)")
        expect(KoreanComposer.resolveToggle(before: before, english: english, hangul: hangul, atDocStart: true) == nil, true,
               "F-6 대조: 기본값은 왼쪽 경계를 묻는다: \(before)")
    }

    // F-1 (오너 결정 가): Shift 겹쳐 누름 판정 — 순수 함수.
    let mShift: UInt = 0x20000, mControl: UInt = 0x40000, mOption: UInt = 0x80000, mCommand: UInt = 0x100000
    let mCapsLock: UInt = 0x10000, mFunction: UInt = 0x800000
    for (text, code, mods, expected, label): (String?, UInt16, UInt, Bool, String) in [
        ("P", 35, mShift, true, "Shift+ㅖ"), ("R", 15, mShift, true, "Shift+ㄲ"), ("?", 44, mShift, true, "물음표"),
        ("!", 18, mShift, true, "느낌표"), (")", 29, mShift, true, "닫는 괄호"), ("\"", 39, mShift, true, "큰따옴표"),
        ("P", 35, mShift | mCapsLock, true, "CapsLock 켠 한글 모드"), ("P", 35, mShift | 0x0002, true, "오른쪽 Shift 장치 비트"),
        ("Ø", 31, mShift | mOption, true, "Option+Shift 글자"),
        ("p", 35, 0, false, "Shift 없는 글자"), (" ", 49, mShift, false, "Shift+Space"), ("\r", 36, mShift, false, "Shift+Return"),
        ("\u{3}", 76, mShift, false, "Shift+키패드 Enter"), ("\u{19}", 48, mShift, false, "Shift+Tab"),
        ("P", 35, mShift | mCommand, false, "Cmd+Shift 단축키"), ("P", 35, mShift | mControl, false, "Ctrl+Shift 단축키"),
        ("\u{f700}", 126, mShift | mFunction, false, "Shift+화살표"), (nil, 35, mShift, false, "문자 없음"), ("", 35, mShift, false, "빈 문자"),
        ("\u{7f}", 51, mShift, false, "Shift+Backspace"), ("ab", 0, mShift, false, "두 글자"),
    ] {
        expect(RevertKey.isShiftedCharacterKey(keyCode: code, modifierFlagsRaw: mods, characters: text), expected,
               "F-1 Shift 글자 키 판정: \(label)")
    }
    expect(RevertKey.shiftRolloverWindow == 0.35, true, "F-1 겹쳐 누름 간격 0.35초(오너 결정)")
    for (elapsed, expected) in [(0.0, true), (0.05, true), (0.34, true), (0.36, false), (1.0, false), (-0.1, false)] {
        expect(RevertKey.shiftSpace.isShiftRollover(previousShiftedCharacterAt: 100, now: 100 + elapsed), expected,
               "F-1 Shift+Space 겹쳐 누름 \(elapsed)초")
    }
    expect(RevertKey.shiftSpace.isShiftRollover(previousShiftedCharacterAt: nil, now: 100), false, "F-1 직전이 Shift 글자가 아님")
    for key in [RevertKey.optionSpace, .controlShiftSpace, .optionShiftSpace] {
        expect(key.isShiftRollover(previousShiftedCharacterAt: 100, now: 100.05), false,
               "F-1 다른 수정자를 일부러 누르는 단축키는 해당 없음: \(key.rawValue)")
    }
}

// MARK: - 참조 자동기 무작위 시험 (2026-11-07, #173 리뷰 F-14)

/// 고정 시드 난수(SplitMix64). 시스템 난수를 쓰면 실패가 재현되지 않는다.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `KoreanComposer`의 전이를 베끼지 않고 자모 표만 써서 따로 구현한 두벌식 자동기.
/// 음절 하나를 초성·중성 목록·종성 목록으로 들고 있어 조합기(버퍼 + 복합 표)와 구현 방식이 다르다.
struct ReferenceComposer {
    struct Unit {
        var initial: Consonant?
        var medials: [Vowel] = []
        var finals: [Consonant] = []
        var keys: [Character] = []
        var literal: Character?

        var isEmpty: Bool { initial == nil && medials.isEmpty && finals.isEmpty && literal == nil }
        var text: String {
            if let literal { return String(literal) }
            let vowel = medials.count == 2 ? Vowel.combine(medials[0], medials[1]) : medials.first
            guard let vowel else { return initial.map { String($0.compatibility) } ?? "" }
            guard let initial else { return String(vowel.compatibility) }
            var finalIndex = 0
            if finals.count == 1 { finalIndex = finals[0].finalIndex! }
            if finals.count == 2 { finalIndex = CompoundFinal.index(first: finals[0], second: finals[1])! }
            return String(UnicodeScalar(UInt32(0xAC00 + (initial.initialIndex * 21 + vowel.medialIndex) * 28 + finalIndex))!)
        }
    }
    var done: [Unit] = []
    var current = Unit()

    var text: String { done.map(\.text).joined() + current.text }
    var keys: [Character] { done.flatMap(\.keys) + current.keys }

    private mutating func flush() {
        if !current.isEmpty { done.append(current) }
        current = Unit()
    }
    private mutating func startConsonant(_ consonant: Consonant, key: Character) {
        flush()
        current.initial = consonant
        current.keys = [key]
    }
    mutating func type(_ key: Character) {
        switch KeyboardLayout2Set.jamo(for: key)! {
        case .consonant(let consonant):
            if current.medials.isEmpty || current.initial == nil {
                startConsonant(consonant, key: key)
            } else if current.finals.isEmpty, consonant.finalIndex != nil {
                current.finals = [consonant]
                current.keys.append(key)
            } else if current.finals.count == 1, CompoundFinal.index(first: current.finals[0], second: consonant) != nil {
                current.finals.append(consonant)
                current.keys.append(key)
            } else {
                startConsonant(consonant, key: key)
            }
        case .vowel(let vowel):
            if !current.finals.isEmpty {                       // 도깨비불: 마지막 받침이 다음 음절의 초성이 된다
                let carry = current.finals.removeLast()
                let carryKey = current.keys.removeLast()
                flush()
                current.initial = carry
                current.medials = [vowel]
                current.keys = [carryKey, key]
            } else if current.medials.count == 1, Vowel.combine(current.medials[0], vowel) != nil {
                current.medials.append(vowel)
                current.keys.append(key)
            } else {
                if !current.medials.isEmpty { flush() }
                current.medials = [vowel]
                current.keys.append(key)
            }
        }
    }
    /// 조합이 비어 있거나 이미 아포스트로피가 있으면 false(앱으로 넘어가는 경계다).
    mutating func apostrophe(_ key: Character) -> Bool {
        guard !(done.isEmpty && current.isEmpty), !done.contains(where: { $0.literal != nil }) else { return false }
        flush()
        done.append(Unit(keys: [key], literal: key))
        return true
    }
    /// 조합이 비어 있어 앱이 지울 차례면 false.
    mutating func back() -> Bool {
        if !current.isEmpty {
            if !current.finals.isEmpty { current.finals.removeLast() }
            else if !current.medials.isEmpty { current.medials.removeLast() }
            else { current.initial = nil }
            if !current.keys.isEmpty { current.keys.removeLast() }
            return true
        }
        guard let removed = done.popLast() else { return false }
        if removed.literal != nil, let previous = done.last, previous.literal == nil { current = done.removeLast() }
        return true
    }
}

func runReferenceAutomatonFuzzTests() {
    final class Sink: ComposerClient {
        var inserted = ""
        var marked = ""
        func insertText(_ text: String) { inserted += text; marked = "" }
        func setMarkedText(_ text: String) { marked = text }
    }
    enum Step { case key(Character), apostrophe, back }
    func describe(_ steps: [Step]) -> String {
        steps.map { step -> String in
            switch step {
            case .key(let key): return String(key)
            case .apostrophe: return "'"
            case .back: return "⌫"
            }
        }.joined()
    }
    func apply(_ step: Step, to composer: KoreanComposer, _ sink: Sink) -> Bool {
        switch step {
        case .key(let key): return composer.handleInput(String(key), client: sink)
        case .apostrophe: return composer.handleApostrophe("'", client: sink)
        case .back: return composer.deleteBackward(client: sink)
        }
    }
    let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var rng = SeededGenerator(state: 0x4841_4E45_554C_0173)
    var trials = 0, surfaceMismatch = 0, keyMismatch = 0, passiveMismatch = 0
    var samples: [String] = []
    for backRate in [0.0, 0.15, 0.35] {
        for _ in 0..<fuzzTrialsPerRate {
            trials += 1
            let steps: [Step] = (0..<Int.random(in: 1...14, using: &rng)).map { _ in
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < backRate { return .back }
                if roll < backRate + 0.05 { return .apostrophe }
                return .key(letters.randomElement(using: &rng)!)
            }
            // 1) 매 키마다 화면과 반환값이 참조 자동기와 같다.
            let sink = Sink(), composer = KoreanComposer()
            composer.autoEnglishEnabled = false
            var reference = ReferenceComposer()
            var matches = true
            for step in steps {
                let expected: Bool
                switch step {
                case .key(let key): reference.type(key); expected = true
                case .apostrophe: expected = reference.apostrophe("'")
                case .back: expected = reference.back()
                }
                if apply(step, to: composer, sink) != expected || sink.marked != reference.text { matches = false }
            }
            if !matches {
                surfaceMismatch += 1
                if samples.count < 8 { samples.append("화면 \(describe(steps)) 조합기=[\(sink.marked)] 참조=[\(reference.text)]") }
                continue
            }
            // 2) 조합기가 보관한 키열이 참조와 같다 — 지운 뒤에도 영타 변환이 친 그대로 나와야 한다.
            let keys = String(reference.keys)
            if !keys.isEmpty {
                let keySink = Sink(), keyComposer = KoreanComposer()
                keyComposer.autoEnglishEnabled = false
                for step in steps { _ = apply(step, to: keyComposer, keySink) }
                keyComposer.autoEnglishEnabled = true
                // 2026-11-07 (#174): 혼합 대소문자는 등록한 표기와 정확히 같아야 force다. 참조 키열 자체를 등록 표기로 넣어 키열이 같은지 본다.
                keyComposer.personalDictionary = PersonalDictionary(force: [Contractions.normalizedKey(reference.keys)],
                                                                    registeredSpellings: [keys])
                let converted = keyComposer.commit(to: keySink, convertEnglish: true)
                if converted != keys {
                    keyMismatch += 1
                    if samples.count < 8 { samples.append("키열 \(describe(steps)) 조합기=[\(converted)] 참조=[\(keys)]") }
                }
            }
            // 3) 클릭·포커스 이동의 확정은 화면에 보이던 그대로다.
            let shown = sink.marked
            if composer.commit(to: sink) != shown { passiveMismatch += 1 }
        }
    }
    // 4) 긴 입력: 40유닛 넘침을 지나도 글자가 사라지거나 늘지 않는다.
    var spillMismatch = 0
    for _ in 0..<fuzzLongRuns {
        let sink = Sink(), composer = KoreanComposer()
        composer.autoEnglishEnabled = false
        var reference = ReferenceComposer()
        var matches = true
        for _ in 0..<Int.random(in: 40...120, using: &rng) {
            let key = letters.randomElement(using: &rng)!
            reference.type(key)
            _ = composer.handleInput(String(key), client: sink)
            if sink.inserted + sink.marked != reference.text { matches = false }
        }
        composer.commit(to: sink)
        if !matches || sink.inserted != reference.text { spillMismatch += 1 }
    }
    // 5) 완성형 두 음절의 자판 왕복(도깨비불·겹받침 경계). 한 음절 전수는 위 시험이 맡는다.
    var roundTripMismatch = 0
    for _ in 0..<fuzzRoundTrips {
        let word = String(UnicodeScalar(UInt32.random(in: 0xAC00...0xD7A3, using: &rng))!)
            + String(UnicodeScalar(UInt32.random(in: 0xAC00...0xD7A3, using: &rng))!)
        if ManualToggle.keysToHangul(ManualToggle.hangulToKeys(word) ?? "") != word { roundTripMismatch += 1 }
    }
    samples.forEach { print("참조 자동기 불일치 표본: \($0)") }
    expect(trials, fuzzTrialsPerRate * 3, "참조 자동기: 시험 횟수")
    expect(surfaceMismatch, 0, "참조 자동기: 화면·반환값")
    expect(keyMismatch, 0, "참조 자동기: 보관 키열")
    expect(passiveMismatch, 0, "참조 자동기: 수동 확정은 보이던 그대로")
    expect(spillMismatch, 0, "참조 자동기: 넘침 뒤 글자 보존")
    expect(roundTripMismatch, 0, "참조 자동기: 두 음절 왕복")
}
// 고정 시드라 언제나 같은 열을 돈다. 2026-11-07 무최적화 빌드 실측 약 3초(상한 +5초)로 잡은 횟수다.
let fuzzTrialsPerRate = 12_000
let fuzzLongRuns = 800
let fuzzRoundTrips = 12_000

func runSortedWordTableTests() {
    func table(_ text: String) -> SortedWordTable { SortedWordTable(data: Data(text.utf8)) }
    func has(_ t: SortedWordTable, _ word: String) -> Bool { t.contains(Array(word.utf8)) }
    // 색인 간격(64줄)을 몇 번 넘는 크기. 경계 앞뒤의 낱말을 빠짐없이 찾아야 한다.
    let words = (0..<200).map { String(format: "w%03d", $0) }
    let full = table("# count: 200\n# note\n" + words.joined(separator: "\n") + "\n")
    expect(full.isComplete, true, "정렬 표: 정렬·개수가 맞으면 온전하다")
    expect(words.allSatisfy { has(full, $0) }, true, "정렬 표: 모든 낱말을 찾는다(색인 경계 포함)")
    for missing in ["", "v", "w", "w00", "w0000", "w1995", "w200", "x", "# note", "# count: 200"] {
        expect(has(full, missing), false, "정렬 표: 없는 말 \(missing)")
    }
    let noNewline = table("# count: 2\n가\n나")
    expect(noNewline.isComplete, true, "정렬 표: 마지막 줄바꿈이 없어도 온전하다")
    expect(has(noNewline, "나"), true, "정렬 표: 마지막 줄바꿈 없는 끝 낱말")
    expect(has(noNewline, "다"), false, "정렬 표: 끝 낱말 뒤는 없다")
    // fail-closed: 온전하지 않으면 자동 변환이 꺼진다.
    expect(table("# count: 2\n나\n가\n").isComplete, false, "정렬 표: 정렬이 깨지면 온전하지 않다")
    expect(table("가\n나\n").isComplete, false, "정렬 표: 개수 머리글이 없으면 온전하지 않다")
    expect(table("# count: 3\n가\n나\n").isComplete, false, "정렬 표: 개수가 다르면 온전하지 않다")
    expect(table("").isComplete, false, "정렬 표: 빈 파일")
    expect(table("# count: 0\n").isComplete, false, "정렬 표: 머리글만 있는 파일")
    expect(has(table(""), "가"), false, "정렬 표: 빈 파일 조회")
    expect(table("# count: 2\n가\n가\n나\n").uniqueCount, 2, "정렬 표: 이웃한 같은 줄은 하나로 센다")
    var broken = Data("# count: 1\n가\n".utf8); broken.append(contentsOf: [0xFF, 0xFE, 0x0A])
    expect(SortedWordTable(data: broken).uniqueCount, 1, "정렬 표: 깨진 UTF-8 줄은 세지 않는다")
    // 구간 조회: mayContinue가 쓴다.
    func span(_ low: String, _ high: String) -> Bool { full.hasWord(from: Array(low.utf8), below: Array(high.utf8)) }
    expect(span("w05", "w06"), true, "정렬 표: 구간 안에 낱말이 있다")
    expect(span("w063", "w065"), true, "정렬 표: 색인 경계를 걸친 구간")
    expect(span("w1999", "w2"), false, "정렬 표: 끝 낱말 뒤 구간")
    expect(span("a", "b"), false, "정렬 표: 첫 낱말 앞 구간")
}

func runLoginItemTests() {
    let app = "/Applications/HaneulKeyboard.app"
    func auto(_ done: Bool, _ tried: Bool, _ path: String, icon: Bool = true) -> Bool {
        LoginItemDecision.shouldAutoRegister(onboardingDone: done, iconVisible: icon, alreadyTried: tried, bundlePath: path)
    }
    expect(auto(true, false, app), true, "로그인 항목: 안내를 끝낸 설치본은 자동으로 켠다")
    expect(auto(false, false, app), false, "로그인 항목: 안내 전에는 켜지 않는다")
    expect(auto(true, true, app), false, "로그인 항목: 한 번 시도했으면 다시 켜지 않는다(사용자가 끈 것 존중)")
    expect(auto(true, false, "/Users/a/Downloads/HaneulKeyboard.app"), false, "로그인 항목: 응용 프로그램 밖이면 켜지 않는다")
    expect(auto(true, false, "/Users/a/Library/Developer/Xcode/DerivedData/x/HaneulKeyboard.app"), false, "로그인 항목: 개발 빌드는 켜지 않는다")
    // 2026-11-08 (#201): 아이콘 토글 하나가 로그인 항목까지 정한다.
    expect(auto(true, false, app, icon: false), false, "로그인 항목: 아이콘을 꺼 둔 채면 켜지 않는다")
}

func runAppBundleWatchTests() {
    func quit(_ path: String?, _ exists: Bool, busy: Bool = false) -> Bool {
        AppBundleWatchDecision.shouldQuit(currentPath: path, originalPathExists: exists, busy: busy)
    }
    expect(quit("/Applications/HaneulKeyboard.app", true), false, "번들 감시: 제자리면 계속")
    expect(quit("/Users/a/.Trash/HaneulKeyboard.app", false), true, "번들 감시: 휴지통이면 종료")
    expect(quit("/Volumes/X/.Trashes/501/HaneulKeyboard.app", false), true, "번들 감시: 외장 볼륨 휴지통이면 종료")
    expect(quit("/Users/a/.Trash/HaneulKeyboard.app", true), true, "번들 감시: 새 번들을 두고 옛것을 버려도 종료")
    expect(quit("/Users/a/Apps/HaneulKeyboard.app", false), false, "번들 감시: 다른 폴더로 옮긴 건 버린 게 아니다")
    expect(quit("/Users/a/Trash-like/HaneulKeyboard.app", false), false, "번들 감시: 비슷한 폴더 이름에 속지 않는다")
    expect(quit(nil, false), true, "번들 감시: 지워졌으면 종료")
    expect(quit(nil, true), false, "번들 감시: 새 번들로 교체됐으면 계속")
    expect(quit("/Users/a/.Trash/HaneulKeyboard.app", false, busy: true), false, "번들 감시: 전체 제거 중이면 끼어들지 않는다")
    expect(quit(nil, false, busy: true), false, "번들 감시: 업데이트 교체 중 빈 순간에 끝나지 않는다")
}

func runMenuBarIconTests() {
    expect(MenuBarIconDecision.isVisible(storedValue: nil), true, "아이콘: 저장값 없으면 켜짐")
    expect(MenuBarIconDecision.isVisible(storedValue: true), true, "아이콘: 켜 둠")
    expect(MenuBarIconDecision.isVisible(storedValue: false), false, "아이콘: 꺼 둠")
    expect(MenuBarIconDecision.isVisible(storedValue: "no"), true, "아이콘: 이상한 값이면 켜짐으로 본다")
    func win(_ done: Bool, _ icon: Bool, _ login: Bool) -> String {
        switch MenuBarIconDecision.launchWindow(onboardingDone: done, iconVisible: icon, launchedAsLoginItem: login) {
        case .onboarding: return "안내"
        case .settings: return "설정"
        case .none: return "없음"
        }
    }
    expect(win(false, true, false), "안내", "아이콘: 안내를 안 끝냈으면 안내")
    expect(win(false, false, true), "안내", "아이콘: 안내 우선은 로그인 실행에서도 종전대로")
    expect(win(true, true, false), "없음", "아이콘: 켜져 있으면 창 없이 시작")
    expect(win(true, true, true), "없음", "아이콘: 켜져 있고 로그인 실행이어도 창 없음")
    expect(win(true, false, false), "설정", "아이콘: 끈 채 직접 열면 설정 창")
    expect(win(true, false, true), "없음", "아이콘: 끈 채 로그인 실행이면 창 없음")
}

func runMath109Tests() {
    // 2026-11-07 (#174) 오너 결정: cos=챈은 단독 변환에서 뺐다. 검사는 Tests/EnglishRulesTests.swift의 F-8.
    let words: [(String, String)] = [
        ("ln", "ㅣㅜ"), ("pi", "ㅔㅑ"), ("mu", "ㅡㅕ"), ("nu", "ㅜㅕ"),
        ("abs", "뮨"), ("xi", "탸"),
    ]
    for (word, hangul) in words {
        expect(ManualToggle.keysToHangul(word) ?? "", hangul, "#109 two-set composition: \(word)")
        expect(KoreanDictionary.contains(hangul), false, "#109 original is not a Korean headword: \(word)")
        expect(EnglishDetector.protectedSlang.contains(hangul), false, "#109 original is not protected slang: \(word)")
        expect(type(word).committedText, word, "#109 converts: \(word)")
        expect(typeViaController(word + " ").committedText, word + " ", "#109 active Space: \(word)")
        expect(type(word, autoEnglish: false).committedText, hangul, "#109 global OFF: \(word)")
        expect(typePassive(word).committedText, hangul, "#109 passive boundary keeps marked text: \(word)")
        for blocked in [word, hangul] {
            expect(typeWithPersonalDictionary(word, PersonalDictionary(block: [blocked])).client.committedText,
                   hangul, "#109 personal block wins: \(word)/\(blocked)")
        }
        let result = typeWithPersonalDictionary(word, .empty)
        expect(result.composer.lastConversion?.hangul ?? "", hangul, "#109 stores original Hangul: \(word)")
        expect(KoreanComposer.resolveToggle(before: word + " ", english: word, hangul: hangul, atDocStart: true)?.text ?? "",
               hangul, "#109 Shift+Space restores original: \(word)")
        expect(typeWords([ManualToggle.hangulToKeys("그래서")!, word]).last ?? "", word, "#109 converts after Korean: \(word)")
    }
    // Title Case keeps the typed casing (C/A/X/M/N are no-op Shift keys in two-set; P gives ㅖ).
    for keys in ["Cos", "Abs", "Xi", "Pi"] {
        expect(type(keys).committedText, keys, "#109 Title Case: \(keys)")
    }
    // Nearby real Korean stays Korean: cot=챗(veto), and longer words built from these syllables.
    for word in ["챗", "챈스", "탸", "학교", "그래서", "뮤지컬"] where KoreanDictionary.contains(word) {
        expect(type(ManualToggle.hangulToKeys(word)!).committedText, word, "#109 preserves Korean: \(word)")
    }
    expect(type("cot").committedText, "챗", "#109 cot stays Korean (veto)")
    // A Korean word after the new abbreviations stays Korean.
    expect(typeWords(["abs", ManualToggle.hangulToKeys("학교")!]).last ?? "", "학교", "#109 Korean after abs stays Korean")
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
        // 2026-11-07 (#175): 표가 온전하지 않으면 그 낱말이 변환되지 않는다(과변환이 아니라 미변환으로 샌다).
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--probe-bundled-table" {
            EnglishDetector.bundledTablePath = CommandLine.arguments[2]
            EnglishDetector.systemWordsPath = nil
            EnglishDetector.wordlistPaths = []
            EnglishDetector.curatedPaths = []
            KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
            print(type("playlist").committedText == "playlist" ? "true" : "false")
            return
        }
        // 2026-11-07 (#175): 시스템 파일 경로를 주입해 실제 조합기까지 지나 판정한다. web2 전용 낱말 zythum으로 본다.
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--probe-system-words" {
            EnglishDetector.bundledTablePath = nil
            EnglishDetector.systemWordsPath = CommandLine.arguments[2]
            EnglishDetector.wordlistPaths = []
            EnglishDetector.curatedPaths = []
            KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
            print(type("zythum").committedText == "zythum" ? "true" : "false")
            return
        }
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--probe-kdict" {
            KoreanDictionary.wordlistPath = CommandLine.arguments[2]
            if !KoreanDictionary.isLoaded {
                guard typeViaController("100ml").committedText == "100ㅢ",
                      typeViaController("100 ml").committedText == "100 ㅢ",
                      // 2026-11-01 (#106): 단독 ml 변환도 veto 사전 실패 시 꺼진다.
                      typeViaController("ml").committedText == "ㅢ",
                      typeViaController("pele").committedText == "ㅔ딛",
                      typeViaController("cm").committedText == "츠",
                      typeViaController("githubdp").committedText == "햐소ㅕㅠ에",
                      typeWithPersonalDictionary("githubdp", PersonalDictionary(force: ["github"])).client.committedText == "햐소ㅕㅠ에",
                      typeViaControllerWithPersonalDictionary("1.5ml", PersonalDictionary(force: ["1.5ml"])).committedText == "1.5ㅢ"
                else { print("단위 변환 fail-closed 실패"); exit(1) }
            }
            print(KoreanDictionary.isLoaded ? "true" : "false")
            return
        }

        // Wordlist: 번들 표 + 시스템 web2 + a temp supplement (no app bundle here).
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
        // 2026-11-07 (#175): 배포본처럼 표와 시스템 파일로 찾는다. 표가 manifest와 같은지는 runEnglishTableTests가 본다.
        let manifestEntries = DictManifest.load()
        EnglishDetector.bundledTablePath = "Resources/IM/english_bundled.txt"
        var wordlists = [
            supplementPath,
            namesFixturePath, // broad 전용 — 아래 curated에 미등록 (의도)
        ]
        // 화이트리스트 방식(fail-safe): curated로 신뢰할 경로만 명시 등록.
        var curated: Set<String> = [supplementPath]
        for entry in manifestEntries
        where entry.role == "curated" && FileManager.default.fileExists(atPath: entry.path) {
            wordlists.append(entry.path)
            curated.insert(entry.path)
        }
        EnglishDetector.wordlistPaths = wordlists
        EnglishDetector.curatedPaths = curated
        // v3 한국어 veto 사전 (우리말샘 추출본, repo 루트 기준)
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"

        let dictGoodPath = NSTemporaryDirectory() + "haneul_kdict_good.txt"
        let dictNoHeaderPath = NSTemporaryDirectory() + "haneul_kdict_no_header.txt"
        let dictMismatchPath = NSTemporaryDirectory() + "haneul_kdict_mismatch.txt"
        try? "# count: 2\n# fixture\n가\n가\n나\n".write(
            toFile: dictGoodPath,
            atomically: true,
            encoding: .utf8
        )
        try? "# fixture\n가\n가\n나\n".write(
            toFile: dictNoHeaderPath,
            atomically: true,
            encoding: .utf8
        )
        try? "# count: 3\n# fixture\n가\n가\n나\n".write(
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

        runSparkRegistrationTests()
        runDict106Tests()
        runMath109Tests()

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
        expect(type("hni").committedText, "ㅗㅜㅑ", "#194 vowel slang ㅗㅜㅑ untouched")
        // 2026-11-01 (#106): ㅢ(ml)은 오너 결정으로 단독에서도 변환한다.
        expect(type("ml").committedText, "ml", "ml: 단독 ㅢ도 변환 (#106)")
        // 2026-11-07 오너 결정(#194): ok(ㅐㅏ)·am(므)도 단독 변환. so(내)는 멀쩡한 한글이라 앞이 영어일 때만이다.
        for keys in ["ok", "OK", "Ok", "am", "AM", "Am", "pm", "PM", "Pm"] {
            expect(type(keys).committedText, keys, "#194 단독 \(keys)")
            expect(typeViaController(keys + " ").committedText, keys + " ", "#194 단독 \(keys) Space")
        }
        expect(type("so").committedText, "내", "#194 so(내)는 단독 변환 안 함")
        expect(typeWords(["apple", "so"]).last ?? "", "so", "#194 앞 영어 뒤 so")
        expect(type("ok", autoEnglish: false).committedText, "ㅐㅏ", "#194 ok 자동 변환 OFF")
        expect(type("am", autoEnglish: false).committedText, "므", "#194 am 자동 변환 OFF")
        expect(typePassive("ok").committedText, "ㅐㅏ", "#194 ok 클릭 확정은 그대로")
        expect(typePassive("am").committedText, "므", "#194 am 클릭 확정은 그대로")
        for (keys, hangul) in [("ok", "ㅐㅏ"), ("am", "므")] {
            for blocked in [keys, hangul] {
                expect(typeWithPersonalDictionary(keys, PersonalDictionary(block: [blocked])).client.committedText,
                       hangul, "#194 \(keys) 개인 금지: \(blocked)")
            }
            expect(KoreanComposer.resolveToggle(before: keys + " ", english: keys, hangul: hangul, atDocStart: true)?.text ?? "",
                   hangul, "#194 \(keys) 되돌리기")
        }
        // 2026-11-08 오너 요청(#194): 2글자 등록 목록. 소문자·대문자·첫 글자 대문자 모두 그대로 남아야 한다.
        for word in ["oh", "uh", "yo", "hi", "ya", "ye", "ow", "ip", "hp", "lp", "kb", "uk", "jp", "un", "ph", "op",
                     "bj", "nh", "lh", "pb", "pk", "ob", "ol", "ny", "io", "bl", "ux", "uv", "hd", "iq", "pg", "mc",
                     "mr", "jr", "bg", "bt", "kt", "kr", "mt", "ot", "mv", "ic", "ir", "la", "nc", "bc", "pv", "yt",
                     "ig", "hq", "kc",
                     "tv", "vs", "vr", "ar", "qa", "cg", "ae", "fx", "fc", "ex", "ad", "sd", "dc", "cs", "vc", "gs",
                     "ai", "fm"] {
            for keys in [word, word.uppercased(), word.prefix(1).uppercased() + word.dropFirst()] {
                expect(type(keys).committedText, keys, "#194 단독 \(keys)")
            }
        }
        // 2026-11-08 오너 요청(#194): bio(ㅠㅑㅐ)는 어느 사전에도 없어 어떤 규칙으로도 안 바뀌었다.
        for keys in ["bio", "BIO", "Bio"] { expect(type(keys).committedText, keys, "#194 사전 추가 \(keys)") }
        // 2026-11-08 오너 요청(#194): 일괄 제외했던 단어 중 쓰는 말과 월 이름. 소문자·대문자·첫 글자 대문자 모두 그대로 남아야 한다.
        for word in [
            "acct", "ads", "asst", "avg", "bbc", "bff", "bldg", "blvd", "bmx", "bpm", "byte", "cafe", "cert",
            "cred", "dec", "dvd", "dvds", "etc", "ext", "fave", "fax", "hbo", "hdtv", "hiya", "hrs", "hvac",
            "ibm", "ieee", "imax", "inc", "iou", "ipod", "irc", "jan", "jeez", "jpn", "jul", "jun", "kart",
            "lib", "lng", "lpg", "ltd", "med", "meds", "mega", "mgr", "mia", "mic", "mics", "misc", "mkt",
            "mpeg", "mps", "msg", "mtv", "nasa", "nba", "nbc", "ncaa", "nerd", "nhl", "nike", "nov", "nsa",
            "nsfw", "ntsc", "nyc", "obs", "ocr", "oct", "oink", "opec", "ops", "pct", "pda", "ppv", "pre",
            "pvc", "rec", "rss", "stat", "uhf", "univ", "unix", "ups", "usa", "usda", "ussr", "utc", "vga",
            "ymca", "yrs", "yum", "yup"
        ] {
            for keys in [word, word.uppercased(), word.prefix(1).uppercased() + word.dropFirst()] {
                expect(type(keys).committedText, keys, "#194 사전 추가 \(keys)")
            }
        }
        // 오너가 2026-11-01에 뺀 std는 그대로 한글이다.
        expect(type("std").committedText, "ㄴㅅㅇ", "#194 std는 넣지 않음")
        // 넣지 않은 것은 그대로다: 초성체, 우는 표정, 멀쩡한 한글.
        for (keys, hangul) in [("rc", "ㄱㅊ"), ("da", "ㅇㅁ"), ("re", "ㄱㄷ"), ("ac", "ㅁㅊ"), ("de", "ㅇㄷ"), ("qr", "ㅂㄱ"), ("qt", "ㅂㅅ"),
                               ("mb", "ㅡㅠ"), ("hk", "ㅘ"), ("dm", "으"), ("gb", "휴"), ("tb", "슈"), ("sk", "나")] {
            expect(type(keys).committedText, hangul, "#194 안 넣음 \(keys)")
        }
        expect(type("ai", autoEnglish: false).committedText, "먀", "#194 ai 자동 변환 OFF")
        expect(typePassive("tv").committedText, "ㅅㅍ", "#194 tv 클릭 확정은 그대로")
        for (keys, hangul) in [("ai", "먀"), ("tv", "ㅅㅍ"), ("hi", "ㅗㅑ")] {
            expect(typeWithPersonalDictionary(keys, PersonalDictionary(block: [keys])).client.committedText,
                   hangul, "#194 \(keys) 개인 금지")
            expect(KoreanComposer.resolveToggle(before: keys + " ", english: keys, hangul: hangul, atDocStart: true)?.text ?? "",
                   hangul, "#194 \(keys) 되돌리기")
        }
        // 르·먀로 시작하는 실제 말은 단어 전체 판정이 지킨다.
        expect(type("fmsptkdtm").committedText, "르네상스", "#194 표제어 르네상스 보호")
        expect(type("ahfmsms").committedText, "모르는", "#194 모르는 보호")
        expect(type("aidms").committedText, "ai은", "#194 ai + 조사")
        // 조사가 붙어도 앞말로 인정한다.
        expect(type("okdms").committedText, "ok은", "#194 ok + 조사")
        expect(type("amdms").committedText, "am은", "#194 am + 조사")
        expect(type("pmdms").committedText, "pm은", "#194 pm + 조사")
        // 다른 영어 단어와 같은 규칙이다: 영어 뒤의 짧은 단어(내·새)는 영어 문맥으로 본다. 되돌리기가 안전망이다.
        expect(typeWords(["ok", "so"]).last ?? "", "so", "#194 ok 뒤 so: 일반 영어 문맥과 같다")
        // 므가 들어간 실제 말은 지킨다.
        expect(type("amfh").committedText, "므로", "#194 표제어 므로 보호")
        expect(type("amgma").committedText, "므흠", "#194 조합이 이어지면 단독 판정이 아니다")
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
        // 2026-10-14: 짧은 영어 화이트리스트도 의미 있는 Shift를 존중한다.
        // sO는 so(내)가 아니라 냬(ㅒ)이며, 영어 문맥에서도 원문을 보존한다.
        expect(typeWords(["the", "sO"]).last ?? "", "냬", "R2 Shift 가드: the 뒤 냬 보호")
        expect(typeWords(["want", "sO"]).last ?? "", "냬", "R2 Shift 가드: want 뒤 냬 보호")
        expect(typeWords(["the", "So"]).last ?? "", "So", "R2 Shift no-op: the 뒤 So 변환 유지")
        // 오너 요청 명사·조사 결합은 일반 Space에서 자동 번역하지 않는다.
        for noun in ["단어", "용량", "물", "책", "사람", "사진", "영상", "파일", "소리", "이름", "주소", "설정"] {
            for suffix in ["", "은", "을", "의"] {
                let original = noun + suffix
                let keys = ManualToggle.hangulToKeys(original)!
                expect(typeViaController(keys + " ").committedText, original + " ",
                       "명사·조사 일반 Space 보존: \(original)")
                for previous in ["the", "want"] {
                    expect(typeWordsViaController([previous, keys]).last ?? "", original,
                           "영어 뒤 명사·조사 보존: \(previous) \(original)")
                }
            }
        }
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
        expect(type("td").committedText, "ㅅㅇ", "2글자: 목록에 없는 자음쌍은 유지")  // 2026-11-08 (#194): 예시였던 sd를 목록에 넣어 td로 바꿨다
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
        // ── #70 오너 지정 단어 (2026-09-23) — dmg·pr·xhigh ──
        // 셋 다 통로가 다르다: xhigh=사전 등재(broken 토ㅑ호), pr=shortWords(모음먼저+자음 약어 —
        // pd=ㅔㅇ와 같은 R1 경로, 2글자는 isDictWord가 안 봐서 사전으로 못 넣는다),
        // dmg=standaloneShortWords(clean 1음절 읗 — R5 "2음절+" 가드라 사전만으로는 미도달, gpt=헷과 같은 부류).
        expect(type("xhigh").committedText, "xhigh", "#70 xhigh: 토ㅑ호 → xhigh (사전 등재)")
        expect(type("pr").committedText, "pr", "#70 pr: ㅔㄱ → pr (shortWords·R1)")
        expect(type("PR").committedText, "PR", "#70 PR: ㅖㄲ → PR (대문자도 R1, 대소문자 보존)")
        expect(type("dmg").committedText, "dmg", "#70 dmg: 읗 → dmg (standaloneShortWords)")
        expect(type("DMG").committedText, "DMG", "#70 DMG: d·m·g는 Shift가 자모를 안 바꿔 같은 읗 → DMG")
        // 한국어 미손상 — 판정은 단어 단위라 읗이 낀 실존 단어는 그대로.
        expect(type("gldmg").committedText, "히읗", "#70 히읗(gldmg) 한글 유지")

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
        // 전체 제거 실행 검증은 Tests/UninstallTests.swift에서 실제 공통 순서를 실행한다.

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

        // ── 2026-11-07 (#176, 오너 결정): 메인 앱 찾기는 응용 프로그램 폴더까지만 ──
        // 키 입력을 보는 입력기가 데스크탑·다운로드·문서 폴더를 뒤지면 macOS 권한 창을 부를 수 있다.
        let orphanRoots = OrphanDecision.scanRoots(home: "/Users/x")
        expect(orphanRoots.map(\.path).joined(separator: "|"), "/Applications|/Users/x/Applications", "연동: 스캔은 /Applications·~/Applications만")
        expect(orphanRoots.allSatisfy { $0.depth == 2 }, true, "연동: Utilities 같은 하위 폴더 한 단계까지 본다")
        for sourcePath in ["IMESources/OrphanWatcher.swift", "IMESources/OrphanDecision.swift"] {
            let source = (try? String(contentsOfFile: sourcePath, encoding: .utf8)) ?? ""
            expect(!source.isEmpty && !["Desktop", "Downloads", "Documents"].contains { source.contains($0) }, true,
                   "연동: \(sourcePath)에 보호 폴더 이름이 없다")
        }
        let orphanTree: [String: [String]] = [
            "/Applications": ["HaneulKeyboard.app", "Other.app", "Utilities", ".hidden", "notes.txt"],
            "/Applications/Utilities": ["Copy.app", "Deep"],
            "/Applications/Utilities/Deep": ["TooDeep.app"],
            "/Applications/.hidden": ["Hidden.app"],
            "/Users/x/Applications": [],
        ]
        func orphanScan(_ unreadable: Set<String> = []) -> [String]? {
            OrphanDecision.findApps(
                in: orphanRoots, bundleID: "our.id",
                list: { unreadable.contains($0) ? nil : orphanTree[$0] ?? [] },
                isDirectory: { orphanTree[$0] != nil },
                identifier: { $0.hasSuffix("Other.app") ? "other.id" : "our.id" })
        }
        expect(orphanScan()?.joined(separator: "|") ?? "nil", "/Applications/HaneulKeyboard.app|/Applications/Utilities/Copy.app",
               "연동: 우리 앱만 찾고, 깊이 제한·숨김 폴더·남의 앱은 제외")
        expect(orphanScan(["/Applications"]) == nil, true, "연동: 응용 프로그램 폴더를 못 읽으면 관찰 불가(정리 보류)")
        expect(orphanScan(["/Users/x/Applications"]) == nil, true, "연동: ~/Applications를 못 읽으면 관찰 불가(정리 보류)")
        expect(orphanScan(["/Applications/Utilities"]) == nil, true, "연동: 하위 폴더를 못 읽어도 없다고 단정하지 않음")


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
        // base가 사전에 없으면 축약형도 한글로 남는다(축약형 로직이 아니라 base 사전의 몫, `'`가 경계였던 예전과 결과가 같다).
        // 2026-11-13 (#225 후속): 예전 예시 john은 web2에 대문자 "John"만 있어 빠져 있었는데, 빠진 성씨를 되살리며 사전에 들어왔다 —
        // 그래서 john's는 이제 바뀌고, '사전에 없는 base' 예시는 없는 철자 juhn으로 바꿨다.
        expect(
            typeViaController("juhn's").committedText, "ㅓㅕㅗㅜ'ㄴ",
            "축약형: base가 사전에 없으면(juhn) 한글 유지"
        )
        expect(typeViaController("john's").committedText, "john's", "축약형: 되살린 이름 john의 소유격")

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
            "축약형 문맥: i'm 뒤 ㅐㅏ(ok)가 영어로"
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
        // 저장된 전체 쌍은 끝의 아포스트로피까지 되돌린다.
        expect(KoreanComposer.resolveToggle(before: "i' ", english: "i'", hangul: "ㅑ'",
                                             atDocStart: true)?.text ?? "",
               "ㅑ'", "축약형 되돌리기: 끝의 아포스트로피 포함")

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

        // ═══ 개인 사전 (#53, 2026-09-21) ═══
        // (a) 판정 순수 함수 — PersonalDictionary.decision
        do {
            let pd = PersonalDictionary(force: ["vismo"], block: ["apple", "메ㅔㅣㄷ"])
            expect(pd.decision(word: "vismo", hangul: "퍄느ㅐ") == .forceConvert, true, "PD.decision: force")
            expect(pd.decision(word: "apple", hangul: "메ㅔㅣㄷ") == .block, true, "PD.decision: block(영어)")
            expect(pd.decision(word: "zzzz", hangul: "메ㅔㅣㄷ") == .block, true, "PD.decision: block(한글 표기만 일치)")
            expect(pd.decision(word: "apple", hangul: "다른한글") == .block, true, "PD.decision: block(영어만 일치)")
            expect(pd.decision(word: "banana", hangul: "ㅠ무무") == nil, true, "PD.decision: 없음 → nil")
            expect(pd.decision(word: "Vismo", hangul: "퍄느ㅐ") == .forceConvert, true, "PD.decision: 대문자 키열도 force")
            expect(pd.decision(word: "APPLE", hangul: "x") == .block, true, "PD.decision: 대문자 키열도 block")
            let both = PersonalDictionary(force: ["apple"], block: ["apple"])
            expect(both.decision(word: "apple", hangul: "메ㅔㅣㄷ") == .block, true, "PD.decision: 양쪽에 있으면 block 우선")
            expect(PersonalDictionary.empty.decision(word: "apple", hangul: "메ㅔㅣㄷ") == nil, true, "PD.decision: 빈 사전은 nil")
            // 곱은 아포스트로피 키열도 저장된 직선 따옴표 항목과 맞는다
            let apo = PersonalDictionary(force: ["y'know"], block: [])
            expect(apo.decision(word: "y\u{2019}know", hangul: "ㅛ'ㅏㅜㅐㅈ") == .forceConvert, true, "PD.decision: U+2019 키열 정규화")
        }
        // 정규화 동치 — PersonalDictionary는 메인 앱에도 컴파일되어 Contractions를 못 쓰므로
        // 자체 구현이다. 커밋 때 조회 키(Contractions.normalizedKey)와 어긋나면 여기서 잡힌다.
        for sample in ["Apple", "don\u{2019}t", "I\u{2019}M", "y'know", "VISMO", "", "'", "Ab'C\u{2019}d"] {
            expect(PersonalDictionary.normalizedEnglish(sample), Contractions.normalizedKey(Array(sample)),
                   "PD.normalizedEnglish == Contractions.normalizedKey: \(sample)")
        }
        // (a') 입력 정규화 — 설정 앱 검증과 저장 시 정규화가 같은 함수
        expect(PersonalDictionary.normalizedForceEntry(" Apple ") ?? "nil", "apple", "PD.force 정규화: 공백 제거+소문자")
        expect(PersonalDictionary.normalizedForceEntry("don\u{2019}t") ?? "nil", "don't", "PD.force 정규화: 곱은 따옴표 → '")
        expect(PersonalDictionary.normalizedForceEntry("app le") == nil, true, "PD.force 검증: 공백 포함 거부")
        expect(PersonalDictionary.normalizedForceEntry("메ㅔㅣㄷ") == nil, true, "PD.force 검증: 한글 거부")
        expect(PersonalDictionary.normalizedForceEntry("'") == nil, true, "PD.force 검증: 글자 없는 ' 거부")
        expect(PersonalDictionary.normalizedForceEntry("abc1") ?? "", "abc1", "PD.force 검증: 숫자 포함 제품명 허용")
        expect(PersonalDictionary.normalizedForceEntry("") == nil, true, "PD.force 검증: 빈 문자열 거부")
        expect(PersonalDictionary.normalizedBlockEntry(" Apple ") ?? "nil", "apple", "PD.block 정규화: 영어 소문자")
        expect(PersonalDictionary.normalizedBlockEntry("메ㅔㅣㄷ") ?? "nil", "메ㅔㅣㄷ", "PD.block 정규화: 한글 표기 그대로")
        expect(PersonalDictionary.normalizedBlockEntry("애ㅜ'ㅅ") ?? "nil", "애ㅜ'ㅅ", "PD.block 정규화: 축약형 한글형(')")
        expect(PersonalDictionary.normalizedBlockEntry("app le") == nil, true, "PD.block 검증: 공백 포함 거부")
        expect(PersonalDictionary.normalizedBlockEntry("apple메") == nil, true, "PD.block 검증: 영한 혼합 거부")
        expect(PersonalDictionary.normalizedBlockEntry("123") == nil, true, "PD.block 검증: 숫자 거부")
        expect(PersonalDictionary.normalizedBlockEntry("") == nil, true, "PD.block 검증: 빈 문자열 거부")
        do {
            // 저장 목록 → 사전: 규칙에 안 맞는 항목은 조용히 버린다
            let pd = PersonalDictionary(forceList: ["Vismo", "", "메ㅔㅣㄷ", "ok"], blockList: ["Apple", "메ㅔㅣㄷ", "  ", "a b"])
            expect(pd.force == ["vismo", "ok"], true, "PD(list): force 정규화·필터")
            expect(pd.block == ["apple", "메ㅔㅣㄷ"], true, "PD(list): block 정규화·필터")
            expect(PersonalDictionary(forceList: [], blockList: []) == .empty, true, "PD(list): 빈 목록 = empty")
        }

        // (b) composer 통합 — 사전 판정 앞뒤로 합성
        // vismol: 어느 사전에도 없어 지금은 미변환 (baseline)
        expect(type("vismol").committedText, "퍄느ㅐㅣ", "PD baseline: vismol는 사전에 없어 한글 유지")
        do {
            let r = typeWithPersonalDictionary("vismol", PersonalDictionary(force: ["vismol"]))
            expect(r.client.committedText, "vismol", "PD force: 사전에 없는 단어도 변환")
            expect(r.composer.lastConversion?.hangul ?? "", "퍄느ㅐㅣ", "PD force: lastConversion 한글(되돌리기 가능)")
            expect(r.composer.lastConversion?.english ?? "", "vismol", "PD force: lastConversion 영어")
            expect(r.composer.lastEnglishWord ?? "", "vismol", "PD force: 영어 문맥 이어짐")
        }
        expect(
            typeWithPersonalDictionary("vismol", PersonalDictionary(force: ["vismol"]), autoEnglish: false).client.committedText,
            "퍄느ㅐㅣ", "PD force: 자동 변환 꺼짐이면 force도 무력(마스터 스위치가 위)")
        expect(
            typeWithPersonalDictionary("vismol", PersonalDictionary(force: ["vismol"]), passive: true).client.committedText,
            "퍄느ㅐㅣ", "PD force: passive 경계는 화면 그대로(force 무관)")
        expect(
            typeWithPersonalDictionary("Vismol", PersonalDictionary(force: ["vismol"])).client.committedText,
            "Vismol", "PD force: 대문자로 쳐도 변환, 출력은 친 그대로")
        // 자판 대응이 안 맞으면 force도 안 걸린다 — 다른 키로 친 단어는 word가 다르다
        expect(
            typeWithPersonalDictionary("vismoll", PersonalDictionary(force: ["vismol"])).client.committedText,
            "퍄느ㅐㅣㅣ", "PD force: 키열이 정확히 그 단어여야 함(vismoll ≠ vismol)")
        // 한국어 veto 단어(책=cor)도 force면 변환
        expect(type("cor").committedText, "책", "PD baseline: 책(cor)은 veto 보호")
        expect(
            typeWithPersonalDictionary("cor", PersonalDictionary(force: ["cor"])).client.committedText,
            "cor", "PD force: 우리말샘 veto(책)보다 우선")
        // block: 사전에 있는 단어(apple)가 영어로도, 한글 표기로도 막힌다
        expect(type("apple").committedText, "apple", "PD baseline: apple 변환")
        do {
            let r = typeWithPersonalDictionary("apple", PersonalDictionary(block: ["apple"]))
            expect(r.client.committedText, "메ㅔㅣㄷ", "PD block(영어): apple 미변환")
            expect(r.composer.lastConversion == nil, true, "PD block: 변환이 없으니 lastConversion도 없음")
            expect(r.composer.lastEnglishWord == nil, true, "PD block: 영어 문맥도 안 생김")
        }
        expect(
            typeWithPersonalDictionary("apple", PersonalDictionary(block: ["메ㅔㅣㄷ"])).client.committedText,
            "메ㅔㅣㄷ", "PD block(한글 표기): 메ㅔㅣㄷ으로도 막힘")
        expect(
            typeWithPersonalDictionary("Apple", PersonalDictionary(block: ["apple"])).client.committedText,
            "메ㅔㅣㄷ", "PD block: 대문자로 쳐도 막힘(대소문자 무시)")
        expect(
            typeWithPersonalDictionary("apple", PersonalDictionary(force: ["apple"], block: ["apple"])).client.committedText,
            "메ㅔㅣㄷ", "PD 양쪽: block 우선")
        // 다른 단어에는 영향 없음
        expect(
            typeWithPersonalDictionary("apple", PersonalDictionary(force: ["vismol"], block: ["banana"])).client.committedText,
            "apple", "PD: 무관한 항목은 기존 판정 그대로(apple 변환)")
        expect(
            typeWithPersonalDictionary("cor", PersonalDictionary(force: ["vismol"])).client.committedText,
            "책", "PD: 무관한 항목은 기존 판정 그대로(책 보호)")
        // 영어 문맥(R2)도 block이 이긴다 — "good wha"의 좀은 veto, "how are"의 ㅁㄱㄷ는 변환되던 것
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            composer.personalDictionary = PersonalDictionary(block: ["are"])
            for ch in "how" { _ = composer.handleInput(String(ch), client: client) }
            _ = composer.commit(to: client, convertEnglish: true)
            for ch in "are" { _ = composer.handleInput(String(ch), client: client) }
            expect(composer.commit(to: client, convertEnglish: true), "ㅁㄱㄷ", "PD block: 영어 문맥 뒤에서도 are 미변환")
        }
        // 축약형·소유격(컨트롤러 경로) — base 경로도 같은 합성
        expect(typeViaController("vismol's").committedText, "퍄느ㅐㅣ'ㄴ", "PD baseline: vismol's 미변환")
        expect(
            typeViaControllerWithPersonalDictionary("vismol's", PersonalDictionary(force: ["vismol"])).committedText,
            "vismol's", "PD force(base): vismol's도 통째로 변환")
        expect(
            typeViaControllerWithPersonalDictionary("apple's", PersonalDictionary(block: ["apple"])).committedText,
            "메ㅔㅣㄷ'ㄴ", "PD block(base): apple's도 한글 유지")
        expect(
            typeViaControllerWithPersonalDictionary("apple's", PersonalDictionary(block: ["메ㅔㅣㄷ"])).committedText,
            "메ㅔㅣㄷ'ㄴ", "PD block(base 한글 표기): 메ㅔㅣㄷ 금지가 메ㅔㅣㄷ'ㄴ까지")
        expect(typeViaController("don't").committedText, "don't", "PD baseline: don't 축약형 변환")
        expect(
            typeViaControllerWithPersonalDictionary("don't", PersonalDictionary(block: ["don't"])).committedText,
            "애ㅜ'ㅅ", "PD block(통째): 축약형 소사전보다 금지가 먼저")
        expect(
            typeViaControllerWithPersonalDictionary("don't", PersonalDictionary(block: ["애ㅜ'ㅅ"])).committedText,
            "애ㅜ'ㅅ", "PD block(통째 한글형): 애ㅜ'ㅅ으로도 막힘")
        expect(typeViaController("y'know").committedText, "ㅛ'ㅏㅜㅐㅈ", "PD baseline: y'know는 소사전에 없어 미변환")
        expect(
            typeViaControllerWithPersonalDictionary("y'know", PersonalDictionary(force: ["y'know"])).committedText,
            "y'know", "PD force(통째): 소사전에 없는 축약형도 변환")
        // 한글 단어는 force가 아닌 한 절대 건드리지 않는다(회귀 방어)
        expect(
            typeWithPersonalDictionary("dkssud", PersonalDictionary(force: ["vismol"], block: ["apple"])).client.committedText,
            "안녕", "PD: 한글 단어(안녕)는 그대로")

        // (c) 최근 되돌린 변환 — RecentReverts 순수 함수
        do {
            var r = RecentReverts()
            expect(r.entries.count, 0, "RR: 처음은 비어 있음")
            r = r.recording(hangul: "메ㅔㅣㄷ", english: "apple")
            expect(r.entries.count, 1, "RR: 1개 추가")
            r = r.recording(hangul: "퍄느ㅐ", english: "vismo")
            expect(r.entries.first?.english ?? "", "vismo", "RR: 최신이 앞")
            expect(r.entries.last?.english ?? "", "apple", "RR: 오래된 것이 뒤")
            r = r.recording(hangul: "메ㅔㅣㄷ", english: "apple")
            expect(r.entries.count, 2, "RR: 같은 쌍은 중복 안 됨")
            expect(r.entries.first?.english ?? "", "apple", "RR: 같은 쌍은 최신으로 올라옴")
            // 같은 영어라도 한글 표기가 다르면 다른 쌍(Apple/apple 등)
            r = r.recording(hangul: "메ㅔㅣㄷ", english: "Apple")
            expect(r.entries.count, 3, "RR: (한글, 영어) 쌍 단위로 중복 판정")
            // "금지" 뒤 제거 — 대소문자 무시로 그 영어 항목 전부
            let removed = r.removing(blockedBy: "apple")
            expect(removed.entries.count, 1, "RR.removing: apple/Apple 둘 다 제거")
            expect(removed.entries.first?.english ?? "", "vismo", "RR.removing: 나머지는 유지")
            expect(r.removing(blockedBy: "nothere").entries.count, 3, "RR.removing: 없는 단어는 그대로")
            // 상한 50 — 60개 넣으면 최신 50개만
            var many = RecentReverts()
            for i in 0..<60 { many = many.recording(hangul: "h\(i)", english: "w\(i)") }
            expect(many.entries.count, RecentReverts.maxCount, "RR: 상한 50")
            expect(many.entries.first?.english ?? "", "w59", "RR: 상한 넘으면 최신 유지")
            expect(many.entries.last?.english ?? "", "w10", "RR: 가장 오래된 10개가 잘림")
            // plist 왕복
            let plist = r.plist
            expect(plist.count, 3, "RR.plist: 항목 수")
            expect(plist.first?["hangul"] ?? "", "메ㅔㅣㄷ", "RR.plist: hangul 키")
            expect(plist.first?["english"] ?? "", "Apple", "RR.plist: english 키")
            expect(RecentReverts(plist: plist) == r, true, "RR.plist: 왕복 동일")
            expect(RecentReverts(plist: nil).entries.count, 0, "RR(plist:nil): 빈 목록")
            expect(RecentReverts(plist: "garbage").entries.count, 0, "RR(plist:이상한 값): 빈 목록")
            expect(
                RecentReverts(plist: [["hangul": "메"], ["english": "x"], ["hangul": "", "english": "y"], ["hangul": "뭉", "english": "and"]]).entries.count,
                1, "RR(plist): 키 빠짐·빈 값 항목은 버림")
            expect(
                RecentReverts(plist: [["hangul": "뭉", "english": "and"], ["hangul": "뭉", "english": "and"]]).entries.count,
                1, "RR(plist): 저장본의 중복도 걸러냄")
            expect(RecentReverts(entries: many.entries + many.entries).entries.count, RecentReverts.maxCount, "RR(entries): 생성자도 상한 적용")
        }

        // (d) 단어 제안 창구 — WordSuggestion URL 생성 (#55, 2026-09-21)
        // 여기서 고정하는 것은 두 가지다: ① 제목·본문의 모양(설정 화면과 이슈 템플릿이 같은 꼴),
        // ② 인코딩. ②가 핵심인데, URLQueryItem에 맡기면 `+ / ; : @ '`가 날것으로 남고
        // GitHub(Rails)은 쿼리의 `+`를 공백으로 읽는다(2026-09-21 실측) → 직접 %XX.
        do {
            expect(WordSuggestion.Kind.add.displayName, "변환 추가 제안", "WS: add 표시 이름")
            expect(WordSuggestion.Kind.block.displayName, "변환 금지 제안", "WS: block 표시 이름")
            expect(WordSuggestion.Kind.allCases.count, 3, "WS: 단어 추가·금지와 분야 제안")
            for url in [WordSuggestion.issueURL(typed: "영상 후반 작업", expected: "", kind: .field),
                        WordSuggestion.emailURL(typed: "영상 후반 작업", expected: "", kind: .field)] {
                expect(url != nil, true, "분야 제안: 영어 결과 없이도 작성 가능")
                let body = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                    .queryItems?.first { $0.name == "body" }?.value ?? ""
                expect(body.contains("산업군·분야") && body.contains("영상 후반 작업"), true,
                       "분야 제안: 양쪽 작성창에 분야와 내용 보존")
            }
            expect(WordSuggestion.issueURL(typed: " ", expected: "", kind: .field) == nil,
                   true, "빈 분야 제안은 작성 불가")

            // 제목
            expect(
                WordSuggestion.issueTitle(typed: "메ㅔㅣㄷ", expected: "apple", kind: .add),
                "[단어 제안] 메ㅔㅣㄷ → apple", "WS: 추가 제안 제목")
            expect(
                WordSuggestion.issueTitle(typed: "뭉", expected: "and", kind: .block),
                "[단어 제안] 뭉 → and (변환 금지)", "WS: 금지 제안 제목")

            // 빈 입력 → nil (설정 화면의 버튼 비활성화가 이 판정을 그대로 쓴다)
            expect(WordSuggestion.issueURL(typed: "", expected: "apple", kind: .add) == nil, true, "WS: 친 글자 비면 nil")
            expect(WordSuggestion.issueURL(typed: "메ㅔㅣㄷ", expected: "", kind: .add) == nil, true, "WS: 기대 결과 비면 nil")
            expect(WordSuggestion.issueURL(typed: " \n ", expected: "apple", kind: .add) == nil, true, "WS: 공백·줄바꿈만이면 nil")
            expect(WordSuggestion.issueURL(typed: "메ㅔㅣㄷ", expected: "apple", kind: .add) != nil, true, "WS: 정상 입력은 URL")
            if let email = WordSuggestion.emailURL(typed: "ㅊ+ㅊ", expected: "c+c", kind: .block,
                                                   note: "a&b#c", appVersion: "2026.10.15_hotfix1", osVersion: "27.0") {
                let components = URLComponents(url: email, resolvingAgainstBaseURL: false)!
                expect(components.scheme ?? "", "mailto", "이메일 제안: 작성창만 열기")
                expect(components.path, "lifeismotive@gmail.com", "이메일 제안: 승인된 수신자 고정")
                let query = components.queryItems ?? []
                expect(Set(query.map(\.name)) == Set(["subject", "body"]), true, "이메일 제안: 수신자/헤더 주입 없음")
                expect(query.first { $0.name == "subject" }?.value ?? "", "[단어 제안] ㅊ+ㅊ → c+c (변환 금지)", "이메일 제목 인코딩")
                expect(query.first { $0.name == "body" }?.value?.contains("a&b#c") == true, true, "이메일 본문 특수 문자 보존")
            } else { expect(false, true, "이메일 제안 생성") }
            expect(WordSuggestion.emailURL(typed: "", expected: "apple", kind: .add) == nil, true, "이메일 제안: 빈 필수 값 거부")
            let longEmail = WordSuggestion.emailURL(typed: "메ㅔㅣㄷ", expected: "apple", kind: .add,
                                                    note: String(repeating: "긴 한글 메모 &+\n", count: 1000))
            expect(longEmail != nil && longEmail!.absoluteString.count <= WordSuggestion.maxURLLength, true, "이메일 제안: URL 길이 상한")

            // 인코딩 — 비예약 문자만 남기고 전부 UTF-8 바이트별 %XX
            expect(WordSuggestion.percentEncoded("a+b"), "a%2Bb", "WS 인코딩: + (GitHub이 공백으로 읽는 문자)")
            expect(WordSuggestion.percentEncoded("a&b"), "a%26b", "WS 인코딩: &")
            expect(WordSuggestion.percentEncoded("a#b"), "a%23b", "WS 인코딩: #")
            expect(WordSuggestion.percentEncoded("a b"), "a%20b", "WS 인코딩: 공백")
            expect(WordSuggestion.percentEncoded("a\nb"), "a%0Ab", "WS 인코딩: 줄바꿈")
            expect(WordSuggestion.percentEncoded("a/b;c:d@e'f"), "a%2Fb%3Bc%3Ad%40e%27f", "WS 인코딩: / ; : @ ' 도 직접")
            expect(WordSuggestion.percentEncoded("-._~Az9"), "-._~Az9", "WS 인코딩: 비예약 문자는 그대로")
            expect(WordSuggestion.percentEncoded("한"), "%ED%95%9C", "WS 인코딩: 한글 UTF-8 3바이트")
            expect(WordSuggestion.percentEncoded("ㅔ"), "%E3%85%94", "WS 인코딩: 낱자모도 3바이트")
            expect(WordSuggestion.percentEncoded(""), "", "WS 인코딩: 빈 문자열")

            // URL 구조 + 왕복(%XX를 풀면 원래 문자열)
            if let url = WordSuggestion.issueURL(
                typed: "메ㅔㅣㄷ", expected: "apple", kind: .add,
                note: "회사에서 자주 씁니다", appVersion: "2026.08", osVersion: "27.0") {
                expect(url.scheme ?? "", "https", "WS URL: https")
                expect(url.host ?? "", "github.com", "WS URL: 호스트")
                expect(url.absoluteString.hasPrefix(WordSuggestion.newIssueURL + "?"), true, "WS URL: 이슈 작성 경로 + 쿼리")
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                expect(items.count, 3, "WS URL: 쿼리 3개(title·body·labels)")
                func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
                expect(value("labels"), WordSuggestion.label, "WS URL: labels=enhancement")
                expect(value("title"), "[단어 제안] 메ㅔㅣㄷ → apple", "WS URL: title 왕복")
                let body = value("body")
                expect(body.contains("- **친 글자 (한글 모드에서 보인 표기):** 메ㅔㅣㄷ"), true, "WS 본문: 친 글자")
                expect(body.contains("- **기대한 결과:** apple"), true, "WS 본문: 기대 결과")
                expect(body.contains("회사에서 자주 씁니다"), true, "WS 본문: 메모")
                expect(body.contains("- 하늘키보드: 2026.08"), true, "WS 본문: 앱 버전")
                expect(body.contains("- macOS: 27.0"), true, "WS 본문: macOS 버전")
                expect(body.contains("개인 사전"), true, "WS 본문: 개인 사전으로 먼저 해결했는지 확인 문구")
                expect(body.contains("\n"), true, "WS 본문: 줄바꿈이 살아서 마크다운이 된다")
            } else {
                failures += 1
                print("FAIL WS URL: 정상 입력인데 nil")
            }

            // `+`·`&`·`#`가 든 입력 — 날것으로 새면 GitHub에서 내용이 바뀐다
            if let url = WordSuggestion.issueURL(typed: "ㅊ+ㅊ", expected: "c+c", kind: .add, note: "a&b#c") {
                let raw = url.absoluteString
                expect(raw.contains("+"), false, "WS URL: raw `+`가 한 글자도 남지 않는다")
                expect(raw.contains("%2B"), true, "WS URL: +는 %2B로 들어간다")
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                expect(items.first { $0.name == "title" }?.value ?? "", "[단어 제안] ㅊ+ㅊ → c+c", "WS URL: +가 든 제목 왕복")
                expect((items.first { $0.name == "body" }?.value ?? "").contains("a&b#c"), true, "WS URL: &·#이 든 메모 왕복")
            } else {
                failures += 1
                print("FAIL WS URL(+&#): nil")
            }

            // 길이 상한 — 넘치면 메모부터 잘라 8000자 이하로 맞춘다
            let hugeNote = String(repeating: "한글메모 ", count: 4000)
            if let url = WordSuggestion.issueURL(
                typed: "메ㅔㅣㄷ", expected: "apple", kind: .add, note: hugeNote,
                appVersion: "2026.08", osVersion: "27.0") {
                expect(url.absoluteString.count <= WordSuggestion.maxURLLength, true, "WS 길이: 상한 이내")
                expect(url.absoluteString.count > WordSuggestion.maxURLLength - 200, true, "WS 길이: 상한 가까이까지는 남긴다")
                let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "body" }?.value ?? ""
                expect(body.contains(WordSuggestion.truncationMarker), true, "WS 길이: 잘림 표시가 붙는다")
                expect(body.contains("- **기대한 결과:** apple"), true, "WS 길이: 잘라도 본문 뼈대는 남는다")
            } else {
                failures += 1
                print("FAIL WS 길이: 긴 메모에서 nil")
            }

            // 최악 입력(두 필드 상한 + 메모 없음)도 상한 이내 — 위 이분 탐색이 nil로 끝나지 않는 근거
            let longField = String(repeating: "쨝", count: 400)
            if let url = WordSuggestion.issueURL(
                typed: longField, expected: longField, kind: .block, note: "",
                appVersion: "2026.08 (build 999)", osVersion: "27.0 (26A428)") {
                expect(url.absoluteString.count <= WordSuggestion.maxURLLength, true, "WS 길이: 최악 입력도 상한 이내")
                let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "title" }?.value ?? ""
                expect(title.count <= 120, true, "WS 제목: GitHub 제목 상한(256) 한참 아래")
            } else {
                failures += 1
                print("FAIL WS 길이: 최악 입력에서 nil")
            }

            // 값 정리
            expect(WordSuggestion.singleLine("  메ㅔㅣㄷ  ") ?? "", "메ㅔㅣㄷ", "WS 정리: 앞뒤 공백 제거")
            expect(WordSuggestion.singleLine("a\nb") ?? "", "a b", "WS 정리: 줄바꿈 → 공백")
            expect(WordSuggestion.singleLine("") == nil, true, "WS 정리: 빈 값은 nil")
            expect(
                (WordSuggestion.singleLine(String(repeating: "가", count: 200)) ?? "").count,
                WordSuggestion.maxFieldLength + 1, "WS 정리: 120자로 자르고 … 한 글자")
            expect(
                WordSuggestion.issueTitle(typed: String(repeating: "가", count: 100), expected: "x", kind: .add)
                    .contains(String(repeating: "가", count: WordSuggestion.maxTitleFieldLength) + "…"),
                true, "WS 제목: 값은 40자까지만")

            // 버전·메모를 모를 때 / 금지 제안의 라벨
            let unknown = WordSuggestion.issueBody(
                typed: "뭉", expected: "and", kind: .block, note: "", appVersion: "", osVersion: "")
            expect(unknown.contains("- 하늘키보드: (알 수 없음)"), true, "WS 본문: 앱 버전 미상")
            expect(unknown.contains("- macOS: (알 수 없음)"), true, "WS 본문: macOS 버전 미상")
            expect(unknown.contains("### 메모\n(없음)"), true, "WS 본문: 메모 없음")
            expect(unknown.contains("- **바꾼 결과 (원치 않음):** and"), true, "WS 본문: 금지 제안은 두 번째 값의 라벨이 다르다")
        }

        // MARK: 되돌리기 키를 모든 단어로 — 수동 한↔영 토글 (#15, 2026-09-21)
        //
        // 자동변환이 일부러 포기한 영역(우리말샘 veto `재가`, 사전에 있을 수 없는 `ㅡ5`)을
        // 사용자가 키를 눌러 직접 뚫는 경로. 사전을 보지 않고 자판 배열만 쓴다.
        do {
            // (a) 티켓 검산 케이스 — 양방향
            expect(ManualToggle.hangulToKeys("재가") ?? "", "work", "ManualToggle: 재가 → work")
            expect(ManualToggle.keysToHangul("work") ?? "", "재가", "ManualToggle: work → 재가")
            expect(ManualToggle.manualToggle(word: "재가") ?? "", "work", "manualToggle: 재가 → work (방향 자동)")
            expect(ManualToggle.manualToggle(word: "work") ?? "", "재가", "manualToggle: work → 재가 (방향 자동)")
            expect(ManualToggle.manualToggle(word: "ㅡ5") ?? "", "m5", "manualToggle: ㅡ5 → m5 (숫자 통과)")
            expect(ManualToggle.manualToggle(word: "m5") ?? "", "ㅡ5", "manualToggle: m5 → ㅡ5")
            expect(ManualToggle.manualToggle(word: "ㅏ3") ?? "", "k3", "manualToggle: ㅏ3 → k3")
            expect(ManualToggle.manualToggle(word: "k3") ?? "", "ㅏ3", "manualToggle: k3 → ㅏ3")
            expect(ManualToggle.manualToggle(word: "안녕") ?? "", "dkssud", "manualToggle: 안녕 → dkssud")
            expect(ManualToggle.manualToggle(word: "dkssud") ?? "", "안녕", "manualToggle: dkssud → 안녕")

            // (b) 복합 자모 역분해 — 티켓이 짚은 주의 지점
            expect(ManualToggle.hangulToKeys("ㅘ") ?? "", "hk", "ManualToggle: ㅘ → ㅗ+ㅏ = hk")
            expect(ManualToggle.hangulToKeys("ㄳ") ?? "", "rt", "ManualToggle: 겹받침 ㄳ → ㄱ+ㅅ = rt")
            expect(ManualToggle.hangulToKeys("삯") ?? "", "tkrt", "ManualToggle: 음절 속 겹받침 삯 → tkrt")
            expect(ManualToggle.hangulToKeys("ㄲ") ?? "", "R", "ManualToggle: 쌍자음 ㄲ → Shift 키 R")
            expect(ManualToggle.hangulToKeys("ㅒ") ?? "", "O", "ManualToggle: ㅒ → Shift 키 O")
            expect(ManualToggle.hangulToKeys("과") ?? "", "rhk", "ManualToggle: 과 → ㄱ+ㅗ+ㅏ = rhk")
            expect(ManualToggle.hangulToKeys("의") ?? "", "dml", "ManualToggle: 의 → ㅇ+ㅡ+ㅣ = dml")
            expect(ManualToggle.hangulToKeys("따") ?? "", "Ek", "ManualToggle: 따 → 쌍자음 초성 E+k")

            // (c) 자동변환 경로와 같은 결과여야 한다 — 조합기를 재사용하므로 갈릴 수 없다.
            //     (Vismo는 대문자로 시작해도 자판 위치가 같아 같은 한글이 나온다.)
            expect(ManualToggle.keysToHangul("Vismo") ?? "", "퍄느ㅐ", "ManualToggle: Vismo → 퍄느ㅐ (자동변환 경로와 동일)")
            expect(typePassive("vismo").committedText, ManualToggle.keysToHangul("vismo") ?? "",
                   "ManualToggle: vismo 조합 결과 = 조합기 실제 출력")
            expect(typePassive("apple").committedText, ManualToggle.keysToHangul("apple") ?? "",
                   "ManualToggle: apple 조합 결과 = 조합기 실제 출력")
            expect(ManualToggle.hangulToKeys("메ㅔㅣㄷ") ?? "", "apple", "ManualToggle: 메ㅔㅣㄷ → apple (자동변환과 같은 결과)")

            // (d) 바꿀 수 없는 입력은 손대지 않는다(nil) — 호출자는 키를 흘려보낸다.
            expect(ManualToggle.manualToggle(word: "") == nil, true, "manualToggle: 빈 문자열 → nil")
            expect(ManualToggle.manualToggle(word: " ") == nil, true, "manualToggle: 공백 → nil")
            expect(ManualToggle.manualToggle(word: "재 가") == nil, true, "manualToggle: 공백 포함 → nil")
            expect(ManualToggle.manualToggle(word: "😀") == nil, true, "manualToggle: 이모지 → nil")
            expect(ManualToggle.manualToggle(word: "재work") == nil, true, "manualToggle: 한글+영어 혼합 → nil")
            expect(ManualToggle.manualToggle(word: "123") == nil, true, "manualToggle: 숫자뿐 → 바꿀 게 없어 nil")
            expect(ManualToggle.manualToggle(word: "漢") == nil, true, "manualToggle: 한자 → nil")
            expect(ManualToggle.classify(word: "재가") == .hangul, true, "classify: 재가 = hangul")
            expect(ManualToggle.classify(word: "work") == .english, true, "classify: work = english")
            expect(ManualToggle.classify(word: "ㅡ5") == .hangul, true, "classify: ㅡ5 = hangul(숫자는 통과 문자)")
            expect(ManualToggle.classify(word: "재work") == .unsupported, true, "classify: 혼합 = unsupported")

            // (e) 표가 빠뜨린 자모가 없는지 — 손으로 적은 표가 아니라 기존 표에서 만들지만,
            //     그래도 전수로 확인한다(자모가 늘면 여기서 걸린다).
            var jamoOK = true
            for consonant in Consonant.allCases where ManualToggle.hangulToKeys(String(consonant.compatibility)) == nil {
                jamoOK = false
            }
            for vowel in Vowel.allCases where ManualToggle.hangulToKeys(String(vowel.compatibility)) == nil {
                jamoOK = false
            }
            expect(jamoOK, true, "ManualToggle: 낱자모 19+21개 전부 키로 역매핑됨")
            var compoundOK = true
            for (character, first, second) in ManualToggle.compoundFinalCompatibilityPairs {
                if CompoundFinal.index(first: first, second: second) == nil { compoundOK = false }
                if ManualToggle.hangulToKeys(String(character)) == nil { compoundOK = false }
            }
            expect(compoundOK, true, "ManualToggle: 겹자모 표기 표가 CompoundFinal과 짝이 맞음")

            // (f) 완성형 전수 왕복 — 분해 → 키 → 재조합이 원문과 같아야 한다(11,172자).
            var roundTripFailure = ""
            for code in 0xAC00...0xD7A3 {
                let syllable = String(UnicodeScalar(code)!)
                guard let keys = ManualToggle.hangulToKeys(syllable),
                      ManualToggle.keysToHangul(keys) == syllable else {
                    roundTripFailure = syllable
                    break
                }
            }
            expect(roundTripFailure, "", "ManualToggle: 완성형 11,172자 전부 한→키→한 왕복")

            // (g) 커서 앞 단어 잘라내기 — resolveToggle과 같은 isWordChar 규칙.
            expect(KoreanComposer.wordBeforeCursor(before: "재가 ", atDocStart: true)?.word ?? "",
                   "재가", "wordBeforeCursor: 뒤에 스페이스가 있어도 단어를 찾음")
            expect(KoreanComposer.wordBeforeCursor(before: "재가 ", atDocStart: true)?.trailing ?? -1,
                   1, "wordBeforeCursor: trailing 1")
            expect(KoreanComposer.wordBeforeCursor(before: "go work ", atDocStart: false)?.word ?? "",
                   "work", "wordBeforeCursor: 앞 단어가 더 있어도 마지막 단어만")
            expect(KoreanComposer.wordBeforeCursor(before: "재가", atDocStart: true)?.word ?? "",
                   "재가", "wordBeforeCursor: 커서가 단어에 붙어 있어도 됨(trailing 0)")
            expect(KoreanComposer.wordBeforeCursor(before: "재가", atDocStart: false) == nil, true,
                   "wordBeforeCursor: 읽기 창 앞에 닿음+문서 시작 아님 → 안전 nil")
            expect(KoreanComposer.wordBeforeCursor(before: "ㅡ5", atDocStart: true)?.word ?? "",
                   "ㅡ5", "wordBeforeCursor: 숫자도 단어 전체에 포함")
            expect(KoreanComposer.wordBeforeCursor(before: "ㅡ5", atDocStart: true)?.trailing ?? -1,
                   0, "wordBeforeCursor: ㅡ5의 trailing 0")
            expect(KoreanComposer.wordBeforeCursor(before: "   ", atDocStart: true) == nil, true,
                   "wordBeforeCursor: 경계 글자뿐이면 nil")
            expect(KoreanComposer.wordBeforeCursor(before: "", atDocStart: true) == nil, true,
                   "wordBeforeCursor: 빈 문자열 nil")
            expect(KoreanComposer.isWordChar(0x0035), true, "isWordChar: 숫자 5도 단어 문자")
            expect(KoreanComposer.isWordChar(0xC7AC), true, "isWordChar: 완성형 재는 단어 문자")

            // (h) 수동 토글로 바꾼 뒤 **한 번 더 누르면 되돌아온다** — 컨트롤러가 세우는
            //     lastConversion을 기존 되돌리기 경로가 그대로 매칭해야 한다.
            expect(KoreanComposer.resolveToggle(before: "work ", english: "work", hangul: "재가",
                                                atDocStart: true)?.text ?? "",
                   "재가", "재토글: 수동 변환 후 work → 재가")
            expect(KoreanComposer.resolveToggle(before: "m5", english: "m5", hangul: "ㅡ5",
                                                atDocStart: true)?.text ?? "",
                   "ㅡ5", "재토글: m5 전체 → ㅡ5")

            // (i) 조합 중(marked text)에는 수동 토글을 하지 않는다 — 문서에 아직 없기 때문.
            do {
                let client = FakeClient()
                let composer = KoreanComposer()
                expect(composer.hasPendingComposition, false, "hasPendingComposition: 처음엔 없음")
                _ = composer.handleInput("w", client: client)
                expect(composer.hasPendingComposition, true, "hasPendingComposition: 조합 중이면 true")
                composer.commit(to: client)
                expect(composer.hasPendingComposition, false, "hasPendingComposition: 확정 후 false")
            }

            // (j) 2026-11-10 (#216): `미리 친 단어 한/영 바꾸기` 토글을 없앴다 — 설정 키가 더는 없다(입력기는 늘 수동 변환한다).
            //     옛 값을 무시하는지는 InputControllerSessionTests의 `pair_mismatch_legacy_off`가 본다.

            // (k) 값싼 사전 필터 — 맨 스페이스는 defaults를 읽지 않는다.
            let plain = RevertKey.Modifiers([]).rawValue
            let shiftOnly = RevertKey.Modifiers.shift.rawValue
            let capsOnly = RevertKey.Modifiers.capsLock.rawValue
            expect(RevertKey.couldMatch(keyCode: 49, modifierFlagsRaw: plain), false,
                   "couldMatch: 맨 스페이스는 통과 못 함(defaults 안 읽음)")
            expect(RevertKey.couldMatch(keyCode: 49, modifierFlagsRaw: capsOnly), false,
                   "couldMatch: CapsLock만 붙은 스페이스도 통과 못 함")
            expect(RevertKey.couldMatch(keyCode: 49, modifierFlagsRaw: shiftOnly), true,
                   "couldMatch: Shift+Space는 통과")
            expect(RevertKey.couldMatch(keyCode: 0, modifierFlagsRaw: shiftOnly), false,
                   "couldMatch: Space가 아니면 false")
            var everyCandidatePasses = true
            for candidate in RevertKey.allCases
            where !RevertKey.couldMatch(keyCode: 49, modifierFlagsRaw: candidate.requiredModifiers.rawValue) {
                everyCandidatePasses = false
            }
            expect(everyCandidatePasses, true, "couldMatch: 후보 4종은 전부 사전 필터를 통과한다")
        }
        // ═══ 자동 업데이트 판단 (#19, 2026-09-21) ═══
        // 네트워크·파일 교체 없이 "무엇을 결정하는가"만 검증한다. 인터넷에서 받은 파일로
        // 앱을 갈아끼우는 기능이라, 애매하면 "업데이트 없음 / 설치 금지"로 닫혀야 한다.

        // ── CalVer 파싱·비교 ──
        func ver(_ s: String) -> CalVer? { CalVer(s) }
        expect(ver("2026.07") != nil, true, "CalVer: 2026.07 파싱")
        expect(ver("2026.08.1") != nil, true, "CalVer: 3칸 파싱")
        expect(ver("2026.07")! < ver("2026.08")!, true, "CalVer: 2026.07 < 2026.08")
        expect(ver("2026.08")! < ver("2026.08.1")!, true, "CalVer: 2026.08 < 2026.08.1")
        expect(ver("2026.08.1")! < ver("2026.09")!, true, "CalVer: 2026.08.1 < 2026.09")
        expect(ver("2026.09")! < ver("2027.01")!, true, "CalVer: 연도 우선")
        expect(ver("2026.02.10")! > ver("2026.02.09")!, true, "CalVer: 세 번째 칸도 정수(10 > 9)")
        expect(ver("2026.10")! > ver("2026.9")!, true, "CalVer: 두 번째 칸 정수(10 > 9, 소수점 아님)")
        expect(ver("2026.08") == ver("2026.08"), true, "CalVer: 같은 버전")
        expect(ver("2026.08") == ver("2026.08.0"), true, "CalVer: 핫픽스 0은 없는 것과 같음")
        expect(ver("2026.08")! < ver("2026.08")!, false, "CalVer: 같은 버전은 더 새 것이 아님")
        expect(ver("2026.08")?.description ?? "", "2026.08", "CalVer: 표시는 원문")
        expect(ver("v2026.08") == nil, true, "CalVer: v 접두어 거부")
        expect(ver("2026") == nil, true, "CalVer: 1칸 거부")
        expect(ver("2026.08.1.2") == nil, true, "CalVer: 4칸 거부")
        expect(ver("2026..08") == nil, true, "CalVer: 빈 칸 거부")
        expect(ver("2026.-1") == nil, true, "CalVer: 음수 거부")
        expect(ver("2026.0x8") == nil, true, "CalVer: 숫자 아닌 문자 거부")
        expect(ver("") == nil, true, "CalVer: 빈 문자열 거부")
        expect(ver("2026.08 ") == nil, true, "CalVer: 공백 거부")
        expect(ver("２０２６.08") == nil, true, "CalVer: 전각 숫자 거부")

        // 2026-10-09: 정식 배포 YYYY.MM.DD, 이전 순번형 설치본에서의 전환도 유지.
        expect(ver("2026.10.10")?.description ?? "", "2026.10.10", "날짜 버전: 원문 표시")
        expect(ver("2026.07")! < ver("2026.10.10")!, true, "날짜 버전: 공개 베타에서 상승")
        expect(ver("2026.9")! < ver("2026.10.10")!, true, "날짜 버전: 내부 후보에서 상승")
        expect(ver("2026.10.09")! < ver("2026.10.10")!, true, "날짜 버전: 일 비교")
        expect(ver("2026.10.31")! < ver("2026.11.01")!, true, "날짜 버전: 월 경계")
        expect(ver("2026.12.31")! < ver("2027.01.01")!, true, "날짜 버전: 연도 경계")
        expect(ver("2026.07-beta") == nil, true, "날짜 버전: 베타 태그는 정식 업데이트 대상 아님")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.9", currentBuild: 62,
                   newVersion: "2026.10.10", newBuild: 63), true, "날짜 버전: 내부 후보에서 정식으로 교체 허용")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.10.10", currentBuild: 63,
                   newVersion: "2026.10.10", newBuild: 64), false, "날짜 버전: 같은 날 같은 번호 재게시로 업데이트되지 않음")
        let datedRelease = ReleaseInfo(tag: "2026.10.10", assets: [ReleaseAsset(
            name: "HaneulKeyboard_2026.10.10.zip",
            downloadURL: URL(string: "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.10.10/HaneulKeyboard_2026.10.10.zip")!,
            size: 1_000)], pageURL: nil)
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.9", release: datedRelease)?.tag ?? "",
               "2026.10.10", "날짜 버전: 태그와 파일명이 일치하는 정식 업데이트 탐지")

        // 2026-10-10: 공개 이름의 핫픽스와 Apple 숫자 버전 항목을 연결한다.
        // 2026-11-04 (#131): 오너 결정으로 `_hotfix` 하나 → `_hotfix1`, `_hotfix2` … 번호. 번호는 숫자로 비교한다.
        expect(ver("2026.10.15")! < ver("2026.10.15_hotfix1")!, true, "핫픽스는 같은 날짜의 기본판보다 새 버전")
        expect(ver("2026.10.15_hotfix1")! < ver("2026.10.15_hotfix2")!, true, "핫픽스 번호가 크면 새 버전")
        expect(ver("2026.10.15_hotfix9")! < ver("2026.10.15_hotfix10")!, true, "핫픽스 번호는 글자가 아니라 숫자로 비교")
        expect(ver("2026.10.15_hotfix12")! < ver("2026.10.16")!, true, "다음 날짜는 전날 핫픽스보다 새 버전")
        expect(ver("2026.10.15_hotfix2")! == ver("2026.10.15_hotfix2")!, true, "같은 핫픽스는 같음")
        expect(ver("2026.10.15_hotfix1")! == ver("2026.10.15")!, false, "핫픽스와 기본판은 다름")
        expect(ver("2026.10.15_hotfix1")?.description ?? "", "2026.10.15_hotfix1", "핫픽스 표기 보존")
        expect(ver("2026.10.15_hotfix999")?.isHotfix ?? false, true, "핫픽스 999까지")
        expect(ver("2026.10.15")?.isHotfix ?? true, false, "기본판은 핫픽스 아님")
        for invalid in ["2026.10.15_hotfix", "2026.10_hotfix1", "2026.10.15_hotfix0", "2026.10.15_hotfix01",
                        "2026.10.15_hotfix1000", "2026.10.15_hotfix-1", "2026.10.15_hotfix1_hotfix1",
                        "2026.10.15_hotfix1 ", "2026.10.15_hotfix١", "2026.10.15_HOTFIX1", "2026.10.15_hotfixa",
                        "2026.2.15_hotfix1", "2026.13.15_hotfix1", "2026.02.29_hotfix1", "2026.04.31_hotfix1"] {
            expect(ver(invalid) == nil, true, "확정된 핫픽스 형식만 허용: \(invalid)")
        }
        expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.10.15", "HaneulReleaseSuffix": "_hotfix2"]) ?? "",
               "2026.10.15_hotfix2", "서명된 번들 항목에서 공개 핫픽스 버전 읽기")
        expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.10.15", "HaneulReleaseSuffix": ""]) ?? "",
               "2026.10.15", "빈 접미어는 기본판")
        expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.9"]) ?? "", "2026.9", "과거 번들 호환")
        for badSuffix in ["oops", "_hotfix", "_hotfix0", "hotfix1", "_hotfix1_hotfix1"] {
            expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.10.15", "HaneulReleaseSuffix": badSuffix]) == nil,
                   true, "미확인 번들 접미어 거부: \(badSuffix)")
        }
        expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.10.15", "HaneulReleaseSuffix": 1]) == nil,
               true, "잘못된 번들 항목 타입 거부")
        expect(UpdateDecision.releaseVersion(info: ["CFBundleShortVersionString": "2026.10_", "HaneulReleaseSuffix": "_hotfix1"]) == nil,
               true, "핫픽스는 날짜 3칸에만")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.10.15", currentBuild: 69,
                   newVersion: "2026.10.15_hotfix1", newBuild: 70), true, "기본판에서 핫픽스 설치 허용")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.10.15_hotfix1", currentBuild: 70,
                   newVersion: "2026.10.15_hotfix2", newBuild: 71), true, "핫픽스1에서 핫픽스2 설치 허용")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.10.15_hotfix2", currentBuild: 71,
                   newVersion: "2026.10.15_hotfix1", newBuild: 72), false, "핫픽스 번호 역행 금지")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.10.15_hotfix1", currentBuild: 70,
                   newVersion: "2026.10.15", newBuild: 71), false, "핫픽스에서 기본판으로 역행 금지")
        let hotfixRelease = ReleaseInfo(tag: "2026.10.15_hotfix1", assets: [ReleaseAsset(
            name: "HaneulKeyboard_2026.10.15_hotfix1.zip",
            downloadURL: URL(string: "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.10.15_hotfix1/HaneulKeyboard_2026.10.15_hotfix1.zip")!,
            size: 1_000)], pageURL: nil)
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15", release: hotfixRelease)?.tag ?? "",
               "2026.10.15_hotfix1", "핫픽스 파일명과 태그의 실제 업데이트 탐지")
        let secondHotfix = ReleaseInfo(tag: "2026.10.15_hotfix2", assets: [ReleaseAsset(
            name: "HaneulKeyboard_2026.10.15_hotfix2.zip",
            downloadURL: URL(string: "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.10.15_hotfix2/HaneulKeyboard_2026.10.15_hotfix2.zip")!,
            size: 1_000)], pageURL: nil)
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15_hotfix1", release: secondHotfix)?.tag ?? "",
               "2026.10.15_hotfix2", "두 번째 핫픽스도 업데이트로 탐지")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15_hotfix2", release: hotfixRelease) == nil,
               true, "더 낮은 번호의 핫픽스는 제공하지 않음")
        let installerAsset = ReleaseAsset(name: "HaneulKeyboard_2026.10.15_hotfix1.dmg",
            downloadURL: URL(string: "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.10.15_hotfix1/HaneulKeyboard_2026.10.15_hotfix1.dmg")!, size: 1_000)
        let dualFormatRelease = ReleaseInfo(tag: hotfixRelease.tag, assets: [installerAsset] + hotfixRelease.assets, pageURL: nil)
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15", release: dualFormatRelease)?.asset.name ?? "",
               "HaneulKeyboard_2026.10.15_hotfix1.zip", "첫 설치 DMG와 함께 있어도 앱 안 업데이트는 ZIP 선택")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15_hotfix1", release: dualFormatRelease) == nil,
               true, "같은 핫픽스는 다시 제공하지 않음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15", release:
            ReleaseInfo(tag: hotfixRelease.tag, assets: [installerAsset], pageURL: nil)) == nil,
               true, "업데이트 ZIP 누락이면 DMG로 임의 대체하지 않음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10.15", release:
            ReleaseInfo(tag: "2026.10.15_hotfix", assets: [ReleaseAsset(name: "HaneulKeyboard_2026.10.15_hotfix.zip",
                downloadURL: URL(string: "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.10.15_hotfix/HaneulKeyboard_2026.10.15_hotfix.zip")!,
                size: 1_000)], pageURL: nil)) == nil,
               true, "번호 없는 옛 핫픽스 태그는 업데이트로 보지 않음(fail-closed)")

        // ── 저장소·URL·자산 이름 ──
        expect(UpdateDecision.isValidRepository("Hyunjin-Cho/HaneulKeyboard"), true, "업데이트: 정상 슬러그")
        expect(UpdateDecision.isValidRepository("Hyunjin-Cho/HaneulKeyboard-updatetest"), true, "업데이트: 테스트 슬러그")
        expect(UpdateDecision.isValidRepository("HaneulKeyboard"), false, "업데이트: 슬래시 없는 슬러그 거부")
        expect(UpdateDecision.isValidRepository("a/b/c"), false, "업데이트: 슬래시 2개 거부")
        expect(UpdateDecision.isValidRepository("../etc"), false, "업데이트: .. 거부")
        expect(UpdateDecision.isValidRepository("a b/c"), false, "업데이트: 공백 거부")
        expect(UpdateDecision.isValidRepository("a/c?x=1"), false, "업데이트: 쿼리 문자 거부")
        expect(
            UpdateDecision.latestReleaseURL(repository: "Hyunjin-Cho/HaneulKeyboard")?.absoluteString ?? "",
            "https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest",
            "업데이트: latest 엔드포인트"
        )
        expect(UpdateDecision.latestReleaseURL(repository: "bad slug") == nil, true, "업데이트: 잘못된 슬러그면 URL 없음")
        expect(UpdateDecision.assetName(forTag: "2026.07"), "HaneulKeyboard_2026.07.zip", "업데이트: 자산 이름 = 빌드 스크립트 산출물명")

        // ── 허용 호스트(HTTPS만, 2026-09-21 실측 리다이렉트 포함) ──
        expect(UpdateDecision.isAllowedURL(URL(string: "https://github.com/x/y/releases/download/1/a.zip")!), true, "업데이트: github.com 허용")
        expect(UpdateDecision.isAllowedURL(URL(string: "https://release-assets.githubusercontent.com/x")!), true, "업데이트: 실측 리다이렉트 호스트 허용")
        expect(UpdateDecision.isAllowedURL(URL(string: "https://objects.githubusercontent.com/x")!), true, "업데이트: objects.githubusercontent.com 허용")
        expect(UpdateDecision.isAllowedURL(URL(string: "http://github.com/x")!), false, "업데이트: HTTP 거부")
        expect(UpdateDecision.isAllowedURL(URL(string: "https://evil.example.com/x")!), false, "업데이트: 다른 호스트 거부")
        expect(UpdateDecision.isAllowedURL(URL(string: "https://github.com.evil.example/x")!), false, "업데이트: 접두어 함정 거부")
        expect(UpdateDecision.isAllowedURL(URL(string: "https://evilgithub.com/x")!), false, "업데이트: 접미어 함정 거부")

        // ── codesign 요구사항 (#19 보안 검토 P1-1, 2026-09-21) ──
        // 실측: 이 인자 배열 그대로 `/Applications/HaneulKeyboard.app`에 돌리면 exit 0,
        // 팀 ID만 다른 값으로 바꾸면 exit 3(code failed to satisfy specified code requirement(s)).
        do {
            let args = UpdateDecision.codesignArguments(appPath: "/Applications/HaneulKeyboard.app")
            expect(args.count, 5, "codesign: 인자 5개")
            expect(args[0], "--verify", "codesign: --verify")
            expect(args[1], "--deep", "codesign: --deep")
            expect(args[2], "--strict", "codesign: --strict")
            expect(args[3], "-R=anchor apple generic and certificate leaf[subject.OU] = \"6RH6FXY82P\"",
                   "codesign: 요구사항은 --strict 뒤 한 인자(애플 앵커 + 우리 Team)")
            expect(args[4], "/Applications/HaneulKeyboard.app", "codesign: 경로는 맨 뒤")
            expect(UpdateDecision.codesignRequirement.contains("anchor apple generic"), true,
                   "codesign: 애플 앵커가 요구사항에 있다(자체 서명 위조 차단)")
            expect(UpdateDecision.codesignRequirement.contains(UpdateDecision.signingTeamIdentifier), true,
                   "codesign: Team ID 상수를 그대로 쓴다(문자열 사본 없음)")
        }

        // ── 릴리스 JSON 파싱(2026-09-21 실측 응답 형태) ──
        let releaseJSON = """
        {"tag_name":"2026.09","name":"2026.09","draft":false,"prerelease":false,
         "html_url":"https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2026.09",
         "assets":[
           {"name":"HaneulKeyboard_2026.09.zip","browser_download_url":"https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.09/HaneulKeyboard_2026.09.zip","size":5899281,"content_type":"application/zip"},
           {"name":"HaneulKeyboardIM_2026.09.zip","browser_download_url":"https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.09/HaneulKeyboardIM_2026.09.zip","size":100}
         ]}
        """
        let release = UpdateDecision.parseRelease(Data(releaseJSON.utf8))
        expect(release?.tag ?? "", "2026.09", "업데이트: tag_name 파싱")
        expect(release?.assets.count ?? 0, 2, "업데이트: 자산 2개 파싱")
        expect(release?.pageURL?.absoluteString ?? "", "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2026.09", "업데이트: html_url 파싱")
        expect(UpdateDecision.parseRelease(Data("not json".utf8)) == nil, true, "업데이트: JSON 아니면 nil")
        expect(UpdateDecision.parseRelease(Data("{}".utf8)) == nil, true, "업데이트: tag_name 없으면 nil")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"draft\":true}".utf8)) == nil, true, "업데이트: draft면 nil(fail-closed)")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"prerelease\":true}".utf8)) == nil, true, "업데이트: prerelease면 nil")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\"}".utf8))?.assets.count ?? -1, 0, "업데이트: assets 없으면 빈 배열")
        // html_url도 다운로드 URL과 같은 화이트리스트를 통과해야 채워진다 (#19 P2-1, 2026-09-21)
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"html_url\":\"https://evil.example.com/releases/tag/2026.09\"}".utf8))?.pageURL == nil, true,
               "업데이트: 허용 밖 호스트의 html_url은 버린다(릴리스 노트 링크로 임의 주소 열기 차단)")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"html_url\":\"http://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2026.09\"}".utf8))?.pageURL == nil, true,
               "업데이트: HTTP html_url 거부")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"html_url\":\"https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2026.09\"}".utf8))?.pageURL?.absoluteString ?? "",
               "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2026.09",
               "업데이트: github.com html_url은 통과")
        expect(UpdateDecision.parseRelease(Data("{\"tag_name\":\"2026.09\",\"html_url\":\"https://evil.example.com/x\"}".utf8))?.tag ?? "", "2026.09",
               "업데이트: html_url이 막혀도 릴리스 파싱 자체는 계속된다(링크만 안 보임)")

        // ── 자산 선택: 이름 정확 일치 + 허용 URL ──
        expect(UpdateDecision.selectAsset(in: release!)?.name ?? "", "HaneulKeyboard_2026.09.zip", "업데이트: 이름 정확 일치 자산 선택")
        expect(UpdateDecision.selectAsset(in: release!)?.size ?? 0, 5899281, "업데이트: 자산 크기 전달")
        let imOnly = ReleaseInfo(tag: "2026.09", assets: [
            ReleaseAsset(name: "HaneulKeyboardIM_2026.09.zip", downloadURL: URL(string: "https://github.com/a")!, size: 1),
            ReleaseAsset(name: "haneulkeyboard_2026.09.zip", downloadURL: URL(string: "https://github.com/b")!, size: 1),
            ReleaseAsset(name: "HaneulKeyboard_2026.09.zip.sig", downloadURL: URL(string: "https://github.com/c")!, size: 1),
        ], pageURL: nil)
        expect(UpdateDecision.selectAsset(in: imOnly) == nil, true, "업데이트: 비슷한 이름은 전부 거부(대소문자·접미·IM 단독)")
        let badHost = ReleaseInfo(tag: "2026.09", assets: [
            ReleaseAsset(name: "HaneulKeyboard_2026.09.zip", downloadURL: URL(string: "https://evil.example.com/HaneulKeyboard_2026.09.zip")!, size: 1),
        ], pageURL: nil)
        expect(UpdateDecision.selectAsset(in: badHost) == nil, true, "업데이트: 허용 밖 호스트 자산 거부")
        let plainHTTP = ReleaseInfo(tag: "2026.09", assets: [
            ReleaseAsset(name: "HaneulKeyboard_2026.09.zip", downloadURL: URL(string: "http://github.com/x.zip")!, size: 1),
        ], pageURL: nil)
        expect(UpdateDecision.selectAsset(in: plainHTTP) == nil, true, "업데이트: HTTP 자산 거부")
        let huge = ReleaseInfo(tag: "2026.09", assets: [
            ReleaseAsset(name: "HaneulKeyboard_2026.09.zip", downloadURL: URL(string: "https://github.com/x.zip")!, size: UpdateDecision.maxAssetBytes + 1),
        ], pageURL: nil)
        expect(UpdateDecision.selectAsset(in: huge) == nil, true, "업데이트: 크기 상한 초과 자산 거부")

        // ── "업데이트 있음" 판정 ──
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.08", release: release!)?.tag ?? "", "2026.09", "업데이트: 2026.08 → 2026.09 있음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.09", release: release!) == nil, true, "업데이트: 같은 버전이면 없음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.10", release: release!) == nil, true, "업데이트: 현재가 더 새면 없음(다운그레이드 금지)")
        expect(UpdateDecision.availableUpdate(currentVersion: "dev", release: release!) == nil, true, "업데이트: 현재 버전 형식 오류면 없음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.08", release: ReleaseInfo(tag: "v2026.09", assets: release!.assets, pageURL: nil)) == nil, true, "업데이트: tag 형식 오류면 없음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.08", release: ReleaseInfo(tag: "2026.09", assets: [], pageURL: nil)) == nil, true, "업데이트: 자산 없으면 없음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.08", release: imOnly) == nil, true, "업데이트: 맞는 자산 없으면 없음")
        expect(UpdateDecision.availableUpdate(currentVersion: "2026.08", release: release!)?.asset.downloadURL.absoluteString ?? "",
               "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2026.09/HaneulKeyboard_2026.09.zip", "업데이트: 다운로드 URL 전달")

        // ── 매월 1일 확인 (2026-11-08 #201, 예전 24시간) ──
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ sec: Int = 0) -> Date {
            seoul.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: sec))!
        }
        func due(_ last: Date?, _ now: Date, auto: Bool = true, forced: Bool = false) -> Bool {
            UpdateDecision.shouldCheckNow(autoCheckEnabled: auto, lastCheck: last, now: now, forced: forced, calendar: seoul)
        }
        let now = at(2026, 11, 8, 12, 0)
        expect(due(nil, now), true, "월간 확인: 처음이면 확인")
        expect(due(at(2026, 11, 1, 0, 0, 0), now), false, "월간 확인: 이번 달 1일 0시에 확인했으면 대기")
        expect(due(at(2026, 10, 31, 23, 59, 59), now), true, "월간 확인: 지난달 마지막 순간이면 확인")
        expect(due(at(2026, 10, 1, 9), at(2026, 11, 1, 0, 0, 0)), true, "월간 확인: 1일 0시가 되면 확인")
        expect(due(at(2026, 10, 1, 9), at(2026, 10, 31, 23, 59, 59)), false, "월간 확인: 1일 전 마지막 순간엔 대기")
        expect(due(at(2026, 10, 2, 9), at(2026, 11, 5, 9)), true, "월간 확인: 1일에 안 켰으면 그다음 켤 때 확인")
        expect(due(at(2026, 11, 5, 9), at(2026, 11, 5, 10)), false, "월간 확인: 같은 달에 이미 확인했으면 대기")
        expect(due(at(2026, 11, 3, 9), at(2026, 11, 30, 23)), false, "월간 확인: 같은 달 말일까지 대기")
        expect(due(at(2026, 12, 15), at(2027, 1, 1, 0, 0, 1)), true, "월간 확인: 해가 바뀌어도 1일에 확인")
        expect(due(now, now), false, "월간 확인: 방금 확인했으면 대기")
        expect(due(now.addingTimeInterval(3600), now), true, "월간 확인: 마지막 확인이 미래(시계 되감김)면 확인")
        expect(due(nil, now, auto: false), false, "월간 확인: 토글 OFF면 자동 확인 안 함(네트워크 0)")
        expect(due(nil, now, auto: false, forced: true), true, "월간 확인: 토글 OFF여도 '지금 확인'은 확인")
        expect(due(now, now, forced: true), true, "월간 확인: '지금 확인'은 주기 무시")
        expect(UpdateDecision.startOfMonth(containing: at(2026, 2, 28, 23), calendar: seoul) == at(2026, 2, 1), true, "월간 확인: 달의 시작")

        // ── 버전 상승(다운그레이드·재설치 금지) ──
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.09", newBuild: 51), true, "버전 상승: 버전·빌드 모두 큼")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.09", newBuild: 50), false, "버전 상승: 빌드번호 같으면 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.09", newBuild: 49), false, "버전 상승: 빌드번호 낮으면 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.08", newBuild: 51), false, "버전 상승: 버전 같으면 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.07", newBuild: 60), false, "버전 상승: 버전 낮으면 빌드가 커도 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: nil, newBuild: 51), false, "버전 상승: 새 버전 못 읽으면 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: 50, newVersion: "2026.09", newBuild: nil), false, "버전 상승: 새 빌드 못 읽으면 거부")
        expect(UpdateDecision.isVersionIncrease(currentVersion: "2026.08", currentBuild: nil, newVersion: "2026.09", newBuild: 51), false, "버전 상승: 현재 빌드 못 읽으면 거부")

        // ── 검증 결과 합성: 하나라도 실패하면 설치 금지 ──
        let allPass = UpdateVerification(bundleIDMatches: true, sameTeamSigned: true, codesignValid: true, notarizationAccepted: true, versionIncreases: true)
        expect(allPass.passed, true, "검증: 5종 통과")
        expect(allPass.failures.count, 0, "검증: 실패 목록 비어 있음")
        var oneFail = allPass; oneFail.bundleIDMatches = false
        expect(oneFail.passed, false, "검증: 번들 ID 실패 → 금지")
        oneFail = allPass; oneFail.sameTeamSigned = false
        expect(oneFail.passed, false, "검증: Team 실패 → 금지")
        oneFail = allPass; oneFail.codesignValid = false
        expect(oneFail.passed, false, "검증: codesign 실패 → 금지")
        oneFail = allPass; oneFail.notarizationAccepted = false
        expect(oneFail.passed, false, "검증: spctl 실패 → 금지")
        expect(oneFail.failures.joined(separator: "|").contains("Gatekeeper"), true, "검증: 실패 사유 문구")
        oneFail = allPass; oneFail.versionIncreases = false
        expect(oneFail.passed, false, "검증: 버전 상승 실패 → 금지")
        let allFail = UpdateVerification(bundleIDMatches: false, sameTeamSigned: false, codesignValid: false, notarizationAccepted: false, versionIncreases: false)
        expect(allFail.failures.count, 5, "검증: 전부 실패면 사유 5개")

        // ── IME 갱신 판단 ──
        expect(UpdateDecision.shouldRefreshIME(installedBuild: 50, bundledBuild: 51), true, "IME 갱신: 설치본 < 임베드본")
        expect(UpdateDecision.shouldRefreshIME(installedBuild: 51, bundledBuild: 51), false, "IME 갱신: 같으면 안 함")
        expect(UpdateDecision.shouldRefreshIME(installedBuild: 52, bundledBuild: 51), false, "IME 갱신: 설치본이 더 새면 안 함")
        expect(UpdateDecision.shouldRefreshIME(installedBuild: nil, bundledBuild: 51), false, "IME 갱신: 설치본 없음/못 읽음 → 안 함(H-01)")
        expect(UpdateDecision.shouldRefreshIME(installedBuild: 50, bundledBuild: nil), false, "IME 갱신: 임베드본 못 읽음 → 안 함")

        // ── 푼 번들이 실체인가 (#19 보안 검토 P3-1, 2026-09-21) ──
        // 실측: `ditto -x -k`는 zip의 심볼릭 링크 엔트리를 링크 그대로 만들고, `fileExists`는
        // 그 링크를 따라가므로 검증이 **바깥 번들**에 적용된다. 여기서 먼저 잘라낸다.
        do {
            let extractDir = "/private/var/folders/ab/HaneulKeyboardUpdate-1/extract"
            let good = extractDir + "/HaneulKeyboard.app"
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: good, resolvedExtractDirPath: extractDir),
                   true, "추출 검사: 추출 폴더 안의 실제 디렉터리는 통과")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: true, isDirectory: true,
                                                     resolvedAppPath: good, resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 심볼릭 링크면 거부")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: false,
                                                     resolvedAppPath: good, resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 디렉터리가 아니면 거부(파일 하나짜리 위장)")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: "/Applications/HaneulKeyboard.app",
                                                     resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 링크를 푼 실경로가 추출 폴더 밖이면 거부")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: extractDir, resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 추출 폴더 자신은 거부")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: extractDir + "-evil/HaneulKeyboard.app",
                                                     resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 접두어만 같은 형제 폴더 거부")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: extractDir + "/../HaneulKeyboard.app",
                                                     resolvedExtractDirPath: extractDir),
                   false, "추출 검사: 경로에 .. 가 남아 있으면 거부")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: good, resolvedExtractDirPath: extractDir + "/"),
                   true, "추출 검사: 추출 폴더 끝 슬래시는 무시")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: "/HaneulKeyboard.app", resolvedExtractDirPath: "/"),
                   false, "추출 검사: 추출 폴더가 루트면 거부(fail-closed)")
            expect(UpdateDecision.isSafeExtractedApp(isSymbolicLink: false, isDirectory: true,
                                                     resolvedAppPath: good, resolvedExtractDirPath: "extract"),
                   false, "추출 검사: 상대 경로면 거부(fail-closed)")
        }

        // ── 실행 위치·교체 전략 ──
        expect(UpdateDecision.isRunningFromDestination(bundlePath: "/Applications/HaneulKeyboard.app", destinationPath: "/Applications/HaneulKeyboard.app"), true, "교체: /Applications에서 실행 중")
        expect(UpdateDecision.isRunningFromDestination(bundlePath: "/Users/x/Downloads/HaneulKeyboard.app", destinationPath: "/Applications/HaneulKeyboard.app"), false, "교체: 다운로드 폴더면 중단")
        expect(UpdateDecision.isRunningFromDestination(bundlePath: "/Applications/Renamed.app", destinationPath: "/Applications/HaneulKeyboard.app"), false, "교체: 이름 바뀐 사본이면 중단")
        expect(UpdateDecision.replaceStrategy(destinationOwnerUID: 501, currentUID: 501, parentWritable: true) == .userAtomic, true, "교체: 사용자 소유 → 원자 교체")
        expect(UpdateDecision.replaceStrategy(destinationOwnerUID: 0, currentUID: 501, parentWritable: true) == .adminPrompt, true, "교체: root 소유 → 관리자 프롬프트")
        expect(UpdateDecision.replaceStrategy(destinationOwnerUID: 501, currentUID: 501, parentWritable: false) == .adminPrompt, true, "교체: 부모 폴더 쓰기 불가 → 관리자 프롬프트")
        expect(UpdateDecision.replaceStrategy(destinationOwnerUID: nil, currentUID: 501, parentWritable: true) == .adminPrompt, true, "교체: 소유자 못 읽으면 관리자 프롬프트")

        expect(typeWordsViaController(["a24", "so"]).joined(separator: " "), "a24 내", "숫자 이름 뒤 한국어 보호")
        expect(typeViaController("123 a24").committedText, "123 a24", "일반 숫자 뒤 공백에서 새 이름 시작")
        expect(typeViaControllerWithPersonalDictionary("x9q", .empty).committedText, "ㅌ9ㅂ", "개인 사전 제거 후 미등록 이름 유지")

        // 2026-10-06 (#74): 대표 범주의 실제 컨트롤러 경로 + 개인 사전 금지 우선 회귀.
        let categoryText = try! String(contentsOfFile: "dict_work/2026-10-06-nature-film-coverage.txt", encoding: .utf8)
        let categoryWords = categoryText.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        expect(categoryWords.count, 201, "범주 대표 이름 표본 수")
        for name in categoryWords {
            expect(typeViaController(name).committedText, name, "범주 이름 자동 변환: \(name)")
            let hangul = typeViaController(name, autoEnglish: false).committedText
            expect(typeViaControllerWithPersonalDictionary(name, PersonalDictionary(force: [name], block: [name])).committedText,
                   hangul, "범주 이름도 개인 사전 금지 우선: \(name)")
        }

        // 2026-10-08: 아트 용어의 실제 입력 결과와 개인 사전 금지 우선.
        // slab=니뮤는 한글 표현 보호 때문에 curated 승격에서 제외했다.
        let artText = try! String(contentsOfFile: "dict_work/2026-10-08-art-design-coverage.txt", encoding: .utf8)
        let artWords = artText.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        expect(artWords.count, 202, "아트·디자인 대표 용어 표본 수")
        for word in artWords {
            expect(typeViaController(word).committedText, word == "slab" ? "니뮤" : word,
                   "아트 용어 자동 변환/한글 보호: \(word)")
            let hangul = typeViaController(word, autoEnglish: false).committedText
            expect(hangul != word, true, "아트 용어 자동 변환 OFF: \(word)")
            expect(typeViaControllerWithPersonalDictionary(word, PersonalDictionary(force: [word], block: [word])).committedText,
                   hangul, "아트 용어도 개인 사전 금지 우선: \(word)")
        }
        expect(typeViaControllerWithPersonalDictionary("slab", PersonalDictionary(force: ["slab"])).committedText,
               "slab", "보류한 용어는 사용자 명시 추가로 변환 가능")
        expect(typeViaController("slabb").committedText, "니뮤ㅠ", "아트 용어 보완 후 한글 감정 표현 보호")

        // ── 2026-10-06: 등록된 숫자 이름·개인 사전·수동 토글 회귀 (#5/#74~78) ──
        for name in ["tangerine", "vismo", "opencode", "anti", "cinestill", "superia", "velvia"] {
            expect(typeViaController(name).committedText, name, "요청 단어: \(name)")
        }
        for (keys, expected) in [("wOrk", "쟤가"), ("Work", "Work"), ("WORK", "WORK"), ("worK", "worK")] {
            expect(typeViaController(keys).committedText, expected, "Shift 보호: \(keys)")
        }
        for name in ["T800", "t800", "800T", "800t", "a24", "A24", "a16z", "A16Z", "a7r", "a7R"] {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in name { typeKeyViaController(ch, composer: composer, client: client) }
            // 2026-11-04 (오너 결정): 단어 첫머리 숫자는 앱에 바로 들어간다(CLI 숫자 선택). 800T는 800이 먼저 확정되고
            // 경계에서 뒤 글자만 넣는다(앞 숫자를 붙여 예전 판정 그대로). 되돌림 쌍은 화면 단어 전체(800ㅆ↔800T)다.
            let lead = String(name.prefix(while: \.isNumber))
            let raw = lead + client.marked
            expect(client.committedText, lead, "숫자 이름: 경계 전 확정 없음 \(name)")
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, name, "숫자 이름: 전체·대소문자 보존 \(name)")
            expect(composer.lastConversion?.hangul ?? "", raw, "숫자 이름: 전체 되돌림 쌍 \(name)")
            expect(composer.lastEnglishWord == nil, true, "숫자 이름: 다음 한국어 문맥 보호 \(name)")
            expect(KoreanComposer.resolveToggle(before: name + " ", english: name, hangul: raw,
                                                 atDocStart: true)?.text ?? "", raw, "숫자 이름: 직후 되돌리기 \(name)")
            expect(typeViaController(name, autoEnglish: false).committedText, raw, "숫자 이름: 자동 변환 OFF \(name)")
            expect(typeViaControllerWithPersonalDictionary(name, PersonalDictionary(block: [name.lowercased()])).committedText,
                   raw, "숫자 이름: 영어 금지 \(name)")
            expect(typeViaControllerWithPersonalDictionary(name, PersonalDictionary(block: [raw])).committedText,
                   raw, "숫자 이름: 한글 금지 \(name)")
            expect(typeViaControllerWithPersonalDictionary(name, PersonalDictionary(force: [name.lowercased()], block: [name.lowercased()])).committedText,
                   raw, "숫자 이름: 금지 우선 \(name)")
            composer.applyToggle(toEnglish: true, hangul: raw, english: name)
            expect(composer.lastEnglishWord == nil, true, "숫자 이름: 재토글도 문맥 보호 \(name)")
        }
        for name in ["x9q", "42abc", "z8's", "z’8"] {
            let pd = PersonalDictionary(forceList: [name], blockList: [])
            expect(typeViaControllerWithPersonalDictionary(name, pd).committedText, name, "숫자 개인 사전: \(name)")
        }
        for (keys, expected) in [("123a24", "123ㅁ24"), ("za24", "ㅋㅁ24"), ("a24z", "ㅁ24ㅋ"),
                                 ("a7r5", "ㅁ7ㄱ5"), ("T8000", "ㅆ8000"), ("dir2dkf", "약2알"),
                                 ("anf2flxj", "물2리터"), ("zz123", "ㅋㅋ123"), ("r2", "ㄱ2"),
                                 ("apple2", "apple2"), ("apple800T", "apple800ㅆ"), ("a1", "ㅁ1"), ("800", "800")] {
            expect(typeViaController(keys).committedText, expected, "숫자 이름: 미등록·한국어 보존 \(keys)")
        }
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "a24" { typeKeyViaController(ch, composer: composer, client: client) }
            expect(composer.commit(to: client, convertEnglish: false), "ㅁ24", "숫자 이름: 포커스 이동은 화면 그대로")
            composer.resetEnglishContext()
            for ch in "a1" { typeKeyViaController(ch, composer: composer, client: client) }
            expect(composer.deleteBackward(client: client), true, "숫자 이름: 숫자 백스페이스")
            typeKeyViaController("k", composer: composer, client: client)
            expect(client.marked, "마", "숫자 삭제 후 이전 한글 음절 조합 복원")
            composer.commit(to: client, convertEnglish: false)
        }
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "a" + String(repeating: "2", count: 90) { typeKeyViaController(ch, composer: composer, client: client) }
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "ㅁ" + String(repeating: "2", count: 90), "숫자 이름: 긴 후보 유실 없이 원문 유지")
            expect(client.marked.isEmpty, true, "숫자 이름: 긴 후보 조합 종료")
        }
        for invalid in ["'apple", "a'b'c", "a’’b", "123", "a-24"] {
            expect(PersonalDictionary.normalizedForceEntry(invalid) == nil, true, "개인 사전: 불가능한 전체 단어 거부 \(invalid)")
        }
        expect(PersonalDictionary.normalizedForceEntry(" A7R ") ?? "", "a7r", "개인 사전: 숫자 이름 정규화")
        expect(PersonalDictionary.normalizedBlockEntry("ㅁ24") ?? "", "ㅁ24", "개인 사전: 숫자 한글형 금지")
        expect(PersonalDictionary.normalizedBlockEntry("애ㅜ’ㅅ") ?? "", "애ㅜ'ㅅ", "개인 사전: 한글형 곱은 아포스트로피 정규화")
        for word in ["don't", "don’t", "a16z", "a7R", "ㅁ24", "한글".decomposedStringWithCanonicalMapping] {
            let found = KoreanComposer.wordBeforeCursor(before: "🎬 " + word + "! ", atDocStart: false)
            expect(found?.word ?? "", word, "수동 토글: 전체 단어 추출 \(word)")
            expect(found?.trailing ?? -1, 2, "수동 토글: UTF-16 뒤 경계 유지 \(word)")
            expect(ManualToggle.manualToggle(word: found?.word ?? "") != nil, true, "수동 토글: 추출 후 실제 변환 \(word)")
        }
        expect(KoreanComposer.wordBeforeCursor(before: "'apple' ", atDocStart: true)?.word ?? "", "apple", "수동 토글: 바깥 따옴표 유지")
        expect(KoreanComposer.resolveToggle(before: "don't ", english: "t", hangul: "ㅅ", atDocStart: true) == nil,
               true, "되돌림: 축약형 끝 조각만 매칭 금지")
        expect(KoreanComposer.resolveToggle(before: "a24 ", english: "a", hangul: "ㅁ", atDocStart: true) == nil,
               true, "되돌림: 숫자 이름 앞 조각만 매칭 금지")
        expect(KoreanComposer.wordBeforeCursor(before: "a16z", atDocStart: false) == nil, true, "수동 토글: 읽기 창 잘린 이름 보호")
        let recentNumeric = RecentReverts().recording(hangul: "ㅁ24", english: "A24")
        expect(recentNumeric.entries.first?.english ?? "", "A24", "최근 되돌림: 숫자 이름 대소문자 보존")
        expect(PersonalDictionary.normalizedBlockEntry(recentNumeric.entries.first?.english ?? "") ?? "", "a24", "최근 되돌림: 금지로 이동 가능")
        for blocked in ["apple2", "메ㅔㅣㄷ2"] {
            expect(typeViaControllerWithPersonalDictionary("apple2", PersonalDictionary(forceList: [], blockList: [blocked])).committedText,
                   "메ㅔㅣㄷ2", "숫자 금지 목록: 부분 영어 변환도 막음 \(blocked)")
        }
        expect(typeViaControllerWithPersonalDictionary("don’t", PersonalDictionary(forceList: [], blockList: ["애ㅜ’ㅅ"])).committedText,
               "애ㅜ’ㅅ", "개인 사전: 곱은 아포스트로피 한글형 금지 적용")

        // ── 2026-10-07 (#82): 단위·수량 — 실제 컨트롤러와 같은 키 분배 ──
        // 검역에서 확인한 실제 한글 충돌은 숫자 뒤에서도 그대로 남긴다.
        let quantityKoreanCollisions = ["dm": "으", "dl": "이", "cl": "치", "wk": "자", "em": "드"]
        // 2026-11-10 오너 결정(#222): 소문자 gb(휴)·tb(슈)는 숫자에 붙여 쓸 때만 단위다. 띄어 쓴 `100 휴`는 한글.
        let spacedKoreanCollisions = ["gb": "휴", "tb": "슈"]
        for unit in MeasurementUnits.symbols.sorted() {
            let raw = typeViaController(unit, autoEnglish: false).committedText
            for (amount, separator) in [("100", ""), ("100", " "), ("1.25", "")] {
                let expected = quantityKoreanCollisions[unit] ?? (separator == " " ? spacedKoreanCollisions[unit] : nil) ?? unit
                expect(typeViaController(amount + separator + unit).committedText, amount + separator + expected,
                       "단위 전수 수량: \(amount)\(separator)\(unit)")
            }
            expect(typeViaController("100" + unit, autoEnglish: false).committedText, "100" + raw,
                   "단위 전수 OFF: \(unit)")
            expect(typeViaControllerWithPersonalDictionary("100" + unit, PersonalDictionary(forceList: [], blockList: [unit])).committedText,
                   "100" + raw, "단위 전수 개인 금지: \(unit)")
        }
        for unit in ["oz", "km", "cm", "kg", "mg", "lb", "ft", "yd", "Hz", "kHz", "MHz",
                     "fps", "rpm", "mol", "kPa", "kcal", "mAh", "Mbps", "dpi", "px", "mp", "MP", "Mp"] {
            expect(typeViaController(unit).committedText, unit, "단위 단독: \(unit)")
        }
        for value in ["12oz", "100ml", "100mL", "35mm", "2cm", "5km", "24fps", "48kHz",
                      "100Mbps", "10GB", "10dB", "10dL", "5mW", "5MW", "800ml", "8000ml",
                      "100 ml", "35 mm", "10 GB", "10 dB", "10 dL", "0.5ml", "1.25 kg",
                      "-12.5km", "+5mL", "(100ml)", "100cc", "5qt",
                      "12mp", "12MP", "12Mp", "12 mp", "12 MP", "12.5mp", "12.5MP"] {
            expect(typeViaController(value).committedText, value, "숫자+단위: \(value)")
        }
        // 2026-11-01 (#106): 오너 결정으로 단독 ml/mL(ㅢ)은 변환한다. 숫자 뒤가 아닌
        // 경계(두 칸 공백·줄바꿈·쉼표·`1.`) 뒤의 ml도 단독 ml과 같이 변환된다.
        // 2026-11-08 오너 결정(#194): nm은 숫자가 붙을 때만 바꾼다. 단독 ㅜㅡ와 얼굴 ㅜㅡㅜ는 그대로다.
        for value in ["10nm", "10 nm", "1.5nm", "1.5 nm"] {
            expect(typeViaController(value).committedText, value, "#194 숫자 뒤 nm: \(value)")
        }
        expect(type("nm").committedText, "ㅜㅡ", "#194 단독 nm은 ㅜㅡ 그대로")
        expect(typeViaController("nm ").committedText, "ㅜㅡ ", "#194 단독 nm Space")
        expect(typeWords(["apple", "nm"]).last ?? "", "ㅜㅡ", "#194 영어 뒤 nm도 그대로")
        expect(type("nmn").committedText, "ㅜㅡㅜ", "#194 얼굴 ㅜㅡㅜ 그대로")
        expect(type("um").committedText, "um", "#194 같은 단위 경로의 um은 그대로 변환")
        for value in ["ml", "mL", "100  ml", "100\nml", "100,ml", "1.ml"] {
            expect(typeViaController(value).committedText, value, "단위: 단독 ml 변환 (#106) \(value)")
        }
        for (keys, expected) in [("mm", "ㅡㅡ"), ("cc", "ㅊㅊ"),
                                 ("qt", "ㅂㅅ"), ("dl", "이"), ("cl", "치"), ("wk", "자"),
                                 ("100dl", "100이"), ("100 dl", "100 이"), ("3cl", "3치"),
                                 ("10wk", "10자"), ("5ro", "5개"), ("3aud", "3명"),
                                 ("2flxj", "2리터"), ("3dnjs", "3원"), ("10rue", "10겯"),
                                 ("100mlx", "100ㅢㅌ"), ("100mLx", "100ㅢㅌ"),
                                 ("100ml dl", "100ml 이"), ("100 ml dl", "100 ml 이")] {
            expect(typeViaController(keys).committedText, expected, "단위: 한글·경계 보호 \(keys)")
        }
        for value in ["100ml", "100 ml", "1.5ml", "800ml", "35mm", "10GB", "10dB", "12mp", "12MP"] {
            let raw = typeViaController(value, autoEnglish: false).committedText
            let client = FakeClient(), composer = KoreanComposer()
            for ch in value { typeKeyViaController(ch, composer: composer, client: client) }
            let beforeCommit = client.committedText + client.marked
            composer.commit(to: client, convertEnglish: false)
            expect(client.committedText, beforeCommit, "단위: 포커스 이동은 표시 그대로 \(value)")
            expect(composer.lastConversion == nil, true, "단위: passive 되돌림 없음 \(value)")
            expect(raw != value, true, "단위: 자동 변환 OFF \(value)")
        }
        for blocked in ["ml", "ㅢ", "100ml", "100ㅢ"] {
            expect(typeViaControllerWithPersonalDictionary("100ml", PersonalDictionary(block: [blocked])).committedText,
                   "100ㅢ", "단위: 금지 항목 \(blocked)")
        }
        expect(typeViaControllerWithPersonalDictionary("100 ml", PersonalDictionary(block: ["ml"])).committedText,
               "100 ㅢ", "단위: 띄어쓴 단위 금지")
        for blocked in ["mp", "ㅡㅔ", "12mp", "12ㅡㅔ"] {
            expect(typeViaControllerWithPersonalDictionary("12mp", PersonalDictionary(block: [blocked])).committedText,
                   "12ㅡㅔ", "메가픽셀: 약어/전체 항목 금지 \(blocked)")
        }
        expect(typeViaController("12mp dl").committedText, "12mp 이", "메가픽셀 뒤 한국어 문맥 보호")
        expect(typeViaControllerWithPersonalDictionary("100ml", PersonalDictionary(force: ["100ml"], block: ["ml"])).committedText,
               "100ㅢ", "단위: 전체 강제보다 단위 금지 우선")
        for blocked in ["1.5ml", "1.5ㅢ"] {
            let dictionary = PersonalDictionary(forceList: [], blockList: [blocked])
            expect(dictionary.block.contains(blocked), true, "소수 단위 금지 등록: \(blocked)")
            expect(typeViaControllerWithPersonalDictionary("1.5ml", dictionary).committedText,
                   "1.5ㅢ", "소수 단위 금지 적용: \(blocked)")
        }
        expect(typeViaControllerWithPersonalDictionary("1.5foo", PersonalDictionary(forceList: ["1.5foo"], blockList: [])).committedText,
               "1.5foo", "개인 사전: 명시한 소수 수량 전체 추가")
        for invalid in ["a.b", "1.ml", ".5ml", "1.2.3ml", "1.2", "1.2a3"] {
            expect(PersonalDictionary.normalizedForceEntry(invalid) == nil, true, "개인 사전: 수량 아닌 점 보호 \(invalid)")
        }
        for value in ["100ml", "1.25ml", "800ml", "10GB", "12mp", "12MP"] {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in value { typeKeyViaController(ch, composer: composer, client: client) }
            let raw = client.committedText + client.marked     // 2026-11-04: 숫자는 먼저 앱에 — 원문 쌍은 화면 단어 전체
            composer.commit(to: client, convertEnglish: true)
            expect(composer.lastEnglishWord == nil, true, "단위: 다음 한글 문맥 보호 \(value)")
            expect(composer.lastConversion?.hangul ?? "", raw, "단위: 전체 원문 저장 \(value)")
            expect(KoreanComposer.resolveToggle(before: value + " ", english: value, hangul: raw,
                                                 atDocStart: true)?.text ?? "", raw, "단위: 전체 수량 되돌림 \(value)")
        }
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "100 ml " { typeKeyViaController(ch, composer: composer, client: client) }
            composer.applyToggle(toEnglish: false, hangul: "ㅢ", english: "ml")
            composer.applyToggle(toEnglish: true, hangul: "ㅢ", english: "ml")
            expect(composer.lastEnglishWord == nil, true, "단위: 띄어쓴 수량 재토글도 영어 문맥 차단")
        }
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "100 " { typeKeyViaController(ch, composer: composer, client: client) }
            composer.resetEnglishContext() // 앱·입력칸·커서 이동
            // 2026-11-01 (#106): ml은 이제 단독으로도 변환되므로, 숫자 문맥에서만
            // 변환되는 mm(ㅡㅡ)으로 "문맥 폐기"를 확인한다.
            for ch in "mm" { typeKeyViaController(ch, composer: composer, client: client) }
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "100 ㅡㅡ", "단위: 숫자 문맥 이동 시 폐기")
        }
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "12.5ml" { typeKeyViaController(ch, composer: composer, client: client) }
            // 2026-11-04: 12.5는 이미 앱에 있다 — 앞 두 번은 조합기가 자모를, 뒤 두 번은 앱이 5와 소수점을 지운다.
            for i in 0..<4 { expect(deleteKeyViaController(composer: composer, client: client), i < 2, "단위: 자모/소수점 삭제") }
            expect(client.committedText + client.marked, "12", "단위: 소수점까지 지운 숫자")
            for ch in "oz" { typeKeyViaController(ch, composer: composer, client: client) }
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "12oz", "단위: 삭제 후 다른 단위")
        }
        // 2026-11-04 오너 신고: CLI에서 숫자를 눌러도 안 먹었다(1. Yes / 2. No) — 첫머리 숫자를 조합 중 글자로 붙잡아서.
        // 이제 조합이 없을 때 숫자는 바로 앱에 들어가고(붙잡지 않음), 수량·이름 변환은 경계에서 예전과 같은 결과를 낸다.
        do {
            let client = FakeClient(), composer = KoreanComposer()
            expect(composer.handleDigit("1", client: client), false, "CLI: 첫머리 숫자는 붙잡지 않음")
            for digit in "1234567890" {
                let c = FakeClient(), k = KoreanComposer()
                typeKeyViaController(digit, composer: k, client: c)
                expect(c.committedText + "|" + c.marked, String(digit) + "|", "CLI: 숫자 하나가 바로 들어감 \(digit)")
            }
            for (keys, expected) in [("10kg", "10kg"), ("1.5kg", "1.5kg"), ("10 kg", "10 kg"), ("35mm", "35mm"),
                                     ("12 ", "12 "), ("2026.11.4", "2026.11.4"), ("123", "123")] {
                let c = FakeClient(), k = KoreanComposer()
                for ch in keys { typeKeyViaController(ch, composer: k, client: c) }
                k.commit(to: c, convertEnglish: true)
                expect(c.committedText, expected, "CLI 숫자 즉시 + 수량 유지: \(keys)")
            }
            let c = FakeClient(), k = KoreanComposer()
            for ch in "10" { typeKeyViaController(ch, composer: k, client: c) }
            expect(c.committedText + "|" + c.marked, "10|", "CLI: 10은 경계 전에 이미 앱에")
            for ch in "kg" { typeKeyViaController(ch, composer: k, client: c) }
            expect(c.committedText + "|" + c.marked, "10|ㅏㅎ", "숫자 뒤 단위는 조합 중")
        }
        // 2026-11-04 Fable 리뷰(58ca392) 재현 테스트 — 숫자를 먼저 보내는 방식의 구멍.
        // F1: 숫자로 시작해 글자 뒤에 숫자가 또 오는 개인 사전 항목(force·block)이 예전처럼 통째로 판정돼야 한다.
        expect(typeViaControllerWithPersonalDictionary("10a2", PersonalDictionary(force: ["10a2"])).committedText,
               "10a2", "리뷰 F1: 숫자+글자+숫자 개인 추가 통째 변환")
        expect(typeViaControllerWithPersonalDictionary("1a1", PersonalDictionary(force: ["1a1"])).committedText,
               "1a1", "리뷰 F1: 1a1 개인 추가")
        for block in ["3d2", "3ㅇ2"] {
            expect(typeViaControllerWithPersonalDictionary("3d2", PersonalDictionary(block: [block])).committedText,
                   "3ㅇ2", "리뷰 F1: 숫자+글자+숫자 금지는 한글 유지 \(block)")
        }
        // F6: 사전 없이도 예전과 같은 결과(두 번째 숫자에서 반쪽만 단위로 바뀌지 않는다).
        expect(typeViaController("3d2").committedText, "3ㅇ2", "리뷰 F6: 3d2 반쪽 변환 없음")
        expect(typeViaController("10h30m").committedText, "10ㅗ30ㅡ", "리뷰 F6: 10h30m 반쪽 변환 없음")
        // F5: 숫자 뒤 영어 단어(10apple)도 Shift+Space 되돌림 쌍이 화면 단어 전체여야 되돌릴 수 있다.
        do {
            let client = FakeClient(), composer = KoreanComposer()
            for ch in "10apple" { typeKeyViaController(ch, composer: composer, client: client) }
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "10apple", "리뷰 F5: 10apple 변환")
            let pair = composer.lastConversion
            expect((pair?.hangul ?? "") + "|" + (pair?.english ?? ""), "10메ㅔㅣㄷ|10apple", "리뷰 F5: 되돌림 쌍은 화면 단어 전체")
            expect(KoreanComposer.resolveToggle(before: "10apple ", english: pair?.english ?? "", hangul: pair?.hangul ?? "",
                                                atDocStart: true)?.text ?? "", "10메ㅔㅣㄷ", "리뷰 F5: 10apple 되돌리기")
        }
        let longQuantity = String(repeating: "1", count: 95)
        expect(typeViaController(longQuantity).committedText, longQuantity, "단위: 긴 숫자 유실 없음")
        expect(typeViaController("123.456.789").committedText, "123.456.789", "단위: 여러 점 숫자 유실 없음")

        runEnglishParticleTests()
        runPhoneticTests()
        runMenuBarIconTests()
        runAppBundleWatchTests()
        runLoginItemTests()
        runSortedWordTableTests()
        runInputCoreReviewTests()
        runInputCoreReview1112Tests()
        runReferenceAutomatonFuzzTests()
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

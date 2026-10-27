import Foundation

// 실사전 + 실제 조합기/활성 경계/되돌리기 순수 경로. OS IMK 검사는 수동 검사표에 따로 둔다.
func runEnglishParticleTests() {
    func raw(_ english: String, _ particle: String) -> String {
        english + ManualToggle.hangulToKeys(particle)!
    }
    func hangul(_ keys: String) -> String { ManualToggle.keysToHangul(keys)! }

    for (english, particle) in [("github", "에"), ("google", "에서"), ("apple", "를"),
        ("API", "는"), ("UI", "로"), ("PC", "에서도"), ("render", "까지"),
        ("DaVinci", "보다"), ("iPhone", "으로"), ("hello", "와"), ("github", "에서부터"),
        ("github", "에서부터는요"), ("API", "에게는"), ("UI", "랑은"),
        ("render", "까지는"), ("google", "에겐"), ("github", "조차"), ("PC", "로부터")] {
        let keys = raw(english, particle)
        let expected = english + particle
        expect(type(keys).committedText, expected, "조사: \(english)+\(particle)")
    }
    for particle in EnglishParticleSplitter.particles.sorted() {
        expect(type(raw("github", particle)).committedText, "github" + particle, "조사 목록: \(particle)")
        let live = KoreanComposer(); let sink = FakeClient()
        for key in raw("github", particle) { _ = live.handleInput(String(key), client: sink) }
        expect(sink.marked, "github" + particle, "전체 조사 미리보기: \(particle)")
    }

    // Shift를 늦게 놓아도 두벌식 자모가 같으면 조사 판정은 같아야 한다.
    for (typed, expected) in [("githubDp", "github에"), ("APISMS", "API는"),
                              ("APIsMs", "API는"), ("APIDMF", "API을"),
                              ("GitHubDmf", "GitHub을"), ("githubRptJ", "github께서")] {
        expect(type(typed).committedText, expected, "조사 Shift 동등 입력: \(typed)")
    }
    let noEffectShift = Set("asdfghjklzxcvbnmyui")
    for particle in EnglishParticleSplitter.particles.sorted() {
        let suffix = ManualToggle.hangulToKeys(particle)!
        let shifted = String(suffix.map { key in
            noEffectShift.contains(key) ? Character(String(key).uppercased()) : key
        })
        expect(type("github" + shifted).committedText, "github" + particle,
               "조사 Shift 동등 결합: \(particle)")
    }
    for typed in ["githubDP", "githubRk", "githubQhek", "githubWl", "githubEh", "githubdpTj"] {
        expect(type(typed).committedText, hangul(typed), "실제 자모를 바꾸는 Shift 보존: \(typed)")
    }
    for blocked in ["api", hangul("API")] {
        for typed in ["APIsms", "APISMS", "APIsMs", "APIDMF"] {
            let result = typeWithPersonalDictionary(typed, PersonalDictionary(block: [blocked]))
            expect(result.client.committedText, hangul(typed), "Shift 조사도 접두어 금지 준수")
            expect(result.composer.lastConversion == nil, true, "Shift 금지는 변환 쌍 없음")
        }
    }
    expect(typeWords(["APISMS", "so"]).last ?? "", "내", "Shift 혼합 결과 뒤 한글 문맥")
    expect(typeWords(["APIDMF", "to"]).last ?? "", "새", "Shift 혼합 결과 뒤 짧은 한글 보호")
    let shiftedOriginal = hangul("APISMS")
    let shiftedPair = typeWithPersonalDictionary("APISMS", .empty).composer.lastConversion
    expect(shiftedPair?.hangul ?? "", shiftedOriginal, "Shift 조사 원문 쌍 보존")
    expect(shiftedPair?.english ?? "", "API는", "Shift 조사 혼합 쌍 보존")

    // 한글 표제어+조사는 표제어 사전의 전체 일치만으로 보호할 수 없다. 접두어도 보호한다.
    let korean = ["한글", "한국", "사람", "영상", "편집", "영어", "조사", "키보드", "입력",
                  "학교", "나무", "사과", "책", "내", "새", "재가", "양", "해", "모든", "과외",
                  "값", "삶", "흙", "닭", "씨", "때", "우리", "고양이", "파일", "프로그램"]
    for word in korean {
        for particle in EnglishParticleSplitter.particles.sorted() {
            let text = word + particle
            let keys = ManualToggle.hangulToKeys(text)!
            expect(EnglishParticleSplitter.split(keys: Array(keys), hangul: text,
                                                personalDictionary: .empty) == nil,
                   true, "한글 조사 보호: \(text)")
        }
    }
    for keys in ["sork", "workdptj", "formdptj", "hello", "someone", "anywhere", "apples",
                 "walking", "githubrkxdmsrjs", "githubgkek", "githubzz", "zqxyqdp", "xdp"] {
        expect(EnglishParticleSplitter.split(keys: Array(keys), hangul: hangul(keys),
                                            personalDictionary: .empty) == nil,
               true, "분리 제외: \(keys)")
    }

    let keys = "githubdp"
    let original = hangul(keys)
    expect(type(keys, autoEnglish: false).committedText, original, "조사: 자동 변환 OFF")
    expect(typePassive(keys).committedText, "github에", "조사: 클릭/포커스 확정은 미리보기 그대로")
    let disabled = KoreanComposer()
    disabled.autoEnglishEnabled = AutoConvertPolicy.allowed(globalEnabled: true,
        disabledIDs: ["com.apple.Terminal"], clientBundleID: "com.apple.Terminal")
    let disabledClient = FakeClient()
    for key in keys { _ = disabled.handleInput(String(key), client: disabledClient) }
    expect(disabled.commit(to: disabledClient, convertEnglish: true), original, "조사: 앱별 OFF")

    for blocked in [keys, original, "github", hangul("github")] {
        let dictionary = PersonalDictionary(force: ["github"], block: [blocked])
        expect(typeWithPersonalDictionary(keys, dictionary).client.committedText,
               original, "조사: 전체/접두어 금지 우선 \(blocked)")
    }
    expect(typeWithPersonalDictionary("vismotivedp", PersonalDictionary(force: ["vismotive"])).client.committedText,
           "vismotive에", "조사: 개인 영어 추가")
    expect(typeWithPersonalDictionary("workdptj", PersonalDictionary(force: ["work"])).client.committedText,
           "work에서", "조사: 명시한 개인 접두어는 한글 충돌 예외")
    expect(typeWithPersonalDictionary(keys, PersonalDictionary(force: [keys])).client.committedText,
           keys, "조사: 전체 개인 추가는 전체 영어 의도 유지")
    let ambiguous = "githubdptjeh"
    expect(EnglishParticleSplitter.split(keys: Array(ambiguous), hangul: hangul(ambiguous),
        personalDictionary: PersonalDictionary(force: ["github", "githubdptj"])) == .preserveHangul,
           true, "조사: github+에서도 / githubdptj+도 모호하면 보류")
    for blocked in ["api", hangul("API")] {
        let result = typeWithPersonalDictionary("APIsms", PersonalDictionary(block: [blocked]))
        expect(result.client.committedText, hangul("APIsms"), "조사: 접두어 금지를 전체 굴절형 추정으로 우회하지 않음")
        expect(result.composer.lastConversion == nil, true, "조사: 금지 결과는 변환 기록 안 남김")
    }
    let ambiguousResult = typeWithPersonalDictionary(ambiguous,
        PersonalDictionary(force: ["github", "githubdptj"]))
    expect(ambiguousResult.client.committedText, hangul(ambiguous), "조사: 모호한 분리는 원문 유지")
    expect(ambiguousResult.composer.lastConversion == nil, true, "조사: 모호한 결과는 변환 기록 안 남김")

    // 미리보기는 marked text만 바꾸며, 확정 전 원본 키와 되돌림 상태는 유지한다.
    let composer = KoreanComposer()
    let client = FakeClient()
    for key in keys { _ = composer.handleInput(String(key), client: client) }
    expect(client.marked, "github에", "조사: Space 전 혼합 미리보기")
    expect(client.committedText, "", "조사: Space 전 삽입 안 함")
    typeKeyViaController(" ", composer: composer, client: client)
    expect(client.committedText, "github에 ", "조사: Space 경로")
    expect(client.marked, "", "조사: 확정 뒤 조합 제거")
    expect(composer.lastConversion?.hangul ?? "", original, "조사: 되돌리기 원문 보존")
    expect(composer.lastConversion?.english ?? "", "github에", "조사: 되돌리기 결과 보존")
    expect(composer.shouldRecordAutomaticRevert, true, "조사: 자동 되돌림 기록 대상")
    expect(composer.lastEnglishWord == nil, true, "조사: 한국어 문맥")

    for (before, replacement) in [("github에 ", original), (original + " ", "github에"),
                                   ("github에, ", original)] {
        let toggle = KoreanComposer.resolveToggle(before: before, english: "github에", hangul: original,
                                                 atDocStart: true)
        expect(toggle?.text ?? "", replacement, "조사: Shift+Space 양방향 \(before)")
    }
    composer.applyToggle(toEnglish: false, hangul: original, english: "github에")
    composer.applyToggle(toEnglish: true, hangul: original, english: "github에")
    expect(composer.lastEnglishWord == nil, true, "조사: 재토글 후에도 영어 문맥 없음")
    for key in "so" { _ = composer.handleInput(String(key), client: client) }
    expect(composer.commit(to: client, convertEnglish: true), "내", "조사: 뒤의 내 보호")
    expect(typeWords([keys, "to"]).last ?? "", "새", "조사: 뒤의 새 보호")
    expect(typeWords(["want", keys, "so"]).last ?? "", "내", "조사: 앞 영어 문맥 차단")

    let entry = RecentReverts.Entry(hangul: original, english: "github에")
    expect(entry.blockEntry ?? "", original, "조사: 최근 되돌림 금지 키")
    let roundTrip = RecentReverts(plist: RecentReverts(entries: [entry]).plist)
    expect(roundTrip.entries.first?.blockEntry ?? "", original, "조사: 저장/복원 후 금지 키")
    expect(typeWithPersonalDictionary(keys, PersonalDictionary(block: [entry.blockEntry!])).client.committedText,
           original, "조사: 최근 되돌림 금지 실제 적용")
    expect(RecentReverts.Entry(hangul: "메ㅔㅣㄷ", english: "Apple").blockEntry ?? "", "apple",
           "조사: 기존 영어 되돌림 금지 유지")

    // 서로 다른 원문을 금지할 때는 아직 금지하지 않은 기록을 목록에 남긴다.
    let upper = RecentReverts.Entry(hangul: hangul("APIdp"), english: "API에")
    let lower = RecentReverts.Entry(hangul: hangul("apidp"), english: "api에")
    let recorded = RecentReverts().recording(hangul: upper.hangul, english: upper.english)
        .recording(hangul: lower.hangul, english: lower.english)
    let restored = RecentReverts(plist: recorded.plist)
    expect(restored.entries.count, 2, "혼합 최근 기록 대소문자 두 원문 보존")
    let remaining = restored.removing(blockedBy: upper.blockEntry!)
    expect(remaining.entries.count, 1, "혼합 금지 후 다른 금지키 기록은 유지")
    expect(remaining.entries.first?.english ?? "", "api에", "미금지 변형의 기록 유지")
    let blockedUpper = PersonalDictionary(block: [upper.blockEntry!])
    expect(typeWithPersonalDictionary("APIdp", blockedUpper).client.committedText,
           upper.hangul, "선택한 혼합 원문 금지 적용")
    expect(typeWithPersonalDictionary("apidp", blockedUpper).client.committedText,
           lower.english, "다른 혼합 원문은 기존 변환 유지")

    let sameUpper = RecentReverts.Entry(hangul: hangul("UIdp"), english: "UI에")
    let sameLower = RecentReverts.Entry(hangul: hangul("uidp"), english: "ui에")
    expect(sameUpper.blockEntry == sameLower.blockEntry, true, "동등 Shift 원문은 같은 금지 키")
    let sameRecords = RecentReverts(entries: [sameUpper, sameLower, lower])
    let sameRemoved = sameRecords.removing(blockedBy: sameUpper.blockEntry!)
    expect(sameRemoved.entries == [lower], true, "실제로 같은 금지 키에 걸리는 혼합 기록은 함께 제거")
    expect(sameRecords.removing(blockedBy: "혼합mixed") == sameRecords, true, "잘못된 금지 키는 기록 유지")

    // 표시 중에는 원본 키·문맥·확정 기록을 바꾸지 않는다.
    for (typed, expected) in [("githubdp", "github에"), ("googledptj", "google에서"),
                              ("APISMS", "API는"), ("githubRptJ", "github께서")] {
        let live = KoreanComposer()
        let sink = FakeClient()
        for key in typed { _ = live.handleInput(String(key), client: sink) }
        expect(sink.marked, expected, "라이브 미리보기: \(typed)")
        expect(sink.committedText, "", "미리보기는 문서 확정 없음")
        expect(live.lastConversion == nil, true, "미리보기는 확정 되돌림 쌍 없음")
        expect(live.hasPendingComposition, true, "미리보기는 조합 유지")
        expect(live.togglePendingParticlePreview(client: sink), true, "조합 중 원문 되돌리기")
        expect(sink.marked, hangul(typed), "미리보기 원문은 Shift까지 복원")
        expect(live.togglePendingParticlePreview(client: sink), true, "조합 중 혼합 재표시")
        expect(sink.marked, expected, "조합 중 혼합 왕복")
        expect(live.commit(to: sink), expected, "클릭/입력 소스 전환은 화면 그대로")
        expect(sink.marked, "", "passive 확정 뒤 조합 종료")
        expect(live.pendingParticlePreviewText == nil, true, "확정 뒤 미리보기 상태 초기화")
    }
    let extended = KoreanComposer()
    let extendedSink = FakeClient()
    for key in "githubdp" { _ = extended.handleInput(String(key), client: extendedSink) }
    expect(extendedSink.marked, "github에", "연장 전 완성 조사")
    _ = extended.handleInput("t", client: extendedSink)
    expect(extendedSink.marked, "github엣", "조사 연장 중 영어 접두어 유지")
    _ = extended.handleInput("j", client: extendedSink)
    expect(extendedSink.marked, "github에서", "연장 조사 완성")
    _ = extended.deleteBackward(client: extendedSink)
    expect(extendedSink.marked, "github엣", "삭제 중 영어 접두어 유지")
    _ = extended.deleteBackward(client: extendedSink)
    expect(extendedSink.marked, "github에", "삭제로 짧은 조사 복귀")
    _ = extended.deleteBackward(client: extendedSink)
    expect(extendedSink.marked, hangul("github"), "완성 음절 조사를 모두 지우면 원래 한글 조합")
    _ = extended.handleInput("d", client: extendedSink)
    expect(extendedSink.marked, hangul("githubd"), "미완성 조사부터 새 표시 시작하지 않음")
    _ = extended.handleInput("p", client: extendedSink)
    expect(extendedSink.marked, "github에", "완성 조사에서 미리보기 재개")
    _ = extended.handleInput("z", client: extendedSink)
    expect(extendedSink.marked, hangul("githubdpz"), "조사 연장 밖으로 나가면 후보 해제")

    // 유효한 연장 도중 클릭은 표시를 보존하지만, Space는 완성 조사 정책을 다시 확인한다.
    for active in [false, true] {
        let partial = KoreanComposer(); let sink = FakeClient()
        for key in "githubdpt" { _ = partial.handleInput(String(key), client: sink) }
        expect(sink.marked, "github엣", "미완성 연장 표시")
        let result = partial.commit(to: sink, convertEnglish: active)
        expect(result, active ? hangul("githubdpt") : "github엣", "경계별 미완성 조사 처리")
    }
    let rejected = KoreanComposer(); let rejectedSink = FakeClient()
    for key in "githubdp" { _ = rejected.handleInput(String(key), client: rejectedSink) }
    _ = rejected.togglePendingParticlePreview(client: rejectedSink)
    _ = rejected.handleInput("t", client: rejectedSink)
    _ = rejected.handleInput("j", client: rejectedSink)
    expect(rejectedSink.marked, hangul("githubdptj"), "원문 선택은 같은 단어 연장에도 유지")
    expect(rejected.commit(to: rejectedSink, convertEnglish: true), hangul("githubdptj"), "원문 선택 후 Space 재변환 방지")
    for key in "githubdp" { _ = rejected.handleInput(String(key), client: rejectedSink) }
    expect(rejectedSink.marked, "github에", "다음 단어에는 미리보기 다시 활성화")

    for dictionary in [PersonalDictionary(block: ["github"]),
                       PersonalDictionary(block: [hangul("github")]),
                       PersonalDictionary(block: ["githubdp"]),
                       PersonalDictionary(block: [hangul("githubdp")]),
                       PersonalDictionary(force: ["githubdp"])] {
        let live = KoreanComposer(); live.personalDictionary = dictionary
        let sink = FakeClient()
        for key in "githubdp" { _ = live.handleInput(String(key), client: sink) }
        expect(sink.marked, hangul("githubdp"), "전체 지정/금지와 접두어 금지는 미리보기보다 우선")
    }
    let changedSettings = KoreanComposer(); let changedSink = FakeClient()
    for key in "githubdp" { _ = changedSettings.handleInput(String(key), client: changedSink) }
    changedSettings.autoEnglishEnabled = false
    _ = changedSettings.handleInput("t", client: changedSink)
    expect(changedSink.marked, hangul("githubdpt"), "입력 도중 OFF는 다음 키부터 원문")
    changedSettings.autoEnglishEnabled = true
    _ = changedSettings.handleInput("j", client: changedSink)
    expect(changedSink.marked, "github에서", "입력 도중 ON 복귀")
    changedSettings.personalDictionary = PersonalDictionary(block: ["github"])
    _ = changedSettings.deleteBackward(client: changedSink)
    let rawAfterDeletion = KoreanComposer(); rawAfterDeletion.autoEnglishEnabled = false
    let rawAfterDeletionSink = FakeClient()
    for key in "githubdptj" { _ = rawAfterDeletion.handleInput(String(key), client: rawAfterDeletionSink) }
    _ = rawAfterDeletion.deleteBackward(client: rawAfterDeletionSink)
    expect(changedSink.marked, rawAfterDeletionSink.marked, "입력 도중 금지 변경은 삭제에도 반영")
    let emptied = KoreanComposer(); let emptiedSink = FakeClient()
    for key in "githubdp" { _ = emptied.handleInput(String(key), client: emptiedSink) }
    _ = emptied.togglePendingParticlePreview(client: emptiedSink)
    var deletes = 0
    while emptied.hasPendingComposition && deletes < 30 {
        _ = emptied.deleteBackward(client: emptiedSink); deletes += 1
    }
    expect(emptied.hasPendingComposition, false, "원문 표시 후 전체 삭제")
    expect(emptiedSink.marked, "", "전체 삭제 뒤 표시도 비움")
    for key in "githubdp" { _ = emptied.handleInput(String(key), client: emptiedSink) }
    expect(emptiedSink.marked, "github에", "전체 삭제 뒤 새 단어 억제 상태 누출 방지")
    expect(emptied.commit(to: emptiedSink, convertEnglish: true), "github에", "전체 삭제 뒤 새 단어 확정")

    let blockedPartial = KoreanComposer(); let blockedPartialSink = FakeClient()
    for key in "githubdp" { _ = blockedPartial.handleInput(String(key), client: blockedPartialSink) }
    blockedPartial.personalDictionary = PersonalDictionary(force: ["githubdpt"])
    _ = blockedPartial.handleInput("t", client: blockedPartialSink)
    expect(blockedPartialSink.marked, hangul("githubdpt"), "연장 후보도 전체 개인 지정 우선")

    let deleted = KoreanComposer()
    let edited = FakeClient()
    for key in "githubd" { _ = deleted.handleInput(String(key), client: edited) }
    expect(deleted.deleteBackward(client: edited), true, "조사: 뒷부분 삭제")
    for key in "fmf" { _ = deleted.handleInput(String(key), client: edited) }
    expect(deleted.commit(to: edited, convertEnglish: true), "github를", "조사: 삭제 후 다른 조사")
    expect(typeViaController("githubdp, googlefmf.").committedText, "github에, google를.",
           "조사: 기존 문장부호 경계")

    // 2026-10-20 빌드90: 닫는 작은따옴표가 혼합 표시를 축약형 원문으로 바꾸면 안 된다.
    // 실제 컨트롤러처럼 handleApostrophe → 활성 경계 순서로 입력한다.
    for (typed, mixed) in [("githubfh", "github로"), ("githubdptj", "github에서"), ("APISMS", "API는")] {
        for quote: Character in ["'", "’"] {
            for toggles in 0...2 {
                let live = KoreanComposer(); let sink = FakeClient()
                typeKeyViaController("'", composer: live, client: sink)
                for key in typed { typeKeyViaController(key, composer: live, client: sink) }
                expect(sink.marked, mixed, "따옴표 전 조사 미리보기: \(typed)")
                for _ in 0..<toggles {
                    expect(live.togglePendingParticlePreview(client: sink), true, "따옴표 전 미리보기 수동 왕복")
                }
                let displayed = toggles == 1 ? hangul(typed) : mixed
                expect(sink.marked, displayed, "따옴표 전 사용자 표시 선택 보존")
                typeKeyViaController(quote, composer: live, client: sink)
                expect(sink.committedText, "'" + displayed + String(quote), "닫는 작은따옴표로 조사 표시 확정")
                expect(sink.marked, "", "닫는 작은따옴표 뒤 미확정 조합 없음")
                expect(live.hasPendingComposition, false, "작은따옴표는 조사 뒤 활성 경계")
                expect(live.lastEnglishWord == nil, true, "닫는 작은따옴표 뒤 영어 문맥 없음")
                for key in " so" { typeKeyViaController(key, composer: live, client: sink) }
                _ = live.commit(to: sink, convertEnglish: true)
                expect(sink.committedText, "'" + displayed + String(quote) + " 내",
                       "닫는 작은따옴표 뒤 정상 한글 보호")
            }
        }
    }
    for quote in ["'", "’"] {
        expect(typeViaController("'githubfh" + quote, autoEnglish: false).committedText,
               "'" + hangul("githubfh") + quote, "조사 따옴표도 자동 변환 OFF 보존")
    }
    let long = String(repeating: "githubdp", count: 20)
    expect(type(long).committedText, hangul(long), "조사: 긴 입력 spill 뒤 부분 변환 없음")
}

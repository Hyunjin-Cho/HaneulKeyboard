import Foundation

// 2026-11-07 (#177): 메인 앱 화면 쪽 판단·자원 검사. 화면(AppKit·SwiftUI)은 띄우지 않는다.
//   scripts/run_onboarding_tests.sh  (저장소 루트에서 실행 — 자원 경로는 현재 폴더 기준)
// 컴파일: Shared/HaneulDefaultsKeys.swift · Sources/AppUIDecisions.swift · Sources/OnboardingScrollData.swift

var failures = 0
var passes = 0

func expect(_ condition: Bool, _ label: String) {
    if condition { passes += 1 } else { failures += 1; print("FAIL \(label)") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected { passes += 1 } else { failures += 1; print("FAIL \(label): expected \(expected), got \(actual)") }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func readSource(_ path: String) -> String? {
    try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

// MARK: - 안내 1페이지 설치 칸 강조 (#187)

func runOnboardingInstallPanelTests() {
    typealias P = OnboardingInstallPanel
    expectEqual(P.resolve(statusKnown: false, busy: false, installed: false, refreshNeeded: false), .checking, "읽기 전에는 빨갛게 하지 않는다")
    expectEqual(P.resolve(statusKnown: true, busy: true, installed: false, refreshNeeded: false), .checking, "설치 중에는 빨갛게 하지 않는다")
    expectEqual(P.resolve(statusKnown: true, busy: false, installed: false, refreshNeeded: false), .actionNeeded, "읽었고 없음 = 강조")
    expectEqual(P.resolve(statusKnown: true, busy: false, installed: true, refreshNeeded: true), .actionNeeded, "입력기가 낡음 = 강조")
    expectEqual(P.resolve(statusKnown: false, busy: false, installed: true, refreshNeeded: true), .checking, "낡음도 읽기 전에는 강조하지 않는다")
    expectEqual(P.resolve(statusKnown: true, busy: false, installed: true, refreshNeeded: false), .ready, "설치 완료")
    expectEqual(P.resolve(statusKnown: true, busy: true, installed: true, refreshNeeded: false), .checking, "업데이트 교체 중 = 확인 중")
}

// MARK: - 후원 주소 (#20) — 주소가 틀리면 돈이 잘못 간다

func runSupportLinkTests() {
    expectEqual(SupportLink.sponsors.absoluteString, "https://github.com/sponsors/Hyunjin-Cho", "오너가 대조한 후원 주소")
    expect(readSource(".github/FUNDING.yml")?.contains("github: \(SupportLink.account)") == true, "FUNDING.yml이 앱과 같은 계정")
    expect(readSource("PRIVACY.md")?.contains(SupportLink.sponsors.absoluteString) == true, "개인정보 문서가 앱과 같은 주소")
    expect(readSource("README.md")?.contains(SupportLink.sponsors.absoluteString) == true, "README가 앱과 같은 주소")
    // 2026-11-08 (#20): 응원 창 A안 — 후원처 목록. 첫 줄은 GitHub Sponsors이고 주소가 정본과 같다.
    expectEqual(SupportLink.channels.first?.url, SupportLink.sponsors, "후원처 목록 첫 줄 = GitHub Sponsors")
    expect(Set(SupportLink.channels.map(\.id)).count == SupportLink.channels.count, "후원처 id가 겹치지 않는다")
    expect(SupportLink.channels.count <= 3, "응원 창에는 후원처가 3곳까지 들어간다")
}

// MARK: - 입력기 상태 표시 (리뷰 app-ui-F-1)

func runIMEStatusTests() {
    typealias P = IMEStatusPresentation
    // 읽기 전: 캐시된 false를 "미설치"로 말하지 않는다.
    expectEqual(P.resolve(statusKnown: false, busy: false, installed: false, disabled: false), .checking, "읽기 전 = 확인 중")
    // 로그인 직후 입력기 준비 중(ensureIMEActive): 설치된 입력기를 "미설치"라고 하지 않는다.
    expectEqual(P.resolve(statusKnown: true, busy: true, installed: false, disabled: false), .checking, "작업 중 = 확인 중(미설치 아님)")
    // 작업 중에는 "다시 켜기"도 권하지 않는다(작업권을 잡고 있어 눌러도 busy 오류).
    expectEqual(P.resolve(statusKnown: true, busy: true, installed: false, disabled: true), .checking, "작업 중 = 다시 켜기 아님")
    expectEqual(P.resolve(statusKnown: true, busy: false, installed: false, disabled: false), .notInstalled, "읽었고 없음 = 미설치")
    expectEqual(P.resolve(statusKnown: true, busy: false, installed: false, disabled: true), .disabled, "읽었고 꺼짐 = 다시 켜기")
    // 이미 쓸 수 있는 입력기는 다른 작업(업데이트 등)이 돌아도 안내 칸을 만들지 않는다.
    expectEqual(P.resolve(statusKnown: true, busy: true, installed: true, disabled: false), .ready, "설치됨 + 작업 중 = 정상")
    expectEqual(P.resolve(statusKnown: false, busy: false, installed: true, disabled: false), .ready, "설치됨 = 정상")
    expect(P.ready.menuTitle == nil, "정상이면 메뉴 칸 제목 없음")
    expect(P.checking.menuTitle?.contains("확인") == true, "확인 중 제목에 '확인'")
    expect(P.checking.menuTitle?.contains("미설치") == false, "확인 중 제목에 '미설치' 없음")
    expect(P.notInstalled.menuTitle?.contains("미설치") == true, "미설치 제목")
    expect(P.disabled.menuTitle?.contains("다시 켜기") == true, "꺼짐 제목")
}

// MARK: - 입력 소스 문구 (리뷰 app-ui-F-7)

func runInputSourceTests() {
    typealias D = InputSourceDescription
    let haneul = "com.hyunjincho.inputmethod.haneul.korean"
    let cases: [(String?, String?, D)] = [
        (haneul, "하늘키보드", .haneul),
        ("com.apple.inputmethod.Korean.2SetKorean", "두벌식", .otherKorean(name: "두벌식")),
        ("com.apple.inputmethod.Korean.HNCRomaja", nil, .otherKorean(name: nil)),
        ("com.apple.keylayout.ABC", "ABC", .other(name: "ABC")),
        ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "히라가나", .other(name: "히라가나")),
        ("com.apple.keylayout.French", "프랑스어", .other(name: "프랑스어")),
        ("com.apple.keylayout.ABC", "  ", .other(name: nil)),
        (nil, nil, .unknown),
    ]
    for (id, name, expected) in cases {
        expectEqual(D.classify(sourceID: id, localizedName: name, haneulID: haneul), expected, "분류 \(id ?? "nil")")
    }
    // 하늘키보드는 이름과 상관없이 ID 정확 일치만 인정한다(접두어만 같은 다른 모드는 하늘키보드가 아니다 — 안내 창의 `selectedHaneul`과 같은 규칙).
    expectEqual(D.classify(sourceID: haneul + ".other", localizedName: nil, haneulID: haneul), .otherKorean(name: nil), "접두어만 같음 = 하늘키보드 아님")
    expectEqual(D.classify(sourceID: "com.hyunjincho.inputmethod.haneul", localizedName: nil, haneulID: haneul), .other(name: nil), "부모 ID만 같음 = 하늘키보드 아님")

    // 한국어 외 입력 소스를 "영어"라고 말하지 않는다. (메뉴·툴팁·VoiceOver 모두)
    for source in [D.other(name: "ABC"), .other(name: "히라가나"), .other(name: nil), .unknown, .otherKorean(name: "두벌식")] {
        for text in [source.menuLine, source.toolTip, source.accessibilityLabel] {
            expect(!text.contains("영어"), "'영어' 단정 없음: \(text)")
        }
    }
    expectEqual(D.haneul.menuLine, "현재 입력 소스: 하늘키보드", "하늘키보드 메뉴 문구")
    expectEqual(D.other(name: "ABC").menuLine, "현재 입력 소스: ABC", "ABC 메뉴 문구(이름 그대로)")
    expectEqual(D.other(name: nil).menuLine, "현재 입력 소스: 다른 입력 소스", "이름을 모를 때 메뉴 문구")
    expect(D.otherKorean(name: "두벌식").menuLine.contains("하늘키보드가 아니에요"), "Apple 두벌식은 하늘키보드가 아니라고 말한다")
    expect(D.otherKorean(name: nil).menuLine.contains("한국어 입력 소스"), "이름 모르는 한국어 소스")
    expectEqual(D.unknown.menuLine, "현재 입력 소스를 확인하지 못했어요", "읽지 못했을 때")
    expectEqual(D.other(name: "ABC").toolTip, "하늘키보드 · 현재 입력 소스: ABC", "툴팁")
    expectEqual(D.other(name: "ABC").accessibilityLabel, "하늘키보드, 현재 입력 소스 ABC", "VoiceOver")
    expectEqual(D.unknown.accessibilityLabel, "하늘키보드, 현재 입력 소스를 확인하지 못했어요", "VoiceOver(알 수 없음)")
}

// MARK: - defaults 키·도메인 (리뷰 app-ui-F-8)

func runDefaultsKeyTests() {
    // 저장 형식이 바뀌면 안 된다 — 사용자 저장소에 이미 쓰인 값이다.
    expectEqual(HaneulDefaultsKey.hasCompletedOnboarding, "haneul.hasCompletedOnboarding", "키: 안내 완료")
    expectEqual(HaneulDefaultsKey.autoEnglishEnabled, "haneul.autoEnglishEnabled", "키: 영타 자동 변환")
    expectEqual(HaneulDefaultsKey.mainAppPath, "haneul.mainAppPath", "키: 메인 앱 경로")
    expectEqual(HaneulDefaultsKey.mainAppFileID, "haneul.mainAppFileID", "키: 메인 앱 파일 번호")

    // 입력기(IMESources)는 아직 같은 문자열을 직접 쓴다. 한쪽만 바뀌면 설정이 입력기에 조용히 반영되지 않으므로 소스 글로 일치를 확인한다.
    // 입력기가 이 상수로 옮겨 가면 `HaneulDefaultsKey.<이름>` 표기도 인정한다.
    let imeUses: [(file: String, key: String, name: String)] = [
        ("IMESources/HaneulInputController.swift", HaneulDefaultsKey.autoEnglishEnabled, "autoEnglishEnabled"),
        ("IMESources/OrphanWatcher.swift", HaneulDefaultsKey.mainAppPath, "mainAppPath"),
        ("IMESources/OrphanWatcher.swift", HaneulDefaultsKey.mainAppFileID, "mainAppFileID"),
    ]
    for use in imeUses {
        guard let text = readSource(use.file) else { expect(false, "입력기 소스 읽기: \(use.file)"); continue }
        expect(text.contains("\"\(use.key)\"") || text.contains("HaneulDefaultsKey.\(use.name)"),
               "입력기(\(use.file))가 같은 키를 쓴다: \(use.key)")
    }
    // 앱 쪽에 같은 문자열이 상수 밖에 다시 퍼지지 않았는지(복제 회귀 방지). 정의 파일 자신은 제외한다.
    let appFiles = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources").path)) ?? []
    var strays: [String] = []
    for file in appFiles where file.hasSuffix(".swift") {
        guard let text = readSource("Sources/" + file) else { continue }
        for literal in ["\"com.hyunjincho.inputmethod.haneul\"", "\"haneul.hasCompletedOnboarding\"",
                        "\"haneul.autoEnglishEnabled\"", "\"haneul.mainAppPath\"", "\"haneul.mainAppFileID\""]
        where text.contains(literal) {
            // 입력기 번들 ID의 정본 정의 한 줄(IMEInstaller.imeBundleID)만 허용한다.
            if file == "IMEInstaller.swift", literal == "\"com.hyunjincho.inputmethod.haneul\"",
               text.components(separatedBy: literal).count == 2 { continue }
            strays.append("\(file): \(literal)")
        }
    }
    expect(strays.isEmpty, "앱 Sources에 흩어진 설정 도메인·키 리터럴 없음 \(strays)")
}

// MARK: - 두루마리 자원 (리뷰 app-ui-F-6)

func runScrollResourceTests() {
    let dir = root.appendingPathComponent("Resources/Onboarding")
    guard let scrollData = try? Data(contentsOf: dir.appendingPathComponent("OnboardingScroll.json")),
          let peopleData = try? Data(contentsOf: dir.appendingPathComponent("OnboardingPeople.json")) else {
        expect(false, "두루마리 JSON 두 개를 읽을 수 있다"); return
    }
    // 제품이 쓰는 같은 구조체로 실제 디코드한다. 키 이름이 바뀌면(haneul-art 재출력) 앱이 녹색·빈 무대로 뜨기 전에 여기서 실패한다.
    guard let scroll = try? JSONDecoder().decode(OnboardingScrollArt.Scroll.self, from: scrollData) else {
        expect(false, "OnboardingScroll.json 디코드"); return
    }
    guard let people = try? JSONDecoder().decode(OnboardingScrollArt.People.self, from: peopleData) else {
        expect(false, "OnboardingPeople.json 디코드"); return
    }
    expect(true, "두 JSON 디코드")
    expectEqual(scroll.stations.count, 7, "정거장 7개(1~7페이지)")
    expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("OnboardingScroll.jpg").path), "두루마리 그림 OnboardingScroll.jpg")

    // 참조 PNG가 모두 있어야 한다 — 제품은 없으면 조용히 nil(그림 없음)이다.
    func png(_ file: String) -> URL {
        dir.appendingPathComponent(OnboardingScrollArt.pngResourceName(file) + ".png")
    }
    var referenced: [String] = scroll.props?.map(\.file) ?? []
    if let roll = scroll.roll { referenced.append(roll.file) }
    referenced += people.sprites.values.map(\.file)
    expect(referenced.count >= 20, "참조 PNG가 충분히 있다(\(referenced.count)개)")
    for file in referenced {
        expect(FileManager.default.fileExists(atPath: png(file).path), "참조 PNG 존재: \(file)")
    }
    // 제품 코드가 만드는 자세 이름도 sprites에 있어야 한다: 사람마다 p1~p6·walkA·walkB, 공중 자세(hops)의 up·down.
    for who in people.order {
        for pose in (1...6).map({ "p\($0)" }) + ["walkA", "walkB"] {
            expect(people.sprites["\(who)_\(pose)"] != nil, "자세 있음: \(who)_\(pose)")
        }
    }
    for at in scroll.people {
        for hop in at.hops ?? [] {
            guard people.order.indices.contains(hop.who) else { expect(false, "hop.who 범위: \(hop.who)"); continue }
            let who = people.order[hop.who]
            for pose in [hop.up, hop.down] {
                expect(people.sprites["\(who)_\(pose)"] != nil, "공중 자세 있음: \(who)_\(pose)")
            }
        }
    }

    // 대조군: 필수 키(stage_pt)를 빼면 실패해야 한다 — 위 검사가 살아 있다는 증거.
    if var object = (try? JSONSerialization.jsonObject(with: scrollData)) as? [String: Any] {
        object.removeValue(forKey: "stage_pt")
        let broken = try? JSONSerialization.data(withJSONObject: object)
        expect((try? JSONDecoder().decode(OnboardingScrollArt.Scroll.self, from: broken ?? Data())) == nil,
               "대조군: stage_pt를 빼면 디코드 실패")
    } else {
        expect(false, "대조군 JSON 준비")
    }
}

@main
struct AppUITests {
    static func main() {
        runOnboardingInstallPanelTests()
        runSupportLinkTests()
        runIMEStatusTests()
        runInputSourceTests()
        runDefaultsKeyTests()
        runScrollResourceTests()
        print("AppUI: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

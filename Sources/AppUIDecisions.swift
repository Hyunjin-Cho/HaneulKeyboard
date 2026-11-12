import Foundation

/// 2026-11-07 (#177): 메인 앱 화면(상태 아이콘 메뉴·설정·안내)이 입력기 상태와 입력 소스를 "어떻게 말할지"의 판단.
/// 화면(AppKit·SwiftUI)에 묶이지 않게 Foundation만 쓴다. `Tests/AppUITests.swift`가 `scripts/run_onboarding_tests.sh`에서 검증한다.

/// 입력기 설치 상태를 화면에 어떻게 보일지. (리뷰 app-ui-F-1)
/// 입력기 상태는 비동기로 읽는다. 아직 읽기 전이거나 설치·활성화·제거가 진행 중일 때 캐시된 `false`를 그대로 보여 주면
/// 이미 설치된 입력기를 "미설치"라고 잘못 말한다 — 그때는 "확인 중"이라고 말한다.
enum IMEStatusPresentation: Equatable {
    /// 읽는 중이거나 작업이 진행 중이다. 설치·다시 켜기를 권하지 않는다.
    case checking
    case ready
    /// 번들은 있는데 시스템 설정에서 입력 소스가 꺼져 있다. (#32)
    case disabled
    case notInstalled

    /// - statusKnown: 입력기 상태를 한 번이라도 실제로 읽었는가.
    /// - busy: 설치·활성화·업데이트 교체·제거 중인가(`AppCore.isPreparingIME`).
    static func resolve(statusKnown: Bool, busy: Bool, installed: Bool, disabled: Bool) -> Self {
        if installed { return .ready }
        if busy || !statusKnown { return .checking }
        return disabled ? .disabled : .notInstalled
    }

    var menuTitle: String? {
        switch self {
        case .ready: nil
        case .checking: "한글 입력기 상태를 확인하고 있어요…"
        case .disabled: "한글 입력기가 꺼져 있음 — 다시 켜기"
        case .notInstalled: "한글 입력기(IME) 미설치 — 설정에서 설치 권장"
        }
    }
}

/// 2026-11-07 오너(#187): 안내 1페이지 설치 칸의 상태. 첫 화면에서 어떻게 설치하는지 모를 수 있어 설치가 필요하면 빨갛게 강조한다.
/// 읽기 전·작업 중에는 강조하지 않는다. 이미 설치된 Mac에서 창을 열 때 잠깐 빨갛게 번쩍이면 고장처럼 보인다.
enum OnboardingInstallPanel: Equatable {
    case checking
    case ready
    case actionNeeded

    /// - refreshNeeded: 입력기가 앱보다 낡아 다시 설치해야 한다(`AppCore.imeRefreshNeeded`).
    static func resolve(statusKnown: Bool, busy: Bool, installed: Bool, refreshNeeded: Bool) -> Self {
        if busy { return .checking }
        if installed && !refreshNeeded { return .ready }
        return statusKnown ? .actionNeeded : .checking
    }
}

/// 2026-11-07 (#20): 후원 주소의 정본. 오너가 대조해 승인했다. `.github/FUNDING.yml`·README·PRIVACY.md와 어긋나면 `Tests/AppUITests.swift`가 실패한다.
enum SupportLink {
    static let account = "Hyunjin-Cho"
    static let sponsors = URL(string: "https://github.com/sponsors/\(account)")!
    static var displayAddress: String { "github.com/sponsors/\(account)" }

    /// 2026-11-08 오너(#20): 응원 창은 후원처 목록(A안)이다. 후원처가 늘면 여기에 한 줄 더한다(창에 3곳까지 들어간다).
    static let channels: [SupportChannel] = [
        SupportChannel(id: "github", name: "GitHub Sponsors", detail: "한 번 또는 매달 · GitHub 계정이 필요해요",
                       url: sponsors, displayAddress: displayAddress),
    ]
}

/// 응원 창 한 줄: 후원처 이름, 방법과 필요한 것 한 줄, 여는 주소.
struct SupportChannel: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let url: URL
    let displayAddress: String
}

/// 지금 쓰는 입력 소스를 사실대로 말하기 위한 분류. (리뷰 app-ui-F-7)
/// 예전엔 입력 소스 ID에 korean·hangul이 있으면 "한국어", 아니면 전부 "영어"라고 했다 — 일본어·중국어·프랑스어 자판도 "영어"가 되고,
/// Apple 두벌식이 "한국어"로 보여 하늘키보드를 고르지 않았다는 사실도 가려졌다. 안내 창은 처음부터 정확한 ID 비교를 쓴다.
enum InputSourceDescription: Equatable {
    /// 하늘키보드(우리 입력기의 한국어 모드)를 쓰는 중.
    case haneul
    /// 한국어 입력 소스지만 하늘키보드가 아니다(예: Apple 두벌식).
    case otherKorean(name: String?)
    /// 한국어가 아닌 입력 소스(ABC·일본어 등).
    case other(name: String?)
    /// 현재 입력 소스를 읽지 못했다.
    case unknown

    /// - sourceID: TIS 입력 소스 ID(`kTISPropertyInputSourceID`).
    /// - localizedName: 시스템이 지역화한 이름(`kTISPropertyLocalizedName`).
    /// - haneulID: 하늘키보드의 입력 모드 ID(`InputSwitcher.koreanModeID`).
    static func classify(sourceID: String?, localizedName: String?, haneulID: String) -> Self {
        guard let sourceID else { return .unknown }
        if sourceID == haneulID { return .haneul }
        let trimmed = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let lower = sourceID.lowercased()
        return lower.contains("korean") || lower.contains("hangul") ? .otherKorean(name: name) : .other(name: name)
    }

    /// 입력 소스 이름 뒤에 조사를 붙이지 않는다(받침에 따라 달라져 이름이 바뀔 때마다 틀린다).
    private var summary: String {
        switch self {
        case .haneul: "하늘키보드"
        case .otherKorean(let name): "\(name ?? "한국어 입력 소스") (하늘키보드가 아니에요)"
        case .other(let name): name ?? "다른 입력 소스"
        case .unknown: ""
        }
    }

    /// 상태 아이콘 메뉴의 한 줄.
    var menuLine: String {
        self == .unknown ? "현재 입력 소스를 확인하지 못했어요" : "현재 입력 소스: \(summary)"
    }

    var toolTip: String { "하늘키보드 · " + menuLine }

    /// VoiceOver는 쉼표로 쉬어 읽는다. 문장부호 ':'는 읽지 않게 뺀다.
    var accessibilityLabel: String {
        self == .unknown ? "하늘키보드, \(menuLine)" : "하늘키보드, 현재 입력 소스 \(summary)"
    }
}

/// 2026-11-13 (#227, 리뷰 app-ui-F-5): 상태 글자색(초록·주황·빨강)의 정본. sRGB 0~1.
/// 설정 화면은 시스템 색(.green·.orange·.red)을 글자에 직접 써서 밝은 화면에서 대비가 2:1 안팎이었다(읽기 기준 4.5:1).
/// 안내 창이 쓰던 진한 색(`FeedbackStatus`)을 설정에도 쓰고, 그 값을 여기 한 곳에 둬 `Tests/AppUITests.swift`가
/// 한지 바탕·흰 바탕·안내 띠 바탕(밝은·어두운)에서 4.5:1 이상인지 계산으로 고정한다. 화면 쪽 `Color`는 `FeedbackStyle.swift`가 만든다.
/// 색 계열(초록·주황·빨강)은 예전 그대로다. 리소 잉크(초록 겹침 #08A866·주황 겹침 #FB6F21)는 한지 바탕에서 2.5~2.8:1이라
/// 글자색으로 쓰지 않는다(Visual Spec의 text_rule도 본문 글자는 선명한 일반 글자로 둔다).
enum FeedbackStatus: CaseIterable {
    case success, pending, warning

    func rgb(dark: Bool) -> StatusRGB {
        switch self {
        // 2026-11-13 (#227): 밝은 화면 초록 (0, 0.502, 0) → (0, 0.43, 0). 하늘색 안내 띠 위에서 4.14:1이었다.
        case .success: dark ? StatusRGB(0.20, 0.85, 0.30) : StatusRGB(0, 0.43, 0)
        // 2026-11-13 (#227): 밝은 화면 주황 (0.69, 0.30, 0.02) → (0.63, 0.27, 0.02). 경고 띠 위에서 4.17:1이었다.
        case .pending: dark ? StatusRGB(1, 0.66, 0.30) : StatusRGB(0.63, 0.27, 0.02)
        case .warning: dark ? StatusRGB(1, 0.56, 0.56) : StatusRGB(0.72, 0.10, 0.14)
        }
    }
}

/// sRGB 색 한 점과 WCAG 2 대비 계산(상대 휘도). 화면을 띄우지 않고 글자색을 검사하려고 쓴다.
struct StatusRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: StatusRGB) -> Double {
        let (a, b) = (relativeLuminance, other.relativeLuminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// 이 색 위에 `top`을 `alpha`만큼 덮은 색(안내 띠처럼 반투명 칠).
    func overlaid(with top: StatusRGB, alpha: Double) -> StatusRGB {
        StatusRGB(red * (1 - alpha) + top.red * alpha, green * (1 - alpha) + top.green * alpha,
                  blue * (1 - alpha) + top.blue * alpha)
    }
}

// MARK: - 설정 메뉴 (2026-11-13 #227: SettingsView.swift에서 옮겼다 — 메뉴·설정 열기 판단을 시험하려고. 값·순서는 그대로다)

/// 2026-10-11 (#88): 일반을 정리한 메뉴. 응원하기는 본문 선택과 별도인 버튼이다.
/// 2026-11-07 오너(#189): 「입력 기능」을 자동 변환과 단축키·슬래시로 나눠 다섯 메뉴가 됐다. 저장 값은 그대로다.
enum SettingsTab: Hashable, CaseIterable, Identifiable {
    case automatic
    case shortcuts
    case personalDictionary
    case update
    case appManagement

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: return "자동 변환"
        case .shortcuts: return "단축키·슬래시"
        case .personalDictionary: return "개인 사전"
        case .update: return "설치·업데이트"
        case .appManagement: return "앱 관리"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .shortcuts: return "command"
        case .personalDictionary: return "character.book.closed"
        case .update: return "arrow.down.circle"
        case .appManagement: return "wrench.and.screwdriver"
        }
    }
}

/// 2026-11-13 (#227, 리뷰 app-ui-F-4): 상태 아이콘 메뉴의 입력기 줄을 눌렀을 때 할 일.
/// 예전엔 미설치 줄이 회색(누를 수 없음)이라, 할 일을 알리는 유일한 줄이 막다른 길이었다.
enum IMEMenuAction: Equatable {
    /// 줄이 없거나(정상·확인 중) 누를 것이 없다.
    case none
    /// 꺼진 입력 소스를 다시 켠다(#32).
    case reenable
    /// 설정의 「설치·업데이트」를 연다.
    case openInstallSettings
}

extension IMEStatusPresentation {
    var menuAction: IMEMenuAction {
        switch self {
        case .ready, .checking: .none
        case .disabled: .reenable
        case .notInstalled: .openInstallSettings
        }
    }
}

/// 2026-11-13 (#227, 리뷰 app-ui-F-4·F-8): 메뉴의 `설정…`·앱 다시 열기·실행 직후에 설정 창을 어느 메뉴로 열지.
/// nil이면 마지막으로 본 메뉴(처음엔 자동 변환)다.
enum SettingsEntryDecision {
    /// - iconVisible: 앱 안 `메뉴바에 아이콘 보기` 값. 꺼 두었으면 다시 켜는 항목이 있는 앱 관리로 간다(#154).
    /// - refreshNeeded: 입력기가 앱보다 낡았다(`AppCore.imeRefreshNeeded`). 해결 안내가 「설치·업데이트」에 있다.
    static func preferredTab(imeStatus: IMEStatusPresentation, refreshNeeded: Bool, iconVisible: Bool) -> SettingsTab? {
        if !iconVisible { return .appManagement }
        // 설치가 필요하면 설치 버튼이 있는 곳으로 바로 간다. 꺼짐은 메뉴의 `다시 켜기`가 맡아 사용자가 고른 메뉴를 그대로 둔다.
        if imeStatus == .notInstalled || refreshNeeded && imeStatus != .checking { return .update }
        return nil
    }

    /// 2026-11-13 (#227, 리뷰 app-ui-F-8): macOS 26은 시스템 설정 → 메뉴 막대에서 아이콘을 숨길 수 있고, 앱은 그 값을 따로 받지 못한다.
    /// 앱 안 토글이 켜져 있어도 아이콘이 실제로 화면에 없으면, 사용자가 직접 실행했을 때 아무 일도 없는 것처럼 보인다.
    /// 로그인 항목으로 뜬 것은 사용자가 연 것이 아니므로 창을 띄우지 않는다(#154).
    /// - iconOnScreen: 상태 항목이 실제로 메뉴 막대에 그려져 있다고 확인됐는가. 확인하지 못하면 false로 넘긴다.
    static func shouldOpenSettingsAfterLaunch(launchedAsLoginItem: Bool, iconPreferenceOn: Bool, iconOnScreen: Bool) -> Bool {
        !launchedAsLoginItem && iconPreferenceOn && !iconOnScreen
    }
}

/// 2026-11-13 (#227, 리뷰 app-ui-F-6): 전체 제거가 도는 동안의 설정 창. 결과 창(시트)이 이 창에 붙고 앱 종료도 거기서 이어진다.
enum RemovalWindowDecision {
    /// 제거 중(또는 다 지우고 종료를 기다리는 중)에는 설정 창을 닫지 않는다 — 닫힌 창에 붙은 결과는 보이지 않는다.
    static func allowsClosingSettings(removingProduct: Bool) -> Bool { !removingProduct }
    /// 결과가 나왔는데 창이 화면에 없으면(닫혔거나 숨음) 다시 앞으로 꺼낸다.
    static func shouldRevealSettings(windowVisible: Bool) -> Bool { !windowVisible }
}

// MARK: - 설치·업데이트 탭 (2026-11-13 #227, 리뷰 app-ui-F-2·F-3·F-10)

/// 「한글 입력기」 구획이 무엇을 보일지. 버튼 이름은 여기 한 곳에서 정해 아래 갱신 안내가 같은 이름을 가리킨다.
struct InputMethodSectionPresentation: Equatable {
    enum Status: Equatable {
        /// 설치되어 있고 쓸 수 있다. 기존 두벌식 빼기 안내가 함께 보인다.
        case installed
        /// 읽는 중이거나 설치·교체·제거가 진행 중이다. 버튼을 보이지 않는다.
        case checking
        /// 번들은 있는데 입력 소스가 꺼져 있다.
        case disabled
        case notInstalled
    }

    static let installButtonTitle = "입력기 설치"
    static let updateButtonTitle = "입력기 업데이트"

    let status: Status
    /// `입력기 설치` 버튼(꺼짐·미설치에서 보인다).
    let showsInstallButton: Bool
    /// `입력기 업데이트` 버튼(사용자 폴더의 낡은 입력기 — 시작할 때 자동 교체가 실패했을 때만).
    let showsUpdateButton: Bool

    static func resolve(statusKnown: Bool, busy: Bool, installed: Bool, disabled: Bool,
                        refreshNeeded: Bool, blockedBySystemInstall: Bool) -> Self {
        let status: Status
        switch IMEStatusPresentation.resolve(statusKnown: statusKnown, busy: busy, installed: installed, disabled: disabled) {
        case .ready: status = .installed
        case .checking: status = .checking
        case .disabled: status = .disabled
        case .notInstalled: status = .notInstalled
        }
        return Self(status: status,
                    showsInstallButton: status == .disabled || status == .notInstalled,
                    showsUpdateButton: status == .installed && refreshNeeded && !blockedBySystemInstall)
    }

    /// 「버전·업데이트」의 `입력기 업데이트 필요` 안내 둘째 줄. 위 구획에 실제로 보이는 버튼만 가리킨다.
    /// 예전엔 입력 소스가 꺼져 `입력기 설치`만 보일 때도 `‘입력기 업데이트’를 눌러 주세요`라고 했다(리뷰 app-ui-F-3).
    /// nil이면 안내 자체를 보이지 않는다.
    func refreshNotice(refreshNeeded: Bool, blockedBySystemInstall: Bool) -> String? {
        guard refreshNeeded else { return nil }
        let first = "앱은 새 버전인데 입력기는 아직 이전 버전이에요."
        if blockedBySystemInstall { return first + "\n앱 관리의 ‘하늘키보드 전체 제거’로 지운 뒤 다시 설치해 주세요." }
        if showsUpdateButton { return first + "\n위 ‘\(Self.updateButtonTitle)’를 눌러 주세요." }
        if showsInstallButton { return first + "\n위 ‘\(Self.installButtonTitle)’를 눌러 주세요." }
        // 확인·작업 중에는 누를 버튼이 없다. 끝나면 다시 판단한다.
        return first
    }
}

/// 업데이트 진행 단계(`Updater.Phase`)를 화면 판단에 넘기는 모양. 새 버전 정보(자산 주소 등)는 판단에 필요 없어 뺐다.
enum UpdatePhaseKind: Equatable {
    case idle, checking, upToDate, available, downloading, verifying, installing, failed
}

/// 「버전·업데이트」 상태 줄과 상태 아이콘 메뉴의 새 버전 줄.
struct UpdateStatusPresentation: Equatable {
    enum Line: Equatable { case none, checking, newVersion, downloading, verifying, installing, failed }

    let line: Line
    /// `새 버전 설치` 버튼.
    let showsInstallButton: Bool
    /// 버튼을 누르면 설치 전에 서버에 다시 물어야 하는가. 앱을 다시 켜면 받을 파일 정보는 없고 저장된 최신 번호만 남는다.
    let installRechecksFirst: Bool
    /// 상태 아이콘 메뉴에 `새 버전 … — 설치·업데이트…` 줄을 둘까.
    let showsMenuNotice: Bool

    /// - storedLatestOrder: 설치된 버전과 저장된 최신 번호의 비교(설치 < 최신 = `.orderedAscending`). 번호가 없거나 못 읽으면 nil.
    /// 2026-11-08 오너(#201): 숫자 두 줄로 알 수 있는 `최신 버전이에요`·`설치된 버전이 더 새로워요`는 보이지 않는다.
    static func resolve(phase: UpdatePhaseKind, storedLatestOrder: ComparisonResult?) -> Self {
        switch phase {
        case .available:
            return Self(line: .newVersion, showsInstallButton: true, installRechecksFirst: false, showsMenuNotice: true)
        case .idle where storedLatestOrder == .orderedAscending:
            // 2026-11-13 (#227, 리뷰 app-ui-F-2): 다시 켠 뒤에도 `새 버전이 있어요`만 남고 설치 버튼·메뉴 줄이 사라졌다.
            // 자동 확인은 매달 1일 기준이라 그 달엔 다시 묻지 않는다. 버튼은 누를 때 다시 물은 뒤 설치한다(네트워크는 누를 때만).
            return Self(line: .newVersion, showsInstallButton: true, installRechecksFirst: true, showsMenuNotice: true)
        case .idle, .upToDate:
            return Self(line: .none, showsInstallButton: false, installRechecksFirst: false, showsMenuNotice: false)
        case .checking: return Self(line: .checking)
        case .downloading: return Self(line: .downloading)
        case .verifying: return Self(line: .verifying)
        case .installing: return Self(line: .installing)
        case .failed: return Self(line: .failed)
        }
    }

    private init(line: Line, showsInstallButton: Bool = false, installRechecksFirst: Bool = false, showsMenuNotice: Bool = false) {
        self.line = line
        self.showsInstallButton = showsInstallButton
        self.installRechecksFirst = installRechecksFirst
        self.showsMenuNotice = showsMenuNotice
    }

    /// 메뉴 줄 글자. `version`은 알림에 온 태그, 없으면 저장된 최신 번호.
    static func menuTitle(version: String) -> String { "새 버전 \(version) — \(SettingsTab.update.title)…" }
}

// MARK: - 안내 1페이지 설치 칸 문장 (2026-11-13 #227, 리뷰 app-ui-F-10: OnboardingView에서 옮겼다. 문장은 그대로다)

extension OnboardingInstallPanel {
    static func statusText(panel: Self, blockedBySystemInstall: Bool, refreshNeeded: Bool, disabled: Bool) -> String {
        switch panel {
        case .checking: return "설치 상태를 확인하고 있어요"
        case .ready: return "설치 완료"
        case .actionNeeded:
            if blockedBySystemInstall { return "이전 버전 입력기를 지우고 다시 설치해 주세요" }
            if refreshNeeded { return "입력기를 새 버전으로 업데이트해 주세요" }
            if disabled { return "설치되어 있어요 · 입력 소스를 다시 켜 주세요" }
            // 2026-11-07 오너(#187): 무엇을 눌러야 하는지 칸 안에서 바로 말한다.
            return "아직 설치되지 않았어요.\n오른쪽 버튼을 눌러 설치해 주세요."
        }
    }
}

// MARK: - 안내 연습 페이지의 꺼진 기능 (2026-11-13 #227, 리뷰 app-ui-F-10: OnboardingView에서 옮겼다)

/// 3~6페이지 연습. 기능이 꺼져 있으면 경고를 보이고 설정으로 보낸다.
enum OnboardingLesson: Equatable {
    case automatic, reversal, registeredWord, slash

    /// 연습할 기능이 꺼져 있는가.
    func isDisabled(autoEnabled: Bool, phoneticEnabled: Bool, slashEnabled: Bool) -> Bool {
        switch self {
        case .automatic, .reversal: !autoEnabled
        case .registeredWord: !phoneticEnabled
        case .slash: !slashEnabled
        }
    }

    /// 경고의 `설정 열기`가 갈 메뉴. 자동 변환이 꺼진 게 먼저다(2026-11-07 #189).
    func settingsTab(autoEnabled: Bool) -> SettingsTab {
        (self == .automatic || self == .reversal) && !autoEnabled ? .automatic : .shortcuts
    }
}

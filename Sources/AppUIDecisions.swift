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

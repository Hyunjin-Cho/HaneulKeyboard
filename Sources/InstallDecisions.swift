import Foundation

/// 앱 이동·전체 제거 흐름의 **판단 부분**만 모아둔 순수 함수·값 타입. (review-0712 P3-8)
///
/// 실제 파일 복사·삭제·admin 프롬프트·TIS 조작은 AppKit/Security/Carbon에 묶여
/// 있어서 CI에서 돌릴 수 없다. 그래서 "어디로 옮길지 / 덮어써도 되는지 /
/// 메인 앱을 지워도 되는지 / 사용자에게 뭐라고 말할지"라는 **결정**만 Foundation
/// 전용으로 떼어냈다. 이 파일은 `scripts/run_ime_tests.sh`가 그대로 컴파일해
/// 검증한다 — 예전엔 이 판단들이 컴파일만 되고 행동 테스트가 없어서, 리뷰가
/// 잡은 P2들(남의 앱 덮어쓰기·삭제 실패 후 복구 수단 상실)이 "213개 통과"
/// 상태로 숨어 있었다.

// MARK: - /Applications 이동

enum AppMoveDecision {
    /// 메인 앱 bundle identifier — 목적지가 "우리 앱"인지 판별하는 기준.
    static let mainAppBundleID = "com.hyunjincho.haneulkeyboard"

    /// /Applications에 놓일 **고정** 파일명. 실행 중인 번들의 파일명을 그대로
    /// 쓰면, 사용자가 받은 앱을 SomeApp.app으로 바꿔 실행했을 때 무관한
    /// /Applications/SomeApp.app을 덮어쓴다. (review-0712 P2-1)
    static let destinationName = "HaneulKeyboard.app"

    static func destinationURL(applicationsDir: String = "/Applications") -> URL {
        URL(fileURLWithPath: applicationsDir, isDirectory: true)
            .appendingPathComponent(destinationName)
    }

    /// 이미 /Applications 안에서 실행 중인가 — 그러면 옮길 필요가 없다.
    static func isAlreadyInPlace(
        bundlePath: String,
        applicationsDir: String = "/Applications"
    ) -> Bool {
        bundlePath.hasPrefix(applicationsDir + "/")
    }

    /// 목적지에 이미 있는 번들을 덮어써도 되는가.
    /// bundle ID가 우리 것이고 **서명 Team까지 같을 때만** true.
    /// 하나라도 어긋나면 남의 앱으로 보고 건드리지 않는다.
    static func canReplaceDestination(
        destinationBundleID: String?,
        isSameTeamSigned: Bool
    ) -> Bool {
        destinationBundleID == mainAppBundleID && isSameTeamSigned
    }
}

// MARK: - 전체 제거

/// 전체 제거 결과. 필수 단계가 모두 확인돼야 종료한다.
struct UninstallOutcome {
    let report: RemovalReport
    var killedProcess: Bool { report.succeeded("process") }
    var removedIMEBundle: Bool { report.succeeded("ime") }
    var removedMainApp: Bool { report.succeeded("main") }
    var keptMainAppForRetry: Bool { !removedMainApp }
    var unregisteredLS: Bool { report.succeeded("registration") }
    var clearedUserDefaults: Bool { report.succeeded("settings") }
    var stillEnabledInPicker: Bool {
        report.steps.contains { if case .needsUserAction = $0.state { return $0.id == "input" || $0.id == "sources" }; return false }
    }
    var fullyRemoved: Bool { report.mode == .wholeProduct && report.complete && removedMainApp }
    var statusText: String {
        report.statusText + (fullyRemoved ? "\n\n필수 정리를 모두 확인했어요. 확인을 누르면 실행 중인 앱도 종료해요." : "\n\n완료되지 않은 항목을 확인한 뒤 이 앱에서 다시 시도해 주세요.")
    }
}

/// 2026-11-06 (#160): 로그인할 때 열기 자동 등록의 판단. 오너 결정 = 기본 켜짐, 원하지 않으면 사용자가 끈다.
/// 자동 등록은 안내를 끝낸 뒤 **한 번만** 한다. 그래야 사용자가 끈 것을 되돌리지 않는다.
/// 실행할 때마다 등록을 부르면 macOS 알림이 매번 뜬다는 보고가 있다(sindresorhus/LaunchAtLogin #100).
/// 응용 프로그램 폴더 밖의 사본(개발 빌드, 받은 그대로의 앱)은 등록하지 않는다.
enum LoginItemDecision {
    static let autoRegisteredKey = "haneul.loginItemAutoRegistered"

    static func shouldAutoRegister(onboardingDone: Bool, alreadyTried: Bool, bundlePath: String) -> Bool {
        onboardingDone && !alreadyTried && AppMoveDecision.isAlreadyInPlace(bundlePath: bundlePath)
    }
}

/// 2026-11-06 (#157): 실행 중인 메인 앱을 휴지통에 넣었을 때 스스로 끝낼지의 판단.
/// 다른 폴더로 옮긴 것은 버린 것이 아니므로 그대로 둔다.
enum AppBundleWatchDecision {
    /// - currentPath: 번들이 지금 있는 곳. 번들이 지워졌으면 nil.
    /// - originalPathExists: 실행할 때의 경로에 무언가 있는가. nil과 함께 true면 새 번들로 교체된 것이다.
    /// - busy: 업데이트 교체 또는 전체 제거 중. 그 작업이 앱 종료까지 맡으므로 끼어들지 않는다.
    static func shouldQuit(currentPath: String?, originalPathExists: Bool, busy: Bool) -> Bool {
        if busy { return false }
        if let currentPath { return OrphanDecision.isInTrash(currentPath) }
        return !originalPathExists
    }
}

/// 2026-11-06 (#154): 메뉴바 아이콘 켜고 끄기의 판단. 기본은 켜짐이다.
/// 아이콘을 끈 동안에도 사용자가 앱을 직접 열면 반드시 창이 보여야 한다(아니면 눌러도 아무 일도 안 일어난 것처럼 보인다).
/// 로그인 항목으로 뜰 때는 사용자가 연 것이 아니므로 창을 띄우지 않는다.
enum MenuBarIconDecision {
    static let defaultsKey = "haneul.showsMenuBarIcon"

    enum LaunchWindow: Equatable { case onboarding, settings, none }

    /// 저장값이 없으면(처음 실행, 전체 제거 뒤) 켜짐이다.
    static func isVisible(storedValue: Any?) -> Bool { storedValue as? Bool ?? true }

    static func launchWindow(onboardingDone: Bool, iconVisible: Bool, launchedAsLoginItem: Bool) -> LaunchWindow {
        if !onboardingDone { return .onboarding }
        if iconVisible || launchedAsLoginItem { return .none }
        return .settings
    }
}

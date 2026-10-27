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

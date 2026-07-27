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

enum UninstallDecision {
    /// 메인 앱(/Applications)을 지워도 되는가.
    ///
    /// IME 번들 삭제가 성공했을 때만 true. 실패했는데도 메인 앱을 지우면
    /// 사용자가 같은 화면에서 "전체 제거"를 다시 누를 수단이 사라진다
    /// (재다운로드 전엔 복구 불가). LaunchServices 등록 해제나 설정 정리
    /// 실패는 앱 없이도 복구되므로 차단 사유가 아니다. (review-0712 P2-2)
    static func shouldRemoveMainApp(removedIMEBundle: Bool) -> Bool {
        removedIMEBundle
    }
}

/// 전체 제거 결과 스냅샷.
struct UninstallOutcome {
    let killedProcess: Bool
    /// IME 번들(시스템/사용자 도메인) 삭제 성공 여부.
    let removedIMEBundle: Bool
    /// 메인 앱(/Applications) 삭제 성공 여부.
    let removedMainApp: Bool
    /// IME 삭제가 실패해 메인 앱을 **일부러 남겼는가**.
    let keptMainAppForRetry: Bool
    let unregisteredLS: Bool
    let clearedUserDefaults: Bool
    /// 사용자가 System Settings에서 입력 소스를 아직 켜둔 상태인가.
    /// 번들을 지운 뒤에도 감지할 수 있다.
    let stillEnabledInPicker: Bool

    /// "완료"라고 말해도 되는가 — 모든 필수 단계가 성공했을 때만.
    /// 예전엔 `stillEnabledInPicker` 하나만 보고, 삭제가 실패해도
    /// "모두 삭제됐습니다"라고 안내했다.
    var fullyRemoved: Bool {
        removedIMEBundle && removedMainApp && unregisteredLS
            && clearedUserDefaults && !stillEnabledInPicker
    }

    /// 사용자에게 보여줄 결과 문구. 단계별 성패를 그대로 적고, 마지막 줄에
    /// 지금 무엇을 해야 하는지를 상황별로 안내한다.
    var statusText: String {
        let tail: String
        if keptMainAppForRetry {
            tail = "IME 번들을 지우지 못해 메인 앱은 남겨뒀어요(암호 창을 취소했거나 권한이 부족했을 수 있어요). 이 앱에서 \"전체 제거\"를 다시 실행해 주세요."
        } else if stillEnabledInPicker {
            tail = "마지막 단계 — 시스템 설정 → 키보드 → 입력 소스에서 \"하늘키보드 (두벌식)\"을 \"-\" 로 제거한 뒤 재부팅하세요."
        } else if fullyRemoved {
            tail = "완료. 메인 앱·IME·설정이 모두 삭제됐습니다. 입력 소스 목록을 완전히 비우려면 재부팅하세요."
        } else {
            tail = "일부 단계가 실패했어요. 위 목록에서 \"실패\" 항목을 확인한 뒤, 남은 파일은 scripts/uninstall.sh로 정리할 수 있어요."
        }
        let mainAppLine = keptMainAppForRetry
            ? "건너뜀(재시도용 보존)"
            : (removedMainApp ? "OK" : "실패")
        return """
        IME 프로세스 종료: \(killedProcess ? "OK" : "—")
        IME 번들 삭제: \(removedIMEBundle ? "OK" : "실패")
        메인 앱 삭제: \(mainAppLine)
        LaunchServices 등록 해제: \(unregisteredLS ? "OK" : "실패")
        사용자 설정 초기화: \(clearedUserDefaults ? "OK" : "실패")

        \(tail)
        """
    }
}

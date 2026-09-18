import Foundation

/// 메인 앱이 사라졌을 때 IME가 **스스로 정리해도 되는지의 판단**만 모은 순수 로직. (#32, 2026-09-19)
///
/// 배경: 메인 앱(메뉴바)을 Finder에서 지워도 IME 번들과 입력 소스가 남아 한글 입력이
/// 계속됐다. 앱을 휴지통에 버리는 순간 실행되는 훅은 없지만, **IME 프로세스 자체가
/// 우리 코드**이고 한글 모드가 활성화될 때마다 실행되므로 거기서 앱 유무를 확인해
/// 스스로 정리할 수 있다. (#29 배경의 "완전 연동은 macOS에서 불가"는 이 점을 놓쳤다.)
///
/// 실제 LaunchServices 조회·파일 삭제·TIS 비활성화는 `OrphanWatcher`(AppKit/Carbon)가
/// 하고, 이 파일은 Foundation 전용이라 `scripts/run_ime_tests.sh`가 그대로 컴파일해
/// 검증한다 — `InstallDecisions.swift`·`resolveToggle`과 같은 분리 패턴.
///
/// 🚨 2026-09-19 리뷰 반영: 처음 안은 "휴지통이면 즉시 정리"였다. 리뷰가 짚은 대로
/// 앱을 휴지통에 버렸다가 "제자리에 놓기"로 되돌리는 건 macOS의 일상적 실수이고,
/// 즉시 정리하면 그 순간 IME·설정이 복구 불가로 사라진다. 그래서 **어떤 관찰도 한 번으로
/// 정리하지 않는다** — 휴지통은 짧은 유예, 부재는 긴 유예를 두고 두 번 확인한다.
enum OrphanDecision {
    /// 한 번의 관찰에서 메인 앱이 어떻게 보였는가.
    enum AppPresence: Equatable {
        /// 휴지통 밖 어딘가에 살아 있다 — 아무것도 하지 않는다.
        case present
        /// 찾은 복사본이 전부 휴지통 안이다 — 사용자가 지웠다는 강한 증거.
        case trashed
        /// 어디에서도 못 찾았다 — 휴지통을 비웠거나, 일시적 상태(앱 교체 중·볼륨 미마운트)일 수 있다.
        case missing
    }

    /// 경로가 휴지통(사용자 `~/.Trash`, 외장 볼륨 `.Trashes`) 안인가.
    /// 경로 구성요소 **정확 일치**로만 판정한다 — `Trash-like` 같은 폴더명에 걸리지 않게.
    static func isInTrash(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return components.contains(".Trash") || components.contains(".Trashes")
    }

    /// 휴지통에서 찾은 번들을 "사용자가 방금 버린 우리 앱"으로 인정해도 되는가.
    /// bundle ID가 우리 것이어야 하고, 메인 앱이 실행 때 기록해 둔 파일 번호(inode)가
    /// 있으면 **그것과 같아야** 한다 — 같은 볼륨 안에서 옮긴 파일은 inode가 그대로라,
    /// 휴지통에 남아 있던 **옛 버전 사본**(다른 inode)에 속아 정리하는 일을 막는다.
    /// (리뷰 H-1: 앱을 다른 폴더로 옮겨 두고 실행하지 않은 사이, 휴지통의 옛 사본만 보고
    /// 정리해 버리는 경로가 있었다.) 기록이 없으면 bundle ID만으로 인정한다.
    static func acceptsTrashedCopy(bundleIDMatches: Bool, recordedFileID: Int?, candidateFileID: Int?) -> Bool {
        guard bundleIDMatches else { return false }
        guard let recorded = recordedFileID else { return true }
        return candidateFileID == recorded
    }

    /// 후보 경로들(LaunchServices가 아는 복사본 + 메인 앱이 기록한 자기 경로 + 그 이름의
    /// 휴지통 사본 + 표준 폴더 스캔)을 하나의 관찰로 요약한다.
    /// `exists`로 지금 디스크에 실재하는 것만 센다 — LaunchServices 캐시는 지워진 앱을
    /// 한동안 계속 알고 있다.
    static func classify(candidatePaths: [String], exists: (String) -> Bool) -> AppPresence {
        let live = candidatePaths.filter(exists)
        if live.contains(where: { !isInTrash($0) }) { return .present }
        if live.contains(where: isInTrash) { return .trashed }
        return .missing
    }

    /// 자기 정리를 실행해도 되는가. **한 번의 관찰로는 절대 정리하지 않는다.**
    /// - `.present`: 아니오. 호출자는 이전 부재 관찰(`previousAbsentAt`)도 무효화해야 한다.
    /// - `.trashed`: 이전 부재 관찰이 있고 그로부터 `trashedInterval` 이상 지났을 때만 —
    ///   휴지통에서 "제자리에 놓기"로 되돌릴 시간을 준다.
    /// - `.missing`: 이전 부재 관찰이 있고 `missingInterval` 이상 지났을 때만 — 앱 교체
    ///   (옛 번들이 휴지통으로 가고 새 번들이 복사되는 몇 초)·외장 볼륨 마운트 전·
    ///   LaunchServices가 아직 모르는 이동 같은 일시적 부재에 반응하지 않기 위해 길게 둔다.
    /// 부재 관찰은 `.trashed`와 `.missing`을 구분하지 않고 이어 센다(버린 뒤 휴지통을 비우면
    /// trashed → missing으로 바뀌는데, 그래도 "계속 없었다"는 사실은 같다).
    static func shouldSelfRemove(
        current: AppPresence,
        previousAbsentAt: Date?,
        now: Date,
        trashedInterval: TimeInterval,
        missingInterval: TimeInterval
    ) -> Bool {
        guard current != .present, let previous = previousAbsentAt else { return false }
        let required = current == .trashed ? trashedInterval : missingInterval
        return now.timeIntervalSince(previous) >= required
    }

    /// 자기 번들을 **삭제**해도 되는가 — 사용자 도메인(`~/Library/Input Methods/`) 설치본만.
    /// 시스템 도메인(`/Library`, root 소유)이나 개발 빌드 경로면 감시 자체를 하지 않는다
    /// (리뷰 M-4: 지우지도 못하면서 입력 소스만 끄고 종료하는 어정쩡한 상태를 만들지 않기 위해).
    /// 접두어 함정(`…/Input Methods2/`)을 피하려고 디렉터리 구분자까지 붙여 비교한다.
    static func mayDeleteBundle(bundlePath: String, userInputMethodsDir: String) -> Bool {
        let bundle = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        let dir = URL(fileURLWithPath: userInputMethodsDir).standardizedFileURL.path
        return bundle.hasPrefix(dir + "/")
    }
}

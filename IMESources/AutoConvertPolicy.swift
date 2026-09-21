import Foundation

/// 영타 자동 변환을 **이 클라이언트 앱에서 해도 되는가**의 판단만 모은 순수 로직. (#54, 2026-09-21)
///
/// 설정의 "앱별 자동 변환 끄기" 목록(bundle ID 배열)을 IME가 active boundary — 변환이 실제로
/// 일어나는 유일한 지점(`HaneulInputController.handle` 끝부분) — 에서 다시 읽어
/// `client.bundleIdentifier()`와 대조한다. 목록은 설정 앱이 실행 중인 앱에서 골라 채운다.
///
/// 이 파일은 IME·설정 앱 양쪽 타겟에 들어가고(저장 키의 단일 진실) `scripts/run_ime_tests.sh`가
/// Foundation만으로 컴파일해 검증한다.
enum AutoConvertPolicy {
    /// IME defaults 도메인(`com.hyunjincho.inputmethod.haneul`)의 키. 값은 bundle ID 문자열 배열.
    /// "전체 제거"의 `haneul.*` 일괄 삭제에 포함된다.
    static let disabledAppsKey = "haneul.disabledAppBundleIDs"

    /// 이번 경계에서 변환해도 되는가.
    /// - 전역 토글(`haneul.autoEnglishEnabled`)이 꺼져 있으면 무조건 false.
    /// - 켜져 있으면 목록에 없는 앱만 true.
    /// - **bundle ID를 못 얻으면(nil·빈 문자열) true** — 목록은 "끄기"용 예외 목록이라, 판정이
    ///   불가능할 때는 기본 동작(변환)으로 돌아가는 게 맞다. 조용히 기능이 꺼지는 쪽이 더 나쁘다.
    /// - 대조는 앞뒤 공백을 떼고 대소문자 무시. LaunchServices가 bundle ID를 대소문자 구분 없이
    ///   다루고, 목록은 실행 중인 앱에서 고른 값이라 표기가 어긋날 이유는 없지만 방어적으로 둔다(가정).
    static func allowed(globalEnabled: Bool, disabledIDs: [String], clientBundleID: String?) -> Bool {
        guard globalEnabled else { return false }
        guard let id = normalized(clientBundleID) else { return true }
        return !disabledIDs.contains { normalized($0)?.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// 목록에 추가 — 공백을 떼고, 이미 있으면(대소문자 무시) 그대로, 순서는 유지. 설정 앱이 쓴다.
    static func adding(_ bundleID: String, to list: [String]) -> [String] {
        guard let id = normalized(bundleID) else { return list }
        if list.contains(where: { normalized($0)?.caseInsensitiveCompare(id) == .orderedSame }) {
            return list
        }
        return list + [id]
    }

    /// 목록에서 제거(대소문자 무시). 없으면 그대로.
    static func removing(_ bundleID: String, from list: [String]) -> [String] {
        guard let id = normalized(bundleID) else { return list }
        return list.filter { normalized($0)?.caseInsensitiveCompare(id) != .orderedSame }
    }

    private static func normalized(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

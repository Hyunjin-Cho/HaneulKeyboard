import ServiceManagement

/// 2026-11-06 (#160): Mac에 로그인할 때 앱을 여는 macOS 등록을 감싼다. 판단은 `LoginItemDecision`이 맡는다.
/// 켜 두어야 재시동 뒤에도 메뉴바 아이콘과 새 버전 알림이 이어진다. 한글 입력은 입력기가 따로 돌아 이것과 무관하다.
/// 2026-11-08 오너(#201): 설정에 따로 토글을 두지 않는다. `메뉴바에 아이콘 보기`를 켜고 끌 때 함께 켜고 끈다.
enum LoginItem {
    enum State: Equatable { case on, needsApproval, off }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

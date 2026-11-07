import SwiftUI

/// 2026-10-10 (#88): 로그인 항목·메뉴바 아이콘·전체 제거를 구획으로 모은다.
/// 2026-11-07 오너(#189): 입력기 설치·제거는 「설치·업데이트」로 옮겼다(`InputMethodSettingsSection`).
/// 전체 제거 확인/결과 창은 SettingsView가 보존한다.
struct AppManagementSettingsTab: View {
    @Bindable var core: AppCore
    @Binding var showingUninstallConfirm: Bool
    /// 2026-11-06 (#154): 메인 앱만 읽는 설정이라 입력기 도메인이 아니라 기본 도메인에 둔다.
    @AppStorage(MenuBarIconDecision.defaultsKey) private var showsMenuBarIcon = true
    /// 2026-11-06 (#160): 시스템 설정에서도 바뀌는 값이라 저장하지 않고 macOS에 물어본다.
    @State private var loginItem = LoginItem.state
    @State private var loginItemError: String?

    private var isBusy: Bool {
        if core.isPreparingIME { return true }
        switch core.updater.phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    var body: some View {
        Form {
            // 2026-11-06 (#154): 아이콘을 꺼도 메뉴에 있던 일을 여기서 할 수 있다. 설정과 응원하기는 왼쪽 메뉴에 있다.
            HaneulSettingsSection("로그인할 때 열기") {
                Toggle("Mac에 로그인할 때 하늘키보드 열기", isOn: Binding(
                    get: { loginItem != .off },
                    set: { setLoginItem($0) }))
                Text("켜 두면 로그인할 때 메뉴바 아이콘이 함께 뜨고 새 버전 알림도 받아요. 꺼도 한글 입력과 영어 자동 변환은 그대로 돼요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                if loginItem == .needsApproval {
                    HStack(spacing: 12) {
                        Label("시스템 설정에서 허용해 주세요.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("로그인 항목 열기") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(SettingsTypography.body)
                        .foregroundStyle(.red)
                }
            }

            HaneulSettingsSection("메뉴바 아이콘") {
                Toggle("메뉴바에 아이콘 보기", isOn: $showsMenuBarIcon)
                    .onChange(of: showsMenuBarIcon) { _, _ in
                        NotificationCenter.default.post(name: .haneulMenuBarIconChanged, object: nil)
                    }
                Text("아이콘을 꺼도 한글 입력과 영어 자동 변환은 그대로 돼요. 설정을 다시 열려면 응용 프로그램 폴더에서 하늘키보드를 열어 주세요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                Text("아이콘을 꺼도 앱은 뒤에서 새 버전 알림을 받아요. ‘메뉴바 앱 종료’는 메뉴바 앱만 꺼요. 한글 입력은 계속 돼요. 로그인할 때 열기가 켜져 있으면 다음 로그인 때 다시 열려요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("시작하기 다시 보기") {
                        NotificationCenter.default.post(name: .haneulOnboardingRequested, object: nil)
                    }
                    Spacer()
                    Button("메뉴바 앱 종료") { NSApp.terminate(nil) }
                        .disabled(isBusy)
                }
            }

            HaneulSettingsSection("하늘키보드 전체 제거") {
                Text("앱·입력기·설정·개인 사전을 모두 지워요. 다시 쓰려면 새로 내려받아 설치해야 해요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("하늘키보드 전체 제거…", role: .destructive) {
                        showingUninstallConfirm = true
                    }
                    .disabled(isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = LoginItem.state
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled: enabled)
            loginItemError = nil
        } catch {
            loginItemError = "바꾸지 못했어요. 시스템 설정 → 일반 → 로그인 항목에서 바꿔 주세요. (\(error.localizedDescription))"
        }
        loginItem = LoginItem.state
    }
}

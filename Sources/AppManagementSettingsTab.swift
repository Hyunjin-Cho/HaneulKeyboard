import SwiftUI

/// 2026-10-10 (#88): 입력기 관리와 전체 제거를 별도 구획으로 모은다.
/// 설치/제거 상태는 AppCore가, 전체 제거 확인/결과 창은 SettingsView가 보존한다.
struct AppManagementSettingsTab: View {
    @Bindable var core: AppCore
    @Binding var showingUninstallConfirm: Bool
    @State private var operationError: String?
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
            HaneulSettingsSection("한글 입력기") {
                if core.imeInstalled {
                    Label("한글 입력기가 설치되어 있습니다.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("시스템 입력 소스에서 기존 \"두벌식\"은 제거하세요.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("자모가 깨지는 것을 막습니다.")
                            .font(SettingsTypography.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(core.imeDisabled
                        ? "시스템 입력 소스에서 하늘키보드가 꺼져 있습니다."
                        : "한글 입력기가 설치되어 있지 않습니다.",
                        systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("하늘키보드 입력기를 ~/Library/Input Methods/에 설치합니다. 설치한 뒤 시스템 설정에서 입력 소스로 추가하세요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                    Button("입력기 설치") {
                        Task {
                            operationError = nil
                            if let error = await core.installIME() {
                                operationError = "설치하지 못했습니다: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }

                if let message = operationError ?? core.imeActivationError.map({ "입력기를 준비하지 못했습니다: \($0.localizedDescription)" }) {
                    Text(message)
                        .font(SettingsTypography.body)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let warning = core.imeSettingsRefreshWarning {
                    Text(warning).font(SettingsTypography.body).foregroundStyle(.orange).textSelection(.enabled)
                }

                if core.isPreparingIME {
                    ProgressView("입력기를 관리하는 중…")
                        .controlSize(.small)
                }

                HStack(spacing: 12) {
                    Button("입력 소스 설정 열기") {
                        IMEInstaller.openInputSourcesSettings()
                    }
                    .disabled(isBusy)
                    Spacer()
                    if core.imeInstalled || core.imeDisabled || core.imeOnDisk {
                        Button("입력기 제거", role: .destructive) {
                            Task {
                                operationError = nil
                                if let error = await core.uninstallIME() {
                                    operationError = "제거하지 못했습니다: \(error.localizedDescription)"
                                }
                            }
                        }
                        .disabled(isBusy)
                    }
                }
                if let report = core.lastInputRemovalReport, operationError == nil {
                    Text(report.statusText).font(SettingsTypography.body).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("입력기만 제거해도 하늘키보드 앱과 사용자 설정은 남습니다.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
            }

            // 2026-11-06 (#154): 아이콘을 꺼도 메뉴에 있던 일을 여기서 할 수 있다. 설정과 응원하기는 왼쪽 메뉴에 있다.
            HaneulSettingsSection("로그인할 때 열기") {
                Toggle("Mac에 로그인할 때 하늘키보드 열기", isOn: Binding(
                    get: { loginItem != .off },
                    set: { setLoginItem($0) }))
                Text("켜 두면 Mac을 켤 때 앱이 뒤에서 열려 메뉴바 아이콘과 새 버전 알림이 이어집니다. 꺼도 한글 입력과 영타 변환은 그대로 동작합니다.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                if loginItem == .needsApproval {
                    HStack(spacing: 12) {
                        Label("시스템 설정에서 허용해야 합니다.", systemImage: "exclamationmark.triangle.fill")
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
                Text("꺼도 한글 입력과 영타 변환은 그대로 동작합니다. 아이콘을 끈 동안에는 응용 프로그램 폴더에서 하늘키보드를 열면 이 화면이 열립니다.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                Text("아이콘을 꺼도 앱은 뒤에서 실행되어 새 버전 알림을 받습니다. 앱 종료를 누르면 꺼지고, 로그인할 때 열기가 켜져 있으면 다음 로그인 때 다시 열립니다.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("시작하기 다시 보기") {
                        NotificationCenter.default.post(name: .haneulOnboardingRequested, object: nil)
                    }
                    Spacer()
                    Button("앱 종료") { NSApp.terminate(nil) }
                        .disabled(isBusy)
                }
            }

            HaneulSettingsSection("하늘키보드 전체 제거") {
                Text("하늘키보드의 앱·입력기·설정을 모두 지웁니다. 다시 쓰려면 내려받아 설치해야 합니다.")
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
            loginItemError = "바꾸지 못했습니다. 시스템 설정 → 일반 → 로그인 항목에서 바꿔 주세요. (\(error.localizedDescription))"
        }
        loginItem = LoginItem.state
    }
}

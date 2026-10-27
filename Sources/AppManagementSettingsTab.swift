import SwiftUI

/// 2026-10-10 (#88): 입력기 관리와 전체 제거를 별도 구획으로 모은다.
/// 설치/제거 상태는 AppCore가, 전체 제거 확인/결과 창은 SettingsView가 보존한다.
struct AppManagementSettingsTab: View {
    @Bindable var core: AppCore
    @Binding var showingUninstallConfirm: Bool
    @State private var operationError: String?

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
    }
}

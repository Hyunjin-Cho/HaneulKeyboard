import SwiftUI

/// 2026-11-07 오너(#189): 앱 관리에 있던 「한글 입력기」 구획을 「설치·업데이트」로 옮겼다(#88의 위치를 오너가 바꿨다).
/// 앱 관리는 내용이 넘치고 버전 화면은 아래 절반이 비었는데, 버전 화면의 갱신 안내가 앱 관리로 보내고 있었다.
/// 설치/제거 상태는 AppCore가 맡는다.
struct InputMethodSettingsSection: View {
    @Bindable var core: AppCore
    @State private var operationError: String?

    /// 2026-11-07 (#177, 리뷰 app-ui-F-1): 읽기 전·작업 중에는 캐시된 false를 "설치되어 있지 않아요"로 말하지 않는다.
    private var imeStatus: IMEStatusPresentation {
        .resolve(statusKnown: core.imeStatusKnown, busy: core.isPreparingIME,
                 installed: core.imeInstalled, disabled: core.imeDisabled)
    }

    private var isBusy: Bool {
        if core.isPreparingIME { return true }
        switch core.updater.phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    var body: some View {
        HaneulSettingsSection("한글 입력기") {
            if core.imeInstalled {
                Label("한글 입력기가 설치되어 있어요.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 6) {
                    Label("기존 Apple ‘두벌식’은 입력 소스에서 빼 주세요.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    // 2026-11-07 오너: 예전 문구 "자모가 깨지는 것을 막습니다"는 근거 기록을 못 찾아 확실한 말로 바꿨다.
                    Text("그쪽으로 바뀌면 영어 자동 변환이 안 돼요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                }
            } else if imeStatus == .checking {
                Label("한글 입력기 상태를 확인하고 있어요.", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else {
                Label(core.imeDisabled
                    ? "시스템 입력 소스에서 하늘키보드가 꺼져 있어요."
                    : "한글 입력기가 설치되어 있지 않아요.",
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("‘입력기 설치’를 누른 뒤, 시스템 설정에서 입력 소스로 추가해 주세요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                    .help("~/Library/Input Methods/에 설치돼요.")
                Button("입력기 설치") {
                    Task {
                        operationError = nil
                        if let error = await core.installIME() {
                            operationError = "설치하지 못했어요: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }

            // 2026-11-07 (#177, 리뷰 app-ui-F-3): 시스템 영역의 낡은 입력기는 앱이 직접 바꿀 수 없다. 안내 1단계가 가리키는 해결 자리가 여기다.
            if core.imeRefreshBlockedBySystemInstall {
                VStack(alignment: .leading, spacing: 6) {
                    Label("시스템 폴더에 이전 버전 입력기가 남아 있어요.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("앱이 직접 바꿀 수 없어요. 아래 ‘입력기 제거’로 지운 뒤(관리자 암호가 필요해요) ‘입력기 설치’를 눌러 주세요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = operationError ?? core.imeActivationError.map({ "입력기를 준비하지 못했어요: \($0.localizedDescription)" }) {
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
                                operationError = "제거하지 못했어요: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(isBusy)
                }
            }
            if let report = core.lastInputRemovalReport, operationError == nil {
                Text(report.statusText).font(SettingsTypography.body).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("입력기만 지우면 하늘키보드 앱과 설정은 그대로 남아요. 앱까지 모두 지우려면 앱 관리의 전체 제거를 써 주세요.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        }
    }
}

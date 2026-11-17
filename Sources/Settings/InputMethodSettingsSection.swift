import SwiftUI

/// 2026-11-07 오너(#189): 앱 관리에 있던 「한글 입력기」 구획을 「설치·업데이트」로 옮겼다(#88의 위치를 오너가 바꿨다).
/// 앱 관리는 내용이 넘치고 버전 화면은 아래 절반이 비었는데, 버전 화면의 갱신 안내가 앱 관리로 보내고 있었다.
/// 설치/제거 상태는 AppCore가 맡는다.
/// 2026-11-08 오너(#201): '입력기 제거' 버튼을 뺐다. 입력기만 지울 일은 없고, 지우는 일은 앱 관리의 전체 제거가 맡는다.
/// 입력기가 앱보다 낡았으면 '입력기 업데이트'로 바로 바꾼다(사용자 폴더 설치본). 시스템 폴더 설치본은 전체 제거 뒤 다시 설치한다.
/// 2026-11-08 오너(#209): 상태 줄(설치됨·두벌식 빼기 등)은 다른 줄보다 커 보여 `SettingsTypography.status`(15pt)로 줄였다.
struct InputMethodSettingsSection: View {
    @Bindable var core: AppCore
    @State private var operationError: String?

    /// 2026-11-07 (#177, 리뷰 app-ui-F-1): 읽기 전·작업 중에는 캐시된 false를 "설치되어 있지 않아요"로 말하지 않는다.
    /// 2026-11-13 (#227, 리뷰 app-ui-F-3·F-10): 무엇을 보일지(상태·버튼)는 `InputMethodSectionPresentation`이 정한다.
    /// 아래 「버전·업데이트」의 갱신 안내가 같은 판단으로 버튼 이름을 고른다.
    private var presentation: InputMethodSectionPresentation { core.inputMethodSection }

    private var isBusy: Bool {
        if core.isPreparingIME { return true }
        switch core.updater.phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    // 2026-11-13 (#227, 리뷰 app-ui-F-5): 시스템 초록·주황·빨강 글자는 밝은 화면에서 대비가 2~3.6:1이었다. 같은 계열의 진한 상태색(`FeedbackStatus`, 4.5:1 이상)을 쓴다.
    var body: some View {
        HaneulSettingsSection("한글 입력기") {
            switch presentation.status {
            case .installed:
                Label("한글 입력기가 설치되어 있어요.", systemImage: "checkmark.circle.fill")
                    .font(SettingsTypography.status)
                    .foregroundStyle(FeedbackStatus.success.adaptiveColor)
                VStack(alignment: .leading, spacing: 6) {
                    // 2026-11-08 오너(#201): 부연 설명("그쪽으로 바뀌면…")은 뺐다.
                    Label("기존 Apple ‘두벌식’은 입력 소스에서 빼 주세요.", systemImage: "exclamationmark.triangle.fill")
                        .font(SettingsTypography.status)
                        .foregroundStyle(FeedbackStatus.pending.adaptiveColor)
                }
            case .checking:
                Label("한글 입력기 상태를 확인하고 있어요.", systemImage: "hourglass")
                    .font(SettingsTypography.status)
                    .foregroundStyle(.secondary)
            case .disabled, .notInstalled:
                Label(presentation.status == .disabled
                    ? "시스템 입력 소스에서 하늘키보드가 꺼져 있어요."
                    : "한글 입력기가 설치되어 있지 않아요.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(SettingsTypography.status)
                    .foregroundStyle(FeedbackStatus.pending.adaptiveColor)
                Text("‘\(InputMethodSectionPresentation.installButtonTitle)’를 누른 뒤, 시스템 설정에서 입력 소스로 추가해 주세요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                    .help("~/Library/Input Methods/에 설치돼요.")
            }
            if presentation.showsInstallButton {
                Button(maru: InputMethodSectionPresentation.installButtonTitle) {
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
                        .font(SettingsTypography.status)
                        .foregroundStyle(FeedbackStatus.pending.adaptiveColor)
                    Text("앱이 직접 바꿀 수 없어요.\n앱 관리의 ‘하늘키보드 전체 제거’로 지운 뒤 다시 설치해 주세요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = operationError ?? core.imeActivationError.map({ "입력기를 준비하지 못했어요: \($0.localizedDescription)" }) {
                Text(message)
                    .font(SettingsTypography.body)
                    .foregroundStyle(FeedbackStatus.warning.adaptiveColor)
                    .textSelection(.enabled)
            }
            if let warning = core.imeSettingsRefreshWarning {
                Text(warning).font(SettingsTypography.body).foregroundStyle(FeedbackStatus.pending.adaptiveColor).textSelection(.enabled)
            }

            if core.isPreparingIME {
                ProgressView("입력기를 관리하는 중…")
                    .controlSize(.small)
            }

            HStack(spacing: 12) {
                Button(maru: "입력 소스 설정 열기") {
                    IMEInstaller.openInputSourcesSettings()
                }
                .disabled(isBusy)
                Spacer()
                // 앱을 시작할 때 사용자 폴더의 낡은 입력기는 저절로 바뀐다(`AppCore.ensureIMEActive`). 그게 실패했을 때만 보인다.
                if presentation.showsUpdateButton {
                    Button(maru: InputMethodSectionPresentation.updateButtonTitle) {
                        Task {
                            operationError = nil
                            if let error = await core.installIME() {
                                operationError = "업데이트하지 못했어요: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }
            }
        }
    }
}

extension AppCore {
    /// 2026-11-13 (#227, 리뷰 app-ui-F-3): 「한글 입력기」 구획과 「버전·업데이트」의 갱신 안내가 함께 쓰는 판단.
    var inputMethodSection: InputMethodSectionPresentation {
        .resolve(statusKnown: imeStatusKnown, busy: isPreparingIME, installed: imeInstalled, disabled: imeDisabled,
                 refreshNeeded: imeRefreshNeeded, blockedBySystemInstall: imeRefreshBlockedBySystemInstall)
    }
}

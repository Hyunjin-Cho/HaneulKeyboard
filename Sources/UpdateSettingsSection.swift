import SwiftUI

/// 2026-10-24: 새 버전 알림과 직접 확인을 기존 버전·업데이트 화면으로 통합한다.
/// 간결한 상태 왼쪽 / 확인·업데이트 버튼 오른쪽. 마지막 확인·자동 확인·IME 갱신 안내를 유지한다.
/// 동작은 `AppCore.updater`(`Updater`)가, 판단은 `UpdateDecisions.swift`가 맡는다.
struct UpdateSettingsSection: View {
    @Bindable var core: AppCore

    private var updater: Updater { core.updater }

    private var isBusy: Bool {
        switch updater.phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    // 2026-11-08 오너(#201): 설치된 버전 → 최신 버전 → 마지막 확인(날짜만)과 지금 확인 한 줄 → 새 버전 알림.
    // 숫자 두 줄로 알 수 있는 '최신 버전이에요'·'설치된 버전이 더 새로워요'는 빼고, 할 일이 있을 때(새 버전·진행·오류)만 상태 줄을 보인다.
    // 새 버전 알림의 설명도 뺐다.
    var body: some View {
        HaneulSettingsSection("버전·업데이트") {
            versionRow("설치된 버전", value: Updater.currentVersion)
            versionRow("최신 버전", value: updater.latestVersion ?? "확인 전")

            HStack(spacing: 12) {
                Text(lastCheckText)
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button(maru: "지금 확인") {
                    Task { await updater.checkNow(forced: true, showNotice: false) }
                }
                .disabled(isBusy || core.isPreparingIME)
                .fixedSize()
            }

            if hasStatusToShow {
                HStack(spacing: 12) {
                    statusLine
                    if case .available(let update) = updater.phase, let page = update.pageURL {
                        Link("바뀐 내용 보기", destination: page)
                            .font(SettingsTypography.body)
                    }
                    Spacer(minLength: 12)
                    if case .available = updater.phase {
                        Button(maru: "새 버전 설치") {
                            Task { await updater.installAvailableUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy || core.isPreparingIME)
                        .fixedSize()
                    }
                }
            }

            Toggle("새 버전 알림", isOn: Binding(
                get: { updater.autoCheckEnabled },
                set: { updater.setAutoCheckEnabled($0) }
            ))

            if core.imeRefreshNeeded {
                VStack(alignment: .leading, spacing: 4) {
                    Label("입력기 업데이트 필요", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    // 2026-09-21 (#60): 설정 창을 보는 사람은 빌드 스크립트를 돌리는 사람이
                    // 아니다 — 시스템 도메인 설치 안내는 README/체크리스트가 맡는다.
                    // 2026-11-08 (#201): '입력기 제거' 버튼이 없어져 해결 경로를 바꿨다.
                    Text(core.imeRefreshBlockedBySystemInstall
                         ? "앱은 새 버전인데 입력기는 아직 이전 버전이에요.\n앱 관리의 ‘하늘키보드 전체 제거’로 지운 뒤 다시 설치해 주세요."
                         : "앱은 새 버전인데 입력기는 아직 이전 버전이에요.\n위 ‘입력기 업데이트’를 눌러 주세요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 2026-11-08 오너(#201): 시간은 빼고 날짜만. 앱의 언어 설정과 상관없이 한국어로 쓴다(예전엔 "Nov 8, 2026 at 10:09"로 나왔다).
    private var lastCheckText: String {
        guard let lastCheck = updater.lastCheck else { return "아직 확인하지 않았어요" }
        return "마지막 확인: " + lastCheck.formatted(
            Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "ko_KR")))
    }

    /// 할 일이 있을 때만 상태 줄을 보인다. 최신·더 새로움은 위 두 숫자로 알 수 있다.
    private var hasStatusToShow: Bool {
        switch updater.phase {
        case .checking, .available, .downloading, .verifying, .installing, .failed: return true
        case .upToDate: return false
        case .idle:
            if let latest = updater.latestVersion.flatMap(CalVer.init), let current = CalVer(Updater.currentVersion) {
                return current < latest
            }
            return false
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch updater.phase {
        case .idle:
            // 재실행 뒤에는 실제로 저장된 최신 번호만 비교한다. 조회 전에는 최신이라고 추정하지 않는다.
            if let latest = updater.latestVersion.flatMap(CalVer.init),
               let current = CalVer(Updater.currentVersion) {
                if current < latest {
                    newVersionStatus
                } else {
                    upToDateStatus
                }
            } else {
                Text("아직 확인하지 않았어요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
            }
        case .checking:
            Label("확인 중…", systemImage: "arrow.triangle.2.circlepath")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        case .upToDate:
            upToDateStatus
        case .available:
            newVersionStatus
        case .downloading:
            Label("내려받는 중…", systemImage: "arrow.down.circle")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        case .verifying:
            Label("안전한 파일인지 확인하는 중…", systemImage: "checkmark.shield")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        case .installing:
            Label("설치 중이에요. 잠시 뒤 앱이 다시 열려요.", systemImage: "gearshape")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text("업데이트 오류: \(reason)")
                .font(SettingsTypography.body)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func versionRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(SettingsTypography.version)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private var upToDateStatus: some View {
        // 공개 전 검토 빌드처럼 설치 번호가 서버의 최신 공개 번호보다 앞서는 경우도 구분한다.
        if let latest = updater.latestVersion.flatMap(CalVer.init),
           let current = CalVer(Updater.currentVersion), current > latest {
            Label("설치된 버전이 더 새로워요.", systemImage: "info.circle")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        } else {
            Label("최신 버전이에요.", systemImage: "checkmark.circle.fill")
                .font(SettingsTypography.body)
                .foregroundStyle(.green)
        }
    }

    private var newVersionStatus: some View {
        Label("새 버전이 있어요.", systemImage: "arrow.down.circle.fill")
            .font(SettingsTypography.body)
            .foregroundStyle(.tint)
    }
}

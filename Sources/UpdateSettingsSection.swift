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

    var body: some View {
        HaneulSettingsSection(SettingsTab.update.title) {
            versionRow("최신 버전", value: updater.latestVersion ?? "확인 전")
            versionRow("설치된 버전", value: Updater.currentVersion)

            HStack(spacing: 12) {
                statusLine
                Spacer(minLength: 12)

                // 새 버전이 있을 때만 나타나므로 강조가 과하지 않다.
                if case .available = updater.phase {
                    Button("새 버전 설치") {
                        Task { await updater.installAvailableUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy || core.isPreparingIME)
                    .fixedSize()
                }

                Button("지금 확인") {
                    Task { await updater.checkNow(forced: true, showNotice: false) }
                }
                .disabled(isBusy || core.isPreparingIME)
                .fixedSize()
            }

            if case .available(let update) = updater.phase, let page = update.pageURL {
                Link("릴리스 노트 보기", destination: page)
                    .font(SettingsTypography.body)
            }

            if let lastCheck = updater.lastCheck {
                Text("마지막 확인: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
            }

            Toggle("새 버전 알림", isOn: Binding(
                get: { updater.autoCheckEnabled },
                set: { updater.setAutoCheckEnabled($0) }
            ))
            Text("새 버전을 자동으로 확인해 한 번 알려드려요. 끄면 ‘지금 확인’을 누를 때만 확인해요. 다운로드와 설치는 ‘새 버전 설치’를 눌러야 시작해요.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)

            if core.imeRefreshNeeded {
                VStack(alignment: .leading, spacing: 4) {
                    Label("한글 입력기 갱신 필요", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    // 2026-09-21 (#60): 설정 창을 보는 사람은 빌드 스크립트를 돌리는 사람이
                    // 아니다 — 시스템 도메인 설치 안내는 README/체크리스트가 맡는다.
                    Text("앱은 새 버전이지만 설치된 입력기는 이전 빌드입니다. 「앱 관리」에서 입력기를 제거한 뒤 다시 설치하세요.")
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                }
            }
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
                Text("아직 확인하지 않았습니다.")
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
            Label("서명·노타리 검증 중…", systemImage: "checkmark.shield")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        case .installing:
            Label("설치 중… 잠시 뒤 앱이 다시 열립니다.", systemImage: "gearshape")
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
            Label("설치된 버전이 더 새롭습니다.", systemImage: "info.circle")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        } else {
            Label("최신 버전입니다.", systemImage: "checkmark.circle.fill")
                .font(SettingsTypography.body)
                .foregroundStyle(.green)
        }
    }

    private var newVersionStatus: some View {
        Label("새 버전이 있습니다.", systemImage: "arrow.down.circle.fill")
            .font(SettingsTypography.body)
            .foregroundStyle(.tint)
    }
}

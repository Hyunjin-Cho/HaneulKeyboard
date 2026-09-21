import SwiftUI

/// 설정 → 「업데이트」 절. (2026-09-21, #19)
/// 자동 확인 토글(기본 ON) · 지금 확인 · 상태 문구 · 마지막 확인 시각 · IME 갱신 안내(폴백).
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
        Section("업데이트") {
            LabeledContent("현재 버전") {
                Text("\(Updater.currentVersion) (\(Updater.currentBuild.map(String.init) ?? "?"))")
                    .foregroundStyle(.secondary)
            }

            Toggle("업데이트 자동 확인", isOn: Binding(
                get: { updater.autoCheckEnabled },
                set: { updater.setAutoCheckEnabled($0) }
            ))
            Text("켜 두면 앱을 실행할 때와 24시간마다 GitHub 릴리스에서 새 버전이 있는지 확인합니다. 새 버전이 있어도 자동으로 설치하지 않고 알려만 드려요. 끄면 아래 \"지금 확인\"을 누를 때만 인터넷에 접속합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("지금 확인") {
                    Task { await updater.checkNow(forced: true) }
                }
                .disabled(isBusy)

                if case .available = updater.phase {
                    Button("업데이트") {
                        Task { await updater.installAvailableUpdate() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                }

                Spacer()
            }

            statusLine

            if let lastCheck = updater.lastCheck {
                Text("마지막 확인: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if core.imeRefreshNeeded {
                VStack(alignment: .leading, spacing: 4) {
                    Label("한글 입력기(IME) 갱신 필요", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("앱은 새 버전이지만 설치된 입력기는 이전 빌드예요. 위 「한글 입력기 (IME)」 절에서 \"IME 제거\" 후 \"IME 설치\"를 다시 하거나, 시스템 도메인(/Library/Input Methods) 설치본이면 scripts/build_notarize_install.sh로 다시 설치해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch updater.phase {
        case .idle:
            Text("아직 확인하지 않았어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            Label("확인 중…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("최신 버전입니다.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .available(let update):
            VStack(alignment: .leading, spacing: 4) {
                Label("새 버전 \(update.tag)이 있어요.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("\"업데이트\"를 누르면 내려받아 서명·노타리를 검증한 뒤 응용 프로그램 폴더의 앱을 바꾸고 다시 엽니다. 검증에 실패하면 지금 앱을 그대로 둡니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let page = update.pageURL {
                    Link("릴리스 노트 보기", destination: page)
                        .font(.caption)
                }
            }
        case .downloading:
            Label("다운로드 중…", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .verifying:
            Label("서명·노타리 검증 중…", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .installing:
            Label("설치 중… 잠시 뒤 앱이 다시 열립니다.", systemImage: "gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text("실패: \(reason)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

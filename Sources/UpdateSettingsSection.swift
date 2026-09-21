import SwiftUI

/// 설정 → 「업데이트」 절. (2026-09-21, #19)
/// 자동 확인 토글(기본 ON) · 지금 확인 · 상태 문구 · 마지막 확인 시각 · IME 갱신 안내(폴백).
/// 동작은 `AppCore.updater`(`Updater`)가, 판단은 `UpdateDecisions.swift`가 맡는다.
///
/// 2026-09-21 (#60): 탭 재편에서 이 절 하나가 「업데이트」 탭 전체가 됐다(컨테이너는
/// `SettingsView`). 같은 개정에서 **상태줄을 버튼 행 위로 올렸다** — macOS 소프트웨어
/// 업데이트와 같은 "무슨 일이 있는지 읽고 → 누른다" 순서다. 색은 `.blue` 하드코딩을 `.tint`로
/// 바꿔 시스템 강조 색을 따라가게 했다.
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
            Text("켜 두면 앱을 실행할 때와 하루에 한 번 GitHub 릴리스에서 새 버전을 확인합니다. 새 버전이 있어도 자동으로 설치하지 않고 알려만 드립니다. 끄면 \"지금 확인\"을 누를 때만 인터넷에 접속합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusLine

            HStack(spacing: 12) {
                Button("지금 확인") {
                    Task { await updater.checkNow(forced: true) }
                }
                .disabled(isBusy)

                // 새 버전이 있을 때만 나타나므로 강조가 과하지 않다.
                if case .available = updater.phase {
                    Button("업데이트") {
                        Task { await updater.installAvailableUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                }

                Spacer()
            }

            if let lastCheck = updater.lastCheck {
                Text("마지막 확인: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if core.imeRefreshNeeded {
                VStack(alignment: .leading, spacing: 4) {
                    Label("한글 입력기 갱신 필요", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    // 2026-09-21 (#60): 설정 창을 보는 사람은 빌드 스크립트를 돌리는 사람이
                    // 아니다 — 시스템 도메인 설치 안내는 README/체크리스트가 맡는다.
                    Text("앱은 새 버전이지만 설치된 입력기는 이전 빌드입니다. 「일반」 탭에서 입력기를 제거한 뒤 다시 설치하세요.")
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
            Text("아직 확인하지 않았습니다.")
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
                Label("새 버전 \(update.tag)이(가) 있습니다.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("내려받아 서명·노타리를 검증한 뒤 응용 프로그램 폴더의 앱을 바꾸고 다시 엽니다. 검증에 실패하면 지금 앱을 그대로 둡니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let page = update.pageURL {
                    Link("릴리스 노트 보기", destination: page)
                        .font(.caption)
                }
            }
        case .downloading:
            Label("내려받는 중…", systemImage: "arrow.down.circle")
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
            Text("업데이트하지 못했습니다: \(reason)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

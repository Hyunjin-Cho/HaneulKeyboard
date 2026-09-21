import SwiftUI

/// 설정 → 「일반」 탭. (2026-09-21, #60)
///
/// 종전 `SettingsView`의 `Section("한글 입력기 (IME)")`(C01~C08)과 `Section("상태")`(C11)를
/// 옮겨 담았다. 「상태」는 절 하나를 통째로 쓰던 것을 **탭 최상단 상태 카드 두 줄**(설치 배지 /
/// 현재 입력 모드)로 합쳤다 — 창을 열자마자 "정상인가?"가 먼저 답해지는 구조다.
///
/// 상태 카드는 설치 여부가 바뀌어도 **항상 두 행**이라 높이가 변하지 않는다.
struct GeneralSettingsTab: View {
    @Bindable var core: AppCore
    @State private var installError: Error?
    @State private var isInstalling = false

    var body: some View {
        Form {
            Section("상태") {
                if core.imeInstalled {
                    Label("한글 입력기가 설치되어 있습니다.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("한글 입력기가 설치되어 있지 않습니다.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                LabeledContent("현재 입력 모드") {
                    Text(core.isKoreanActive ? "한국어 (한)" : "영어 (A)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("한글 입력기") {
                if core.imeInstalled {
                    installedRows
                } else {
                    notInstalledRows
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 설치됨

    @ViewBuilder
    private var installedRows: some View {
        Text("Caps Lock을 짧게 누르면 한글·영어가 바뀌고, 1초 이상 누르면 Caps Lock이 켜집니다.")
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
            Label("시스템 입력 소스에서 기존 \"두벌식\"은 제거하세요.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("자모가 깨지는 것을 막습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // 파괴적 동작(제거)은 주 동작과 붙여 두지 않는다 — Spacer로 오른쪽 끝에 떼어 놓는다.
        HStack(spacing: 12) {
            Button("입력 소스 설정 열기") {
                IMEInstaller.openInputSourcesSettings()
            }
            Spacer()
            Button("입력기 제거", role: .destructive) {
                Task {
                    do {
                        try await IMEInstaller.uninstall()
                        core.refreshIMEStatus()
                        installError = nil
                    } catch {
                        installError = error
                    }
                }
            }
        }
    }

    // MARK: - 미설치

    @ViewBuilder
    private var notInstalledRows: some View {
        Text("하늘키보드 입력기를 ~/Library/Input Methods/에 설치합니다. 설치한 뒤 시스템 설정에서 입력 소스로 추가하세요.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let installError = installError ?? core.imeActivationError {
            // 2026-09-21 (#60): 오류 문구는 그대로 복사해 이슈에 붙일 수 있어야 한다.
            Text("설치하지 못했습니다: \(installError.localizedDescription)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

        HStack(spacing: 12) {
            Button("입력기 설치") {
                isInstalling = true
                Task {
                    do {
                        _ = try await IMEInstaller.installBundle()
                        core.refreshIMEStatus()
                        installError = nil
                    } catch {
                        installError = error
                    }
                    isInstalling = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling)

            if isInstalling {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("설치 중")
            }
            Spacer()
        }
    }
}

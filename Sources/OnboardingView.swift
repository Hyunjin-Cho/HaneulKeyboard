import SwiftUI

struct OnboardingView: View {
    @Bindable var core: AppCore
    /// (review-0712 P3-6) 창을 닫는 방법을 호출자가 주입한다.
    /// 이 뷰는 `NSHostingController` + 수동 `NSWindow`로 뜨기 때문에 SwiftUI
    /// presentation 컨텍스트가 없고, 예전에 쓰던 `@Environment(\.dismiss)`는
    /// 아무 일도 하지 않아 "완료"를 눌러도 창이 그대로 남았다.
    var onComplete: () -> Void = {}
    @AppStorage("haneul.hasCompletedOnboarding") private var hasCompleted = false

    @State private var step: Int = 0
    @State private var installError: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepIndicator

            Group {
                switch step {
                case 0: welcomeStep
                case 1: imeStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            navigationButtons
        }
        .padding(24)
        .frame(width: 540, height: 420)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            Spacer()
            Text("단계 \(step + 1) / 3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var navigationButtons: some View {
        HStack {
            if step > 0 {
                Button("이전") { step -= 1 }
            }
            Spacer()
            if step < 2 {
                Button(step == 0 ? "시작" : "다음") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("완료") {
                    hasCompleted = true
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "character.bubble")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("HaneulKeyboard")
                .font(.title.bold())
            Text("한글 자모 깨짐 방지를 위한 macOS 한국어 입력기")
                .font(.body)
        }
    }

    private var imeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. 한글 입력기 (IME) 설치")
                .font(.title2.bold())
            Text("HaneulKeyboard 자체 한국어 입력기를 ~/Library/Input Methods/에 설치합니다. Caps Lock으로 한글/영어 모드를 전환할 수 있습니다.")
                .font(.body)

            if core.imeInstalled {
                Label("IME 설치됨", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("다음 단계:")
                        .font(.subheadline.bold())
                    Text("• 시스템 설정 → 키보드 → 입력 소스 열기")
                    Text("• \"+\" → \"한국어\" → \"하늘키보드 (두벌식)\" 추가")
                    Text("• 기존 시스템 한국어 입력기 제거 권장")
                }
                .font(.caption)

                Button("입력 소스 설정 열기") {
                    IMEInstaller.openInputSourcesSettings()
                }
            } else {
                if let installError {
                    Text(installError.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("IME 설치") {
                    Task {
                        do {
                            _ = try await IMEInstaller.install()
                            core.refreshIMEStatus()
                            installError = nil
                        } catch {
                            installError = error
                        }
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("준비 완료")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("• 시스템 설정에서 \"하늘키보드 (두벌식)\"를 입력 소스로 추가했는지 확인하세요.")
                Text("• 입력 소스에서 기존 \"두벌식\"은 제거해주세요. (자모 깨짐 방지)")
                Text("• 앱이 안 보이면 런치패드에서 \"haneulkeyboard\"로 검색할 수 있습니다.")
                Text("• 입력 소스가 확실히 적용되려면 한 번 재부팅하는 것을 권장합니다.")
            }
            .font(.body)
        }
    }
}

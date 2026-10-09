// 2026-10-06 — Isolated SDK compatibility sample; not part of either product target.
// Type-check with macOS 27 SDK and a macOS 14 deployment target.
// No AppCore, installer, defaults, input-source changes, networking or entry point.
import SwiftUI

@available(macOS 14.0, *)
struct NativeOnboardingControlsSample: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var step = 0

    var body: some View {
        HStack {
            navigationButton("이전", prominent: false) { step = max(0, step - 1) }
                .disabled(step == 0)
            Spacer()
            Text("\(step + 1) / 5").foregroundStyle(.secondary)
            Spacer()
            navigationButton(step == 4 ? "시작하기" : "다음", prominent: true) {
                step = min(4, step + 1)
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    @ViewBuilder
    private func navigationButton(_ title: String, prominent: Bool,
                                  action: @escaping () -> Void) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent {
                Button(title, action: action).buttonStyle(.glassProminent)
            } else {
                Button(title, action: action).buttonStyle(.glass)
            }
        } else {
            if prominent {
                Button(title, action: action).buttonStyle(.borderedProminent)
            } else {
                Button(title, action: action).buttonStyle(.bordered)
            }
        }
    }
}

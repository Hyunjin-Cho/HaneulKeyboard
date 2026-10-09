import SwiftUI

/// 2026-10-07 (#80): 손그림·링크는 파란 잉크, 이전·다음은 차분한 하늘색.
enum OnboardingBrand {
    static let red = Color(red: 0.80, green: 0.18, blue: 0.23)
    static let blue = Color(red: 0.0, green: 0.28, blue: 0.63)
    static let sky = Color(red: 104.0 / 255, green: 188.0 / 255, blue: 226.0 / 255)
    static let navigationFill = LinearGradient(
        colors: [Color(red: 130.0 / 255, green: 203.0 / 255, blue: 235.0 / 255), sky],
        startPoint: .top, endPoint: .bottom)

    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.48, green: 0.73, blue: 1) : blue
    }
}

struct OnboardingNavigationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(WindowAppearance.defaultsKey) private var appearance = WindowAppearance.glass
    private var showsColor: Bool { appearsActive && isEnabled }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: controlSize == .large ? 15 : 14, weight: .semibold, design: .rounded))
            .foregroundStyle(showsColor ? Color.white : .primary)
            .shadow(color: .black.opacity(showsColor ? 0.20 : 0), radius: 1, y: 1)
            .padding(.horizontal, controlSize == .large ? 18 : 12)
            .frame(minHeight: controlSize == .large ? 36 : 30)
            .background { surface }
            .overlay(Capsule().strokeBorder(.white.opacity(showsColor ? 0.28 : 0.06), lineWidth: 0.8))
            .shadow(color: .black.opacity(showsColor ? 0.10 : 0), radius: 4, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .contentShape(Capsule())
    }

    @ViewBuilder private var surface: some View {
        if !showsColor {
            Capsule().fill(.primary.opacity(0.18))
        } else if #available(macOS 26.0, *), appearance == .glass && !reduceTransparency {
            Capsule().fill(OnboardingBrand.navigationFill).glassEffect(.clear, in: Capsule())
        } else {
            Capsule().fill(OnboardingBrand.navigationFill)
        }
    }
}

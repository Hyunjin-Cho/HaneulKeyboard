import SwiftUI

/// 2026-10-18: 배경은 설명의 역할, 글자색은 상태를 나타낸다.
enum FeedbackTone {
    case information, advice, warning
    var tint: Color {
        switch self {
        case .information: OnboardingRiso.cyan
        case .advice: OnboardingRiso.yellow
        case .warning: Color(red: 0.85, green: 0.16, blue: 0.20)
        }
    }
}

enum FeedbackStatus {
    case success, pending, warning
    func color(in scheme: ColorScheme) -> Color {
        switch self {
        case .success: scheme == .dark
            ? Color(red: 0.20, green: 0.85, blue: 0.30)
            : Color(red: 0, green: 128.0 / 255.0, blue: 0)
        case .pending: scheme == .dark
            ? Color(red: 1, green: 0.66, blue: 0.30)
            : Color(red: 0.69, green: 0.30, blue: 0.02)
        case .warning: scheme == .dark
            ? Color(red: 1, green: 0.56, blue: 0.56)
            : Color(red: 0.72, green: 0.10, blue: 0.14)
        }
    }
}

private struct FeedbackPanel: ViewModifier {
    let tone: FeedbackTone
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .foregroundStyle(scheme == .dark ? Color(white: 0.94) : Color(white: 0.10))
            .background(tone.tint.opacity(scheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(tone.tint.opacity(0.40), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                RisoRegistrationMark().padding(.leading, 18).offset(y: -6.3)
            }
    }
}

extension View {
    func feedbackPanel(_ tone: FeedbackTone) -> some View { modifier(FeedbackPanel(tone: tone)) }
}

struct FeedbackStatusLabel: View {
    let complete: Bool
    let completedText: String
    let pendingText: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Label(complete ? completedText : pendingText,
              systemImage: complete ? "checkmark.circle.fill" : "circle")
            .foregroundStyle((complete ? FeedbackStatus.success : .pending).color(in: scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

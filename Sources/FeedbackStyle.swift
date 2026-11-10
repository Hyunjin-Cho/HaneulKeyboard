import SwiftUI

/// 2026-10-18: 배경은 설명의 역할, 글자색은 상태를 나타낸다.
enum FeedbackTone {
    /// 2026-11-07 오너(#187): `actionNeeded`는 사용자가 지금 눌러야 하는 칸이다. 경고 띠(옅은 분홍)보다 진하게 칠한다.
    case information, advice, warning, actionNeeded
    var tint: Color {
        switch self {
        case .information: OnboardingRiso.cyan
        case .advice: OnboardingRiso.yellow
        case .warning, .actionNeeded: Color(red: 0.85, green: 0.16, blue: 0.20)
        }
    }
    /// 2026-11-09 오너(#216, 4차): `actionNeeded`는 투명도를 뺐다 — 반투명 빨강(36%)이 한지 무늬와 섞여 탁한 분홍으로 보였다("opacity를 빼볼래?").
    /// 꽉 찬 빨강은 "너무 진하다"여서, 같은 빨강을 밝게 미리 섞은 불투명 색으로 칠한다. 바탕 무늬가 비치지 않아 맑게 보인다.
    /// 2026-11-09 오너(#216, 5차): "50% 더 연하게", "다크 모드는 왜 이렇게 진해? 둘이 같아야지" — 두 모드 모두 바탕에 빨강을 11%만 섞는다
    /// (라이트 = 흰색, 다크 = 창 바탕 실측 (0.149, 0.144, 0.131)). 예전 다크(0.36, 0.12, 0.14)는 바탕보다 훨씬 진하게 튀었다.
    func fill(in scheme: ColorScheme) -> Color {
        if self == .actionNeeded {
            return scheme == .dark ? Color(red: 0.226, green: 0.146, blue: 0.139) : Color(red: 0.98, green: 0.91, blue: 0.91)
        }
        return tint.opacity(scheme == .dark ? 0.16 : 0.10)
    }
    var strokeOpacity: Double { self == .actionNeeded ? 0.70 : 0.40 }
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
    /// 2026-11-05 (#145): 켜면 띠가 남는 높이를 받고 내용은 세로 가운데에 놓인다.
    var fills = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .leading)
            .padding(14)
            .foregroundStyle(scheme == .dark ? Color(white: 0.94) : Color(white: 0.10))
            .background(tone.fill(in: scheme), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(tone.tint.opacity(tone.strokeOpacity), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                RisoRegistrationMark().padding(.leading, 18).offset(y: -6.3)
            }
    }
}

extension View {
    func feedbackPanel(_ tone: FeedbackTone, fills: Bool = false) -> some View {
        modifier(FeedbackPanel(tone: tone, fills: fills))
    }
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

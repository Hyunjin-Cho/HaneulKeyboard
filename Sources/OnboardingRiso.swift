import AppKit
import CoreText
import SwiftUI

/// 2026-10-09: 확정된 단청 아이콘과 Visual-Spec.json을 잇는 안내 화면의 인쇄 색과 종이.
/// 장식에만 잉크 결을 쓰고, 조작부·본문·입력 문자는 네이티브로 선명하게 유지한다.
enum OnboardingRiso {
    static let ivory = Color(red: 247 / 255, green: 242 / 255, blue: 229 / 255)
    static let cyan = Color(red: 3 / 255, green: 150 / 255, blue: 251 / 255)
    static let pink = Color(red: 250 / 255, green: 16 / 255, blue: 156 / 255)
    static let yellow = Color(red: 252 / 255, green: 220 / 255, blue: 12 / 255)
    static let indigo = Color(red: 33 / 255, green: 32 / 255, blue: 162 / 255)
    /// 2026-11-04 오너 결정(#119): 어두운 화면 종이 = 먹색(따뜻한 검정). 예전 회남색(0.13, 0.14, 0.19)·리소 남색과 비교해
    /// 그림 아래 노란 땅·아이보리 종이와 이어지는 쪽을 골랐다. 안내 카드와 창 종이(설정·후원 창도 같은 종이)가 함께 쓴다.
    static let meok = Color(red: 0.150, green: 0.140, blue: 0.128)
    // 작은 흰 버튼 글자와 대비를 확보한 시안 계열의 기능 색 (#0879BA).
    static let actionBlue = Color(red: 8 / 255, green: 121 / 255, blue: 186 / 255)
    static let paper = bundledImage("DancheongPaper")
    static let eaves = bundledImage("DancheongEaves")
    // 2026-11-04 (#118): 10월 안내의 작은 풍경·인물 띠(walkers·landscape·승인 7자세)와 머리 아이콘(appIcon)은
    // 리디자인(#107 — 두루마리·새 세 사람·7페이지 영상) 뒤 쓰이지 않아 자원과 함께 지웠다(git 기록에 남는다).

    private static func bundledImage(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return image
    }

    private static let titleFontName: String? = {
        guard let url = Bundle.main.url(forResource: "GowunBatang-Bold", withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }()

    static func titleFont(size: CGFloat) -> Font {
        if let titleFontName { return .custom(titleFontName, size: size) }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.43, green: 0.79, blue: 1) : indigo
    }
}

struct OnboardingRisoPaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            scheme == .dark ? OnboardingRiso.meok : OnboardingRiso.ivory
            Image(nsImage: OnboardingRiso.paper).resizable().interpolation(.high)
                .colorMultiply(scheme == .dark ? Color(white: 0.19) : .white)
                .opacity(scheme == .dark ? 0.45 : 0.65)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct RisoRegistrationMark: View {
    var body: some View {
        HStack(spacing: -1) {
            ForEach(0..<3) { i in
                Rectangle().fill([OnboardingRiso.cyan, OnboardingRiso.indigo, OnboardingRiso.pink][i])
                    .frame(width: 8, height: 12.6)
            }
            Rectangle().fill(OnboardingRiso.yellow).frame(width: 8, height: 12.6)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OnboardingRisoButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colored: Bool { isEnabled && appearsActive }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colored && prominent ? .white : .primary)
            .padding(.horizontal, prominent ? 18 : 13).frame(minHeight: prominent ? 36 : 32)
            .background {
                if colored && prominent {
                    Capsule().fill(OnboardingRiso.pink.opacity(0.8)).offset(x: 1.5, y: 2)
                    Capsule().fill(OnboardingRiso.actionBlue)
                    RisoInkGrain().clipShape(Capsule())
                } else {
                    Capsule().fill(.primary.opacity(prominent ? 0.16 : 0.045))
                }
            }
            .overlay(Capsule().strokeBorder(colored && !prominent ? OnboardingRiso.ink(for: scheme).opacity(0.35) : .clear))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .contentShape(Capsule())
    }
}

/// 잉크의 미세한 빈 입자는 글자 아래 배경에만 고정된 위치로 그린다.
private struct RisoInkGrain: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<180 {
                let x = CGFloat((i * 73 + 19) % 997) / 997 * size.width
                let y = CGFloat((i * 137 + 7) % 991) / 991 * size.height
                let radius = CGFloat(i % 3 + 1) * 0.19
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(0.22)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

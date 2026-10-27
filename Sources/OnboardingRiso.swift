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
    // 작은 흰 버튼 글자와 대비를 확보한 시안 계열의 기능 색 (#0879BA).
    static let actionBlue = Color(red: 8 / 255, green: 121 / 255, blue: 186 / 255)
    static let paper = bundledImage("DancheongPaper")
    static let eaves = bundledImage("DancheongEaves")
    static let walkers = bundledImage("DancheongWalkers")
    static let landscape = bundledImage("DancheongLandscape")
    // 2026-10-25: 승인된 일곱 자세를 페이지별로 한 번 읽어 캐시한다.
    private static let peopleByPage: [[NSImage]] = (0..<OnboardingPeopleArtwork.pageCount).map {
        OnboardingPeopleArtwork.people(page: $0)
    }

    static func people(for page: Int) -> [NSImage] {
        peopleByPage[OnboardingPeopleArtwork.pageIndex(page)]
    }
    static let appIcon = bundledImage("HaneulBrandIcon")

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
            scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.19) : OnboardingRiso.ivory
            Image(nsImage: OnboardingRiso.paper).resizable().interpolation(.high)
                .colorMultiply(scheme == .dark ? Color(white: 0.19) : .white)
                .opacity(scheme == .dark ? 0.45 : 0.65)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// 종이에 인쇄한 가는 테두리와 색판 표시로 영역을 구분한다.
struct OnboardingPrintPanel: ViewModifier {
    var tint: Color = OnboardingRiso.cyan
    var strongerYellow = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(tint.opacity(strongerYellow ? (scheme == .dark ? 0.16 : 0.13) : (scheme == .dark ? 0.08 : 0.035)), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(tint.opacity(strongerYellow ? 0.7 : 0.28), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                RisoRegistrationMark().padding(.leading, 18).offset(y: -6.3)
            }
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

/// 2026-10-25 (#80): 사용자 선택 B안. 인물만48→60pt(+25%)로 확대한다.
/// 풍경의 크기·색은 유지하고, 상하 여백과 기준 위치로 손·발 잘림을 막는다.
struct OnboardingPeopleScene: View {
    let page: Int
    private var people: [NSImage] { OnboardingRiso.people(for: page) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: OnboardingRiso.landscape).resizable().scaledToFit()
                .frame(width: 240, height: 80)
            if people.count == 3 {
                ForEach(0..<3) { person in
                    Image(nsImage: people[person]).resizable().scaledToFit()
                        .frame(width: 60, height: 60)
                        .position(x: [48.0, 114.0, 178.0][person], y: 33.72)
                }
            }
        }.frame(width: 240, height: 80)
        .frame(width: 280, height: 66, alignment: .trailing)
        .clipped()
        .transaction { $0.animation = nil }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OnboardingRisoFinish: View {
    let ready: Bool
    var onSettings: () -> Void
    var onReplay: () -> Void
    var onSupport: () -> Void
    var onInstall: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { OnboardingRiso.ink(for: scheme) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Spacer(minLength: 0)
                    menuBar.padding(.top, 9)
                }.frame(height: 94, alignment: .top)
                Divider().padding(.vertical, 8)
                RisoMenuRow("하늘키보드 설정…", symbol: "slider.horizontal.3", action: onSettings)
                RisoMenuRow("시작하기 다시 보기…", symbol: "play.circle", action: onReplay)
                RisoMenuRow("하늘키보드 응원하기…", symbol: "heart", action: onSupport)
            }
            .padding(16).modifier(OnboardingPrintPanel())

            VStack(spacing: 10) {
                Text("하늘키보드는 영원히 무료입니다.").font(OnboardingRiso.titleFont(size: 22))
                Text("개발을 응원하고 싶다면, 후원은 자유롭게 선택해 주세요.")
                    .font(.system(size: 14)).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)

            if !ready {
                HStack(spacing: 12) {
                    Text("시작하기를 누르면 입력기 설치·설정을\n이어갈 수 있어요.")
                        .font(.system(size: 13)).lineSpacing(3)
                    Spacer(minLength: 0)
                    Button("설치 단계로 이동", action: onInstall).fixedSize()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var menuBar: some View {
        HStack(spacing: 17) {
            Image(systemName: "wifi").font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
            Image(nsImage: HaneulStatusIcon.image)
                .resizable().renderingMode(.template).scaledToFit().frame(width: 22, height: 22)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .accessibilityLabel("하늘키보드 메뉴바 아이콘")
                .overlay {
                    OnboardingPencilRing().stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) {
                    OnboardingMenuHint().foregroundStyle(ink).offset(y: 53).allowsHitTesting(false)
                }
            Text("10:30").font(.system(size: 14, weight: .medium)).monospacedDigit()
        }.fixedSize()
    }
}

private struct RisoMenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).frame(width: 22)
                Text(title).font(.system(size: 16))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).opacity(hovered ? 1 : 0.4)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(OnboardingRiso.ink(for: scheme).opacity(hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
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

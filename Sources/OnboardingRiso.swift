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
    // 2026-11-04 오너 결정(#137): 창 바탕 = 새 한지 '또렷'. 10월 외부 생성 사진(DancheongPaper)을 창 크기로 늘려 쓰던 것을 바꿨다 —
    // 섬유가 가로로 번지고, 다크에서는 결 세기가 라이트의 1/8로 죽었다(밝기 표준편차 3.78 → 0.49).
    // 라이트·다크가 같은 결 구조를 쓰고(생성 코드: 비공개 haneul-art paper/), 늘리지 않고 1024pt 타일로 깐다.
    // 2026-11-08 오너(#209, #203): 한지를 r2b로 바꿨다 — r2(흰 섬유·솜결)에서 섬유만 70% 남긴 판. 생성기는 비공개 haneul-art `paper/hanji_v3.py --variant r2b`.
    // 2026-11-06 (#156): 앱은 창 없이 뒤에 남으므로 전역에 쥐지 않는다. 2048px 한지는 풀면 한 장에 16MB다.
    @MainActor private static let hanjiShelf = WindowArtShelf()
    @MainActor static func hanji(dark: Bool) -> NSImage {
        hanjiShelf.image(dark ? "dark" : "light") { tileImage(dark ? "HanjiPaperDark" : "HanjiPaperLight") }
    }
    // 2026-11-04 (#118): 10월 안내의 작은 풍경·인물 띠(walkers·landscape·승인 7자세)와 머리 아이콘(appIcon)은
    // 리디자인(#107 — 두루마리·새 세 사람·7페이지 영상) 뒤 쓰이지 않아 자원과 함께 지웠다(git 기록에 남는다).
    // 2026-11-07 (#177, 리뷰 app-ui-F-5): 그때 빠뜨린 10월 종이 RisoPaper.png(약 3MB)와 그것만 읽던 bundledImage도 지웠다.
    // 앱 번들·ZIP·DMG가 3MB 가벼워진다. 원본은 비공개 haneul-art에 있고 git 기록에도 남는다.

    /// 이음매 없는 한지 타일. 2048px 원본을 1024pt(@2x)로 맞춰, 레티나에서 한 픽셀이 그대로 찍히게 한다.
    private static func tileImage(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
        image.size = NSSize(width: 1024, height: 1024)
        return image
    }

    /// 2026-11-08 오너(#209): 제목도 마루부리 Bold다. 고운바탕은 뺐다(`AppFont`).
    static func titleFont(size: CGFloat) -> Font {
        AppFont.font(size: size, weight: .bold)
    }

    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.43, green: 0.79, blue: 1) : indigo
    }
}

/// 2026-11-06 (#156): 창이 떠 있는 동안만 살아 있는 그림 선반. 그림은 보는 쪽(SwiftUI 뷰)이 쥐고 여기는 약하게만 가리킨다.
/// 떠 있는 창끼리는 한 장을 나눠 쓰고, 창이 다 닫히면 그림이 메모리에서 빠진다.
@MainActor final class WindowArtShelf {
    private final class Slot { weak var image: NSImage? }
    private var slots: [String: Slot] = [:]

    func image(_ key: String, load: () -> NSImage) -> NSImage {
        if let live = slots[key]?.image { return live }
        let image = load()
        let slot = Slot()
        slot.image = image
        slots[key] = slot
        return image
    }
}

struct OnboardingRisoPaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            // 텍스처를 못 읽었을 때도 같은 바탕색이 남는다. 한지 텍스처 자체가 이 색을 평균으로 만든 것이다.
            scheme == .dark ? OnboardingRiso.meok : OnboardingRiso.ivory
            Image(nsImage: OnboardingRiso.hanji(dark: scheme == .dark))
                .resizable(resizingMode: .tile)
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
    /// 주 버튼의 잉크. 2026-11-08 (#201): 전체 제거 확인의 '모두 삭제'는 빨간 잉크로 칠한다.
    var tint: Color = OnboardingRiso.actionBlue
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colored: Bool { isEnabled && appearsActive }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.font(size: 15, weight: .semibold))
            .foregroundStyle(colored && prominent ? .white : .primary)
            .padding(.horizontal, prominent ? 18 : 13).frame(minHeight: prominent ? 36 : 32)
            .background {
                if colored && prominent {
                    Capsule().fill(OnboardingRiso.pink.opacity(0.8)).offset(x: 1.5, y: 2)
                    Capsule().fill(tint)
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
struct RisoInkGrain: View {
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

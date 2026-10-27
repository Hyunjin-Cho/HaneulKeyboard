import SwiftUI

/// 2026-10-10 (#88): Studio Display에서 읽기 쉽게 설명 14pt / 항목 17pt로 구분한다.
enum SettingsTypography {
    static let body = Font.system(size: 14, weight: .regular)
    static let control = Font.system(size: 17, weight: .semibold)
    // 2026-10-11 (#88): 번호는 둥근 일반체로 표시해 항목 이름과 무게를 구분한다.
    static let version = Font.system(size: 17, weight: .regular, design: .rounded)
}

/// 2026-10-11: 메뉴 너비와 단청의 오른쪽 끝을 같은 세로 구분선에 맞춘다.
enum SettingsLayout {
    static let sidebarWidth: CGFloat = 160
}

/// 2026-10-10: 안내와 같은 처마·종이·손글씨를 쓰되 본문과 조작부는 시스템 글꼴로 유지한다.
struct SettingsBrandHeader: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: OnboardingRiso.eaves).resizable().scaledToFit()
                .frame(width: 178, height: 60)
                .allowsHitTesting(false).accessibilityHidden(true)
            Text("하늘키보드 설정")
                .font(OnboardingHandwriting.font(size: 30))
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.trailing, 24)
        .frame(height: 68)
    }
}

/// 2026-10-11 (#88): 새로 창작한 리소그래프 매듭 둘은 오른쪽 위, 단청은 왼쪽 아래에 고정한다.
/// 본문 시작 여백을 확보한 고정 장식이며 조작·접근성 탐색에서 제외한다.
struct SettingsCornerArtwork: ViewModifier {
    // 제목 영역 68pt 아래에서도 매듭(상단 4pt + 높이 116pt)이 본문과 겹치지 않게 한다.
    static let bodyTopInset: CGFloat = 52
    // 2026-10-11: 직전 176pt 시안에서 20% 확대한 크기는 유지한다.
    static let dancheongSize: CGFloat = 176 * 1.2
    // 2026-10-12: 중심 꽃의 아래쪽도 보이도록 위로 올리고, 문양 아래 끝은 계속 자른다.
    static let dancheongLift: CGFloat = 32

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(nsImage: SettingsArtwork.knots)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 94, height: 116)
                    .padding(.trailing, 12)
                    .padding(.top, 4)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                Image(nsImage: SettingsArtwork.dancheong)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: Self.dancheongSize, height: Self.dancheongSize)
                    // 오른쪽 끝은 구분선에 유지하고, 크기/가로 위치 변화 없이 세로로만 올린다.
                    .offset(x: SettingsLayout.sidebarWidth - Self.dancheongSize,
                        y: Self.dancheongSize / 2 - Self.dancheongLift)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipped()
    }
}

private enum SettingsArtwork {
    static let knots = bundledImage("SettingsKnotPair")
    static let dancheong = bundledImage("SettingsDancheongRosette")

    private static func bundledImage(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }
}

/// 큰 구획 이름에만 손글씨를 사용한다. 작은 설명·목록·입력란의 읽기 속도를 보존한다.
struct HaneulSettingsSection<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        Section {
            content
                .font(SettingsTypography.control)
                .controlSize(.large)
        } header: {
            Text(title).font(OnboardingHandwriting.font(size: 27))
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
                .textCase(nil)
        }
    }
}

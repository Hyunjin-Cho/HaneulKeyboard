import SwiftUI

/// 2026-10-10 (#88): Studio Display에서 읽기 쉽게 설명 14pt / 항목 17pt로 구분한다.
enum SettingsTypography {
    static let body = Font.system(size: 14, weight: .regular)
    static let control = Font.system(size: 17, weight: .semibold)
    // 2026-10-11 (#88): 번호는 둥근 일반체로 표시해 항목 이름과 무게를 구분한다.
    static let version = Font.system(size: 17, weight: .regular, design: .rounded)
    // 2026-11-08 오너(#209): 색·아이콘이 붙은 상태 줄은 같은 17pt여도 커 보인다. 2pt 줄였다.
    static let status = Font.system(size: 15, weight: .semibold)
}

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 160
    /// 위 정물 띠 높이. 그림은 800×128pt @2x다. 메뉴 다섯 장 + 어두운 판 다섯 장.
    static let bandHeight: CGFloat = 128
}

/// 2026-11-05 오너 결정(#135): 설정은 안내 장면을 다시 쓰지 않고 메뉴마다 따로 찍은 리소 정물을 위 띠에 놓는다.
/// 움직이지 않고 사람도 없다. 구석의 매듭·단청과 손글씨 머리글은 지저분해 보여 뺐다.
/// 그림 원본은 비공개 haneul-art `settings/stills.py`다.
/// 2026-11-07 오너(#190): 어두운 화면에서 띠만 너무 밝았다. 어두운 한지에 흰 밑판을 깔고 찍은 판을 따로 쓴다. 안내 무대는 밝은 채로 둔다(오너 결정).
struct SettingsBand: View {
    let tab: SettingsTab
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(nsImage: SettingsArtwork.band(for: tab, dark: scheme == .dark))
            .resizable().interpolation(.high)
            .frame(height: SettingsLayout.bandHeight)
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("하늘키보드 설정").font(.system(size: 13, weight: .medium))
                    Text(tab.title).font(OnboardingRiso.titleFont(size: 31))
                }
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
                .padding(.leading, 26).padding(.top, 18)
                .accessibilityElement(children: .combine)
            }
            .clipped()
    }
}

/// 2026-11-07 오너(#189): 왼쪽 메뉴 아래가 비어 있어 등잔걸이 정물을 왼쪽·아래 창 가장자리에 붙였다(시안 A).
/// 그림 원본 haneul-art `settings/extras.py`. 창의 y 470~720 자리 한지에 찍어 이음매가 없다.
struct SettingsFoot: View {
    static let size = NSSize(width: 160, height: 250)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(nsImage: SettingsArtwork.foot(dark: scheme == .dark))
            .resizable().interpolation(.high)
            .frame(width: Self.size.width, height: Self.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum SettingsArtwork {
    @MainActor private static let shelf = WindowArtShelf()

    @MainActor static func band(for tab: SettingsTab, dark: Bool) -> NSImage {
        dark
            ? shelf.image("dark-\(tab.bandName)") { bundledImage("SettingsBandDark_\(tab.bandName)") }
            : shelf.image(tab.bandName) { bundledImage("SettingsBand_\(tab.bandName)") }
    }

    @MainActor static func foot(dark: Bool) -> NSImage {
        let name = dark ? "SettingsFootDark" : "SettingsFoot"
        return shelf.image(name) { bundledImage(name) }
    }

    private static func bundledImage(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }
}

private extension SettingsTab {
    var bandName: String {
        switch self {
        case .automatic: return "input"
        case .shortcuts: return "shortcuts"
        case .personalDictionary: return "dictionary"
        case .update: return "update"
        case .appManagement: return "app"
        }
    }
}

/// 2026-11-05 (#135): 구획 이름은 안내 제목과 같은 고운바탕이다(그 전에는 손글씨). 설명·목록·입력란은 시스템 글꼴을 유지한다.
struct HaneulSettingsSection<Content: View>: View {
    /// 2026-11-07 (#189): 위 띠 제목과 같은 말이면 구획 제목을 뺀다(nil).
    let title: String?
    /// 2026-11-08 오너(#201): 되돌릴 수 없는 구획(전체 제거)은 제목을 빨갛게 쓴다. nil이면 잉크색.
    let titleColor: Color?
    let content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String? = nil, titleColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleColor = titleColor
        self.content = content()
    }
    var body: some View {
        Section {
            content
                .font(SettingsTypography.control)
                .controlSize(.large)
        } header: {
            if let title {
                Text(title).font(OnboardingRiso.titleFont(size: 20))
                    .foregroundStyle(titleColor ?? OnboardingRiso.ink(for: scheme))
                    .textCase(nil)
            }
        }
    }
}

/// 2026-11-07 (#189): 토글과 설명을 한 행으로 합친다. 구분선이 둘을 갈라 설명이 다른 항목처럼 보였고, 항목당 높이도 컸다.
struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(SettingsTypography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

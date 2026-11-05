import SwiftUI

/// 2026-10-10 (#88): Studio Display에서 읽기 쉽게 설명 14pt / 항목 17pt로 구분한다.
enum SettingsTypography {
    static let body = Font.system(size: 14, weight: .regular)
    static let control = Font.system(size: 17, weight: .semibold)
    // 2026-10-11 (#88): 번호는 둥근 일반체로 표시해 항목 이름과 무게를 구분한다.
    static let version = Font.system(size: 17, weight: .regular, design: .rounded)
}

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 160
    /// 위 정물 띠 높이. 그림은 800×128pt @2x다.
    static let bandHeight: CGFloat = 128
}

/// 2026-11-05 오너 결정(#135): 설정은 안내 장면을 다시 쓰지 않고 메뉴마다 따로 찍은 리소 정물을 위 띠에 놓는다.
/// 움직이지 않고 사람도 없다. 구석의 매듭·단청과 손글씨 머리글은 지저분해 보여 뺐다.
/// 그림 원본은 비공개 haneul-art `settings/stills.py`다. 띠는 종이 그림이라 어두운 화면에서도 그대로 밝다(안내 무대와 같다).
struct SettingsBand: View {
    let tab: SettingsTab
    var body: some View {
        Image(nsImage: SettingsArtwork.band(for: tab))
            .resizable().interpolation(.high)
            .frame(height: SettingsLayout.bandHeight)
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("하늘키보드 설정").font(.system(size: 13, weight: .medium))
                    Text(tab.title).font(OnboardingRiso.titleFont(size: 31))
                }
                .foregroundStyle(OnboardingRiso.ink(for: .light))
                .padding(.leading, 26).padding(.top, 18)
                .accessibilityElement(children: .combine)
            }
            .clipped()
    }
}

private enum SettingsArtwork {
    private static let bands: [SettingsTab: NSImage] = Dictionary(uniqueKeysWithValues: SettingsTab.allCases.map {
        ($0, bundledImage("SettingsBand_\($0.bandName)"))
    })

    static func band(for tab: SettingsTab) -> NSImage { bands[tab] ?? NSImage(size: NSSize(width: 1, height: 1)) }

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
        case .inputFeatures: return "input"
        case .personalDictionary: return "dictionary"
        case .update: return "update"
        case .appManagement: return "app"
        }
    }
}

/// 2026-11-05 (#135): 구획 이름은 안내 제목과 같은 고운바탕이다(그 전에는 손글씨). 설명·목록·입력란은 시스템 글꼴을 유지한다.
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
            Text(title).font(OnboardingRiso.titleFont(size: 20))
                .foregroundStyle(OnboardingRiso.ink(for: scheme))
                .textCase(nil)
        }
    }
}

import AppKit
import SwiftUI

/// 2026-10-11 (#20, #29, #88): 설정의 독립 응원 버튼과 메뉴바가 같은 안내를 쓴다.
/// 2026-11-07 (#20): 후원을 GitHub Sponsors로 연결했다(오너가 주소를 대조했다). 앱은 기본 브라우저로 후원 페이지만 연다.
/// 후원 여부는 기능에 영향이 없고, 앱이 후원자나 결제 정보를 알 길도 없다.
struct SupportView: View {
    static let title = "하늘키보드 응원하기"
    /// 위 그림 크기. 그림은 이 크기 @2x로 창 바탕 한지 왼쪽 위 조각에 찍었다(앱이 같은 타일을 왼쪽 위부터 깔아 이음매가 없다).
    static let size = NSSize(width: 520, height: 148)
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var openFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: SupportArtwork.band(dark: scheme == .dark))
                .resizable().interpolation(.high)
                .frame(width: Self.size.width, height: Self.size.height)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.title).font(OnboardingRiso.titleFont(size: 24))
                    .foregroundStyle(OnboardingRiso.ink(for: scheme))
                Text("하늘키보드는 무료예요. 후원해도 안 해도 기능은 똑같아요.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("도움이 되었다면 GitHub Sponsors에서 응원해 주세요.\n한 번만 또는 매달 후원할 수 있고, GitHub 계정이 필요해요.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SupportLink.displayAddress)
                    .font(AppFont.font(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if openFailed {
                    Text("브라우저를 열지 못했어요.\n위 주소를 복사해 브라우저에 붙여 넣어 주세요.")
                        .foregroundStyle(FeedbackStatus.warning.color(in: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("닫기", action: onClose)
                        .buttonStyle(OnboardingRisoButtonStyle(prominent: false))
                        .keyboardShortcut(.cancelAction)
                    Button("GitHub에서 후원하기") {
                        openFailed = !NSWorkspace.shared.open(SupportLink.sponsors)
                    }
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .font(AppFont.font(size: 14))
            .lineSpacing(3)  // 2026-11-08 (#209): 마루부리는 줄 사이가 좁다.
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
        }
        .frame(width: Self.size.width)
        .haneulWindowAppearance()
    }
}

/// 설정 띠와 같은 선반을 쓴다. 창을 닫으면 그림이 메모리에서 빠진다(#156).
private enum SupportArtwork {
    @MainActor private static let shelf = WindowArtShelf()

    @MainActor static func band(dark: Bool) -> NSImage {
        let name = dark ? "SupportBandDark" : "SupportBand"
        return shelf.image(name) {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
            return image
        }
    }
}

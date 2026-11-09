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
    /// 브라우저로 열지 못한 후원처. nil이면 문제없음.
    @State private var openFailed: SupportChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: SupportArtwork.band(dark: scheme == .dark))
                .resizable().interpolation(.high)
                .frame(width: Self.size.width, height: Self.size.height)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                // 2026-11-09 오너(#216): 제목 → 문장, 문장 → 문장은 6pt(앱 전체 규칙). 예전엔 12pt라 두 문장이 다른 문단처럼 떨어져 보였다.
                VStack(alignment: .leading, spacing: AppFont.lineSpacing) {
                    Text(Self.title).font(OnboardingRiso.titleFont(size: 24))
                        .foregroundStyle(OnboardingRiso.ink(for: scheme))
                    Text("하늘키보드는 무료예요. 후원해도 안 해도 기능은 똑같아요.")
                        .fixedSize(horizontal: false, vertical: true)
                    // 2026-11-08 오너(#20): A안 — 후원처를 목록으로 똑같이 보여 준다(B안 'GitHub 중심 + 다른 방법 한 줄'은 반려).
                    Text("도움이 되었다면 편한 곳에서 응원해 주세요.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    ForEach(SupportLink.channels) { channel in channelRow(channel) }
                }
                if let failed = openFailed {
                    // 주소 줄을 따로 두지 않으므로, 열지 못했을 때 복사할 주소를 여기 보인다.
                    Text("브라우저를 열지 못했어요.\n이 주소를 브라우저에 붙여 넣어 주세요: \(failed.displayAddress)")
                        .foregroundStyle(FeedbackStatus.warning.color(in: scheme))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("닫기", action: onClose)
                        .buttonStyle(OnboardingRisoButtonStyle(prominent: false))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            .font(AppFont.font(size: 14))
            .lineSpacing(AppFont.lineSpacing)
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
        }
        .frame(width: Self.size.width)
        .haneulWindowAppearance()
    }

    private func channelRow(_ channel: SupportChannel) -> some View {
        HStack(spacing: 12) {
            // 2026-11-09 (#216): 이름 → 설명도 설정 토글 행과 같은 6pt.
            VStack(alignment: .leading, spacing: AppFont.lineSpacing) {
                Text(channel.name).font(AppFont.font(size: 15, weight: .semibold))
                Text(channel.detail).font(AppFont.font(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("후원하기") {
                openFailed = NSWorkspace.shared.open(channel.url) ? nil : channel
            }
            .buttonStyle(OnboardingRisoButtonStyle(prominent: true))
            .accessibilityLabel("\(channel.name)에서 후원하기")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
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

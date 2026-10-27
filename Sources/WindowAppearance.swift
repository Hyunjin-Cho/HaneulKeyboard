import AppKit
import SwiftUI

extension View {
    func haneulWindowAppearance() -> some View { modifier(WindowAppearanceModifier()) }
}

private struct WindowAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            // 2026-10-10: 사용자 선택으로 불투명 종이 한 가지를 공유한다.
            // 과거 haneul.windowAppearance 저장 값은 더 이상 읽지 않는다.
            OnboardingRisoPaper()
                .background(WindowSurface())
                .ignoresSafeArea()
        }
    }
}

private struct WindowSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSurfaceView { WindowSurfaceView() }
    func updateNSView(_ view: WindowSurfaceView, context: Context) { view.updateWindow() }
}

/// 배경만 바꾼다. 입력 뷰/SwiftUI 루트를 다시 만들지 않아 조합·커서·선택한 탭을 유지한다.
private final class WindowSurfaceView: NSView {
    override var isOpaque: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindow()
    }

    func updateWindow() {
        window?.isOpaque = true
        window?.backgroundColor = .windowBackgroundColor
        // 일반 제목 막대는 시스템 배경을 유지해 닫기 버튼을 선명하게 보인다.
        // 전체 콘텐츠가 제목 막대를 덮는 안내/알림 창은 종이를 그 위까지 그린다.
        window?.titlebarAppearsTransparent = window?.styleMask.contains(.fullSizeContentView) ?? false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

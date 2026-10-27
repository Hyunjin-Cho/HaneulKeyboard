import AppKit
import SwiftUI

/// 2026-10-07 (#80): 제목 막대까지 하나의 유리 표면으로 그린다.
/// safeAreaRegions를 비워 제목 막대 높이가 800pt에 다시 더해지는 것을 방지한다.
@MainActor
enum OnboardingWindow {
    static func make(rootView: OnboardingView) -> NSWindow {
        var rootView = rootView
        let available = NSScreen.main?.visibleFrame.size ?? OnboardingView.size
        let size = NSSize(width: min(OnboardingView.size.width, available.width - 32),
                          height: min(OnboardingView.size.height, available.height - 32))
        rootView.windowSize = size
        let hosting = NSHostingView(rootView: rootView)
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "하늘키보드 시작하기"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

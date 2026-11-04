import AppKit
import SwiftUI

/// 2026-10-07 (#80): 제목 막대까지 하나의 유리 표면으로 그린다.
/// safeAreaRegions를 비워 제목 막대 높이가 800pt에 다시 더해지는 것을 방지한다.
@MainActor
enum OnboardingWindow {
    static func make(rootView: OnboardingView) -> NSWindow {
        var rootView = rootView
        let available = NSScreen.main?.visibleFrame.size ?? OnboardingView.size
        // 2026-11-03 (#115): 높이는 정해 둔 크기(900·780) 중 화면에 들어가는 큰 쪽. 둘 다 안 들어가는 화면만 남는 높이를 쓴다.
        let room = available.height - 32
        let height = OnboardingView.presetHeights.first { $0 <= room } ?? room
        let size = NSSize(width: min(OnboardingView.size.width, available.width - 32), height: height)
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

import AppKit
import SwiftUI

/// 실제 메뉴바 앱과 독립 화면 검토에서 동일한 닫기 동작을 사용한다.
@MainActor
enum SupportWindow {
    static func make() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        let hosting = NSHostingController(rootView: SupportView { [weak window] in
            window?.close()
        })
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.title = SupportView.title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

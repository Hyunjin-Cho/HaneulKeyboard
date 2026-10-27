import AppKit
import SwiftUI

/// 2026-10-18: 활성 안내창에서만 좌우 이동. 입력칸의 문자 편집은 NSTextView가 처리한다.
struct OnboardingPageNavigation: NSViewRepresentable {
    var move: (Int) -> Void

    func makeNSView(context: Context) -> NavigationView {
        let view = NavigationView()
        view.move = move
        return view
    }

    func updateNSView(_ view: NavigationView, context: Context) { view.move = move }

    static func dismantleNSView(_ view: NavigationView, coordinator: Void) { view.stop() }

    final class NavigationView: NSView {
        var move: (Int) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event, applicationIsActive: NSApp.isActive, keyWindow: NSApp.keyWindow)
            }
        }

        func handle(_ event: NSEvent, applicationIsActive: Bool, keyWindow: NSWindow?) -> NSEvent? {
            guard let window, applicationIsActive, keyWindow === window, event.window === window,
                  event.type == .keyDown,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  event.keyCode == 123 || event.keyCode == 124 else { return event }
            // 2026-10-20: read-only selectable text must not block page navigation.
            // AppKit releases hidden/removed editors in the offscreen regression;
            // do not assume that a stale editor caused the reported missed keys.
            if let text = window.firstResponder as? NSText, text.isEditable,
               text.window === window, !text.isHiddenOrHasHiddenAncestor { return event }
            if !event.isARepeat { move(event.keyCode == 123 ? -1 : 1) }
            return nil
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

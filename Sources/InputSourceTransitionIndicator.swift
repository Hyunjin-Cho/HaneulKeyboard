import AppKit
import Carbon

extension Notification.Name {
    static let haneulInputSourceIndicatorPreferencesChanged =
        Notification.Name("haneul.inputSourceIndicatorPreferencesChanged")
}

/// #81 · 2026-10-12: 메인 앱의 기존 TIS 알림으로 띄우는, 입력 포커스를 받지 않는 짧은 안내.
/// 캐럿 조회/IMK IPC/키 감시/입력 합성을 하지 않는다. 시스템 파란 HUD 자체와 별개다.
@MainActor
final class InputSourceTransitionIndicator {
    private var policy: InputSourceTransitionPolicy
    private var panel: InputSourceIndicatorPanel?
    private var expiryTask: Task<Void, Never>?

    init(currentSourceID: String?) {
        policy = InputSourceTransitionPolicy(haneulSourceID: InputSwitcher.koreanModeID,
                                             currentSourceID: currentSourceID)
    }

    func sourceDidChange(to sourceID: String?, isPreparingIME: Bool) {
        let action = policy.observe(sourceID: sourceID,
                                    enabled: InputSourceTransitionPolicy.isEnabled(in: .standard),
                                    secureInput: IsSecureEventInputEnabled(),
                                    isPreparingIME: isPreparingIME)
        switch action {
        case .unchanged:
            break
        case .hide:
            hidePanel()
        case .showHaneul(let token):
            guard let screen = screenForIndicator() else { dismiss(); return }
            expiryTask?.cancel()
            let display = panel ?? InputSourceIndicatorPanel()
            panel = display
            let frame = screen.visibleFrame
            let size = InputSourceIndicatorPanel.indicatorSize
            display.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                           y: frame.maxY - size.height - 18))
            // canBecomeKey/Main=false, nonactivatingPanel, ignoresMouseEvents=true.
            // activate/makeKeyAndOrderFront는 입력 포커스를 바꾸므로 호출하지 않는다.
            display.orderFrontRegardless()
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(900)) }
                catch { return }
                guard !Task.isCancelled, let self, self.policy.expire(token: token) else { return }
                self.hidePanel()
            }
        }
    }

    func preferencesDidChange() {
        if !InputSourceTransitionPolicy.isEnabled(in: .standard) { dismiss() }
    }

    func dismiss() {
        policy.cancelPendingDisplay()
        hidePanel()
    }

    private func hidePanel() {
        expiryTask?.cancel()
        expiryTask = nil
        panel?.orderOut(nil)
    }

    private func screenForIndicator() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }

    deinit { expiryTask?.cancel() }
}

/// Offscreen 검사도 제품과 같은 패널/글자를 사용한다.
@MainActor
final class InputSourceIndicatorPanel: NSPanel {
    static let indicatorSize = NSSize(width: 84, height: 36)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.indicatorSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none // 움직임 줄이기 설정과 무관하게 위치·크기 애니메이션 없음.

        let content = NSView(frame: NSRect(origin: .zero, size: Self.indicatorSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemBlue.cgColor
        content.layer?.cornerRadius = Self.indicatorSize.height / 2
        let label = NSTextField(labelWithString: "하늘")
        label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityLabel("하늘키보드 한국어 입력기로 전환됨")
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
        ])
        contentView = content
    }
}

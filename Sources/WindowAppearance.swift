import AppKit
import SwiftUI

/// 2026-10-07 (#80): 메인 앱의 세 안내 창이 공유하는 저장 설정. IME 입력 설정과 분리한다.
enum WindowAppearance: String, CaseIterable {
    case glass
    case solid
    static let defaultsKey = "haneul.windowAppearance"
}

extension View {
    func haneulWindowAppearance() -> some View { modifier(WindowAppearanceModifier()) }
}

private struct WindowAppearanceModifier: ViewModifier {
    @AppStorage(WindowAppearance.defaultsKey) private var appearance = WindowAppearance.glass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var usesGlass: Bool { appearance == .glass && !reduceTransparency }

    func body(content: Content) -> some View {
        content.background {
            WindowSurface(usesGlass: usesGlass)
                .overlay {
                    // 2026-10-07 (#80): 유리의 블러·굴절은 유지하고 배경 면만 한 톤 낮춘다.
                    // 본문/버튼 위에 씌우지 않으며 다크 모드에서는 더 약하게 적용한다.
                    if usesGlass {
                        Color.black.opacity(colorScheme == .dark ? 0.04 : 0.08)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .ignoresSafeArea()
        }
    }
}

private struct WindowSurface: NSViewRepresentable {
    let usesGlass: Bool
    func makeNSView(context: Context) -> WindowSurfaceView { WindowSurfaceView() }
    func updateNSView(_ view: WindowSurfaceView, context: Context) { view.configure(usesGlass: usesGlass) }
}

/// 배경만 바꾼다. 입력 뷰/SwiftUI 루트를 다시 만들지 않아 조합·커서·선택한 탭을 유지한다.
private final class WindowSurfaceView: NSView {
    private var usesGlass = false
    private var backdrop: NSView?
    override var isOpaque: Bool { !usesGlass }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(usesGlass: Bool) {
        guard self.usesGlass != usesGlass else { return }
        self.usesGlass = usesGlass
        if usesGlass {
            let backdrop: NSView
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = .regular
                glass.tintColor = nil
                glass.cornerRadius = 20
                backdrop = glass
            } else {
                let effect = NSVisualEffectView(frame: bounds)
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
                backdrop = effect
            }
            backdrop.autoresizingMask = [.width, .height]
            // 2026-10-07: 밝은 underWindow 재질 위에 Glass를 겹치지 않는다.
            // Clear는 활성 창에서 배경 무늬가 그대로 보여 본문 가독성을 해친다.
            // Regular 한 겹으로 색은 받아들이되 세부 무늬는 가린다. 별도 흰 덮개는 두지 않는다.
            addSubview(backdrop)
            self.backdrop = backdrop
        } else {
            backdrop?.removeFromSuperview()
            backdrop = nil
        }
        updateWindow()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindow()
    }

    private func updateWindow() {
        window?.isOpaque = !usesGlass
        window?.backgroundColor = usesGlass ? .clear : .windowBackgroundColor
        window?.titlebarAppearsTransparent = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if !usesGlass {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}

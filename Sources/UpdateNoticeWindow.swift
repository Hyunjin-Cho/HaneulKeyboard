import AppKit
import SwiftUI

/// 실제 업데이트 감지와 화면 검토에서 공유하는 안내창. 다른 창의 동작을 막지 않는다.
@MainActor
enum UpdateNoticeWindow {
    static func make(version: String, currentVersion: String, onShowUpdate: @escaping () -> Void) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: UpdateNoticeView(
            version: version, currentVersion: currentVersion,
            onLater: { [weak window] in window?.close() },
            onShowUpdate: { [weak window] in
                window?.close()
                onShowUpdate()
            }))
        // Glass가 창 배경을 clear로 만들므로 제목 막대도 콘텐츠로 덮는다.
        // 기본 제목 막대만 남기면 닫기 버튼 뒤로 바탕화면이 그대로 비친다.
        hosting.safeAreaRegions = []
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.title = "하늘키보드 업데이트"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// SwiftUI 내용 뒤의 빈 공간만 이동 손잡이로 쓴다. macOS 14에서도 같은 경로다.
private struct UpdateNoticeDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private struct UpdateNoticeDragging: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents()
        } else {
            content.background(UpdateNoticeDragArea().accessibilityHidden(true))
        }
    }
}

private struct UpdateNoticeView: View {
    let version: String
    let currentVersion: String
    let onLater: () -> Void
    let onShowUpdate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("새로운 하늘키보드가 나왔어요")
                .font(.system(size: 21, weight: .semibold))
            HStack(spacing: 32) {
                VStack(spacing: 5) {
                    Text("현재 버전").font(.system(size: 13))
                    Text(currentVersion).font(.system(size: 17, weight: .semibold))
                }
                Image(systemName: "arrow.right").accessibilityHidden(true)
                VStack(spacing: 5) {
                    Text("새 버전").font(.system(size: 13))
                    Text(version).font(.system(size: 17, weight: .semibold))
                }
            }
            Text("업데이트 내용을 확인하고\n원할 때 새 버전을 설치해 주세요.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("나중에", action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button("업데이트 보기", action: onShowUpdate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.top, 16)
        .padding(28)
        .frame(width: 420)
        .modifier(UpdateNoticeDragging())
        .haneulWindowAppearance()
    }
}

import AppKit

/// 실제 제품 패널을 화면에 띄우지 않고 검사한다. 입력 소스/설치/포커스는 바꾸지 않는다.
@main
enum InputSourceIndicatorPanelTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let panel = InputSourceIndicatorPanel()
        var count = 0
        func check(_ value: Bool, _ message: String) {
            guard value else { fatalError(message) }
            count += 1
        }
        check(!panel.isVisible, "Offscreen 패널")
        check(!panel.canBecomeKey, "키보드 포커스를 받지 않음")
        check(!panel.canBecomeMain, "기존 앱의 메인 창 유지")
        check(panel.styleMask.contains(.nonactivatingPanel), "앱을 활성화하지 않는 스타일")
        check(panel.ignoresMouseEvents, "마우스 입력을 가로채지 않음")
        check(panel.animationBehavior == .none, "위치·크기 애니메이션 없음")
        check(panel.collectionBehavior.contains(.fullScreenAuxiliary), "전체 화면 보조 표시")
        check(panel.collectionBehavior.contains(.canJoinAllSpaces), "작업 공간 보조 표시")
        check(panel.frame.size == NSSize(width: 84, height: 36), "고정된 짧은 안내")
        let content = panel.contentView!
        content.layoutSubtreeIfNeeded()
        let label = content.subviews.compactMap { $0 as? NSTextField }.first!
        check(label.stringValue == "하늘", "보이는 글자")
        check(!label.isEditable && !label.isSelectable, "입력 불가능한 라벨")
        check(label.textColor == .white, "파란 바탕에 흰 글자")
        check(label.frame.width >= label.intrinsicContentSize.width, "글자 가로 잘림 없음")
        check(label.frame.height >= label.intrinsicContentSize.height, "글자 세로 잘림 없음")
        check(NSApp.keyWindow == nil, "숨겨진 검사로 포커스 변동 없음")
        if CommandLine.arguments.count > 1 {
            let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                panel.appearance = NSAppearance(named: appearance)
                content.displayIfNeeded()
                let image = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: image)
                let png = image.representation(using: .png, properties: [:])!
                try png.write(to: destination.appendingPathComponent("indicator-\(name).png"))
            }
        }
        print("Input source indicator panel: \(count) passed, 0 failed (offscreen)")
    }
}

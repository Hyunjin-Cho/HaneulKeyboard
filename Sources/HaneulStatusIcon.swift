import AppKit

/// 2026-10-09: 메뉴바와 안내 화면이 사용자 확정 처마/ㅎ 원본을 공유한다.
enum HaneulStatusIcon {
    static let image: NSImage = {
        let image = NSImage(named: "HaneulRoofTemplate")
            ?? Bundle.main.url(forResource: "HaneulRoofTemplate", withExtension: "png")
                .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "하늘키보드")!
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        image.accessibilityDescription = "하늘키보드"
        return image
    }()
}

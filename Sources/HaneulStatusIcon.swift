import AppKit

/// 2026-10-09: 메뉴바와 안내 화면이 사용자 확정 처마/ㅎ 원본을 공유한다.
enum HaneulStatusIcon {
    static let image: NSImage = {
        let image = NSImage(named: "HaneulRoofTemplate")
            ?? Bundle.main.url(forResource: "HaneulRoofTemplate", withExtension: "png")
                .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "하늘키보드")!
        // 2026-11-07 오너(#188): 다른 메뉴바 아이콘보다 커서 20% 줄였다(높이 41px → 34px @2x, 옆 Claude 아이콘 32px).
        // 칸도 22pt → 18pt다. 그림은 이 크기의 화소 칸에 맞춰 다시 찍은 것이라 크기만 바꾸면 선이 뭉개진다(원본: 비공개 haneul-art G6).
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "하늘키보드"
        return image
    }()
}

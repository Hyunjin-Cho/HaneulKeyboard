import AppKit
import CoreText
import Foundation

// 2026-10-09. Reproducible monochrome UI assets. Run from the repository root.
// The colorful Dock/app icon is a separate resource and is not modified here.
// --menu-only exports the approved roof/ㅎ PNG without changing input-source glyphs.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let menuDirectory = root.appendingPathComponent("Resources/MenuBar")
let inputDirectory = root.appendingPathComponent("Resources/IM")
try FileManager.default.createDirectory(at: menuDirectory, withIntermediateDirectories: true)
let menuSource = root.appendingPathComponent("Resources/Brand/HaneulKeyboard_Menu_Icon_2@2x.png")
guard let menuIcon = NSImage(contentsOf: menuSource) else {
    fatalError("Could not load the approved menu icon")
}

func bitmap(size: NSSize, scale: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                              pixelsHigh: Int(size.height) * scale, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    graphics.imageInterpolation = .high
    NSGraphicsContext.current = graphics
    let cg = graphics.cgContext
    // NSGraphicsContext uses rep.size to apply the Retina scale already.
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: url)
    print("\(url.lastPathComponent): \(rep.pixelsWide)×\(rep.pixelsHigh)")
}

for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    let menuSize = NSSize(width: 22, height: 22)
    let menu = bitmap(size: menuSize, scale: scale) { _ in
        menuIcon.draw(in: NSRect(origin: .zero, size: menuSize), from: .zero, operation: .sourceOver, fraction: 1)
    }
    let menuOutput = menuDirectory.appendingPathComponent("HaneulRoofTemplate\(suffix).png")
    if scale == 2 {
        // Preserve the user's hand-prepared 44×44 Retina icon byte-for-byte.
        try Data(contentsOf: menuSource).write(to: menuOutput)
        print("\(menuOutput.lastPathComponent): 44×44 (user original)")
    } else {
        try save(menu, to: menuOutput)
    }
    if CommandLine.arguments.contains("--menu-only") { continue }

    // Two glyphs need more horizontal room than one A. Keep the baseline and
    // height centered, fully opaque, and use the native Korean bold font.
    let inputSize = NSSize(width: 22, height: 16)
    for (name, white) in [("HaneulInputTemplate", false), ("HaneulInputSelected", true)] {
        let rep = bitmap(size: inputSize, scale: scale) { cg in
            let font = CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, 10.5, nil)
            let color = CGColor(gray: white ? 1 : 0, alpha: 1)
            let attributed = NSAttributedString(string: "하늘", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            cg.textPosition = CGPoint(x: (inputSize.width - bounds.width) / 2 - bounds.minX,
                                      y: (inputSize.height - bounds.height) / 2 - bounds.minY)
            CTLineDraw(line, cg)
        }
        try save(rep, to: inputDirectory.appendingPathComponent("\(name)\(suffix).png"))
    }
}

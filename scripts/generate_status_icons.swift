import AppKit
import CoreText
import Foundation

// 2026-10-20. Reproducible monochrome input-source glyphs. Run from the repository root.
// The colorful Dock/app icon is a separate resource and is not modified here.
// --palette-only exports only the plain black reference and bright white palette glyph.
// 2026-11-08 (#214): the menu bar roof icon is no longer made here. It comes from the private
// haneul-art repo (icon-b/src/menubar_glyph.py, approved G6). Running this script with no option
// used to overwrite Resources/MenuBar with the old Resources/Brand roof, so that part and the
// Resources/Brand dependency were removed. --input-only is still accepted and means the default.
if CommandLine.arguments.contains("--menu-only") {
    fatalError("The menu bar icon comes from haneul-art icon-b/src/menubar_glyph.py, not this script.")
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let inputDirectory = root.appendingPathComponent("Resources/IM")

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

func inputGlyph(scale: Int, white: Bool) -> NSBitmapImageRep {
    let size = NSSize(width: 22, height: 16)
    return bitmap(size: size, scale: scale) { cg in
        let font = CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, 10.5, nil)
        let attributed = NSAttributedString(string: "하늘", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: white ? 1 : 0, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        cg.textPosition = CGPoint(x: (size.width - bounds.width) / 2 - bounds.minX,
                                  y: (size.height - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, cg)
    }
}

for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    // #81: preserve b52–62's transparent background and opaque glyph shape.
    for (name, white) in [("HaneulInputPalette", false), ("HaneulInputPaletteWhite", true)] {
        let palette = inputGlyph(scale: scale, white: white)
        try save(palette, to: inputDirectory.appendingPathComponent("\(name)\(suffix).png"))
    }
    if CommandLine.arguments.contains("--palette-only") { continue }

    // 2026-10-20: macOS can reuse the menu template in the blue Caps Lock HUD.
    // Only the letters may be opaque: a filled badge becomes a white rectangle.
    // Match the palette's 22×16 pt glyph; the system tints it for the HUD/menu.
    for (name, white) in [("HaneulInputTemplate", false), ("HaneulInputSelected", true)] {
        let rep = inputGlyph(scale: scale, white: white)
        try save(rep, to: inputDirectory.appendingPathComponent("\(name)\(suffix).png"))
    }
}

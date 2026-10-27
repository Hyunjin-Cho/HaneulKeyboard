import AppKit
import CoreText
import Foundation

// 2026-10-12. Reproducible monochrome UI assets. Run from the repository root.
// The colorful Dock/app icon is a separate resource and is not modified here.
// --menu-only exports the roof/ㅎ PNG without changing input-source glyphs.
// --palette-only exports the plain black reference and bright white palette glyph.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let menuDirectory = root.appendingPathComponent("Resources/MenuBar")
let inputDirectory = root.appendingPathComponent("Resources/IM")
try FileManager.default.createDirectory(at: menuDirectory, withIntermediateDirectories: true)
let menuSource = root.appendingPathComponent("Resources/Brand/HaneulKeyboard_Menu_Icon_2@2x.png")
guard let menuIcon = NSImage(contentsOf: menuSource) else {
    fatalError("Could not load the approved menu icon")
}
guard let sourceCG = menuIcon.cgImage(forProposedRect: nil, context: nil, hints: nil),
      sourceCG.width == 44, sourceCG.height == 44,
      let roofCG = sourceCG.cropping(to: CGRect(x: 0, y: 0, width: 44, height: 22)),
      let letterCG = sourceCG.cropping(to: CGRect(x: 19, y: 21, width: 20, height: 21)) else {
    fatalError("Expected the approved 44×44 menu icon")
}
let roof = NSImage(cgImage: roofCG, size: NSSize(width: 22, height: 11))
let letter = NSImage(cgImage: letterCG, size: NSSize(width: 10, height: 10.5))

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
    if !CommandLine.arguments.contains("--menu-only") {
        // #81: preserve b52–62's transparent background and opaque glyph shape.
        // b75 uses a separate white glyph for the user's bright-on-blue request.
        // Keep the black reference and menu images unchanged; don't invert alpha.
        let paletteSize = NSSize(width: 22, height: 16)
        for (name, white) in [("HaneulInputPalette", false), ("HaneulInputPaletteWhite", true)] {
            let palette = bitmap(size: paletteSize, scale: scale) { cg in
                let font = CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, 10.5, nil)
                let attributed = NSAttributedString(string: "하늘", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: white ? 1 : 0, alpha: 1)
                ])
                let line = CTLineCreateWithAttributedString(attributed)
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                cg.textPosition = CGPoint(x: (paletteSize.width - bounds.width) / 2 - bounds.minX,
                                          y: (paletteSize.height - bounds.height) / 2 - bounds.minY)
                CTLineDraw(line, cg)
            }
            try save(palette, to: inputDirectory.appendingPathComponent("\(name)\(suffix).png"))
        }
    }
    if CommandLine.arguments.contains("--palette-only") { continue }
    let menuSize = NSSize(width: 22, height: 22)
    let menu = bitmap(size: menuSize, scale: scale) { _ in
        roof.draw(in: NSRect(x: 0, y: 11, width: 22, height: 11),
                  from: .zero, operation: .sourceOver, fraction: 1)
        // Keep the roof and original glyph center; reduce only ㅎ by one point.
        letter.draw(in: NSRect(x: 10, y: 1.5, width: 9, height: 9.5),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }
    let menuOutput = menuDirectory.appendingPathComponent("HaneulRoofTemplate\(suffix).png")
    try save(menu, to: menuOutput)
    if CommandLine.arguments.contains("--menu-only") { continue }

    // 2026-10-12: match the 22×16 pt input-mode assets measured in macOS 27's
    // KeyboardLayouts.framework/Resources/Assets.car (44×32 px at 2x).
    // Keep both syllables on one line; this asset does not configure the caret HUD.
    // The template variant lets macOS tint the badge for the current background.
    let inputSize = NSSize(width: 22, height: 16)
    for (name, white) in [("HaneulInputTemplate", false), ("HaneulInputSelected", true)] {
        let rep = bitmap(size: inputSize, scale: scale) { cg in
            cg.setFillColor(CGColor(gray: white ? 1 : 0, alpha: 1))
            cg.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: inputSize),
                              cornerWidth: 4, cornerHeight: 4, transform: nil))
            cg.fillPath()
            let font = CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, 10, nil)
            let color = CGColor(gray: 0, alpha: 1)
            let attributed = NSAttributedString(string: "하늘", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            cg.textPosition = CGPoint(x: (inputSize.width - bounds.width) / 2 - bounds.minX,
                                      y: (inputSize.height - bounds.height) / 2 - bounds.minY)
            cg.setBlendMode(.destinationOut)
            CTLineDraw(line, cg)
        }
        try save(rep, to: inputDirectory.appendingPathComponent("\(name)\(suffix).png"))
    }
}

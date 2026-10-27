import AppKit
import Foundation

/// 2026-10-10: 확정한 색동 보자기·작은 삼태극 위에 본문을 조판한다.
/// 실제 앱/Applications 아이콘과 이름은 Finder가 그리며 preview에만 합성한다.
@main @MainActor enum DMGArtwork {
    struct Caption: Decodable {
        let text: String
        let top, fontSize: CGFloat
    }
    struct Layout: Decodable {
        let canvasSize, windowSize: [CGFloat]
        let iconSize, textSize: CGFloat
        let appCenter, applicationsCenter: [CGFloat]
        let backgroundArtwork: String
        let subtitle, instruction: Caption
        let defaultVariant: String
        let variants: [String]
    }
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let ink = NSColor(calibratedRed: 33/255, green: 32/255, blue: 162/255, alpha: 1)

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: dmg-artwork OUTPUT_DIRECTORY saekdong|all")
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: root.appendingPathComponent("Resources/Installer/layout.json")))
        let requested = CommandLine.arguments[2]
        guard requested == "all" || layout.variants.contains(requested) else { exit(2) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for variant in requested == "all" ? layout.variants : [requested] {
            for scale in [1, 2] {
                let bitmap = try render(layout: layout, scale: scale, preview: false)
                let suffix = scale == 1 ? "" : "@2x"
                try png(bitmap).write(to: output.appendingPathComponent("\(variant)\(suffix).png"))
            }
            try png(render(layout: layout, scale: 2, preview: true)).write(to: output.appendingPathComponent("\(variant)-preview.png"))
            print("\(variant): \(Int(layout.canvasSize[0]))×\(Int(layout.canvasSize[1]))pt, 1x/2x + preview")
        }
    }

    static func png(_ bitmap: NSBitmapImageRep) throws -> Data {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    static func render(layout: Layout, scale: Int, preview: Bool) throws -> NSBitmapImageRep {
        let width = layout.canvasSize[0], height = layout.canvasSize[1]
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
            pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = NSSize(width: width, height: height)
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        graphics.imageInterpolation = .high
        NSGraphicsContext.current = graphics
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x, y: height - y - h, width: w, height: h)
        }
        let artworkURL = root.appendingPathComponent("Resources/Installer").appendingPathComponent(layout.backgroundArtwork)
        guard let artwork = NSImage(contentsOf: artworkURL) else { throw CocoaError(.fileReadCorruptFile) }
        artwork.draw(in: rect(0, 0, width, height), from: .zero, operation: .copy, fraction: 1)

        for caption in [layout.subtitle, layout.instruction] {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: caption.fontSize, weight: .medium), .foregroundColor: ink
            ]
            let size = (caption.text as NSString).size(withAttributes: attributes)
            precondition(size.width < width - 120, "DMG text overlaps the border: \(caption.text)")
            (caption.text as NSString).draw(at: NSPoint(x: (width - size.width)/2, y: height - caption.top - size.height), withAttributes: attributes)
        }

        if preview {
            guard let appIcon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let folder = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns")
                ?? NSWorkspace.shared.icon(forFile: "/Applications")
            for (image, point, label) in [(appIcon, layout.appCenter, "HaneulKeyboard"), (folder, layout.applicationsCenter, "Applications")] {
                image.draw(in: rect(point[0]-layout.iconSize/2, point[1]-layout.iconSize/2, layout.iconSize, layout.iconSize),
                           from: .zero, operation: .sourceOver, fraction: 1)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: layout.textSize), .foregroundColor: NSColor.black
                ]
                let size = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(in: rect(point[0]-size.width/2, point[1]+layout.iconSize/2+7, size.width+2, size.height), withAttributes: attributes)
            }
        }
        return bitmap
    }
}

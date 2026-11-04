import AppKit
import CoreText
import Foundation

/// 2026-10-10: 확정한 그림 위에 본문을 조판한다.
/// 실제 앱/Applications 아이콘과 이름은 Finder가 그리며 preview에만 합성한다.
/// 2026-11-04 (#89): layout.json을 변형(variant)별 설정으로 나눴다. 새 기본 = maeul(안내 리소 디자인을 이어받은 마을 어귀),
/// 옛 saekdong(색동 보자기)은 그대로 보존해 같은 명령으로 다시 만들 수 있다. 글줄마다 글꼴(번들 TTF)·굵기를 고른다.
@main @MainActor enum DMGArtwork {
    struct Caption: Decodable {
        let text: String
        let top, fontSize: CGFloat
        /// 저장소 안 TTF 이름(확장자 없이, Resources/Onboarding). 없으면 시스템 글꼴.
        let font: String?
        /// regular·medium·semibold·bold. 없으면 medium(2026-10-10 조판과 같다).
        let weight: String?
    }
    struct Variant: Decodable {
        let canvasSize, windowSize: [CGFloat]
        let iconSize, textSize: CGFloat
        let appCenter, applicationsCenter: [CGFloat]
        let backgroundArtwork: String
        let captions: [Caption]
    }
    struct Layout: Decodable {
        let defaultVariant: String
        let variants: [String: Variant]
    }
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let ink = NSColor(calibratedRed: 33/255, green: 32/255, blue: 162/255, alpha: 1)

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: dmg-artwork OUTPUT_DIRECTORY <variant>|all")
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: root.appendingPathComponent("Resources/Installer/layout.json")))
        let requested = CommandLine.arguments[2]
        guard requested == "all" || layout.variants[requested] != nil else { exit(2) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in requested == "all" ? layout.variants.keys.sorted() : [requested] {
            let variant = layout.variants[name]!
            for scale in [1, 2] {
                let bitmap = try render(variant, scale: scale, preview: false)
                let suffix = scale == 1 ? "" : "@2x"
                try png(bitmap).write(to: output.appendingPathComponent("\(name)\(suffix).png"))
            }
            try png(render(variant, scale: 2, preview: true)).write(to: output.appendingPathComponent("\(name)-preview.png"))
            print("\(name): \(Int(variant.canvasSize[0]))×\(Int(variant.canvasSize[1]))pt, 1x/2x + preview")
        }
    }

    static func png(_ bitmap: NSBitmapImageRep) throws -> Data {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// 번들 TTF를 이 프로세스에만 등록하고 글꼴을 만든다(시스템에 설치하지 않는다).
    static func font(for caption: Caption) throws -> NSFont {
        if let name = caption.font {
            let url = root.appendingPathComponent("Resources/Onboarding/\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let postScript = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }),
                  let font = NSFont(name: postScript, size: caption.fontSize) else { throw CocoaError(.fileReadCorruptFile) }
            return font
        }
        let weights: [String: NSFont.Weight] = ["regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold]
        guard let weight = weights[caption.weight ?? "medium"] else { throw CocoaError(.fileReadCorruptFile) }
        return NSFont.systemFont(ofSize: caption.fontSize, weight: weight)
    }

    static func render(_ layout: Variant, scale: Int, preview: Bool) throws -> NSBitmapImageRep {
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

        for caption in layout.captions {
            let attributes: [NSAttributedString.Key: Any] = [.font: try font(for: caption), .foregroundColor: ink]
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

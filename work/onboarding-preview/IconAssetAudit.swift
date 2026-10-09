import AppKit
import Foundation

// 2026-10-06. Read-only audit of source bitmap colors and glyph bounds.
for file in CommandLine.arguments.dropFirst() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
          let bitmap = NSBitmapImageRep(data: data) else { continue }
    var colors: [String: Int] = [:]
    var maxAlpha: CGFloat = 0
    var bounds = CGRect.null
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0 else { continue }
            maxAlpha = max(maxAlpha, c.alphaComponent)
            let rgb = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            colors[rgb, default: 0] += 1
            bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    print("\(file): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), bounds=\(bounds), maxAlpha=\(maxAlpha), RGB=\(colors.sorted { $0.value > $1.value }.prefix(4))")
}

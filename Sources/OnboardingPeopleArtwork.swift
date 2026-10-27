import AppKit

/// 2026-10-25 (#80): seven user-approved, independent poses for each person.
/// PNGs retain their approved square canvas. All21 use the same uniform inset;
/// no pose-dependent cropping, body deformation or motion interpolation.
/// Selection/order/hashes: Resources/Onboarding/HaneulApprovedPoses.json.
enum OnboardingPeopleArtwork {
    static let canvasSize = 512
    static let pageCount = 7

    static func pageIndex(_ page: Int) -> Int {
        min(max(page, 0), pageCount - 1)
    }

    static func resourceNames(for page: Int) -> [String] {
        let frame = String(format: "%02d", pageIndex(page) + 1)
        return ["HaneulPoseBob", "HaneulPoseMan", "HaneulPoseBraid"].map { $0 + frame }
    }

    static func people(page: Int = 0, resourceURL: (String) -> URL? = {
        Bundle.main.url(forResource: $0, withExtension: "png")
    }) -> [NSImage] {
        var people: [NSImage] = []
        for name in resourceNames(for: page) {
            guard let url = resourceURL(name),
                  let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let rendered = render(source) else { return [] }
            people.append(NSImage(cgImage: rendered, size: NSSize(width: 48, height: 48)))
        }
        return people
    }

    private static func render(_ source: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: canvasSize, height: canvasSize,
                bitsPerComponent: 8, bytesPerRow: canvasSize * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        let size = CGFloat(canvasSize)
        // Preserve the approved canvas and relative pose placement. A shared
        // 6% margin keeps raised hands and wide skirts inside the small scene.
        let factor = size * 0.88 / CGFloat(max(source.width, source.height))
        let width = CGFloat(source.width) * factor
        let height = CGFloat(source.height) * factor
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: (size - width) / 2, y: (size - height) / 2,
                                       width: width, height: height))
        return context.makeImage()
    }
}

import AppKit

/// 2026-10-14: 한 몸과 고정 길이 팔다리로 7개의 페이지 자세를 만든다.
/// 좌표는 0...1, 위쪽이 y=0이다. 자세를 바꿔도 몸·손·신발의 크기는 바뀌지 않는다.
enum OnboardingPersonRig {
    enum Woman: CaseIterable { case first, third }
    struct Chain {
        let root: CGPoint
        let joint: CGPoint
        let tip: CGPoint
    }
    struct Skeleton {
        let rightArm: Chain
        let leftArm: Chain
        let rightLeg: Chain
        let leftLeg: Chain
    }
    static let upperArmLength: CGFloat = 0.14
    static let forearmLength: CGFloat = 0.14
    static let thighLength: CGFloat = 0.18
    static let shinLength: CGFloat = 0.19
    // 원본 5프레임은 443×444px. 그림을 다시 줄이거나 체형을 다시 그리지 않는다.
    static let canvasSize = 444

    // 각도는 오른쪽=0°, 아래=90°. 팔의 두 분절은 회전만 하며 늘어나지 않는다.
    private static let firstRight: [(CGFloat, CGFloat)] = [
        (55, 42), (90, 80), (132, 142), (82, 72), (52, 40), (18, 8), (4, 0)
    ]
    private static let thirdRight: [(CGFloat, CGFloat)] = [
        (52, 40), (90, 78), (135, 150), (82, 70), (45, 30), (20, -25), (62, 48)
    ]
    private static let leftAngles: [(CGFloat, CGFloat)] = [
        (145, 150), (90, 80), (25, 15), (105, 100), (145, 150), (140, 145), (130, 135)
    ]
    // 같은 길이의 두 다리로 앞발/뒷발을 교대한다. y가 작은 발은 들어 올린 발이다.
    private static let nearFeet: [CGPoint] = [
        CGPoint(x: 0.75, y: 0.80), CGPoint(x: 0.64, y: 0.80), CGPoint(x: 0.43, y: 0.79),
        CGPoint(x: 0.60, y: 0.80), CGPoint(x: 0.76, y: 0.80), CGPoint(x: 0.65, y: 0.80), CGPoint(x: 0.44, y: 0.79)
    ]
    private static let farFeet: [CGPoint] = [
        CGPoint(x: 0.30, y: 0.789), CGPoint(x: 0.47, y: 0.789), CGPoint(x: 0.70, y: 0.789),
        CGPoint(x: 0.36, y: 0.755), CGPoint(x: 0.31, y: 0.789), CGPoint(x: 0.38, y: 0.765), CGPoint(x: 0.70, y: 0.789)
    ]
    static func skeleton(_ woman: Woman, step: Int) -> Skeleton {
        let page = min(max(step, 0), 6)
        let angles = (woman == .first ? firstRight : thirdRight)[page]
        let shoulder = woman == .first ? CGPoint(x: 0.585, y: 0.262) : CGPoint(x: 0.575, y: 0.29)
        let farShoulder = CGPoint(x: shoulder.x - 0.075, y: shoulder.y + 0.008)
        return Skeleton(rightArm: arm(shoulder, angles), leftArm: arm(farShoulder, leftAngles[page]),
            rightLeg: leg(CGPoint(x: 0.55, y: 0.53), ankle: nearFeet[page]),
            leftLeg: leg(CGPoint(x: 0.51, y: 0.53), ankle: farFeet[page]))
    }
    private static func point(_ origin: CGPoint, length: CGFloat, angle: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: origin.x + length * cos(radians), y: origin.y + length * sin(radians))
    }
    private static func arm(_ shoulder: CGPoint, _ angles: (CGFloat, CGFloat)) -> Chain {
        let elbow = point(shoulder, length: upperArmLength, angle: angles.0)
        return Chain(root: shoulder, joint: elbow, tip: point(elbow, length: forearmLength, angle: angles.1))
    }
    private static func leg(_ hip: CGPoint, ankle: CGPoint) -> Chain {
        let dx = ankle.x - hip.x, dy = ankle.y - hip.y, distance = hypot(dx, dy)
        // 두 고정 길이 원이 만나는 무릎을 구한다. 발 위치로 다리 길이를 바꾸지 않는다.
        precondition(distance > abs(thighLength - shinLength) && distance < thighLength + shinLength)
        let along = (thighLength * thighLength - shinLength * shinLength + distance * distance) / (2 * distance)
        let across = sqrt(max(0, thighLength * thighLength - along * along))
        let knee = CGPoint(x: hip.x + along * dx / distance + across * dy / distance,
                           y: hip.y + along * dy / distance - across * dx / distance)
        return Chain(root: hip, joint: knee, tip: ankle)
    }

    private struct Parts {
        let body: CGImage
        let upperArm: CGImage
        let forearm: CGImage
        let sock: CGImage
        let nearShoe: CGImage
        let farShoe: CGImage
        let nearAnkle: CGPoint
        let farAnkle: CGPoint
    }
    private static func sheet(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    private static func frame(_ name: String, step: Int) -> CGImage? {
        guard let source = sheet(name), source.width == 1774, source.height == 887 else { return nil }
        let column = step % 4, row = step / 4
        let x = source.width * column / 4, y = source.height * row / 2
        return source.cropping(to: CGRect(x: x, y: y,
            width: source.width * (column + 1) / 4 - x, height: source.height * (row + 1) / 2 - y))
    }
    private static func bitmap() -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8,
            bytesPerRow: canvasSize * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    }
    /// 원본의 외곽선을 따라 앱에서 합성한다. PNG의 그림/색/체형은 수정하지 않는다.
    private static func clipped(_ image: CGImage, polygon: [CGPoint], excluding: [[CGPoint]] = []) -> CGImage? {
        guard let context = bitmap() else { return nil }
        context.beginPath()
        func addOutline(_ outline: [CGPoint]) {
            for (index, point) in outline.enumerated() {
                let p = CGPoint(x: point.x, y: CGFloat(canvasSize) - point.y)
                if index == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
            context.closePath()
        }
        addOutline(polygon)
        context.clip()
        if !excluding.isEmpty {
            // 별도 교집합 clip: 제외 도형이 밑단 밖에 걸쳐도 바깥 조각을 다시 그리지 않는다.
            context.beginPath()
            context.addRect(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
            for outline in excluding { addOutline(outline) }
            context.clip(using: .evenOdd)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
    private static func parts(_ woman: Woman) -> Parts? {
        guard let original = frame(woman == .first ? "DancheongPersonWalk7RightOnly" : "DancheongPersonDance7BodyWhiteLegs", step: 4),
              let arm = frame(woman == .first ? "DancheongPersonWalk7FarLeftArm" : "DancheongPersonDance7NearRightArm", step: 1),
              let upper = arm.cropping(to: woman == .first ? CGRect(x: 205, y: 144, width: 75, height: 111) : CGRect(x: 167, y: 91, width: 95, height: 145)),
              let fore = arm.cropping(to: woman == .first ? CGRect(x: 210, y: 231, width: 83, height: 149) : CGRect(x: 170, y: 218, width: 76, height: 170)),
              let sock = frame("DancheongPersonDance7BodyWhiteLegs", step: 4)?.cropping(to: CGRect(x: 114, y: 329, width: 35, height: 15)) else { return nil }
        let body: CGImage
        if woman == .first {
            guard let cleaned = frame("DancheongPersonWalkBodyCleanup86", step: 4), let context = bitmap(),
                  let head = clipped(original, polygon: [.init(x: 0,y: 0),.init(x: 443,y: 0),.init(x: 443,y: 99),.init(x: 240,y: 99),.init(x: 225,y: 169),.init(x: 0,y: 169)]),
                  let skirt = clipped(original, polygon: [.init(x: 207,y: 156),.init(x: 280,y: 156),.init(x: 297,y: 235),.init(x: 343,y: 290),.init(x: 371,y: 328),.init(x: 360,y: 336),.init(x: 350,y: 343),.init(x: 340,y: 348),.init(x: 330,y: 353),.init(x: 320,y: 357),.init(x: 310,y: 360),.init(x: 300,y: 364),.init(x: 290,y: 366),.init(x: 280,y: 368),.init(x: 270,y: 370),.init(x: 260,y: 371),.init(x: 250,y: 371),.init(x: 240,y: 371),.init(x: 230,y: 370),.init(x: 220,y: 368),.init(x: 210,y: 365),.init(x: 200,y: 363),.init(x: 190,y: 359),.init(x: 180,y: 356),.init(x: 170,y: 353),.init(x: 160,y: 352),.init(x: 155,y: 343),.init(x: 150,y: 340),.init(x: 145,y: 338),.init(x: 140,y: 336),.init(x: 135,y: 334),.init(x: 130,y: 337),.init(x: 125,y: 343),.init(x: 120,y: 348),.init(x: 110,y: 349),.init(x: 100,y: 346),.init(x: 90,y: 341),.init(x: 80,y: 335),.init(x: 70,y: 331),.init(x: 60,y: 324),.init(x: 48,y: 320),.init(x: 149,y: 216)], excluding: [[.init(x: 153,y: 343),.init(x: 164,y: 343),.init(x: 164,y: 357),.init(x: 153,y: 357)]]) else { return nil }
            // AI 편집 결과는 팔을 뺀 저고리 영역에만 쓴다. 얼굴·머리·치마는 이전 원본 그대로.
            context.saveGState(); context.clip(to: CGRect(x: 204, y: 444 - 166, width: 83, height: 76))
            context.draw(cleaned, in: CGRect(x: 0,y: 0,width: 443,height: 444)); context.restoreGState()
            context.draw(head, in: CGRect(x: 0,y: 0,width: 444,height: 444))
            context.draw(skirt, in: CGRect(x: 0,y: 0,width: 444,height: 444))
            guard let composed = context.makeImage() else { return nil }; body = composed
        } else {
            // 승인된 이전 5프레임 몸통 하나를 그대로 재사용하고 기존 발만 분리한다.
            guard let torso = clipped(original, polygon: [.init(x: 0,y: 0),.init(x: 443,y: 0),.init(x: 443,y: 318),.init(x: 397,y: 318),.init(x: 390,y: 323),.init(x: 380,y: 331),.init(x: 370,y: 337),.init(x: 360,y: 342),.init(x: 350,y: 344),.init(x: 340,y: 350),.init(x: 330,y: 353),.init(x: 320,y: 356),.init(x: 310,y: 360),.init(x: 300,y: 362),.init(x: 290,y: 364),.init(x: 280,y: 365),.init(x: 270,y: 366),.init(x: 260,y: 367),.init(x: 250,y: 367),.init(x: 240,y: 367),.init(x: 230,y: 367),.init(x: 220,y: 365),.init(x: 210,y: 364),.init(x: 200,y: 362),.init(x: 190,y: 360),.init(x: 180,y: 357),.init(x: 170,y: 353),.init(x: 160,y: 349),.init(x: 150,y: 345),.init(x: 145,y: 320),.init(x: 140,y: 316),.init(x: 135,y: 315),.init(x: 130,y: 312),.init(x: 125,y: 305),.init(x: 120,y: 313),.init(x: 115,y: 319),.init(x: 110,y: 316),.init(x: 100,y: 306),.init(x: 90,y: 295),.init(x: 0,y: 295)], excluding: [[.init(x: 142,y: 320),.init(x: 160,y: 321),.init(x: 160,y: 338),.init(x: 142,y: 338)]]) else { return nil }
            body = torso
        }
        let nearPolygon: [CGPoint] = woman == .first ? [.init(x: 312,y: 344),.init(x: 343,y: 344),.init(x: 352,y: 371),.init(x: 404,y: 379),.init(x: 410,y: 403),.init(x: 340,y: 431),.init(x: 306,y: 420)] : [.init(x: 319,y: 357),.init(x: 353,y: 343),.init(x: 366,y: 367),.init(x: 422,y: 374),.init(x: 429,y: 400),.init(x: 367,y: 432),.init(x: 328,y: 429)]
        let farPolygon: [CGPoint] = woman == .first ? [.init(x: 111,y: 345),.init(x: 146,y: 360),.init(x: 138,y: 383),.init(x: 173,y: 407),.init(x: 156,y: 433),.init(x: 131,y: 427),.init(x: 81,y: 385),.init(x: 81,y: 364)] : [.init(x: 112,y: 325),.init(x: 158,y: 349),.init(x: 137,y: 369),.init(x: 144,y: 411),.init(x: 128,y: 423),.init(x: 102,y: 406),.init(x: 59,y: 363),.init(x: 66,y: 345)]
        guard let near = clipped(original, polygon: nearPolygon), let far = clipped(original, polygon: farPolygon) else { return nil }
        return Parts(body: body, upperArm: upper, forearm: fore, sock: sock, nearShoe: near, farShoe: far,
            nearAnkle: woman == .first ? .init(x: 333,y: 355) : .init(x: 343,y: 365),
            farAnkle: woman == .first ? .init(x: 125,y: 357) : .init(x: 122,y: 348))
    }

    static func poses(_ woman: Woman) -> [NSImage] {
        guard let parts = parts(woman) else { return [] }
        return (0..<7).compactMap { step in
            guard let image = render(parts, woman: woman, skeleton: skeleton(woman, step: step)) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: canvasSize, height: canvasSize))
        }
    }
    private static func render(_ parts: Parts, woman: Woman, skeleton: Skeleton) -> CGImage? {
        guard let context = bitmap() else { return nil }
        context.interpolationQuality = .high
        let size = CGFloat(canvasSize)
        func draw(_ image: CGImage, rect: CGRect) {
            context.draw(image, in: CGRect(x: rect.minX * size, y: (1 - rect.maxY) * size,
                                          width: rect.width * size, height: rect.height * size))
        }
        func segment(_ image: CGImage, start: CGPoint, end: CGPoint, width: CGFloat,
                     topOverlap: CGFloat, bottomExtension: CGFloat) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let angle = atan2(end.y - start.y, end.x - start.x)
            context.saveGState()
            context.translateBy(x: start.x * size, y: (1 - start.y) * size)
            context.rotate(by: .pi / 2 - angle)
            context.draw(image, in: CGRect(x: -width * size / 2,
                y: -(length + bottomExtension) * size, width: width * size,
                height: (length + topOverlap + bottomExtension) * size))
            context.restoreGState()
        }
        func drawArm(_ chain: Chain) {
            segment(parts.upperArm, start: chain.root, end: chain.joint,
                    width: woman == .first ? 0.13 : 0.14, topOverlap: 0.03, bottomExtension: 0.022)
            segment(parts.forearm, start: chain.joint, end: chain.tip,
                    width: woman == .first ? 0.13 : 0.12, topOverlap: 0.032, bottomExtension: 0.045)
        }
        func drawLeg(_ chain: Chain, near: Bool) {
            segment(parts.sock, start: chain.root, end: chain.joint, width: 0.08, topOverlap: 0.015, bottomExtension: 0.015)
            segment(parts.sock, start: chain.joint, end: chain.tip, width: 0.08, topOverlap: 0.015, bottomExtension: 0.015)
            let shoe = near ? parts.nearShoe : parts.farShoe
            let ankle = near ? parts.nearAnkle : parts.farAnkle
            // 원본 신발을 1:1로 평행 이동한다. 발을 작고 가늘게 다시 그리지 않는다.
            draw(shoe, rect: CGRect(x: chain.tip.x - ankle.x / size, y: chain.tip.y - ankle.y / size, width: 1, height: 1))
        }
        // 왼팔은 몸보다 뒤, 양다리는 치마 아래, 오른팔은 몸보다 앞.
        drawArm(skeleton.leftArm)
        drawLeg(skeleton.leftLeg, near: false)
        drawLeg(skeleton.rightLeg, near: true)
        draw(parts.body, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        drawArm(skeleton.rightArm)
        return context.makeImage()
    }
}

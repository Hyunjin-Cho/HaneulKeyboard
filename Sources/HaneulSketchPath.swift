import CoreGraphics

/// 2026-10-10: 안내와 DMG가 같은 손그림 화살표 원본을 공유한다. 좌표는 위에서 아래 방향이다.
enum HaneulSketchPath {
    static func arrow(in rect: CGRect) -> CGPath {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: at(0.05, 0.04))
        path.addCurve(to: at(0.93, 0.85), control1: at(-0.08, 0.5), control2: at(0.42, 0.66))
        path.move(to: at(0.70, 0.94))
        path.addLine(to: at(0.93, 0.85))
        path.addLine(to: at(0.80, 0.54))
        return path
    }
}

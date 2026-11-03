import AppKit
import SwiftUI

/// 2026-11-03 (#116): 안내 1·2 두루마리 무대 — 긴 리소 그림 한 장 위를 카메라가 트럭·푸시 인 한다(앱 안에서 실시간).
/// 오너 결정(2026-11-03 17:46): 3D 세트 없이 그림 한 장 + 앱 안 카메라, 사람은 새로 그린 세 사람.
/// 그림·카메라 정거장·인물 자리의 정본은 비공개 haneul-art `onboarding/`(scroll.py · people.py)이 내보낸
/// OnboardingScroll.json · OnboardingPeople.json이다. 여기에 값을 옮겨 적지 않는다.
enum OnboardingScrollArt {
    struct Station: Decodable { let page: Int; let cx: CGFloat; let cy: CGFloat; let zoom: CGFloat }
    struct PeopleAt: Decodable { let page: Int; let x: CGFloat; let y: CGFloat; let scale: CGFloat; let spacing: CGFloat }
    struct Scroll: Decodable {
        let image_pt: [CGFloat]
        let stage_pt: [CGFloat]
        let stations: [Station]
        let people: [PeopleAt]
    }
    struct Sprite: Decodable { let file: String; let canvas_pt: [CGFloat]; let anchor_pt: [CGFloat] }
    struct People: Decodable { let order: [String]; let sprites: [String: Sprite] }

    static let scroll: Scroll? = decode("OnboardingScroll")
    static let people: People? = decode("OnboardingPeople")
    static let image: CGImage? = cgImage(Bundle.main.url(forResource: "OnboardingScroll", withExtension: "jpg"))
    /// 두루마리 그림이 있는 페이지 수(정거장 수). 2026-11-03 지금은 1·2페이지.
    static var pageCount: Int { image == nil ? 0 : (scroll?.stations.count ?? 0) }

    @MainActor private static var spriteCache: [String: CGImage] = [:]
    @MainActor static func sprite(_ who: String, _ pose: String) -> CGImage? {
        let key = "\(who)_\(pose)"
        if let hit = spriteCache[key] { return hit }
        guard let s = people?.sprites[key] else { return nil }
        let image = cgImage(Bundle.main.url(forResource: (s.file as NSString).deletingPathExtension, withExtension: "png"))
        spriteCache[key] = image
        return image
    }

    private static func decode<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func cgImage(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

struct OnboardingScrollStage: NSViewRepresentable {
    var page: Int
    var reduceMotion: Bool

    func makeNSView(context: Context) -> StageView { StageView() }
    func updateNSView(_ view: StageView, context: Context) { view.show(page: page, animated: !reduceMotion) }

    final class StageView: NSView {
        /// 2026-11-03: 콘티 v1 값 — 앞으로 1.1초(트럭 + 푸시 인), 뒤로는 같은 길을 빠르게 되감는다.
        /// 곡선은 7페이지 카메라와 같은 cubic-bezier(0.3, 0.6, 0.4, 1)(앞 정지 없이 출발해 끝에서 느려진다).
        static let forward: CFTimeInterval = 1.1
        static let backward: CFTimeInterval = 0.8
        static let curve = CAMediaTimingFunction(controlPoints: 0.3, 0.6, 0.4, 1)
        /// 걷기 두 장을 번갈아 보이는 간격(초).
        static let stride: CFTimeInterval = 0.16

        private let world = CALayer()
        private var persons: [CALayer] = []
        private var page: Int?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor(red: 247 / 255, green: 242 / 255, blue: 229 / 255, alpha: 1).cgColor
            layer?.masksToBounds = true
            guard let art = OnboardingScrollArt.scroll else { return }
            // 세계 좌표: 그림 1pt = 레이어 1pt, 원점은 왼쪽 아래(그림 y는 위에서 아래라 높이에서 뺀다).
            world.anchorPoint = .zero
            world.position = .zero
            world.bounds = CGRect(x: 0, y: 0, width: art.image_pt[0], height: art.image_pt[1])
            world.contents = OnboardingScrollArt.image
            world.contentsGravity = .resize
            layer?.addSublayer(world)
            for _ in OnboardingScrollArt.people?.order ?? [] {
                let person = CALayer()
                person.contentsGravity = .resize
                world.addSublayer(person)
                persons.append(person)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var mouseDownCanMoveWindow: Bool { true }   // 안내 창은 배경을 끌어 옮긴다

        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            world.contentsScale = scale
            persons.forEach { $0.contentsScale = scale }
            if let page { place(page) }
        }

        func show(page target: Int, animated: Bool) {
            guard OnboardingScrollArt.scroll != nil, target != page else { return }
            let from = page
            page = target
            guard let from, animated, !bounds.isEmpty else {
                if from != nil, !bounds.isEmpty {        // 동작 줄이기 — 움직이지 않고 디졸브
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = 0.35
                    layer?.add(fade, forKey: "fade")
                }
                place(target)
                return
            }
            travel(from: from, to: target)
        }

        // MARK: 카메라·인물 자리

        private func camera(_ page: Int) -> CATransform3D {
            guard let art = OnboardingScrollArt.scroll else { return CATransform3DIdentity }
            let st = art.stations[page]
            let s = st.zoom * bounds.width / art.stage_pt[0]
            let tx = bounds.width / 2 - st.cx * s
            let ty = bounds.height / 2 - (art.image_pt[1] - st.cy) * s
            return CATransform3DConcat(CATransform3DMakeScale(s, s, 1), CATransform3DMakeTranslation(tx, ty, 0))
        }

        private func personGeometry(_ page: Int, _ index: Int) -> (position: CGPoint, bounds: CGRect, anchor: CGPoint)? {
            guard let art = OnboardingScrollArt.scroll, let people = OnboardingScrollArt.people,
                  let at = art.people.first(where: { $0.page == page + 1 }),
                  let sprite = people.sprites["\(people.order[index])_p\(page + 1)"] else { return nil }
            let canvas = CGSize(width: sprite.canvas_pt[0], height: sprite.canvas_pt[1])
            let x = at.x + CGFloat(index - 1) * at.spacing
            return (CGPoint(x: x, y: art.image_pt[1] - at.y),
                    CGRect(origin: .zero, size: CGSize(width: canvas.width * at.scale, height: canvas.height * at.scale)),
                    CGPoint(x: sprite.anchor_pt[0] / canvas.width, y: 1 - sprite.anchor_pt[1] / canvas.height))
        }

        private func place(_ page: Int) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            world.removeAllAnimations()
            world.transform = camera(page)
            for (i, person) in persons.enumerated() {
                person.removeAllAnimations()
                guard let g = personGeometry(page, i), let who = OnboardingScrollArt.people?.order[i] else { continue }
                person.anchorPoint = g.anchor
                person.bounds = g.bounds
                person.position = g.position
                person.contents = OnboardingScrollArt.sprite(who, "p\(page + 1)")
            }
            CATransaction.commit()
        }

        /// 지금 보이는 자리(이동 중이면 그 순간)에서 목표 정거장으로 — 이동 중에 눌러도 끊기지 않는다.
        private func travel(from: Int, to: Int) {
            let duration = to > from ? Self.forward : Self.backward
            let startCamera = world.presentation()?.transform ?? world.transform
            CATransaction.begin(); CATransaction.setDisableActions(true)
            world.transform = camera(to)
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = startCamera
            move.toValue = world.transform
            move.duration = duration
            move.timingFunction = Self.curve
            world.add(move, forKey: "camera")
            for (i, person) in persons.enumerated() {
                guard let g = personGeometry(to, i), let who = OnboardingScrollArt.people?.order[i] else { continue }
                let startPosition = person.presentation()?.position ?? person.position
                let startBounds = person.presentation()?.bounds ?? person.bounds
                person.anchorPoint = g.anchor
                person.position = g.position
                person.bounds = g.bounds
                person.contents = OnboardingScrollArt.sprite(who, "p\(to + 1)")
                for (key, start, end) in [("position", NSValue(point: startPosition), NSValue(point: g.position)),
                                          ("bounds", NSValue(rect: startBounds), NSValue(rect: g.bounds))] {
                    let a = CABasicAnimation(keyPath: key)
                    a.fromValue = start; a.toValue = end
                    a.duration = duration; a.timingFunction = Self.curve
                    person.add(a, forKey: key)
                }
                // 걷기 두 장을 번갈아(사람마다 반 박자씩 어긋나게), 도착하면 그 페이지 자세로 멈춘다.
                let frames = [OnboardingScrollArt.sprite(who, "walkA"), OnboardingScrollArt.sprite(who, "walkB")]
                let steps = max(2, Int((duration / Self.stride).rounded()))
                let walk = CAKeyframeAnimation(keyPath: "contents")
                walk.values = (0..<steps).compactMap { frames[($0 + i) % 2] }
                walk.calculationMode = .discrete
                walk.duration = duration * 0.92
                person.add(walk, forKey: "walk")
            }
            CATransaction.commit()
        }
    }
}

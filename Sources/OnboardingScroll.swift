import AppKit
import SwiftUI

/// 2026-11-03 (#116): 안내 1~4 두루마리 무대 — 긴 리소 그림 한 장 위를 카메라가 트럭·푸시 인 한다(앱 안에서 실시간).
/// 오너 결정(2026-11-03 17:46): 3D 세트 없이 그림 한 장 + 앱 안 카메라, 사람은 새로 그린 세 사람.
/// 그림·카메라 정거장·인물 자리의 정본은 비공개 haneul-art `onboarding/`(scroll.py · people.py)이 내보낸
/// OnboardingScroll.json · OnboardingPeople.json이다. 여기에 값을 옮겨 적지 않는다.
enum OnboardingScrollArt {
    struct Station: Decodable { let page: Int; let cx: CGFloat; let cy: CGFloat; let zoom: CGFloat }
    /// 인물 자리: 1·2페이지는 가운데 사람(x, y) + 간격, 3페이지부터는 사람마다(figures, PEOPLE 순서).
    /// figures 한 칸 = [x, y] · [x, y, 배율] · [x, y, 배율, 앞뒤]. 앞뒤 기본 10, 따로 찍은 층(Prop)과 비교해 쌓는다.
    struct PeopleAt: Decodable {
        let page: Int
        let scale: CGFloat
        let x: CGFloat?
        let y: CGFloat?
        let spacing: CGFloat?
        let figures: [[CGFloat]]?

        func foot(_ index: Int) -> CGPoint? {
            if let figures, index < figures.count, figures[index].count >= 2 { return CGPoint(x: figures[index][0], y: figures[index][1]) }
            guard let x, let y else { return nil }
            return CGPoint(x: x + CGFloat(index - 1) * (spacing ?? 0), y: y)
        }
        func scale(_ index: Int) -> CGFloat {
            if let figures, index < figures.count, figures[index].count > 2 { return figures[index][2] }
            return scale
        }
        func depth(_ index: Int) -> CGFloat {
            if let figures, index < figures.count, figures[index].count > 3 { return figures[index][3] }
            return 10
        }
    }
    /// 2026-11-03 20:29: 두루마리에서 떼어 따로 찍은 층(4페이지 시소 판 — 시소 뒤에 선 사람을 가린다). x, y = 세계 왼쪽 위 pt.
    struct Prop: Decodable { let page: Int; let file: String; let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat; let z: CGFloat }
    struct Scroll: Decodable {
        let image_pt: [CGFloat]
        let stage_pt: [CGFloat]
        let stations: [Station]
        let people: [PeopleAt]
        let props: [Prop]?
    }
    struct Sprite: Decodable { let file: String; let canvas_pt: [CGFloat]; let anchor_pt: [CGFloat] }
    struct People: Decodable { let order: [String]; let sprites: [String: Sprite] }

    static let scroll: Scroll? = decode("OnboardingScroll")
    static let people: People? = decode("OnboardingPeople")
    static let image: CGImage? = cgImage(Bundle.main.url(forResource: "OnboardingScroll", withExtension: "jpg"))
    /// 두루마리 그림이 있는 페이지 수(정거장 수). 2026-11-03 20:57: 1~7페이지(7 = 영상 첫 프레임 자리).
    static var pageCount: Int { image == nil ? 0 : (scroll?.stations.count ?? 0) }

    @MainActor private static var spriteCache: [String: CGImage] = [:]
    @MainActor static func image(named file: String) -> CGImage? {
        cgImage(Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "png"))
    }

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
        private var props: [CALayer] = []
        private var page: Int?
        private var placedSize: CGSize = .zero
        private var reduceMotion = false
        /// 2026-11-03 20:57 오너(A안): 마지막 정거장 = 7페이지 영상의 첫 프레임(두루마리에 같은 화소로 붙여 둠).
        /// 카메라가 도착하면 영상 무대로 바꿔 끼우고(숨은 컷) 0.2초 멈춘 뒤 달리 인 + 틸트 업을 재생한다.
        private var video: OnboardingStageVideo.StageView?
        private var videoIndex: Int? {
            guard let st = OnboardingScrollArt.scroll?.stations, st.last?.page == OnboardingView.stagePage + 1 else { return nil }
            return st.count - 1
        }

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
                person.zPosition = 10
                world.addSublayer(person)
                persons.append(person)
            }
            for prop in art.props ?? [] {                          // 따로 찍은 층 — 세계에 고정, 앞뒤(z)로 사람과 쌓인다
                let layer = CALayer()
                layer.contents = OnboardingScrollArt.image(named: prop.file)
                layer.contentsGravity = .resize
                layer.frame = CGRect(x: prop.x, y: art.image_pt[1] - prop.y - prop.h, width: prop.w, height: prop.h)
                layer.zPosition = prop.z
                world.addSublayer(layer)
                props.append(layer)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var mouseDownCanMoveWindow: Bool { true }   // 안내 창은 배경을 끌어 옮긴다

        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            world.contentsScale = scale
            persons.forEach { $0.contentsScale = scale }
            props.forEach { $0.contentsScale = scale }
            // 2026-11-03 21:1x: 크기가 바뀔 때만 다시 놓는다. 7페이지 영상 뷰를 떼어 낼 때도 layout이 불려 되감기 애니메이션이
            // 지워졌다(실측 로그: 7→6 show 0.39초 뒤 layout).
            if let page, bounds.size != placedSize { placedSize = bounds.size; place(page) }
        }

        func show(page target: Int, animated: Bool) {
            guard OnboardingScrollArt.scroll != nil, target != page else { return }
            reduceMotion = !animated
            let from = page
            page = target
            if from == videoIndex { leaveVideo(fade: from != nil && !bounds.isEmpty) }
            guard let from, animated, !bounds.isEmpty else {
                if from != nil, !bounds.isEmpty {        // 동작 줄이기 — 움직이지 않고 디졸브
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = 0.35
                    layer?.add(fade, forKey: "fade")
                }
                place(target)
                if target == videoIndex { enterVideo() }
                return
            }
            travel(from: from, to: target) { [weak self] in
                guard let self, target == self.videoIndex else { return }
                self.enterVideo()
            }
        }

        private func enterVideo() {
            guard video == nil else { return }
            let v = OnboardingStageVideo.StageView(animate: !reduceMotion, autoplay: false)
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
            video = v
            guard !reduceMotion else { return }       // 동작 줄이기면 끝 그림만(재생 없음)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak v] in
                guard let self, let v, self.video === v else { return }
                v.start()
            }
        }

        private func leaveVideo(fade: Bool) {
            guard let v = video else { return }
            video = nil
            v.stop()
            guard fade else { v.removeFromSuperview(); return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                v.animator().alphaValue = 0
            }, completionHandler: { v.removeFromSuperview() })
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

        private func personGeometry(_ page: Int, _ index: Int) -> (position: CGPoint, bounds: CGRect, anchor: CGPoint, depth: CGFloat)? {
            guard let art = OnboardingScrollArt.scroll, let people = OnboardingScrollArt.people,
                  let at = art.people.first(where: { $0.page == page + 1 }),
                  let sprite = people.sprites["\(people.order[index])_p\(page + 1)"] else { return nil }
            let canvas = CGSize(width: sprite.canvas_pt[0], height: sprite.canvas_pt[1])
            guard let foot = at.foot(index) else { return nil }
            let s = at.scale(index)
            return (CGPoint(x: foot.x, y: art.image_pt[1] - foot.y),
                    CGRect(origin: .zero, size: CGSize(width: canvas.width * s, height: canvas.height * s)),
                    CGPoint(x: sprite.anchor_pt[0] / canvas.width, y: 1 - sprite.anchor_pt[1] / canvas.height),
                    at.depth(index))
        }

        private func place(_ page: Int) {
            placedSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            world.removeAllAnimations()
            world.transform = camera(page)
            for (i, person) in persons.enumerated() {
                person.removeAllAnimations()
                guard let g = personGeometry(page, i), let who = OnboardingScrollArt.people?.order[i] else { continue }
                person.anchorPoint = g.anchor
                person.bounds = g.bounds
                person.position = g.position
                person.zPosition = g.depth
                person.contents = OnboardingScrollArt.sprite(who, "p\(page + 1)")
            }
            CATransaction.commit()
        }

        /// 지금 보이는 자리(이동 중이면 그 순간)에서 목표 정거장으로 — 이동 중에 눌러도 끊기지 않는다.
        private func travel(from: Int, to: Int, arrive: (() -> Void)? = nil) {
            let duration = to > from ? Self.forward : Self.backward
            let startCamera = world.presentation()?.transform ?? world.transform
            // 앞뒤: 뒤로 들어가는 사람은 출발할 때, 앞으로 나오는 사람은 도착한 뒤에 바꾼다(시소 판을 뚫고 지나가 보이지 않게).
            // 2026-11-03 21:1x: 완료 블록은 애니메이션을 붙이기 "전에" 건다 — Core Animation은 블록을 건 뒤에 붙은 애니메이션만
            // 기다린다. 뒤에 걸었더니 바로 불려 6→7에서 영상이 출발과 동시에 덮였다(녹화 실측: 3프레임 뒤 도착 화면).
            var arrivalDepths: [(CALayer, CGFloat)] = []
            CATransaction.begin(); CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.page == to else { return }
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    arrivalDepths.forEach { $0.0.zPosition = $0.1 }
                    CATransaction.commit()
                    arrive?()
                }
            }
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
                // 한 번도 자리를 받지 않았거나(7페이지에서 바로 열었을 때) 이미 그 자리면 걷지 않고 그대로 둔다.
                if person.contents == nil || (abs(startPosition.x - g.position.x) < 0.5 && abs(startPosition.y - g.position.y) < 0.5) {
                    person.removeAllAnimations()
                    person.anchorPoint = g.anchor; person.position = g.position; person.bounds = g.bounds
                    person.zPosition = g.depth
                    person.contents = OnboardingScrollArt.sprite(who, "p\(to + 1)")
                    continue
                }
                if g.depth < person.zPosition { person.zPosition = g.depth } else { arrivalDepths.append((person, g.depth)) }
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

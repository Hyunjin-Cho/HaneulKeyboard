import AppKit
import SwiftUI

/// 2026-11-03 (#116): 안내 1~4 두루마리 무대 — 긴 리소 그림 한 장 위를 카메라가 트럭·푸시 인 한다(앱 안에서 실시간).
/// 구조체 정의(자료의 모양)는 `OnboardingScrollData.swift`에 있다(2026-11-07, #177).
extension OnboardingScrollArt {

    static let scroll: Scroll? = decode("OnboardingScroll")
    static let people: People? = decode("OnboardingPeople")
    /// 2026-11-06 (#156): 앱은 창 없이 뒤에 남으므로 그림을 여기(전역)에 쥐지 않는다. 13600×960 두루마리는 풀면 52MB다.
    /// 불러 주기만 하고, 쥐는 쪽은 무대(StageView)다. 창이 닫혀 무대가 사라지면 그림도 같이 풀린다.
    /// 2026-11-07 (#177, 리뷰 app-ui-F-6): 번들에 없으면 이유를 로그에 남긴다(안내 1~6페이지가 종이색 무대로 바뀐다).
    private static let imageURL: URL? = {
        let url = Bundle.main.url(forResource: "OnboardingScroll", withExtension: "jpg")
        if url == nil { haneulLog("HaneulKeyboard: 안내 두루마리 그림(OnboardingScroll.jpg)이 번들에 없어요 — 안내 무대를 종이색으로 대신해요") }
        return url
    }()
    static func loadImage() -> CGImage? { cgImage(imageURL) }
    /// 두루마리 그림이 있는 페이지 수(정거장 수). 2026-11-03 20:57: 1~7페이지(7 = 영상 첫 프레임 자리).
    static var pageCount: Int { imageURL == nil ? 0 : (scroll?.stations.count ?? 0) }

    static func image(named file: String) -> CGImage? {
        cgImage(Bundle.main.url(forResource: pngResourceName(file), withExtension: "png"))
    }

    static func loadSprite(key: String) -> CGImage? {
        guard let s = people?.sprites[key] else { return nil }
        return cgImage(Bundle.main.url(forResource: pngResourceName(s.file), withExtension: "png"))
    }

    /// 2026-11-07 (#177, 리뷰 app-ui-F-6): 예전엔 `try?`로 삼켜서, 키 이름이 바뀌거나 파일이 빠져도 원인이 어디에도 남지 않았다.
    /// 실패하면 로그에 이유를 남기고 nil을 돌려준다 — 그러면 `pageCount`가 0이 되어 무대는 종이색이 된다.
    private static func decode<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            haneulLog("HaneulKeyboard: 안내 두루마리 자원 \(name).json이 번들에 없어요 — 안내 무대를 종이색으로 대신해요")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            haneulLog("HaneulKeyboard: 안내 두루마리 자원 \(name).json을 읽지 못했어요 — \(error) — 안내 무대를 종이색으로 대신해요")
            return nil
        }
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
        /// 2026-11-04 (#119): 첫 화면 펼침 — 콘티 v1 오너 결정(2026-11-02) 1.0초. 창이 화면에 뜬 뒤 잠깐 쉬고 시작한다.
        static let unrollDuration: CFTimeInterval = 1.0
        static let unrollDelay: TimeInterval = 0.35
        /// 2026-11-04 (#119): 점프 — 웅크림(예비 동작) · 뛰어오르기 · 뛰어내리기 · 내려앉은 웅크림(초)과 포물선이 직선보다 솟는 높이(pt).
        static let crouchTime: CFTimeInterval = 0.08
        static let riseTime: CFTimeInterval = 0.34
        static let dropTime: CFTimeInterval = 0.26
        static let landTime: CFTimeInterval = 0.06
        static let riseArc: CGFloat = 30
        static let dropArc: CGFloat = 8

        private let world = CALayer()
        /// 2026-11-04 (#119): 세계를 담는 그릇. 첫 화면 펼침 동안만 가림막(mask)을 걸어 축이 지나간 자리까지만 보인다.
        private let reel = CALayer()
        private let roll = CALayer()
        private enum Unroll { case none, pending, scheduled, running }
        private var unroll = Unroll.none
        private var persons: [CALayer] = []
        /// 2026-11-06 (#156): 인물 그림과 7페이지 처음·끝 그림은 이 무대가 사는 동안만 쥔다. 페이지를 오갈 때 다시 풀지 않는다.
        private var spriteCache: [String: CGImage] = [:]
        private lazy var stageFrames = OnboardingStageArt.Frames()
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
            world.contents = OnboardingScrollArt.loadImage()
            world.contentsGravity = .resize
            reel.anchorPoint = .zero
            reel.addSublayer(world)
            layer?.addSublayer(reel)
            if let r = art.roll {
                roll.contents = OnboardingScrollArt.image(named: r.file)
                roll.contentsGravity = .resize
                roll.anchorPoint = CGPoint(x: 0, y: 0.5)
                roll.isHidden = true
                layer?.addSublayer(roll)
            }
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

        private func sprite(_ who: String, _ pose: String) -> CGImage? {
            let key = "\(who)_\(pose)"
            if let hit = spriteCache[key] { return hit }
            let image = OnboardingScrollArt.loadSprite(key: key)
            spriteCache[key] = image
            return image
        }

        override var mouseDownCanMoveWindow: Bool { true }   // 안내 창은 배경을 끌어 옮긴다

        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            world.contentsScale = scale
            roll.contentsScale = scale
            CATransaction.begin(); CATransaction.setDisableActions(true)
            reel.frame = bounds
            reel.mask?.frame.size.height = bounds.height
            if unroll == .pending || unroll == .scheduled { placeRoll(revealed: 0) }
            CATransaction.commit()
            persons.forEach { $0.contentsScale = scale }
            props.forEach { $0.contentsScale = scale }
            // 2026-11-03 21:1x: 크기가 바뀔 때만 다시 놓는다. 7페이지 영상 뷰를 떼어 낼 때도 layout이 불려 되감기 애니메이션이
            // 지워졌다(실측 로그: 7→6 show 0.39초 뒤 layout).
            if let page, bounds.size != placedSize { placedSize = bounds.size; place(page) }
            if unroll == .pending, !bounds.isEmpty, window != nil {
                unroll = .scheduled
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.unrollDelay) { [weak self] in self?.startUnroll(attempt: 0) }
            }
        }

        func show(page target: Int, animated: Bool) {
            guard OnboardingScrollArt.scroll != nil, target != page else { return }
            reduceMotion = !animated
            // 2026-11-04 (#119): 창이 1페이지로 처음 열릴 때만 두루마리를 펼친다(동작 줄이기면 펼치지 않는다).
            if page == nil, target == 0, animated, roll.contents != nil { prepareUnroll() }
            else if unroll == .pending || unroll == .scheduled { finishUnroll() }   // 펼치기 전에 넘기면 바로 다 펼친다
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
            let v = OnboardingStageVideo.StageView(animate: !reduceMotion, autoplay: false, frames: stageFrames)
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

        // MARK: 첫 화면 펼침 (2026-11-04, #119)
        // 콘티 v1(2026-11-02 오너 결정): 첫 화면에서 두루마리가 왼쪽 → 오른쪽으로 펼쳐지는 와이프 1.0초.
        // 말린 축(haneul-art roll.py)을 무대 왼쪽 밖에서 오른쪽 밖까지 굴려 보내고, 축 가운데까지만 세계를 보인다(가림막 너비 = 축 자리).
        // 축은 1페이지 카메라 배율로 그린다 — 망점이 1페이지 그림과 같은 크기로 보인다.

        private func prepareUnroll() {
            unroll = .pending
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.anchorPoint = .zero
            mask.frame = CGRect(x: 0, y: 0, width: 0, height: max(bounds.height, 1))
            CATransaction.begin(); CATransaction.setDisableActions(true)
            reel.mask = mask
            roll.isHidden = false
            placeRoll(revealed: 0)
            CATransaction.commit()
        }

        /// 축 배율·자리. revealed = 세계가 보이는 폭(pt) — 축 가운데가 그 자리에 온다.
        private func rollGeometry() -> (scale: CGFloat, edge: CGFloat, size: CGSize)? {
            guard let art = OnboardingScrollArt.scroll, let r = art.roll, let first = art.stations.first, !bounds.isEmpty else { return nil }
            let s = first.zoom * bounds.width / art.stage_pt[0]
            return (s, r.edge * s, CGSize(width: r.w * s, height: r.h * s))
        }

        private func placeRoll(revealed: CGFloat) {
            guard let g = rollGeometry() else { return }
            roll.bounds = CGRect(origin: .zero, size: g.size)
            roll.position = CGPoint(x: revealed - g.edge, y: bounds.midY)
            reel.mask?.frame = CGRect(x: 0, y: 0, width: revealed, height: bounds.height)
        }

        private func startUnroll(attempt: Int) {
            guard unroll == .scheduled else { return }
            // 창이 아직 화면에 안 보이면(앱이 막 뜨는 중) 조금 더 기다린다 — 안 보이는 곳에서 펼침이 끝나 버리지 않게.
            if window?.occlusionState.contains(.visible) != true, attempt < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.startUnroll(attempt: attempt + 1) }
                return
            }
            guard let g = rollGeometry(), let mask = reel.mask else { finishUnroll(); return }
            unroll = .running
            let endReveal = bounds.width + g.edge                    // 축이 무대 오른쪽 밖으로 다 나간 자리
            CATransaction.begin(); CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated { self?.finishUnroll() }
            }
            for (layer, key, from, to) in [(roll as CALayer, "position.x", -g.edge, endReveal - g.edge),
                                           (mask, "bounds.size.width", 0, endReveal)] {
                let a = CABasicAnimation(keyPath: key)
                a.fromValue = from; a.toValue = to
                a.duration = Self.unrollDuration
                a.timingFunction = Self.curve
                layer.setValue(to, forKeyPath: key)
                layer.add(a, forKey: "unroll")
            }
            CATransaction.commit()
        }

        private func finishUnroll() {
            guard unroll != .none else { return }
            unroll = .none
            CATransaction.begin(); CATransaction.setDisableActions(true)
            roll.removeAllAnimations()
            roll.isHidden = true
            reel.mask = nil
            CATransaction.commit()
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
                person.contents = sprite(who, "p\(page + 1)")
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
                    person.contents = sprite(who, "p\(to + 1)")
                    continue
                }
                if g.depth < person.zPosition { person.zPosition = g.depth } else { arrivalDepths.append((person, g.depth)) }
                person.anchorPoint = g.anchor
                person.position = g.position
                person.bounds = g.bounds
                person.contents = sprite(who, "p\(to + 1)")
                let resize = CABasicAnimation(keyPath: "bounds")
                resize.fromValue = NSValue(rect: startBounds); resize.toValue = NSValue(rect: g.bounds)
                resize.duration = duration; resize.timingFunction = Self.curve
                person.add(resize, forKey: "bounds")
                // 2026-11-04 (#119): 공중 자세(시소 높은 끝·징검돌 사이)로 들고 나는 사람은 땅을 걷고 뛰어오르거나 뛰어내린다.
                // 이동 중에 다시 눌러 지금 자리가 출발 정거장이 아니면 예전처럼 곧게 걷는다(끊김 없이).
                if let departed = departure(at: startPosition, person: i, near: from), let path = hopPath(person: i, from: departed, to: to, duration: duration) {
                    let move = CAKeyframeAnimation(keyPath: "position")
                    move.values = path.points.map { NSValue(point: $0) }
                    move.keyTimes = path.times.map { NSNumber(value: $0 / duration) }
                    move.calculationMode = .linear
                    move.duration = duration
                    person.add(move, forKey: "position")
                    let pose = CAKeyframeAnimation(keyPath: "contents")
                    pose.values = path.frames.map { sprite(who, $0.pose) as Any }
                    pose.keyTimes = (path.frames.map { $0.at / duration } + [1]).map { NSNumber(value: $0) }
                    pose.calculationMode = .discrete
                    pose.duration = duration
                    person.add(pose, forKey: "walk")
                    continue
                }
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: startPosition); move.toValue = NSValue(point: g.position)
                move.duration = duration; move.timingFunction = Self.curve
                person.add(move, forKey: "position")
                // 걷기 두 장을 번갈아(사람마다 반 박자씩 어긋나게), 도착하면 그 페이지 자세로 멈춘다.
                let frames = [sprite(who, "walkA"), sprite(who, "walkB")]
                let steps = max(2, Int((duration / Self.stride).rounded()))
                let walk = CAKeyframeAnimation(keyPath: "contents")
                walk.values = (0..<steps).compactMap { frames[($0 + i) % 2] }
                walk.calculationMode = .discrete
                walk.duration = duration * 0.92
                person.add(walk, forKey: "walk")
            }
            CATransaction.commit()
        }

        // MARK: 점프 길 (2026-11-04, #119)
        // 3→4에서 포니테일이 걷기 그림 그대로 시소 판 위를 걸어 올라가 높은 끝에 닿는 순간 앉은 자세로 바뀌었다(오너 확인 대기 항목).
        // 공중 자세로 들고 나는 페이지(haneul-art scroll.py의 hops)는 이렇게 간다:
        //   [뛰어내림(down 자세, 포물선) → 내려앉은 웅크림] → 땅 위 걷기 → [웅크림 → 뛰어오름(up 자세, 포물선)]
        // 걷기는 넘김 전체 시간 동안 카메라와 같은 곡선으로 땅 자리 사이를 간다(콘티 v1: 트럭 중 사람은 화면에 붙어 걷는다).
        // 점프는 그 위에 얹는 어긋남이다 — 처음엔 공중 자리에서 땅 길로 내려앉고, 끝(곡선이 거의 멈춘 꼬리)에서 땅 길에서 공중 자리로 오른다.
        // 1차(같은 날)는 점프 시간만큼 걷기를 줄였더니 포니테일이 카메라보다 먼저 달려가 시소 앞에서 기다렸다(실제 창 녹화).
        // 포물선 = 고른 x + 2차식 y(일정한 중력). 뒤로 가기는 앞으로 가는 길을 그대로 되감는다.

        private func hop(_ page: Int, _ index: Int) -> OnboardingScrollArt.Hop? {
            OnboardingScrollArt.scroll?.people.first(where: { $0.page == page + 1 })?.hops?.first(where: { $0.who == index })
        }

        /// 지금 자리가 출발 정거장(from)의 그 사람 자리면 from, 아니면 nil(이동 중에 다시 눌렀을 때).
        private func departure(at position: CGPoint, person index: Int, near from: Int) -> Int? {
            guard let g = personGeometry(from, index) else { return nil }
            return abs(position.x - g.position.x) < 1 && abs(position.y - g.position.y) < 1 ? from : nil
        }

        /// 세계 그림 좌표(위가 0) → 레이어 좌표(아래가 0).
        private func layerPoint(_ p: [CGFloat]) -> CGPoint {
            CGPoint(x: p[0], y: (OnboardingScrollArt.scroll?.image_pt[1] ?? 0) - p[1])
        }

        /// 공중 들고 남이 없으면 nil(예전처럼 곧게 걷는다). 있으면 시각(초)마다 발끝 자리와, 그 시각부터 보일 자세 이름.
        private func hopPath(person index: Int, from: Int, to: Int, duration: CFTimeInterval)
            -> (points: [CGPoint], times: [CFTimeInterval], frames: [(at: CFTimeInterval, pose: String)])? {
            // 앞으로 가는 길(lo → hi)로 짓고, 뒤로 가면 되감는다.
            let (lo, hi) = (min(from, to), max(from, to))
            let hopLo = hop(lo, index), hopHi = hop(hi, index)
            guard hopLo != nil || hopHi != nil,
                  let gLo = personGeometry(lo, index), let gHi = personGeometry(hi, index) else { return nil }
            var tDrop = hopLo == nil ? 0 : Self.dropTime, tLand = hopLo == nil ? 0 : Self.landTime
            var tCrouch = hopHi == nil ? 0 : Self.crouchTime, tRise = hopHi == nil ? 0 : Self.riseTime
            let hops = tDrop + tLand + tCrouch + tRise
            if hops > duration * 0.6 {                               // 넘김이 짧으면 점프도 같은 비율로 줄인다
                let k = duration * 0.6 / hops
                tDrop *= k; tLand *= k; tCrouch *= k; tRise *= k
            }
            func air(_ h: OnboardingScrollArt.Hop?, _ g: (position: CGPoint, bounds: CGRect, anchor: CGPoint, depth: CGFloat)) -> CGPoint {
                CGPoint(x: g.position.x, y: g.position.y - (h?.air_dy ?? 0))
            }
            let start = hopLo.map { air($0, gLo) } ?? gLo.position
            let walkFrom = hopLo.map { layerPoint($0.land) } ?? gLo.position
            let walkTo = hopHi.map { layerPoint($0.rise) } ?? gHi.position
            let end = hopHi.map { air($0, gHi) } ?? gHi.position
            func arc(_ a: CGPoint, _ b: CGPoint, _ u: CGFloat, _ lift: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u + 4 * lift * u * (1 - u))   // 레이어 좌표는 위가 +
            }
            let who = OnboardingScrollArt.people?.order[index] ?? ""
            let crouch = sprite(who, "crouch") != nil ? "crouch" : "walkB"
            var points: [CGPoint] = [], times: [CFTimeInterval] = []
            var frames: [(at: CFTimeInterval, pose: String)] = []
            let samples = max(24, Int(duration * 60))
            let t1 = tDrop, t2 = t1 + tLand, t4 = duration - tRise, t3 = t4 - tCrouch
            let zero = CGPoint.zero
            let liftStart = CGPoint(x: start.x - walkFrom.x, y: start.y - walkFrom.y)    // 공중 자리 − 땅 길 출발점
            let liftEnd = CGPoint(x: end.x - walkTo.x, y: end.y - walkTo.y)              // 공중 자리 − 땅 길 도착점
            for k in 0...samples {
                let t = duration * Double(k) / Double(samples)
                let e = CGFloat(Self.ease(t / duration))
                let ground = CGPoint(x: walkFrom.x + (walkTo.x - walkFrom.x) * e, y: walkFrom.y + (walkTo.y - walkFrom.y) * e)
                let off: CGPoint
                if t < t1 { off = arc(liftStart, zero, CGFloat(t / t1), Self.dropArc) }
                else if tRise > 0, t >= t4 { off = arc(zero, liftEnd, CGFloat((t - t4) / tRise), Self.riseArc) }
                else { off = zero }
                points.append(CGPoint(x: ground.x + off.x, y: ground.y + off.y)); times.append(t)
            }
            if let h = hopLo { frames.append((0, h.down)); if tLand > 0 { frames.append((t1, crouch)) } }
            var t = t2, step = 0
            let walkEnd = hopHi == nil ? duration * 0.92 : t3                 // 점프가 없으면 예전처럼 도착 직전에 자세로 멈춘다
            while t < walkEnd - 0.02 { frames.append((t, ["walkA", "walkB"][(step + index) % 2])); t += Self.stride; step += 1 }
            if let h = hopHi { frames.append((t3, crouch)); frames.append((t4, h.up)) }
            else { frames.append((walkEnd, "p\(hi + 1)")) }
            guard to < from else { return (points, times, frames) }
            // 뒤로 가기: 같은 길을 되감는다 — 시각을 뒤집고, 자세는 각 구간이 끝나는 시각부터 보인다.
            let ends = frames.indices.map { $0 + 1 < frames.count ? frames[$0 + 1].at : duration }
            let back = zip(frames, ends).reversed().map { (at: duration - $0.1, pose: $0.0.pose) }
            return (points.reversed(), times.reversed().map { duration - $0 }, back)
        }

        /// 카메라와 같은 곡선(Self.curve)의 값 — 3차 베지어를 x로 풀어 y를 얻는다.
        static func ease(_ x: Double) -> Double {
            var c1: [Float] = [0, 0], c2: [Float] = [0, 0]
            curve.getControlPoint(at: 1, values: &c1); curve.getControlPoint(at: 2, values: &c2)
            let (x1, y1, x2, y2) = (Double(c1[0]), Double(c1[1]), Double(c2[0]), Double(c2[1]))
            func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
            func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 { let mid = (lo + hi) / 2; if bx(mid) < x { lo = mid } else { hi = mid } }
            return by((lo + hi) / 2)
        }
    }
}

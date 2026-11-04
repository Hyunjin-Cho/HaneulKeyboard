import AppKit
import AVFoundation
import SwiftUI

/// 2026-11-03 (#113): 안내 7 무대 — 오너가 승인한 리소 영상(달리 인 + 틸트 업, 끝 = 앱 아이콘 카메라 B).
/// 그림 원본·승인본은 비공개 haneul-art `icon-b/approved/p7_2026-11-03/`. 앱에는 카드 없는 무대만 넣는다
/// (창 @2x 1640×1242, 6초, `riso7.py app`/`appmux`). 카드는 SwiftUI가 그린다.
/// - 처음 프레임 PNG를 영상 아래 깔아 영상이 준비되기 전 빈 화면을 막는다.
/// - 영상이 끝나면 끝 프레임 PNG(무손실)를 위에 덮는다 — 쉬는 화면에 압축 잡음이 남지 않게.
/// - 동작 줄이기면 영상 없이 끝 프레임만 보여 준다.
enum OnboardingStageArt {
    /// 무대 비율 = 창 폭 / 무대 높이(1640 / 1242 ≈ 1.32 — 승인 키 비주얼의 가운데 1.32:1).
    static let aspect: CGFloat = 1640.0 / 1242.0
    static let videoURL = Bundle.main.url(forResource: "OnboardingP7", withExtension: "mp4")
    /// 처음 프레임은 영상이 준비되기 전 잠깐만 보이므로 JPEG(4:4:4, 품질 90), 쉬는 화면인 끝 프레임은 무손실 PNG.
    static let start = cgImage("OnboardingP7Start", "jpg")
    static let end = cgImage("OnboardingP7End", "png")

    private static func cgImage(_ name: String, _ ext: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct OnboardingStageVideo: NSViewRepresentable {
    /// false면(동작 줄이기) 끝 프레임만 보여 준다.
    var animate: Bool

    func makeNSView(context: Context) -> StageView { StageView(animate: animate) }
    func updateNSView(_ view: StageView, context: Context) {}
    static func dismantleNSView(_ view: StageView, coordinator: ()) { view.stop() }

    final class StageView: NSView {
        private let poster = CALayer()
        private let finish = CALayer()
        private var playerLayer: AVPlayerLayer?
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        private let animate: Bool
        /// 2026-11-03 20:57 (#116): 두루마리 무대가 7페이지 첫 프레임에 도착한 뒤 직접 재생을 시작한다(false면 창에 붙어도 기다린다).
        private let autoplay: Bool

        init(animate: Bool, autoplay: Bool = true) {
            self.animate = animate
            self.autoplay = autoplay
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor(red: 247 / 255, green: 242 / 255, blue: 229 / 255, alpha: 1).cgColor
            layer?.masksToBounds = true
            for (image, sub) in [(OnboardingStageArt.start, poster), (OnboardingStageArt.end, finish)] {
                sub.contents = image
                sub.contentsGravity = .resizeAspectFill
                layer?.addSublayer(sub)
            }
            let canPlay = animate && OnboardingStageArt.videoURL != nil
            poster.isHidden = !canPlay
            finish.opacity = canPlay ? 0 : 1
            if canPlay, let url = OnboardingStageArt.videoURL {
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                player.actionAtItemEnd = .pause
                player.preventsDisplaySleepDuringVideoPlayback = false
                let playerLayer = AVPlayerLayer(player: player)
                playerLayer.videoGravity = .resizeAspectFill
                layer?.insertSublayer(playerLayer, above: poster)
                self.player = player
                self.playerLayer = playerLayer
                endObserver = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.showFinish() }
                }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var mouseDownCanMoveWindow: Bool { true }   // 안내 창은 배경을 끌어 옮긴다

        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for sub in [poster, finish] { sub.frame = bounds }
            playerLayer?.frame = bounds
            let scale = window?.backingScaleFactor ?? 2
            poster.contentsScale = scale; finish.contentsScale = scale
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let player else { return }
            if window == nil { player.pause() } else if autoplay { player.seek(to: .zero); player.play() }
        }

        /// 처음부터 재생한다(두루마리에서 넘겨받을 때). 처음 프레임 그림이 아래에 깔려 있어 준비 전에도 빈 화면이 없다.
        func start() {
            guard let player else { return }
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                MainActor.assumeIsolated { player.play() }
            }
        }

        /// 2026-11-03: 영상 끝(압축으로 망점이 살짝 무름) → 무손실 PNG. 블록 평균색은 1 이내로 같고(재생기 화면 실측)
        /// 망점만 또렷해지므로, 카메라가 거의 멈춘 ease-out 끝에서 0.5초 디졸브로 바꾼다.
        private func showFinish() {
            CATransaction.begin(); CATransaction.setAnimationDuration(0.5)
            finish.opacity = 1
            CATransaction.commit()
        }

        func stop() {
            player?.pause()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
        }

        deinit { if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }
    }
}

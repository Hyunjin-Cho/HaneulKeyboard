import Foundation

/// 2026-11-07 (#177, 리뷰 app-ui-F-6): 두루마리 자원(OnboardingScroll.json · OnboardingPeople.json)의 모양을 Foundation만 쓰는 이 파일로 뗐다.
/// 그래야 `scripts/run_onboarding_tests.sh`가 제품이 쓰는 같은 구조체로 두 JSON을 실제 디코드하고 참조 PNG의 존재를 확인한다 —
/// 키 이름이 haneul-art 재출력으로 바뀌거나 자원이 번들에서 빠지면 앱이 아니라 시험이 먼저 실패한다. 그림을 읽고 카메라를 옮기는 코드는
/// `OnboardingScroll.swift`에 그대로 있다(같은 `OnboardingScrollArt`의 extension).
///
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
        /// 2026-11-04 (#119): 공중 자세(시소 높은 끝·징검돌 사이)로 들고 나는 사람.
        let hops: [Hop]?

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
    /// 2026-11-04 (#119): 공중 자세로 들고 나는 사람 — rise = 뛰어오르는 땅 자리, land = 내려앉는 땅 자리(세계 pt, 발끝),
    /// up·down = 오르내리는 동안 보일 자세 이름, air_dy = 공중 자세를 페이지 자세보다 아래에 놓고 바꿔 끼울 거리(엉덩이 높이 맞춤).
    struct Hop: Decodable { let who: Int; let rise: [CGFloat]; let land: [CGFloat]; let up: String; let down: String; let air_dy: CGFloat? }
    /// 2026-11-04 (#119): 첫 화면 펼침용 말린 축. w·h = 세계 pt, edge = 펼친 그림이 끝나는 자리(축 왼쪽에서 pt).
    struct Roll: Decodable { let file: String; let w: CGFloat; let h: CGFloat; let edge: CGFloat }
    /// 2026-11-03 20:29: 두루마리에서 떼어 따로 찍은 층(4페이지 시소 판 — 시소 뒤에 선 사람을 가린다). x, y = 세계 왼쪽 위 pt.
    struct Prop: Decodable { let page: Int; let file: String; let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat; let z: CGFloat }
    struct Scroll: Decodable {
        let image_pt: [CGFloat]
        let stage_pt: [CGFloat]
        let stations: [Station]
        let people: [PeopleAt]
        let props: [Prop]?
        let roll: Roll?
    }
    struct Sprite: Decodable { let file: String; let canvas_pt: [CGFloat]; let anchor_pt: [CGFloat] }
    struct People: Decodable { let order: [String]; let sprites: [String: Sprite] }

    /// JSON의 `file` 값이 번들에서 찾는 PNG 이름(확장자 제외). 제품(`image(named:)`·`loadSprite`)과 시험이 같은 규칙을 쓴다.
    static func pngResourceName(_ file: String) -> String { (file as NSString).deletingPathExtension }
}

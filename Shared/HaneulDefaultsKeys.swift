import Foundation

/// 2026-11-07 (#177, 리뷰 app-ui-F-8): 메인 앱과 입력기가 쓰는 defaults 키의 단일 정의. Foundation 전용이라 양쪽 타겟이 컴파일한다.
/// 값은 이미 사용자 저장소에 쓰여 있다 — 바꾸면 설정이 사라진 것처럼 보이므로 바꾸지 않는다(`Tests/AppUITests.swift`가 값을 고정한다).
/// 설정 도메인 이름(`com.hyunjincho.inputmethod.haneul` — 입력기 번들 ID)은 `IMEInstaller.imeBundleID`가 앱 쪽 정본이다.
/// 입력기 쪽(`IMESources/OrphanWatcher.swift`·`HaneulInputController.swift`)은 아직 같은 문자열을 직접 쓴다.
/// 그 일치도 같은 시험이 소스 글을 읽어 확인한다 — 입력기를 이 상수로 바꾸는 일은 입력기 담당의 몫이다.
enum HaneulDefaultsKey {
    /// 메인 앱 기본 도메인. 시작하기(안내)를 끝까지 마쳤는가.
    static let hasCompletedOnboarding = "haneul.hasCompletedOnboarding"
    /// 입력기 도메인. 영타 자동 변환 전역 스위치(없으면 켜짐).
    static let autoEnglishEnabled = "haneul.autoEnglishEnabled"
    /// 입력기 도메인. 메인 앱이 실행할 때마다 자기 경로와 파일 번호(inode)를 남긴다 — 입력기의 자기 정리 판단 재료(#32).
    static let mainAppPath = "haneul.mainAppPath"
    static let mainAppFileID = "haneul.mainAppFileID"
}

import SwiftUI

/// 설정 창의 탭. (2026-09-21, #60)
/// 탭 순서 = 화면에 보이는 순서이고, `SettingsView`의 `TabView` 선택 상태가 이 값을 쓴다.
enum SettingsTab: Hashable {
    case general
    case englishConversion
    case personalDictionary
    case update
    case advanced
}

/// 설정 창 — **탭 컨테이너**. (2026-09-21, #60)
///
/// 종전에는 이 파일 하나의 `Form`에 `Section`이 12개 세로로 쌓여 있었다. 탭 5개로 나누면서
/// 이 파일에는 **탭 구성 + 창 크기 + 전체 제거 다이얼로그 2개**만 남기고, 각 탭의 본문은
/// `GeneralSettingsTab`·`EnglishConversionSettingsTab`·`PersonalDictionaryTab`·
/// `UpdateSettingsSection`·`AdvancedSettingsTab`이 맡는다.
///
/// 시안 정본: `~/Documents/Code-Reviews/20260921/haneulkeyboard/design/settings-spec_2026-09-21.md`
/// (컨트롤 1:1 이동표 C01~C47 · 문구 확정표 · 비주얼 스펙).
///
/// 창 크기는 **640×580 고정**이고 탭마다 바꾸지 않는다 — 이 창은 `Settings` 씬이 아니라
/// `AppDelegate.openSettings()`의 수동 `NSWindow` + `NSHostingController`로 뜨기 때문에
/// 탭별로 높이를 바꾸면 애니메이션 없이 창이 툭툭 튄다.
struct SettingsView: View {
    /// 창 제목. 2026-09-21 (#60): 오너 미결(시안 Q1 — `하늘키보드 설정` 제안)이라 현행 문구를
    /// 유지하되, 바꿀 때 한 줄만 고치면 되도록 여기 한 곳에 둔다.
    /// 쓰는 곳: `AppDelegate.openSettings()`.
    static let windowTitle = "HaneulKeyboard 설정"

    @Bindable var core: AppCore
    @State private var selectedTab: SettingsTab
    @State private var showingUninstallConfirm = false
    @State private var uninstallResult: Uninstaller.Outcome?

    /// 2026-09-21 (#60): `initialTab`은 스크린샷·프리뷰에서 특정 탭을 펼쳐 그리기 위한 초기값이다
    /// (기본은 「일반」). 창을 열 때마다 이 값으로 시작하고, 그 뒤 선택은 `@State`가 기억한다
    /// — 같은 `NSWindow`를 재사용하므로 닫았다 열어도 마지막 탭이 유지된다.
    init(core: AppCore, initialTab: SettingsTab = .general) {
        self.core = core
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(core: core)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            EnglishConversionSettingsTab()
                .tabItem { Label("영타 변환", systemImage: "textformat.abc") }
                .tag(SettingsTab.englishConversion)

            PersonalDictionaryTab()
                .tabItem { Label("개인 사전", systemImage: "character.book.closed") }
                .tag(SettingsTab.personalDictionary)

            // 2026-09-21 (#19): 업데이트는 절 파일 하나가 곧 탭 하나라 별도 탭 뷰를 만들지 않는다.
            Form {
                UpdateSettingsSection(core: core)
            }
            .formStyle(.grouped)
            .tabItem { Label("업데이트", systemImage: "arrow.down.circle") }
            .tag(SettingsTab.update)

            AdvancedSettingsTab(showingUninstallConfirm: $showingUninstallConfirm)
                .tabItem { Label("고급", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
        }
        // 탭 바깥에 한 번만 — 탭 안에 프레임을 주면 바깥 프레임과 싸운다.
        .frame(width: 640, height: 580)
        .alert("하늘키보드를 모두 지울까요?", isPresented: $showingUninstallConfirm) {
            Button("취소", role: .cancel) { }
            Button("모두 지우기", role: .destructive) {
                uninstallResult = Uninstaller.run()
                core.refreshIMEStatus()
            }
        } message: {
            Text("메인 앱·입력기 번들·시스템 등록·사용자 설정을 모두 지웁니다. 되돌릴 수 없습니다.")
        }
        .alert("제거 결과", isPresented: Binding(
            get: { uninstallResult != nil },
            set: { if !$0 { uninstallResult = nil } }
        )) {
            Button("확인", role: .cancel) {
                let keptForRetry = uninstallResult?.keptMainAppForRetry == true
                uninstallResult = nil
                // 전체 제거 후 앱 자신(메뉴바)도 종료 — 파일만 지우면 실행 중인
                // 프로세스가 남아 메뉴바가 그대로 보인다(#11).
                // (review-0712 P2-2) 단, IME 삭제가 실패해 메인 앱을 일부러
                // 남긴 경우엔 종료하지 않는다 — 바로 다시 시도할 수 있어야 한다.
                if !keptForRetry {
                    NSApp.terminate(nil)
                }
            }
            if uninstallResult?.stillEnabledInPicker == true {
                Button("시스템 설정 열기") {
                    let keptForRetry = uninstallResult?.keptMainAppForRetry == true
                    IMEInstaller.openInputSourcesSettings()
                    uninstallResult = nil
                    // 설정 창이 뜬 뒤 앱 종료(메뉴바 정리).
                    // (review-0712 P2-2) 재시도용으로 앱을 남긴 경우는 종료 안 함.
                    guard !keptForRetry else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSApp.terminate(nil)
                    }
                }
            }
        } message: {
            if let r = uninstallResult {
                // (review-0712 P3-8) 문구 생성은 `UninstallOutcome.statusText`
                // (InstallDecisions.swift)에 있다 — 테스트 하네스가 검증한다.
                Text(r.statusText)
            } else {
                Text("")
            }
        }
    }
}

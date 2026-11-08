import SwiftUI

/// 2026-10-10 (#88): 로그인 항목·메뉴바 아이콘·전체 제거를 구획으로 모은다.
/// 2026-11-07 오너(#189): 입력기 설치·제거는 「설치·업데이트」로 옮겼다(`InputMethodSettingsSection`).
/// 전체 제거 확인/결과 창은 SettingsView가 보존한다.
struct AppManagementSettingsTab: View {
    @Bindable var core: AppCore
    @Binding var showingUninstallConfirm: Bool
    /// 2026-11-06 (#154): 메인 앱만 읽는 설정이라 입력기 도메인이 아니라 기본 도메인에 둔다.
    @AppStorage(MenuBarIconDecision.defaultsKey) private var showsMenuBarIcon = true
    /// 2026-11-06 (#160): 시스템 설정에서도 바뀌는 값이라 저장하지 않고 macOS에 물어본다.
    @State private var loginItem = LoginItem.state

    private var isBusy: Bool {
        if core.isPreparingIME { return true }
        switch core.updater.phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    var body: some View {
        Form {
            // 2026-11-06 (#154): 아이콘을 꺼도 메뉴에 있던 일을 여기서 할 수 있다. 설정과 응원하기는 왼쪽 메뉴에 있다.
            // 2026-11-08 오너(#201): `로그인할 때 열기` 구획을 없앴다. 아이콘 토글 하나가 로그인 항목까지 함께 켜고 끈다
            // ("사용자가 이렇게까지 디테일하게 몰라도 된다. 켜면 둘 다 켜고, 끄면 둘 다 끈다").
            HaneulSettingsSection("메뉴바 아이콘") {
                Toggle("메뉴바에 아이콘 보기", isOn: $showsMenuBarIcon)
                    .onChange(of: showsMenuBarIcon) { _, visible in
                        NotificationCenter.default.post(name: .haneulMenuBarIconChanged, object: nil)
                        followIconWithLoginItem(visible)
                    }
                // 2026-11-08 오너(#201): 두 문단을 한 문단으로 줄였다. 아이콘을 끈 뒤 돌아오는 길(응용 프로그램 폴더에서 열면 앱 관리가 열린다)만 남긴다.
                Text("아이콘을 꺼도 한글 입력과 영어 자동 변환은 그대로 돼요. 다시 켜려면 응용 프로그램 폴더에서 하늘키보드를 열어 주세요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                // 시스템 설정에서 로그인 항목을 막아 둔 경우에만 보인다(macOS가 허용을 요구할 때).
                if showsMenuBarIcon && loginItem == .needsApproval {
                    HStack(spacing: 12) {
                        Label("시스템 설정에서 허용해 주세요.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("로그인 항목 열기") { LoginItem.openSystemSettings() }
                    }
                }
                // 2026-11-08 오너(#209): `시작하기 다시 보기`·`메뉴바 앱 종료` 버튼을 뺐다. 둘 다 메뉴바 메뉴에 있다.
            }

            // 2026-11-08 오너(#201): 되돌릴 수 없는 일이라 제목과 버튼 글자를 빨갛게 쓴다. 설명은 한 문장으로 줄였다.
            HaneulSettingsSection("하늘키보드 전체 제거", titleColor: .red) {
                Text("앱과 개인 사전을 모두 지워요.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showingUninstallConfirm = true
                    } label: {
                        Text("하늘키보드 전체 제거…").foregroundStyle(.red)
                    }
                    .disabled(isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = LoginItem.state
        }
    }

    /// 2026-11-08 오너(#201): 아이콘을 켜면 로그인 항목도 켜고, 끄면 함께 끈다. 실패해도 아이콘은 그대로 바뀐다.
    /// 응용 프로그램 폴더 밖의 사본(개발 빌드)은 자동 등록과 같은 기준으로 넣지 않는다.
    /// (Codex 리뷰) 폴더 밖 사본이 자동 등록 기회를 써 버리지 않게, 경로를 먼저 보고 나서 시도했다고 적는다.
    private func followIconWithLoginItem(_ visible: Bool) {
        if visible && !AppMoveDecision.isAlreadyInPlace(bundlePath: Bundle.main.bundlePath) { return }
        UserDefaults.standard.set(true, forKey: LoginItemDecision.autoRegisteredKey)
        try? LoginItem.set(enabled: visible)
        loginItem = LoginItem.state
    }
}

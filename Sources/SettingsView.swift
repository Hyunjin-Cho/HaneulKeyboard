import SwiftUI

extension Notification.Name {
    static let haneulSettingsTabRequested = Notification.Name("haneul.settingsTabRequested")
}

/// 2026-10-11 (#88): 일반을 정리한 네 메뉴. 응원하기는 본문 선택과 별도인 버튼이다.
enum SettingsTab: Hashable, CaseIterable, Identifiable {
    case inputFeatures
    case personalDictionary
    case update
    case appManagement

    var id: Self { self }

    var title: String {
        switch self {
        case .inputFeatures: return "입력 기능"
        case .personalDictionary: return "개인 사전"
        case .update: return "버전·업데이트"
        case .appManagement: return "앱 관리"
        }
    }

    var symbol: String {
        switch self {
        case .inputFeatures: return "textformat.abc"
        case .personalDictionary: return "character.book.closed"
        case .update: return "arrow.down.circle"
        case .appManagement: return "wrench.and.screwdriver"
        }
    }
}

/// 2026-10-10 (#88): 왼쪽 메뉴 160pt + 기존 본문 너비를 확보한 설정 창.
/// 2026-11-05 (#135): 그림이 창 맨 위까지 올라가게 제목 막대를 겹쳤다. 660 + 제목 막대 28 = 전체 688이라 창 크기는 그대로다.
/// 분류·선택 상태·전체 제거 확인/결과 창을 맡고, 각 본문은 별도 뷰가 맡는다.
/// 근거: https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/88 및 사용자 후속 선택.
struct SettingsView: View {
    /// 창 제목. 2026-09-21 (#60): 오너 미결(시안 Q1 — `하늘키보드 설정` 제안)이라 현행 문구를
    /// 유지하되, 바꿀 때 한 줄만 고치면 되도록 여기 한 곳에 둔다.
    /// 쓰는 곳: `AppDelegate.openSettings()`.
    static let windowTitle = "HaneulKeyboard 설정"

    @Bindable var core: AppCore
    @State private var selectedTab: SettingsTab
    @State private var showingSupport = false
    @State private var showingUninstallConfirm = false
    @State private var uninstallResult: Uninstaller.Outcome?

    /// 기본은 「입력 기능」. AppDelegate가 창을 재사용하므로 다시 열어도 마지막 선택을 유지한다.
    init(core: AppCore, initialTab: SettingsTab = .inputFeatures) {
        self.core = core
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsBand(tab: selectedTab)
            HStack(spacing: 0) {
                // 2026-11-05 (#135): 시스템 목록의 파란 선택 칸 대신 안내 버튼과 같은 잉크 칸을 쓴다.
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        SettingsMenuRow(title: tab.title, symbol: tab.symbol, selected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }
                    SettingsMenuRow(title: "응원하기", symbol: "heart", selected: false) { showingSupport = true }
                        .accessibilityLabel(SupportView.title)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.top, 12)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { moveMenu(by: -1) }
                .onKeyPress(.downArrow) { moveMenu(by: 1) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("설정 메뉴")
                .frame(width: SettingsLayout.sidebarWidth)

                Divider()

                // 메뉴 전환으로 뷰를 없애지 않아 입력 중인 사전·시트·오류 상태를 보존한다.
                ZStack {
                    panel(.inputFeatures) { EnglishConversionSettingsTab() }
                    panel(.personalDictionary) {
                        PersonalDictionaryTab(isSelected: selectedTab == .personalDictionary)
                    }
                    panel(.update) {
                        Form { UpdateSettingsSection(core: core) }
                            .formStyle(.grouped)
                    }
                    panel(.appManagement) {
                        AppManagementSettingsTab(core: core,
                            showingUninstallConfirm: $showingUninstallConfirm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .disabled(core.isRemovingProduct)
        .frame(width: 800, height: 688)
        .ignoresSafeArea()
        .scrollContentBackground(.hidden)
        .tint(OnboardingRiso.actionBlue)
        .haneulWindowAppearance()
        .onReceive(NotificationCenter.default.publisher(for: .haneulSettingsTabRequested)) { notification in
            if let tab = notification.object as? SettingsTab { selectedTab = tab }
        }
        .sheet(isPresented: $showingSupport) {
            SupportView { showingSupport = false }
        }
        .alert("하늘키보드를 모두 지울까요?", isPresented: $showingUninstallConfirm) {
            Button("취소", role: .cancel) { }
            Button("모두 지우기", role: .destructive) {
                Task { uninstallResult = await core.removeFullProduct() }
            }
        } message: {
            Text("메인 앱·입력기 번들·시스템 등록·사용자 설정을 모두 지웁니다. 되돌릴 수 없습니다. 입력기 제거에 실패하거나 그 단계의 관리자 암호창을 취소하면 개인 사전과 설정은 보존합니다.")
        }
        .alert("제거 결과", isPresented: Binding(
            get: { uninstallResult != nil },
            set: { if !$0 { uninstallResult = nil } }
        )) {
            Button("확인", role: .cancel) {
                let canExit = uninstallResult?.fullyRemoved == true
                uninstallResult = nil
                // 전체 제거 후 앱 자신(메뉴바)도 종료 — 파일만 지우면 실행 중인
                // 프로세스가 남아 메뉴바가 그대로 보인다(#11).
                // (review-0712 P2-2) 단, IME 삭제가 실패해 메인 앱을 일부러
                // 남긴 경우엔 종료하지 않는다 — 바로 다시 시도할 수 있어야 한다.
                if canExit {
                    NSApp.terminate(nil)
                }
            }
            if uninstallResult?.stillEnabledInPicker == true {
                Button("시스템 설정 열기") {
                    let canExit = uninstallResult?.fullyRemoved == true
                    IMEInstaller.openInputSourcesSettings()
                    uninstallResult = nil
                    // 설정 창이 뜬 뒤 앱 종료(메뉴바 정리).
                    // (review-0712 P2-2) 재시도용으로 앱을 남긴 경우는 종료 안 함.
                    guard canExit else { return }
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
    private func moveMenu(by offset: Int) -> KeyPress.Result {
        let tabs = SettingsTab.allCases
        guard let index = tabs.firstIndex(of: selectedTab),
              tabs.indices.contains(tabs.index(index, offsetBy: offset)) else { return .ignored }
        selectedTab = tabs[tabs.index(index, offsetBy: offset)]
        return .handled
    }

    private func panel<Content: View>(_ tab: SettingsTab,
        @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .disabled(selectedTab != tab)
            .accessibilityHidden(selectedTab != tab)
    }

}

/// 2026-11-05 (#135): 메뉴 한 줄. 선택 칸은 안내의 주 버튼과 같은 잉크(파랑 + 어긋난 분홍 + 잉크 결)다.
private struct SettingsMenuRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).resizable().scaledToFit().frame(width: 18, height: 18)
                Text(title).lineLimit(1)
            }
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected && appearsActive ? .white : .primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background {
                if selected {
                    if appearsActive {
                        RoundedRectangle(cornerRadius: 10).fill(OnboardingRiso.pink.opacity(0.8)).offset(x: 1.5, y: 2)
                        RoundedRectangle(cornerRadius: 10).fill(OnboardingRiso.actionBlue)
                        RisoInkGrain().clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.16))
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

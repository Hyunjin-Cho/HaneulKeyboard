import SwiftUI

extension Notification.Name {
    static let haneulSettingsTabRequested = Notification.Name("haneul.settingsTabRequested")
    /// 2026-11-06 (#154): 설정의 메뉴바 아이콘 항목이 AppDelegate에 알린다.
    static let haneulMenuBarIconChanged = Notification.Name("haneul.menuBarIconChanged")
}

/// 2026-10-11 (#88): 일반을 정리한 메뉴. 응원하기는 본문 선택과 별도인 버튼이다.
/// 2026-11-07 오너(#189): 「입력 기능」을 자동 변환과 단축키·슬래시로 나눠 다섯 메뉴가 됐다. 저장 값은 그대로다.
enum SettingsTab: Hashable, CaseIterable, Identifiable {
    case automatic
    case shortcuts
    case personalDictionary
    case update
    case appManagement

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: return "자동 변환"
        case .shortcuts: return "단축키·슬래시"
        case .personalDictionary: return "개인 사전"
        case .update: return "설치·업데이트"
        case .appManagement: return "앱 관리"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .shortcuts: return "command"
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

    /// 2026-11-06 (#156): 닫으면 창을 놓아주므로 AppDelegate가 마지막 메뉴를 받아 두었다가 다시 열 때 넘겨준다.
    private let onTabChange: (SettingsTab) -> Void

    /// 기본은 「입력 기능」.
    init(core: AppCore, initialTab: SettingsTab = .automatic, onTabChange: @escaping (SettingsTab) -> Void = { _ in }) {
        self.core = core
        self.onTabChange = onTabChange
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
                .background(alignment: .bottomLeading) { SettingsFoot() }
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
                    panel(.automatic) { EnglishConversionSettingsTab() }
                    panel(.shortcuts) { ShortcutSettingsTab() }
                    panel(.personalDictionary) {
                        PersonalDictionaryTab(isSelected: selectedTab == .personalDictionary)
                    }
                    panel(.update) {
                        Form {
                            InputMethodSettingsSection(core: core)
                            UpdateSettingsSection(core: core)
                        }
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
        // 2026-11-07 (#189): 제목 막대 겹침으로 창이 688 + 안전 영역 32 = 720pt가 되는데, 예전엔 내용을 688로 묶은 뒤 위로 붙여
        // 아래 32pt가 빈 종이로 남고 글이 창 중간에서 잘렸다(오너 스크린샷 실측: 창 719, 구분선 끝 686). 안전 영역을 먼저 무시해 바닥까지 채운다.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .frame(width: 800, height: 688)
        .scrollContentBackground(.hidden)
        .tint(OnboardingRiso.actionBlue)
        .haneulWindowAppearance()
        .onChange(of: selectedTab) { _, tab in onTabChange(tab) }
        .onReceive(NotificationCenter.default.publisher(for: .haneulSettingsTabRequested)) { notification in
            if let tab = notification.object as? SettingsTab { selectedTab = tab }
        }
        .sheet(isPresented: $showingSupport) {
            SupportView { showingSupport = false }
        }
        // 2026-11-08 오너(#201): 시스템 경고창(.alert) 대신 한지 바탕의 앱 창으로 묻고 알린다(`RemovalSheets.swift`).
        // 동작은 예전 경고창과 같다. 확인 창은 응원하기 시트와 다른 뷰에 붙여 두 시트가 한 뷰에서 겹치지 않게 한다.
        .background {
            Color.clear
                .sheet(isPresented: $showingUninstallConfirm) {
                    RemovalConfirmSheet(onCancel: { showingUninstallConfirm = false }) {
                        showingUninstallConfirm = false
                        Task { uninstallResult = await core.removeFullProduct() }
                    }
                }
        }
        .overlay {
            Color.clear.allowsHitTesting(false)
                .sheet(isPresented: Binding(
                    get: { uninstallResult != nil },
                    set: { if !$0 { uninstallResult = nil } }
                )) {
                    if let outcome = uninstallResult {
                        RemovalResultSheet(outcome: outcome, onDone: {
                            let canExit = uninstallResult?.fullyRemoved == true
                            uninstallResult = nil
                            // 전체 제거 후 앱 자신(메뉴바)도 종료 — 파일만 지우면 실행 중인
                            // 프로세스가 남아 메뉴바가 그대로 보인다(#11).
                            // (review-0712 P2-2) 단, IME 삭제가 실패해 메인 앱을 일부러
                            // 남긴 경우엔 종료하지 않는다 — 바로 다시 시도할 수 있어야 한다.
                            if canExit { NSApp.terminate(nil) }
                        }, onOpenInputSettings: {
                            let canExit = uninstallResult?.fullyRemoved == true
                            IMEInstaller.openInputSourcesSettings()
                            uninstallResult = nil
                            // 설정 창이 뜬 뒤 앱 종료(메뉴바 정리).
                            // (review-0712 P2-2) 재시도용으로 앱을 남긴 경우는 종료 안 함.
                            guard canExit else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                NSApp.terminate(nil)
                            }
                        })
                        // 2026-11-08 (#201, Codex 리뷰): Esc로 닫히면 onDone을 거치지 않아 다 지운 뒤에도 앱이 남는다.
                        // 결과 창은 버튼으로만 닫는다.
                        .interactiveDismissDisabled()
                    }
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

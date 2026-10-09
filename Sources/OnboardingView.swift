import SwiftUI
import AppKit
import Carbon

/// 2026-10-09 (#80): 단청·리소그래프 안내 5단계, 720×800pt. 연습과 버튼은 실제 앱 경로다.
struct OnboardingView: View {
    static let size = NSSize(width: 720, height: 800)
    @Bindable var core: AppCore
    var onSettings: (SettingsTab) -> Void = { _ in }
    var onSupport: () -> Void = {}
    var onComplete: () -> Void = {}
    @AppStorage("haneul.hasCompletedOnboarding") private var hasCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var step = 0
    @State private var pageID = UUID()
    @State private var navigationDirection: CGFloat = 1
    @State private var installError: String?
    @State private var selectedHaneul = false
    @State private var sourceError: String?
    @State private var focusRequest = UUID()
    @State private var resetRequest = UUID()
    @State private var practiceStage: OnboardingPracticeStage = .empty
    @State private var dictionaryTab = 0
    @State private var shortcut = RevertKey.default
    @State private var autoEnabled = true
    @State private var allWordsEnabled = true

    private let titles = ["한글 모드 그대로 영어까지", "Mac에서 하늘키보드를 선택", "이번엔 직접 쳐봐요",
                          "단축키로 한영 바꾸기", "메뉴바에서 만나요"]
    private let sections = ["만나보기와 설치", "입력 소스", "영타 자동 변환", "되돌리기와 개인 사전", "메뉴바와 후원"]
    private var ready: Bool { core.imeInstalled && !core.imeRefreshNeeded && !core.isPreparingIME }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                hero.id(pageID).transition(.opacity)
            }.frame(height: 142).clipped()
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case 0: installStep
                        case 1: sourceStep
                        case 2: typingStep
                        case 3: dictionaryStep
                        default: finishStep
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .id(pageID)
                .transition(pageTransition)
            }
            .frame(maxHeight: .infinity)
            .clipped()
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    OnboardingPeopleSequence(step: step)
                }.padding(.trailing, 32)
                Divider().padding(.horizontal, 32)
                navigation.padding(.horizontal, 32).frame(height: 76)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .frame(width: Self.size.width, height: Self.size.height)
        .background { OnboardingRisoPaper().ignoresSafeArea() }
        .tint(OnboardingRiso.ink(for: colorScheme))
        .haneulWindowAppearance()
        .ignoresSafeArea()
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default.publisher(
            for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in
                selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        }
        .onReceive(DistributedNotificationCenter.default.publisher(
            for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))) { _ in refresh() }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: OnboardingRiso.eaves).resizable().scaledToFit()
                .frame(width: 312, height: 104.4).offset(x: -15, y: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false).accessibilityHidden(true)
            Text("하늘키보드 시작하기").font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 23)
            Image(nsImage: OnboardingRiso.appIcon).resizable().interpolation(.high)
                .padding(3).frame(width: 60, height: 60)
                .background(OnboardingRiso.ivory).clipShape(Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                .accessibilityLabel("하늘키보드 앱 아이콘")
                .padding(.top, 50).padding(.trailing, 24)
        }.frame(height: 90, alignment: .top)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Text(String(format: "%02d", step + 1) + "  " + sections[step])
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(OnboardingRiso.yellow.opacity(colorScheme == .dark ? 0.10 : 0.24), in: Capsule())
            Text(titles[step]).font(OnboardingRiso.titleFont(size: 31))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 16)).lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(height: 48, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 42).padding(.top, 8)
        .frame(height: 142, alignment: .top)
    }

    private var subtitle: String {
        switch step {
        case 0: "하늘키보드는 한글로 친 영어 단어를 알아보고 바꿔줘요.\n한/영 키를 누르지 않아도 돼요."
        case 1: "키보드 설정에 하늘키보드를 추가하고\n입력 소스로 선택해 주세요."
        case 2: "한글 모드에서 apple을 입력해 보세요.\n영어로 바뀌어요. 한글 모드는 그대로예요."
        case 3: "사전에 없는 단어도 원하는 대로 바꿀 수 있어요."
        default: "설정을 열거나 이 안내를 다시 보고 싶을 때\n메뉴바의 하늘키보드를 눌러 주세요."
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingConversionDemo()
            HStack(spacing: 14) {
                Image(systemName: ready ? "checkmark.circle" : "keyboard").font(.system(size: 25))
                    .foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                VStack(alignment: .leading, spacing: 5) {
                    Text("하늘키보드 두벌식").font(.system(size: 17, weight: .semibold))
                    Text(installStatus).font(.system(size: 14))
                }
                Spacer()
                if !ready {
                    OnboardingButton(core.isPreparingIME ? "확인·설치 중…" : "하늘키보드 설치") {
                        Task {
                            installError = nil
                            if let error = await core.installIME() { installError = error.localizedDescription }
                        }
                    }.disabled(core.isPreparingIME)
                }
            }.padding(18).modifier(OnboardingPrintPanel(tint: OnboardingRiso.pink))
            if let message = installError ?? core.imeActivationError?.localizedDescription {
                Text(message).font(.system(size: 14)).foregroundStyle(.red).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("메뉴바 앱과 입력기는 하나의 하늘키보드예요.", systemImage: "link")
                HStack {
                    Text("함께 지울 때는 설정 → 고급 → 전체 제거")
                    Spacer()
                    Button("설정 열기") { onSettings(.general) }
                }
            }.font(.system(size: 14)).padding(.horizontal, 4)
        }
    }
    private var installStatus: String {
        if core.isPreparingIME { return "설치 상태를 확인하고 있어요" }
        if core.imeRefreshNeeded { return "입력기를 새 버전으로 업데이트해 주세요" }
        if core.imeInstalled { return "설치 완료" }
        if core.imeDisabled { return "설치되어 있어요 · 입력 소스를 다시 켜 주세요" }
        return "아직 설치되지 않았어요"
    }
    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                HStack(alignment: .top, spacing: 8) {
                    guideColumn("1", "키보드", symbol: "keyboard", detail: "시스템 설정\n키보드 → 텍스트 입력")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).padding(.top, 44)
                    guideColumn("2", "편집 → ＋", symbol: "plus.rectangle", detail: "입력 소스 편집\n추가 버튼 누르기")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).padding(.top, 44)
                    guideColumn("3", "하늘키보드", symbol: "checkmark.circle", detail: "한국어\n하늘키보드 (두벌식)")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label(core.imeInstalled ? "입력 소스에 추가되어 있어요" : "입력 소스 추가를 확인해 주세요",
                          systemImage: core.imeInstalled ? "checkmark.circle.fill" : "circle")
                    Label(selectedHaneul ? "지금 하늘키보드를 선택했어요" : "현재 다른 입력 소스를 사용 중이에요",
                          systemImage: selectedHaneul ? "checkmark.circle.fill" : "circle")
                }.font(.system(size: 15))
            }
            HStack(spacing: 12) {
                OnboardingButton("키보드 설정 열기") { IMEInstaller.openInputSourcesSettings() }
                Button("하늘키보드 선택") { selectHaneul() }.disabled(!core.imeInstalled)
                Button("상태 확인") { refresh() }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("기존 Apple ‘두벌식’은 빼고, ‘ABC’는 남겨 주세요.", systemImage: "keyboard")
                Text("Caps Lock을 짧게 누르면 한글과 영어가 바뀌어요.\n키보드 설정의 ‘Caps Lock 키로 ABC 입력 소스 전환’도 확인해 주세요.")
                    .lineSpacing(4)
            }.font(.system(size: 14))
            sourceFailure
        }
    }
    private var typingStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            practice(manual: false)
            VStack(alignment: .leading, spacing: 6) {
                Text("다른 단어도 자유롭게 쳐보세요.").font(.system(size: 16, weight: .medium))
                HStack(spacing: 9) {
                    exampleWord("bike", tint: OnboardingRiso.cyan)
                    exampleWord("camera", tint: OnboardingRiso.pink)
                    exampleWord("water", tint: OnboardingRiso.yellow)
                }
                Text("개인 사전의 변환 추가·변환 금지도 그대로 적용돼요.").font(.system(size: 14))
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).modifier(OnboardingPrintPanel(tint: OnboardingRiso.yellow, strongerYellow: true))
        }
    }

    private var dictionaryStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            practice(manual: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("설정 → 개인 사전").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button("개인 사전 열기") { onSettings(.personalDictionary) }
                }
                Picker("개인 사전 기능", selection: $dictionaryTab) {
                    Text("변환 추가").tag(0)
                    Text("변환 금지").tag(1)
                    Text("되돌린 단어").tag(2)
                }.pickerStyle(.segmented)
                Text(["기본 사전에 없는 이름도 영어로 바꿔요.\n예: 스페인어 인사말 hola를 변환 추가에 등록해 보세요.",
                      "자동으로 바꾸지 않을 단어를 등록해요.\n변환 추가에도 있는 단어라면 변환 금지가 우선해요.",
                      "영어에서 한글로 직접 되돌린 단어를 모아 보여줘요.\n‘금지’를 누르면 다음부터 자동으로 바꾸지 않아요."][dictionaryTab])
                    .font(.system(size: 14)).lineSpacing(3)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .topLeading)
            }.padding(10).modifier(OnboardingPrintPanel(tint: OnboardingRiso.pink))
            Label("터미널은 \(shortcut.displayName) 단축키가 작동하지 않아요.", systemImage: "terminal")
                .font(.system(size: 14, weight: .bold)).padding(.horizontal, 4)
        }
    }

    private func practice(manual: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    OnboardingSketchNote(text: "여기에 apple을 쳐봐요", compact: true)
                        .opacity(practiceStage == .empty ? 1 : 0)
                    if practiceStage != .empty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cueTitle(manual: manual)).font(OnboardingHandwriting.font())
                            if showPracticeKey(manual: manual) { keycap(manual ? shortcut.displayName : "Space") }
                        }.padding(.top, 4)
                    }
                }.frame(height: 70, alignment: .top).foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                Spacer()
                Button("비우기", systemImage: "arrow.counterclockwise") { resetRequest = UUID() }
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: false)).padding(.top, 8)
            }.animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: practiceStage)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(OnboardingRiso.yellow.opacity(0.65)).offset(x: 3, y: 4)
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.14) : Color(red: 1, green: 0.99, blue: 0.96))
                OnboardingPracticeField(focusRequest: focusRequest, resetRequest: resetRequest,
                                        accessibilityName: manual ? "한영 되돌리기 연습" : "영타 자동 변환 연습",
                                        placeholder: "", onProgressChange: { [observedPage = pageID] stage in
                                            // 전환 중 퇴장하는 입력칸의 늦은 알림이 새 화면을 바꾸지 않게 한다.
                                            guard pageID == observedPage else { return }
                                            practiceStage = stage
                                        })
                    .transaction { $0.animation = nil }
                    .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(OnboardingRiso.cyan.opacity(0.60), lineWidth: 1.3))
            .frame(height: 94)
            Text(practiceMessage(manual: manual)).font(.system(size: 16))
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .topLeading)
            HStack {
                Label(selectedHaneul ? "하늘키보드 선택됨" : "하늘키보드를 선택해 주세요",
                      systemImage: selectedHaneul ? "checkmark.circle.fill" : "keyboard")
                    .font(.system(size: 14))
                Spacer()
                if !selectedHaneul {
                    Button("하늘키보드 선택") {
                        if selectHaneul() { focusRequest = UUID() }
                    }.disabled(!core.imeInstalled)
                }
            }
            if !autoEnabled || (manual && !allWordsEnabled) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(!autoEnabled ? "현재 이 앱의 자동 변환이 꺼져 있어요." : "‘모든 단어로 확대’가 꺼져 있어 직전 자동 변환만 되돌릴 수 있어요.")
                        .font(.system(size: 14))
                    Button("영타 변환 설정 열기") { onSettings(.englishConversion) }
                }
            }
            sourceFailure
        }.padding(.horizontal, 8)
    }

    private func showPracticeKey(manual: Bool) -> Bool {
        manual || [.composing, .readyToCommit, .other].contains(practiceStage)
    }
    private func cueTitle(manual: Bool) -> String {
        if manual { return practiceStage == .reverted ? "한 번 더 눌러봐요" : "이제 이 키를 눌러봐요" }
        switch practiceStage {
        case .converted: return "됐어요! 한글 모드는 그대로"
        case .english: return "이번엔 한글 모드로 쳐봐요"
        default: return "다 썼으면 Space 한 번"
        }
    }
    private func practiceMessage(manual: Bool) -> String {
        if manual {
            switch practiceStage {
            case .reverted: return "한글로 바뀌었어요. 한 번 더 누르면 영어로 돌아가요."
            case .converted: return "영어로 바뀌었어요. 다시 눌러 한글로 바꿔보세요."
            default: return "apple을 입력한 뒤 \(shortcut.displayName)를 눌러보세요."
            }
        }
        switch practiceStage {
        case .converted: return "메ㅔㅣㄷ가 apple로 바뀌었어요. 계속 한글로 입력할 수 있어요."
        case .english: return "apple이 입력됐어요. 한글 모드에서 입력하면 자동 변환을 체험해요."
        case .readyToCommit: return "이제 Space를 누르면 영어 단어를 확인해요."
        case .other: return "자유롭게 입력해도 좋아요. 단어를 쓴 뒤 Space를 눌러보세요."
        default: return "apple을 입력하고 Space를 눌러보세요."
        }
    }

    private func exampleWord(_ word: String, tint: Color) -> some View {
        Text(word).font(.system(size: 16, weight: .medium, design: .serif))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
    private func keycap(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(OnboardingRiso.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.16)))
    }
    private var finishStep: some View {
        OnboardingRisoFinish(ready: ready,
            onSettings: { onSettings(.general) },
            onReplay: { go(to: 0) },
            onSupport: onSupport,
            onInstall: { go(to: 0) })
    }
    private var navigation: some View {
        HStack {
            OnboardingButton("이전", navigation: true) { go(to: step - 1) }.disabled(step == 0 || core.isPreparingIME)
                .frame(width: 180, alignment: .leading)
            Spacer()
            HStack(spacing: 12) {
                ForEach(0..<5) { index in
                    Button { go(to: index) } label: {
                        Capsule().fill(index == step ? OnboardingRiso.cyan : Color.secondary.opacity(0.3))
                            .frame(width: index == step ? 23 : 7, height: 7).padding(.vertical, 8)
                    }.buttonStyle(.plain).accessibilityLabel("\(index + 1)단계 \(sections[index])")
                        .accessibilityAddTraits(index == step ? .isSelected : []).disabled(core.isPreparingIME)
                }
            }
            Spacer()
            Group {
                if step == 4 {
                    OnboardingButton("하늘키보드 시작하기", navigation: true) {
                        if ready {
                            hasCompleted = true
                            onComplete()
                        } else {
                            go(to: 0)
                        }
                    }
                } else {
                    OnboardingButton("다음", navigation: true) { go(to: step + 1) }
                }
            }.disabled(core.isPreparingIME).frame(width: 180, alignment: .trailing)
        }
    }
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 18 * navigationDirection)),
            removal: .opacity.combined(with: .offset(x: -18 * navigationDirection)))
    }

    private func go(to destination: Int) {
        guard (0..<titles.count).contains(destination), destination != step, !core.isPreparingIME else { return }
        navigationDirection = destination > step ? 1 : -1
        refresh()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
            step = destination
            pageID = UUID()
            practiceStage = .empty
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(OnboardingPrintPanel())
    }
    private func guideColumn(_ number: String, _ title: String, symbol: String, detail: String) -> some View {
        let tint = number == "1" ? OnboardingRiso.yellow : number == "2" ? OnboardingRiso.cyan : OnboardingRiso.pink
        return VStack(spacing: 10) {
            Text(number).font(OnboardingRiso.titleFont(size: 18))
            Image(systemName: symbol).font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.monochrome).foregroundStyle(.primary)
                .frame(width: 62, height: 54)
                .background(tint.opacity(colorScheme == .dark ? 0.23 : 0.20), in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 14)).lineSpacing(4).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private var sourceFailure: some View {
        if let sourceError { Text(sourceError).font(.system(size: 14)).foregroundStyle(.red) }
    }
    private func refresh() {
        core.refreshIMEStatus()
        selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        let defaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)
        shortcut = RevertKey.resolve(rawValue: defaults?.string(forKey: RevertKey.defaultsKey))
        allWordsEnabled = defaults?.object(forKey: RevertKey.manualToggleAllWordsKey) as? Bool
            ?? RevertKey.manualToggleAllWordsDefault
        autoEnabled = AutoConvertPolicy.allowed(
            globalEnabled: defaults?.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true,
            disabledIDs: defaults?.stringArray(forKey: AutoConvertPolicy.disabledAppsKey) ?? [],
            clientBundleID: Bundle.main.bundleIdentifier)
    }
    @discardableResult private func selectHaneul() -> Bool {
        let success = InputSwitcher.selectKorean()
        selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        sourceError = success ? nil : "하늘키보드를 선택하지 못했어요. 키보드 설정에서 입력 소스를 추가해 주세요."
        return success
    }
}

private struct OnboardingButton: View {
    let title: String
    let navigation: Bool
    var action: () -> Void
    init(_ title: String, navigation: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.navigation = navigation; self.action = action
    }
    var body: some View {
        Button(title, action: action)
            .buttonStyle(OnboardingRisoButtonStyle(prominent: navigation)).controlSize(.large)
    }
}

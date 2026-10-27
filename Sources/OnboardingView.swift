import SwiftUI
import AppKit
import Carbon

/// 2026-10-12: 한 화면에서 한 기능씩 연습하는 단청 안내 7단계, 720×800pt.
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
    @State private var shortcut = RevertKey.default
    @State private var autoEnabled = true
    @State private var allWordsEnabled = true
    @State private var phoneticEnabled = RevertKey.phoneticDefault
    @State private var slashEnabled = SlashEnglishSession.defaultEnabled

    private enum PracticeLesson: Equatable {
        case automatic, reversal, registeredWord, slash
        var manual: Bool { self == .reversal || self == .registeredWord }
        var hint: String {
            switch self {
            case .automatic, .reversal: "여기에 apple을 쳐봐요"
            case .registeredWord: "여기에 바나나를 쳐봐요"
            case .slash: "여기에 /help를 쳐봐요"
            }
        }
        var accessibilityName: String {
            switch self {
            case .automatic: "영타 자동 변환 연습"
            case .reversal: "한영 되돌리기 연습"
            case .registeredWord: "등록 한글 단어 변환 연습"
            case .slash: "슬래시 영어 입력 연습"
            }
        }
    }

    private let titles = ["한글 모드 그대로 영어까지", "Mac에서 하늘키보드를 선택", "이번엔 직접 쳐봐요",
                          "단축키로 되돌려요", "한글 단어도 영어로", "슬래시 뒤에는 바로 영어", "메뉴바에서 만나요"]
    private let sections = ["만나보기와 설치", "입력 소스", "영타 자동 변환", "한영 되돌리기", "등록 단어 변환", "슬래시 영어 입력", "메뉴바와 후원"]
    private var ready: Bool { core.imeInstalled && !core.imeRefreshNeeded && !core.isPreparingIME }

    init(core: AppCore, initialStep: Int = 0,
         onSettings: @escaping (SettingsTab) -> Void = { _ in },
         onSupport: @escaping () -> Void = {}, onComplete: @escaping () -> Void = {}) {
        self.core = core
        self.onSettings = onSettings
        self.onSupport = onSupport
        self.onComplete = onComplete
        _step = State(initialValue: min(max(initialStep, 0), 6))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                hero.id(pageID).transition(.opacity)
            }.frame(height: 142).clipped()
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch step {
                        case 0: installStep
                        case 1: sourceStep
                        case 2: typingStep
                        case 3: reversalStep
                        case 4: registeredWordStep
                        case 5: slashStep
                        default: finishStep
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48).padding(.vertical, 8)
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
        case 1: core.imeInstalled
            ? "입력 소스에 하늘키보드가 추가됐어요.\n아래 버튼으로 바로 선택해 주세요."
            : "키보드 설정에 하늘키보드를 추가하고\n입력 소스로 선택해 주세요."
        case 2: "한글 모드에서 apple을 입력해 보세요.\n영어로 바뀌어요. 한글 모드는 그대로예요."
        case 3: "방금 바뀐 영어를 \(shortcut.displayName)로 되돌려요.\n다시 누르면 영어로 돌아와요."
        case 4: "바나나를 쓰고 \(shortcut.displayName)를 누르면 banana.\n등록된 한글 단어를 영어로 바꿔요."
        case 5: "한글 모드에서 /help를 입력해 보세요.\n슬래시 뒤에는 바로 영어가 나와요."
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
            settingsRefreshWarning
            VStack(alignment: .leading, spacing: 8) {
                Label("메뉴바 앱과 입력기는 하나의 하늘키보드예요.", systemImage: "link")
                HStack {
                    Text("함께 지울 때는 설정 → 앱 관리 → 하늘키보드 전체 제거")
                    Spacer()
                    Button("앱 관리 열기") { onSettings(.appManagement) }
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
                    guideColumn("1", core.imeInstalled ? "설치 완료" : "키보드", symbol: "keyboard",
                                detail: core.imeInstalled ? "입력 소스에\n추가되어 있어요" : "시스템 설정\n키보드 → 텍스트 입력")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).padding(.top, 44)
                    guideColumn("2", core.imeInstalled ? "아래 버튼" : "편집 → ＋",
                                symbol: core.imeInstalled ? "hand.tap" : "plus.rectangle",
                                detail: core.imeInstalled ? "하늘키보드 선택\n버튼 누르기" : "입력 소스 편집\n추가 버튼 누르기")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).padding(.top, 44)
                    guideColumn("3", "하늘키보드", symbol: "checkmark.circle",
                                detail: core.imeInstalled ? "한글 입력을\n시작해 보세요" : "한국어\n하늘키보드 (두벌식)")
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
                    .disabled(core.isPreparingIME)
                Button("하늘키보드 선택") { selectHaneul() }.disabled(!core.imeInstalled)
                Button("상태 확인") { refresh() }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("기존 Apple ‘두벌식’은 빼고, ‘ABC’는 남겨 주세요.", systemImage: "keyboard")
                Text("Caps Lock을 짧게 누르면 한글과 영어가 바뀌어요.\n키보드 설정의 ‘Caps Lock 키로 ABC 입력 소스 전환’도 확인해 주세요.")
                    .lineSpacing(4)
            }.font(.system(size: 14))
            sourceFailure
            settingsRefreshWarning
        }
    }
    private var typingStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            practice(.automatic)
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

    private var reversalStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            practice(.reversal)
            VStack(alignment: .leading, spacing: 6) {
                Text("방금 변환한 단어를 다시 한글로")
                    .font(.system(size: 16, weight: .semibold))
                Text("apple을 친 뒤 Space → \(shortcut.displayName)를 눌러보세요.\n같은 단축키를 한 번 더 누르면 영어로 돌아와요.")
                    .font(.system(size: 14)).lineSpacing(3)
            }.padding(14).modifier(OnboardingPrintPanel(tint: OnboardingRiso.yellow, strongerYellow: true))
            terminalShortcutNote
        }
    }

    private var registeredWordStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            practice(.registeredWord)
            VStack(alignment: .leading, spacing: 6) {
                Text("바나나 → banana · 사과 → apple · 현물 → spot")
                    .font(.system(size: 15, weight: .medium))
                Text("등록된 표기만 바꿔요. 일반 Space에서는 한글 그대로예요.")
                    .font(.system(size: 14))
                HStack {
                    Text("나만의 변환 규칙은 설정 → 개인 사전에서")
                        .font(.system(size: 13))
                    Spacer(minLength: 4)
                    Button("개인 사전 열기") { onSettings(.personalDictionary) }
                        .font(.system(size: 13))
                }.padding(.top, 4)
            }.padding(12).modifier(OnboardingPrintPanel(tint: OnboardingRiso.cyan))
            terminalShortcutNote
        }
    }

    private var slashStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            practice(.slash)
            VStack(alignment: .leading, spacing: 7) {
                Text("/help → Space → 다시 한글 입력")
                    .font(.system(size: 16, weight: .semibold))
                Text("/는 그대로 남고, 뒤의 글자는 즉시 영어로 나와요.\n일반 Space를 누르면 공백이 들어가고 한글 모드로 돌아와요.")
                    .font(.system(size: 14)).lineSpacing(3)
                HStack {
                    Text("기본으로 켜져 있어요. 설정에서 끌 수 있어요.")
                        .font(.system(size: 13))
                    Spacer(minLength: 4)
                    Button("입력 기능 설정") { onSettings(.inputFeatures) }
                        .font(.system(size: 13))
                }
            }.padding(12).modifier(OnboardingPrintPanel(tint: OnboardingRiso.yellow, strongerYellow: true))
        }
    }

    private var terminalShortcutNote: some View {
        Label("터미널에서는 \(shortcut.displayName)로 되돌릴 수 없어요.", systemImage: "terminal")
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 8)
    }

    private func practice(_ lesson: PracticeLesson) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                ZStack(alignment: .topLeading) {
                    OnboardingSketchNote(text: lesson.hint, compact: true)
                        .opacity(practiceStage == .empty || lesson == .slash ? 1 : 0)
                    if practiceStage != .empty && lesson != .slash {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cueTitle(lesson)).font(OnboardingHandwriting.font())
                            if showPracticeKey(lesson) { keycap(practiceKey(lesson)) }
                        }.padding(.top, 4)
                    }
                }.frame(height: 66, alignment: .top).foregroundStyle(OnboardingRiso.ink(for: colorScheme))
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
                                        accessibilityName: lesson.accessibilityName,
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
            Text(practiceMessage(lesson)).font(.system(size: 15))
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
            if (lesson == .automatic || lesson == .reversal) && !autoEnabled
                || lesson == .reversal && !allWordsEnabled
                || lesson == .registeredWord && !phoneticEnabled
                || lesson == .slash && !slashEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    if (lesson == .automatic || lesson == .reversal) && !autoEnabled {
                        Text("현재 이 앱의 자동 변환이 꺼져 있어요.")
                    }
                    if lesson == .reversal && !allWordsEnabled {
                        Text("영어 글자를 한글 자판 글자로 바꾸는 기능이 꺼져 있어요. 직전 자동 변환은 되돌릴 수 있어요.")
                    }
                    if lesson == .registeredWord && !phoneticEnabled {
                        Text("바나나를 banana로 바꾸는 기능이 꺼져 있어요. 설정에서 ‘등록 단어 변환’를 켜 주세요.")
                    }
                    if lesson == .slash && !slashEnabled {
                        Text("슬래시 영어 입력이 꺼져 있어요. 설정에서 켜고 연습해 주세요.")
                    }
                    Button("입력 기능 설정 열기") { onSettings(.inputFeatures) }
                }.font(.system(size: 14))
            }
            sourceFailure
        }.padding(.horizontal, 8)
    }

    private func showPracticeKey(_ lesson: PracticeLesson) -> Bool {
        lesson.manual || [.composing, .readyToCommit, .other].contains(practiceStage)
    }
    private func practiceKey(_ lesson: PracticeLesson) -> String {
        if lesson == .registeredWord { return shortcut.displayName }
        if lesson == .reversal && [.converted, .reverted, .english].contains(practiceStage) {
            return shortcut.displayName
        }
        return "Space"
    }
    private func cueTitle(_ lesson: PracticeLesson) -> String {
        if lesson == .registeredWord { return practiceStage == .reverted ? "한 번 더 눌러봐요" : "이제 이 키를 눌러봐요" }
        if lesson == .reversal && [.converted, .reverted, .english].contains(practiceStage) {
            return practiceStage == .reverted ? "한 번 더 누르면 영어로" : "이 키로 한글을 되찾아요"
        }
        switch practiceStage {
        case .converted: return "됐어요! 한글 모드는 그대로"
        case .english: return "이번엔 한글 모드로 쳐봐요"
        default: return "다 썼으면 Space 한 번"
        }
    }
    private func practiceMessage(_ lesson: PracticeLesson) -> String {
        if lesson == .slash { return "/help를 쓰고 Space를 누른 뒤, 한글도 이어서 쳐보세요." }
        if lesson.manual {
            switch practiceStage {
            case .reverted: return "한글로 바뀌었어요. 한 번 더 누르면 영어로 돌아가요."
            case .converted: return "영어로 바뀌었어요. 다시 눌러 한글로 바꿔보세요."
            default: return lesson == .registeredWord
                ? "바나나를 입력한 뒤 \(shortcut.displayName)를 눌러보세요."
                : "apple을 입력하고 Space → \(shortcut.displayName)를 눌러보세요."
            }
        }
        switch practiceStage {
        case .converted: return "영어로 바뀌었어요. 계속 한글로 입력할 수 있어요."
        case .english: return "영어가 입력됐어요. 한글 모드에서 입력하면 자동 변환을 체험해요."
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
            onSettings: { onSettings(.inputFeatures) },
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
                ForEach(titles.indices, id: \.self) { index in
                    Button { go(to: index) } label: {
                        Capsule().fill(index == step ? OnboardingRiso.cyan : Color.secondary.opacity(0.3))
                            .frame(width: index == step ? 23 : 7, height: 7).padding(.vertical, 8)
                    }.buttonStyle(.plain).accessibilityLabel("\(index + 1)단계 \(sections[index])")
                        .accessibilityAddTraits(index == step ? .isSelected : []).disabled(core.isPreparingIME)
                }
            }
            Spacer()
            Group {
                if step == titles.count - 1 {
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
    @ViewBuilder private var settingsRefreshWarning: some View {
        if let warning = core.imeSettingsRefreshWarning {
            Text(warning).font(.system(size: 14)).foregroundStyle(.orange).textSelection(.enabled)
        }
    }
    private func refresh() {
        core.refreshIMEStatus()
        selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        let defaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)
        shortcut = RevertKey.resolve(rawValue: defaults?.string(forKey: RevertKey.defaultsKey))
        allWordsEnabled = defaults?.object(forKey: RevertKey.manualToggleAllWordsKey) as? Bool
            ?? RevertKey.manualToggleAllWordsDefault
        phoneticEnabled = defaults?.object(forKey: RevertKey.phoneticKey) as? Bool ?? RevertKey.phoneticDefault
        slashEnabled = defaults?.object(forKey: SlashEnglishSession.defaultsKey) as? Bool
            ?? SlashEnglishSession.defaultEnabled
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

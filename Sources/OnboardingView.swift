import SwiftUI
import AppKit
import Carbon

/// 2026-10-18: 일곱 단계를 본문 스크롤 없이 읽는다. 작은 화면에서는 장식 여백을 줄인다.
struct OnboardingView: View {
    static let size = NSSize(width: 820, height: 900)
    /// 2026-11-03 17:06 오너 승인(#115): 창은 정해 둔 두 크기로만 연다 — 보통 900, 작은 780.
    /// 화면에 들어가는 것 중 큰 쪽을 고른다. 검수할 크기를 둘로 묶으려고 화면에 맞춰 아무 높이나 쓰던 방식을 버렸다.
    static let presetHeights: [CGFloat] = [900, 780]
    /// 작은 창(780)의 카드 높이. 이보다 낮은 화면(드물다)에서는 카드를 지키고 모자란 만큼 무대 위아래를 자른다.
    static var smallCardHeight: CGFloat { presetHeights[1] - (size.width / stageAspect).rounded() }
    var windowSize = Self.size
    private var compact: Bool { windowSize.height < 850 }
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
            case .registeredWord: "여기에 카메라를 쳐봐요"
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
        // 2026-11-03 (#115 블로킹): 1~7 모두 같은 틀(위 무대 + 아래 종이 카드). 안의 내용만 페이지마다 바뀐다.
        framePage
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .frame(width: windowSize.width, height: windowSize.height)
        .background { OnboardingRisoPaper().ignoresSafeArea() }
        .background { OnboardingPageNavigation { go(to: step + $0) } }
        .tint(OnboardingRiso.ink(for: colorScheme))
        .haneulWindowAppearance()
        .ignoresSafeArea()
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(DistributedNotificationCenter.default.publisher(
            for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in
                refreshSelection()
        }
        .onReceive(DistributedNotificationCenter.default.publisher(
            for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))) { _ in refresh() }
    }

    // MARK: 같은 틀 — 위 무대 + 아래 종이 카드 (2026-11-03, #115 블로킹)
    // 2026-11-03 16:10 오너 기획: 모든 안내 페이지가 같은 아트·UI 틀을 쓰고 안의 내용만 바뀐다(가볍고 이해하기 쉽게).
    // 그 전 #113은 콘티 v1의 페이지별 비율(1.46 → 1.9 → 1.32)을 따라 7페이지만 무대가 컸다. 그 비율은 오너 기획과 어긋났다.
    // 2026-11-03 16:43 오너 결정: 무대 2.39:1. 후보 1.85·2.0·2.39를 같은 내용으로 찍어 비교했다(#115).
    // 2.0은 위·아래 중 어디가 중심인지 안 느껴졌다. 2.39는 위 = 움직이는 그림, 아래 = 본문이라는 위계가 분명하다.
    static let stageAspect: CGFloat = 2.39
    static let stagePage = 6
    /// 블로킹 측정용: 카드 윗부분(제목 + 본문) 높이를 하네스에 알린다. 제품에서는 nil이다.
    static var cardTopHeightProbe: ((Int, CGFloat) -> Void)?

    private var stageHeight: CGFloat {
        min((windowSize.width / Self.stageAspect).rounded(), windowSize.height - Self.smallCardHeight)
    }

    private var framePage: some View {
        ZStack(alignment: .top) {
            stage
                .frame(width: windowSize.width, height: stageHeight)
                .clipped()
                .accessibilityHidden(true)
            frameCard
                .frame(width: windowSize.width - 20, height: windowSize.height - stageHeight, alignment: .top)
                .background(alignment: .top) { cardPaper.frame(height: windowSize.height - stageHeight + 40) }
                .offset(y: stageHeight)
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .clipped()
    }

    @ViewBuilder private var stage: some View {
        if step == Self.stagePage {
            OnboardingStageVideo(animate: !reduceMotion)
        } else {
            // 블로킹: 1~6 그림 자리. 검수 하네스가 이 키 색 자리에 콘티 장면을 갈아 끼운다.
            Color(red: 0, green: 1, blue: 0)
        }
    }

    private var cardPaper: some View {
        UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
            .fill(colorScheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.19) : Color(red: 250 / 255, green: 246 / 255, blue: 236 / 255))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: -2)
    }

    private var frameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                cardTitle
                pageBody.padding(.top, compact ? 10 : 14)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if step == Self.stagePage { stageMenuBar.padding(.top, 2) }
            }
            .padding(.horizontal, compact ? 24 : 30).padding(.top, compact ? 14 : 18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [step] height in
                Self.cardTopHeightProbe?(step, height)
            }
            .id(pageID)
            .transition(pageTransition)
            .accessibilityIdentifier("onboarding-page-content")
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 22)
            navigation.padding(.horizontal, 22).frame(height: compact ? 58 : 64)
        }
    }

    private var cardTitle: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(titles[step]).font(OnboardingRiso.titleFont(size: 27))
                Text(String(format: "%02d", step + 1) + "  " + sections[step])
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(OnboardingRiso.yellow.opacity(colorScheme == .dark ? 0.10 : 0.24), in: Capsule())
            }
            Text(subtitle).font(.system(size: 14)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var pageBody: some View {
        switch step {
        case 0: installStep
        case 1: sourceStep
        case 2: typingStep
        case 3: reversalStep
        case 4: registeredWordStep
        case 5: slashStep
        default: menuBarStep
        }
    }

    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button("하늘키보드 설정", systemImage: "slider.horizontal.3") { onSettings(.inputFeatures) }
                Button("시작하기 다시 보기", systemImage: "play.circle") { go(to: 0) }
                Button("응원하기", systemImage: "heart") { onSupport() }
            }.buttonStyle(OnboardingRisoButtonStyle(prominent: false)).font(.system(size: 13)).padding(.top, 3)
            if ready {
                Text("하늘키보드는 영원히 무료입니다. 후원은 자유롭게 선택해 주세요.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("시작하기를 누르면 입력기 설치·설정을 이어갈 수 있어요.").font(.system(size: 13))
                    Button("설치 단계로 이동") { go(to: 0) }.font(.system(size: 13)).fixedSize()
                }
            }
        }
    }

    /// 메뉴바 자리를 알려 주는 작은 모형(옛 7페이지의 연필 동그라미를 카드 오른쪽에 옮겼다).
    private var stageMenuBar: some View {
        let ink = OnboardingRiso.ink(for: colorScheme)
        return HStack(spacing: 14) {
            Image(systemName: "wifi").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
            Image(nsImage: HaneulStatusIcon.image)
                .resizable().renderingMode(.template).scaledToFit().frame(width: 20, height: 20)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .accessibilityLabel("하늘키보드 메뉴바 아이콘")
                .overlay {
                    OnboardingPencilRing().stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) {
                    OnboardingMenuHint().foregroundStyle(ink).offset(y: 50).allowsHitTesting(false)
                }
            Text("10:30").font(.system(size: 13, weight: .medium)).monospacedDigit()
        }.fixedSize().frame(width: 190, height: 110, alignment: .top)
    }

    private var subtitle: String {
        switch step {
        case 0: "하늘키보드는 한글로 친 영어 단어를 알아보고 바꿔줘요.\n한/영 키를 누르지 않아도 돼요."
        case 1: core.imeInstalled
            ? "입력 소스에 하늘키보드가 추가됐어요.\n메뉴바의 입력 소스에서 하늘키보드를 선택해 주세요."
            : "키보드 설정에 하늘키보드를 추가하고\n입력 소스로 선택해 주세요."
        case 2: "한글 모드에서 apple을 입력해 보세요.\n영어로 바뀌어요. 한글 모드는 그대로예요."
        case 3: "방금 바뀐 영어를 \(shortcut.displayName)로 되돌려요.\n다시 누르면 영어로 돌아와요."
        case 4: "카메라를 쓰고 \(shortcut.displayName)를 누르면 camera.\n다시 누르면 내가 쓴 한글로 돌아와요."
        case 5: "한글 모드에서 /help를 입력해 보세요.\n슬래시 뒤에는 바로 영어가 나와요."
        default: "설정을 열거나 이 안내를 다시 보고 싶을 때\n메뉴바의 하늘키보드를 눌러 주세요."
        }
    }

    // 2026-11-03 (#115): 본문은 카드 폭을 꽉 채운 가로 띠를 위아래로 쌓는다. 띠 안의 내용은 왼쪽에서 오른쪽으로 흐른다.
    // 오너(16:43): 왼쪽 상자·오른쪽 상자로 나누면 보기 불편하다. 무대 그림이 가로로 놓였으니 UI도 가로로 가야 한다.
    // 문구·기능·글자 크기는 그대로다.
    private var installStep: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            OnboardingConversionDemo(compact: compact)
            HStack(spacing: 14) {
                Image(systemName: ready ? "checkmark.circle" : "keyboard").font(.system(size: 25))
                    .foregroundStyle((ready ? FeedbackStatus.success : .pending).color(in: colorScheme))
                VStack(alignment: .leading, spacing: 5) {
                    Text("하늘키보드 두벌식").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(installStatus).font(.system(size: 14))
                        .foregroundStyle((ready ? FeedbackStatus.success : .pending).color(in: colorScheme))
                }
                Spacer(minLength: 0)
                if !ready {
                    OnboardingButton(core.isPreparingIME ? "확인·설치 중…" : "하늘키보드 설치") {
                        Task {
                            installError = nil
                            if let error = await core.installIME() { installError = error.localizedDescription }
                        }
                    }.disabled(core.isPreparingIME).fixedSize()
                }
            }.feedbackPanel(.information)
            if let message = installError ?? core.imeActivationError?.localizedDescription ?? core.imeSettingsRefreshWarning {
                Text(message).font(.system(size: 14))
                    .foregroundStyle(FeedbackStatus.warning.color(in: colorScheme)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).feedbackPanel(.warning)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("메뉴바 앱과 입력기는 하나의 하늘키보드예요.", systemImage: "link")
                HStack {
                    Text("함께 지울 때는 설정 → 앱 관리 → 하늘키보드 전체 제거")
                    Spacer()
                    Button("앱 관리 열기") { onSettings(.appManagement) }
                }
            }.font(.system(size: 14)).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            card {
                HStack(alignment: .center, spacing: 8) {
                    guideStep("1", core.imeInstalled ? "설치 완료" : "키보드", symbol: "keyboard",
                              detail: core.imeInstalled ? "입력 소스에\n추가되어 있어요" : "시스템 설정\n키보드 → 텍스트 입력")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    guideStep("2", core.imeInstalled ? "메뉴바" : "편집 → ＋",
                              symbol: core.imeInstalled ? "menubar.rectangle" : "plus.rectangle",
                              detail: core.imeInstalled ? "입력 소스 메뉴에서\n하늘키보드 선택" : "입력 소스 편집\n추가 버튼 누르기")
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    guideStep("3", "하늘키보드", symbol: "checkmark.circle",
                              detail: core.imeInstalled ? "한글 입력을\n시작해 보세요" : "한국어\n하늘키보드 (두벌식)")
                }
                Divider()
                HStack(spacing: 18) {
                    FeedbackStatusLabel(complete: core.imeInstalled,
                        completedText: "입력 소스에 추가되어 있어요", pendingText: "입력 소스 추가를 확인해 주세요")
                    FeedbackStatusLabel(complete: selectedHaneul,
                        completedText: "지금 하늘키보드를 선택했어요", pendingText: "현재 다른 입력 소스를 사용 중이에요")
                    Spacer(minLength: 0)
                    OnboardingButton("키보드 설정 열기") { IMEInstaller.openInputSourcesSettings() }
                        .disabled(core.isPreparingIME).fixedSize()
                }.font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Label("기존 Apple ‘두벌식’은 빼고, ‘ABC’는 남겨 주세요.", systemImage: "keyboard")
                Text("Caps Lock을 짧게 누르면 한글과 영어가 바뀌어요.\n키보드 설정의 ‘Caps Lock 키로 ABC 입력 소스 전환’도 확인해 주세요.")
                    .lineSpacing(4)
                if let message = sourceError ?? core.imeSettingsRefreshWarning {
                    Text(message).foregroundStyle(FeedbackStatus.warning.color(in: colorScheme))
                        .textSelection(.enabled)
                }
            }.font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                .feedbackPanel(.warning)
        }
    }

    /// 위 띠 = 연습(손글씨 안내 → 입력칸, 그 아래 한 줄), 아래 띠 = 도움말. 기능이 꺼져 있으면 경고가 뜨고 도움말은 숨긴다(예전과 같다).
    private func practiceBands<Advice: View>(_ lesson: PracticeLesson, @ViewBuilder advice: () -> Advice) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            practice(lesson)
            if !hasPracticeWarning(lesson) { advice() }
        }
    }

    private var typingStep: some View {
        practiceBands(.automatic) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text("다른 단어도 자유롭게 쳐보세요.").font(.system(size: 16, weight: .medium))
                    HStack(spacing: 9) {
                        exampleWord("bike", tint: OnboardingRiso.cyan)
                        exampleWord("camera", tint: OnboardingRiso.pink)
                        exampleWord("water", tint: OnboardingRiso.yellow)
                    }
                }
                Text("개인 사전의 변환 추가·변환 금지도 그대로 적용돼요.").font(.system(size: 14))
            }.frame(maxWidth: .infinity, alignment: .leading)
                .feedbackPanel(.advice)
        }
    }

    private var reversalStep: some View {
        practiceBands(.reversal) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("방금 변환한 단어를 다시 한글로")
                        .font(.system(size: 16, weight: .semibold))
                    Text("apple을 친 뒤 Space → \(shortcut.displayName)를 눌러보세요.\n같은 단축키를 한 번 더 누르면 영어로 돌아와요.")
                        .font(.system(size: 14)).lineSpacing(3)
                }
                Spacer(minLength: 0)
                terminalShortcutNote
            }.feedbackPanel(.advice)
        }
    }

    private var registeredWordStep: some View {
        practiceBands(.registeredWord) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("렌즈 → lens · 옷 → clothes · 세탁기 → washing machine")
                        .font(.system(size: 15, weight: .medium))
                    Text("등록된 표기만 바꿔요. 일반 Space에서는 한글 그대로예요.")
                        .font(.system(size: 14))
                    HStack(spacing: 10) {
                        Text("나만의 변환 규칙은 설정 → 개인 사전에서")
                            .font(.system(size: 13))
                        Button("개인 사전 열기") { onSettings(.personalDictionary) }
                            .font(.system(size: 13))
                    }.padding(.top, 4)
                }
                Spacer(minLength: 0)
                terminalShortcutNote
            }.feedbackPanel(.information)
        }
    }

    private var slashStep: some View {
        practiceBands(.slash) {
            VStack(alignment: .leading, spacing: 7) {
                Text("/help → Space → 다시 한글 입력")
                    .font(.system(size: 16, weight: .semibold))
                Text("/는 그대로 남고, 뒤에는 즉시 영어가 나와요.\nSpace·슬래시 삭제·닫는 괄호 뒤에는 한글로 돌아와요.")
                    .font(.system(size: 14)).lineSpacing(3)
                HStack {
                    Text("기본으로 켜져 있어요. 설정에서 끌 수 있어요.")
                        .font(.system(size: 13))
                    Spacer(minLength: 4)
                    Button("입력 기능 설정") { onSettings(.inputFeatures) }
                        .font(.system(size: 13))
                }
            }.feedbackPanel(.advice)
        }
    }

    private var terminalShortcutNote: some View {
        Label("터미널에서는 \(shortcut.displayName)로 되돌릴 수 없어요.", systemImage: "terminal")
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 8)
    }

    private func lessonDisabled(_ lesson: PracticeLesson) -> Bool {
        (lesson == .automatic || lesson == .reversal) && !autoEnabled
            || lesson == .reversal && !allWordsEnabled
            || lesson == .registeredWord && !phoneticEnabled
            || lesson == .slash && !slashEnabled
    }
    private func hasPracticeWarning(_ lesson: PracticeLesson) -> Bool {
        sourceError != nil || lessonDisabled(lesson)
    }

    /// 2026-11-03 (#115): 가로 띠. 손글씨 안내는 입력칸 왼쪽에서 화살표로 입력칸을 가리키고,
    /// 안내 문장·선택 상태·비우기는 입력칸 아래 한 줄에 놓는다(예전에는 안내가 입력칸 위에 있었다).
    private func practice(_ lesson: PracticeLesson) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    OnboardingSketchNote(text: lesson.hint, compact: true)
                        .opacity(practiceStage == .empty || lesson == .slash ? 1 : 0)
                    if practiceStage != .empty && lesson != .slash {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cueTitle(lesson)).font(OnboardingHandwriting.font())
                            if showPracticeKey(lesson) { keycap(practiceKey(lesson)) }
                        }.padding(.top, 4)
                    }
                }
                .frame(width: 235, height: compact ? 84 : 94, alignment: .topLeading)
                .foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: practiceStage)
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
                .frame(height: compact ? 84 : 94)
            }
            HStack(alignment: .top, spacing: 12) {
                Text(practiceMessage(lesson)).font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: compact ? 34 : 40, maxHeight: compact ? 34 : 40, alignment: .topLeading)
                FeedbackStatusLabel(complete: selectedHaneul,
                    completedText: "하늘키보드 선택됨", pendingText: "하늘키보드를 선택해 주세요")
                    .font(.system(size: 14)).fixedSize()
                if !selectedHaneul {
                    Button("하늘키보드 선택") {
                        if selectHaneul() { focusRequest = UUID() }
                    }.disabled(!core.imeInstalled).fixedSize()
                }
                Button("비우기", systemImage: "arrow.counterclockwise") { resetRequest = UUID() }
                    .buttonStyle(OnboardingRisoButtonStyle(prominent: false)).fixedSize()
            }
            if hasPracticeWarning(lesson) {
                VStack(alignment: .leading, spacing: 6) {
                    if (lesson == .automatic || lesson == .reversal) && !autoEnabled {
                        Text("현재 이 앱의 자동 변환이 꺼져 있어요.")
                    }
                    if lesson == .reversal && !allWordsEnabled {
                        Text("영어 글자를 한글 자판 글자로 바꾸는 기능이 꺼져 있어요. 직전 자동 변환은 되돌릴 수 있어요.")
                    }
                    if lesson == .registeredWord && !phoneticEnabled {
                        Text("카메라를 camera로 바꾸는 기능이 꺼져 있어요. 설정에서 ‘등록 단어 변환’을 켜 주세요.")
                    }
                    if lesson == .slash && !slashEnabled {
                        Text("슬래시 영어 입력이 꺼져 있어요. 설정에서 켜고 연습해 주세요.")
                    }
                    if let sourceError {
                        Text(sourceError).foregroundStyle(FeedbackStatus.warning.color(in: colorScheme))
                    }
                    if lessonDisabled(lesson) {
                        Button("입력 기능 설정 열기") { onSettings(.inputFeatures) }
                    }
                }.font(.system(size: 14)).feedbackPanel(.warning)
            }
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
                ? "카메라를 입력한 뒤 \(shortcut.displayName)를 눌러보세요."
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
            .feedbackPanel(.information)
    }
    /// 2026-11-03 (#115): 가로 단계 — 번호와 아이콘이 왼쪽, 제목·설명이 오른쪽(예전에는 위에서 아래로 쌓았다).
    private func guideStep(_ number: String, _ title: String, symbol: String, detail: String) -> some View {
        let tint = FeedbackTone.information.tint
        return HStack(alignment: .center, spacing: 9) {
            Text(number).font(OnboardingRiso.titleFont(size: 18))
            Image(systemName: symbol).font(.system(size: compact ? 20 : 24, weight: .medium))
                .symbolRenderingMode(.monochrome).foregroundStyle(.primary)
                .frame(width: compact ? 40 : 48, height: compact ? 36 : 44)
                .background(tint.opacity(colorScheme == .dark ? 0.23 : 0.20), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: compact ? 15 : 16, weight: .semibold))
                Text(detail).font(.system(size: compact ? 13 : 14)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func refresh() {
        core.refreshIMEStatus()
        refreshSelection()
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
    private func refreshSelection() {
        selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        if selectedHaneul { sourceError = nil }
    }
    @discardableResult private func selectHaneul() -> Bool {
        let success = InputSwitcher.selectKorean()
        refreshSelection()
        sourceError = success || selectedHaneul ? nil : "하늘키보드를 선택하지 못했어요. 키보드 설정에서 입력 소스를 추가해 주세요."
        return success || selectedHaneul
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

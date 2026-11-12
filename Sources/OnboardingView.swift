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
    @AppStorage(HaneulDefaultsKey.hasCompletedOnboarding) private var hasCompleted = false
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
    @State private var inputSessionRequest: UUID?
    @State private var practiceStage: OnboardingPracticeStage = .empty
    @State private var shortcut = RevertKey.default
    @State private var autoEnabled = true
    @State private var phoneticEnabled = RevertKey.phoneticDefault
    @State private var slashEnabled = SlashEnglishSession.defaultEnabled

    /// 2026-11-13 (#227, 리뷰 app-ui-F-10): 연습 종류와 "꺼진 기능" 판단은 `OnboardingLesson`(AppUIDecisions, 시험됨)으로 옮겼다.
    /// 화면 문구(안내 손글씨·접근성 이름)만 여기 둔다.
    private typealias PracticeLesson = OnboardingLesson

    private let titles = ["한글 모드 그대로 영어까지", "Mac에서 하늘키보드를 선택", "이번엔 직접 쳐봐요",
                          "단축키로 되돌려요", "한글 단어도 영어로", "슬래시 뒤에는 바로 영어", "메뉴바에서 만나요"]
    private let sections = ["만나보기와 설치", "입력 소스", "영어 자동 변환", "되돌리기", "한글 단어를 영어로", "슬래시 영어 입력", "메뉴바와 응원하기"]
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
        .font(AppFont.font(size: 15))
        // 2026-11-08 (#209): 마루부리는 줄 사이가 좁아 두 줄 안내가 붙어 보였다(설정 창과 같은 3pt).
        .lineSpacing(AppFont.lineSpacing)
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
    static let practiceFieldHeight: CGFloat = 72
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
        if step < OnboardingScrollArt.pageCount {
            // 2026-11-03 (#116): 두루마리 그림 + 앱 안 카메라. 같은 뷰가 페이지만 바꿔 받아 카메라를 옮긴다.
            // 20:57: 7페이지도 이 뷰가 맡는다 — 첫 프레임 자리로 트럭해 들어간 뒤 영상으로 바꿔 끼운다(숨은 컷).
            OnboardingScrollStage(page: step, reduceMotion: reduceMotion)
        } else if step == Self.stagePage {
            OnboardingStageVideo(animate: !reduceMotion)
        } else {
            // 2026-11-07 (#177, 리뷰 app-ui-F-6): 두루마리 자원을 못 읽어 pageCount가 0일 때만 여기로 온다(원인은 `OnboardingScrollArt`가 로그에 남긴다).
            // 예전엔 2026-11-03 틀 잡기(#115) 검수 하네스가 갈아 끼우는 키 색(순녹색)이었다 — 사용자가 보게 되면 형광 녹색 사각형이다.
            // 지금은 1~7페이지 모두 위 두 갈래가 맡아 검수 도구도 이 색을 더 쓰지 않으므로 안내 종이색으로 둔다.
            OnboardingRiso.ivory
        }
    }

    private var cardPaper: some View {
        UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
            .fill(colorScheme == .dark ? OnboardingRiso.meok : Color(red: 250 / 255, green: 246 / 255, blue: 236 / 255))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: -2)
    }

    private var frameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 2026-11-05 오너(#145): 하단이 비어 보였다. 예전엔 내용을 제 키로 고정하고 남는 칸을 Spacer가 먹었다.
            // 이제 본문이 남는 높이를 받아 페이지마다 주인공(입력칸·시연·단계·메뉴 칸)이 늘어난다.
            VStack(alignment: .leading, spacing: 0) {
                cardTitle.fixedSize(horizontal: false, vertical: true)
                pageBody.padding(.top, compact ? 10 : 14)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if step == Self.stagePage { stageMenuBar.padding(.top, 2) }
            }
            .padding(.horizontal, compact ? 24 : 30).padding(.top, compact ? 14 : 18)
            .padding(.bottom, compact ? 12 : 18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [step] height in
                Self.cardTopHeightProbe?(step, height)
            }
            .id(pageID)
            .transition(pageTransition)
            .accessibilityIdentifier("onboarding-page-content")
            Divider().padding(.horizontal, 22)
            navigation.padding(.horizontal, 22).frame(height: compact ? 58 : 64)
        }
    }

    private var cardTitle: some View {
        // 2026-11-09 오너(#216): 제목 → 부제도 6pt(앱 전체 '제목 → 설명' 규칙). 예전 9pt(큰 창)는 부제 두 줄 사이보다 넓었다.
        VStack(alignment: .leading, spacing: adviceLineGap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(titles[step]).font(OnboardingRiso.titleFont(size: 27))
                Text(String(format: "%02d", step + 1) + "  " + sections[step])
                    .font(AppFont.font(size: 12, weight: .semibold)).foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(OnboardingRiso.yellow.opacity(colorScheme == .dark ? 0.10 : 0.24), in: Capsule())
            }
            Text(subtitle).font(AppFont.font(size: 14)).lineSpacing(AppFont.lineSpacing)
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

    /// 2026-11-05 오너(#145): 버튼 한 줄 아래가 통째로 비었다. 같은 세 기능을 카드 폭을 채우는 칸으로 키우고,
    /// 메뉴바 아이콘을 종료했을 때 어떻게 되는지 아래 띠에 적는다(#142에서 정한 종료의 뜻).
    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(spacing: 12) {
                menuTile("하늘키보드 설정", detail: "자동 변환과 개인 사전을\n내 손에 맞게 바꿔요",
                         symbol: "slider.horizontal.3", tint: OnboardingRiso.cyan) { onSettings(.automatic) }
                menuTile("시작하기 다시 보기", detail: "이 안내를 처음부터\n다시 볼 수 있어요",
                         symbol: "play.circle", tint: OnboardingRiso.yellow) { go(to: 0) }
                menuTile("응원하기", detail: "영원히 무료예요\n후원은 자유롭게 선택해 주세요",
                         symbol: "heart", tint: OnboardingRiso.pink) { onSupport() }
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: adviceLineGap) {
                // 2026-11-06 (#154): 설정에서 아이콘을 끌 수 있게 되어 문구를 맞췄다.
                Label("메뉴바 아이콘을 꺼도 입력기는 그대로 동작해요.", systemImage: "menubar.rectangle")
                // 2026-11-09 오너(#216): 돌아오는 길을 설정·메뉴바 툴팁과 같은 말(`앱`에서 실행)로 맞췄다.
                Text("설정 → 앱 관리에서 끌 수 있고, 아이콘이 없을 때는 앱에서 하늘키보드를 실행해 주세요.")
                    .padding(.leading, AdviceLabelStyle.iconWidth + AdviceLabelStyle.spacing)
                // 2026-11-08 오너(#201): 로그인할 때 열기를 아이콘 토글에 합쳐 따로 알리던 줄을 지웠다.
                // 2026-11-09 오너(#216, 4차): 미설치일 때만 보이던 `시작하기를 누르면 입력기 설치·설정을 이어갈 수 있어요.`와
                // `설치 단계로 이동` 버튼(2026-10-10부터)을 뺐다 — "아예 빼버리자". 설치는 1페이지로 돌아가서 한다.
            }
            .labelStyle(AdviceLabelStyle())
            .font(AppFont.font(size: 14)).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
        }
        // 오른쪽 위 메뉴바 모형의 손글씨(필요할 땐 여기!)가 칸에 닿지 않게 내린다.
        .padding(.top, compact ? 16 : 22)
    }

    /// 메뉴 칸 — 누르는 곳이 칸 전체다. 칠과 테두리는 다른 안내 띠와 같은 잉크 계열이다.
    private func menuTile(_ title: String, detail: String, symbol: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Image(systemName: symbol).font(.system(size: compact ? 20 : 26, weight: .medium))
                    .symbolRenderingMode(.monochrome).foregroundStyle(.primary)
                    .frame(width: compact ? 40 : 52, height: compact ? 36 : 46)
                    .background(tint.opacity(colorScheme == .dark ? 0.26 : 0.24), in: RoundedRectangle(cornerRadius: 10))
                // 2026-11-09 오너(#216): 제목 → 설명은 6pt(앱 전체 규칙). 예전엔 아이콘 → 제목과 같은 12pt였다.
                VStack(alignment: .leading, spacing: adviceLineGap) {
                    Text(title).font(AppFont.font(size: compact ? 15 : 17, weight: .semibold))
                    Text(detail).font(AppFont.font(size: compact ? 13 : 14)).lineSpacing(AppFont.lineSpacing)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.09), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(tint.opacity(0.42), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    /// 메뉴바 자리를 알려 주는 작은 모형(옛 7페이지의 연필 동그라미를 카드 오른쪽에 옮겼다).
    private var stageMenuBar: some View {
        let ink = OnboardingRiso.ink(for: colorScheme)
        return HStack(spacing: 14) {
            Image(systemName: "wifi").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
            // 2026-11-07 (#188): 메뉴바 아이콘(G6)은 18pt 화소 격자에 맞춰 그렸다. 다른 크기로 늘이면 2배 화면에서
            // 마구리 점이 회색으로 뭉개져서, 실제 메뉴바와 같은 18pt로 그린다. 연필 동그라미 틀(40×36)은 그대로다.
            Image(nsImage: HaneulStatusIcon.image)
                .resizable().renderingMode(.template).scaledToFit().frame(width: 18, height: 18)
                .padding(.horizontal, 11).padding(.vertical, 9)
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

    /// 2026-11-08 (#209): 마루부리로 바꾸며 문장 중간에서 꺾던 두 줄(2페이지 미설치·7페이지)을 한 줄로 폈다. 두 문장이면 문장마다 줄을 나눈다.
    private var subtitle: String {
        switch step {
        case 0: "하늘키보드는 한글로 친 영어 단어를 알아보고 바꿔줘요.\n한/영 키를 누르지 않아도 돼요."
        case 1: core.imeInstalled
            ? "입력 소스에 하늘키보드가 추가됐어요.\n메뉴바의 입력 소스에서 하늘키보드를 선택해 주세요."
            : "키보드 설정에 하늘키보드를 추가하고 입력 소스로 선택해 주세요."
        case 2: "한글 모드에서 apple을 입력해 보세요.\n영어로 바꿔요. 한글 모드는 그대로예요."
        case 3: "방금 바꾼 영어를 \(shortcut.displayName)로 되돌려요.\n다시 누르면 영어로 돌아와요."
        case 4: "카메라를 쓰고 \(shortcut.displayName)를 누르면 camera.\n다시 누르면 내가 쓴 한글로 돌아와요."
        case 5: "한글 모드에서 /help를 입력해 보세요.\n슬래시 뒤에는 바로 영어가 나와요."
        default: "설정을 열거나 이 안내를 다시 보고 싶을 때 메뉴바의 하늘키보드를 눌러 주세요."
        }
    }

    // 2026-11-03 (#115): 본문은 카드 폭을 꽉 채운 가로 띠를 위아래로 쌓는다. 띠 안의 내용은 왼쪽에서 오른쪽으로 흐른다.
    // 오너(16:43): 왼쪽 상자·오른쪽 상자로 나누면 보기 불편하다. 무대 그림이 가로로 놓였으니 UI도 가로로 가야 한다.
    // 문구·기능·글자 크기는 그대로다.
    private var installStep: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            // 2026-11-05 (#145): 시연이 이 페이지의 주인공이라 남는 높이를 받는다.
            OnboardingConversionDemo(compact: compact)
            HStack(spacing: 14) {
                Image(systemName: installPanel.symbol).font(.system(size: 25))
                    .foregroundStyle(installPanel.iconStatus.color(in: colorScheme))
                // 2026-11-09 (#216): 제목 → 상태도 6pt(앱 전체 규칙).
                VStack(alignment: .leading, spacing: adviceLineGap) {
                    Text("하늘키보드 두벌식").font(AppFont.font(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    // 2026-11-07 (#187): 빨간 칸 위에서는 빨간 글자가 안 읽힌다. 설치가 필요하면 본문색으로 또렷하게 쓴다.
                    Text(installStatus).font(AppFont.font(size: 14, weight: installPanel == .actionNeeded ? .semibold : .regular))
                        .foregroundStyle(installPanel == .actionNeeded ? Color.primary : installPanel.iconStatus.color(in: colorScheme))
                }
                Spacer(minLength: 0)
                if !ready {
                    if core.imeRefreshBlockedBySystemInstall && !core.isPreparingIME {
                        // 2026-11-07 (#177, 리뷰 app-ui-F-3): 설치 버튼은 시스템 영역 입력기를 바꾸지 못하고 재등록만 한다 — 눌러도 그대로라
                        // 막다른 길이었다. 해결이 있는 곳으로 바로 보낸다. 2026-11-08 (#201): 입력기 제거 버튼이 없어져 해결은 앱 관리의 전체 제거다.
                        OnboardingButton("앱 관리 열기") { onSettings(.appManagement) }.fixedSize()
                    } else {
                        // 2026-11-07 오너(#187): 이 페이지에서 사용자가 꼭 눌러야 하는 버튼이라 주 버튼 잉크로 칠한다.
                        // 2026-11-09 오너(#216, 4차): 버튼 왼쪽에 깜빡이는 손그림 화살표를 둔다. 설치 중(.checking)에는 숨긴다.
                        HStack(spacing: 10) {
                            if installPanel == .actionNeeded {
                                OnboardingNudgeArrow().foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                            }
                            OnboardingButton(core.isPreparingIME ? "확인·설치 중…" : "하늘키보드 설치", navigation: true) {
                                Task {
                                    installError = nil
                                    if let error = await core.installIME() { installError = error.localizedDescription }
                                }
                            }.disabled(core.isPreparingIME).fixedSize()
                        }
                    }
                }
            }.feedbackPanel(installPanel == .actionNeeded ? .actionNeeded : .information).fixedSize(horizontal: false, vertical: true)
            if let message = installError ?? systemInstallNotice ?? core.imeActivationError?.localizedDescription
                ?? core.imeSettingsRefreshWarning {
                Text(message).font(AppFont.font(size: 14))
                    .foregroundStyle(FeedbackStatus.warning.color(in: colorScheme)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).feedbackPanel(.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 2026-11-08 오너(#201): 설치한 사람에게 첫 화면부터 지우는 법을 알려 주던 줄을 뺐다.
            // 2026-11-09 오너(#216, 4차): 터미널 안내도 뺐다 — "터미널 앱에서 안 된다는 말이 너무 많다. Shift+Space를 소개하는 곳에서만."
        }
    }
    /// 2026-11-07 (#177, 리뷰 app-ui-F-3): 시스템 영역(/Library/Input Methods)의 낡은 입력기는 앱이 직접 바꿀 수 없다.
    /// 왜 안 되는지와 무엇을 할지를 함께 적는다. 이전엔 이 해결법이 설정 → 버전·업데이트에만 있었다.
    private var systemInstallNotice: String? {
        guard core.imeRefreshBlockedBySystemInstall, !core.isPreparingIME else { return nil }
        // 2026-11-08 오너(#201): '입력기 제거' 버튼을 없앴다. 입력기만 지울 일은 전체 제거가 맡는다.
        return "이 Mac의 시스템 영역(/Library/Input Methods)에 이전 버전 입력기가 있어서 앱이 직접 바꿀 수 없어요.\n설정 → 앱 관리의 ‘하늘키보드 전체 제거’로 지운 뒤 다시 설치해 주세요."
    }
    private var installPanel: OnboardingInstallPanel {
        .resolve(statusKnown: core.imeStatusKnown, busy: core.isPreparingIME,
                 installed: core.imeInstalled, refreshNeeded: core.imeRefreshNeeded)
    }
    /// 2026-11-13 (#227, 리뷰 app-ui-F-10): 문장 고르기는 `OnboardingInstallPanel.statusText`(시험됨)로 옮겼다. 문장은 그대로다.
    private var installStatus: String {
        OnboardingInstallPanel.statusText(panel: installPanel, blockedBySystemInstall: core.imeRefreshBlockedBySystemInstall,
                                          refreshNeeded: core.imeRefreshNeeded, disabled: core.imeDisabled)
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
                // 2026-11-05 (#145): 세 단계가 남는 높이를 받는다.
                .frame(maxHeight: .infinity)
                Divider()
                HStack(spacing: 18) {
                    FeedbackStatusLabel(complete: core.imeInstalled,
                        completedText: "입력 소스에 추가되어 있어요", pendingText: "입력 소스 추가를 확인해 주세요")
                    FeedbackStatusLabel(complete: selectedHaneul,
                        completedText: "지금 하늘키보드를 선택했어요", pendingText: "현재 다른 입력 소스를 사용 중이에요")
                    Spacer(minLength: 0)
                    OnboardingButton("키보드 설정 열기") { IMEInstaller.openInputSourcesSettings() }
                        .disabled(core.isPreparingIME).fixedSize()
                }.font(AppFont.font(size: 15))
            }
            VStack(alignment: .leading, spacing: adviceLineGap) {
                // 2026-11-08 오너(#201): ABC는 macOS가 빼지 못하게 막아 두어 '남겨 주세요'가 필요 없다. Caps Lock 전환 설정은 맥 사용자가 다 안다.
                // 2026-11-09 오너(#216): 남아 있던 `Caps Lock을 누르면 한글과 영어가 바뀌어요.`도 뺐다 — 맥 사용자는 다 안다.
                Label("기존 Apple ‘두벌식’은 빼 주세요.", systemImage: "keyboard")
                // 2026-11-07 (#187): 입력기라 가장 정직해야 하는 대목이다. 근거는 PRIVACY.md 4번과 README 알려진 한계.
                // 2026-11-08 오너(#201): 이유를 먼저, 할 일을 뒤에 쓴다.
                Label("일부 웹사이트의 비밀번호 칸에서는 한글이 입력될 수 있으니 비밀번호는 영문(ABC)으로 쳐 주세요.", systemImage: "lock")
                if let message = sourceError ?? core.imeSettingsRefreshWarning {
                    Text(message).foregroundStyle(FeedbackStatus.warning.color(in: colorScheme))
                        .textSelection(.enabled)
                }
            }.font(AppFont.font(size: 14)).fixedSize(horizontal: false, vertical: true)
                .labelStyle(AdviceLabelStyle())
                .feedbackPanel(.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 위 띠 = 연습(손글씨 안내 → 입력칸 → 안내 한 줄), 아래 띠 = 도움말. 기능이 꺼져 있으면 경고가 뜨고 도움말은 숨긴다(예전과 같다).
    /// 2026-11-05 (#145): 입력칸은 높이가 고정이고 남는 높이는 도움말 띠가 받는다. 그래서 3~6페이지의 칸 자리가 모두 같다.
    private func practiceBands<Advice: View>(_ lesson: PracticeLesson, @ViewBuilder advice: () -> Advice) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            practice(lesson)
            if !hasPracticeWarning(lesson) { advice() }
        }
    }

    private var typingStep: some View {
        practiceBands(.automatic) {
            VStack(alignment: .leading, spacing: adviceLineGap) {
                HStack(spacing: 14) {
                    Text("다른 단어도 자유롭게 쳐보세요.").font(AppFont.font(size: adviceTitleSize, weight: .medium))
                    HStack(spacing: 9) {
                        exampleWord("bike", tint: OnboardingRiso.cyan)
                        exampleWord("camera", tint: OnboardingRiso.pink)
                        exampleWord("water", tint: OnboardingRiso.yellow)
                    }
                }
                Text("개인 사전의 변환 추가·변환 금지도 그대로 적용돼요.").font(AppFont.font(size: adviceBodySize))
            }.frame(maxWidth: .infinity, alignment: .leading)
                .feedbackPanel(.advice, fills: true)
        }
    }

    private var reversalStep: some View {
        practiceBands(.reversal) {
            // 2026-11-09 오너(#216): 제목·문장·터미널 안내 사이를 다른 칸과 같은 간격으로 둔다(예전엔 안쪽 6·바깥 8/12로 달랐다).
            // 2026-11-09 오너(#216): 터미널 설명이 이 페이지만 네 줄이었다. 순서 = 제목 → 해 보기 → 설정 한 줄 → 터미널 한 줄(빨강, 모든 페이지 같은 문장).
            VStack(alignment: .leading, spacing: adviceLineGap) {
                Text("방금 변환한 단어를 다시 한글로")
                    .font(AppFont.font(size: adviceTitleSize, weight: .semibold))
                Text("apple을 친 뒤 Space → \(shortcut.displayName)를 눌러보세요.\n같은 단축키를 한 번 더 누르면 영어로 돌아와요.")
                    .font(AppFont.font(size: adviceBodySize)).lineSpacing(AppFont.lineSpacing)
                Text("설정에서 자동 변환만 끌 수도 있어요.")
                    .font(AppFont.font(size: adviceNoteSize))
                terminalShortcutNote
            }.feedbackPanel(.advice, fills: true)
        }
    }

    private var registeredWordStep: some View {
        practiceBands(.registeredWord) {
            // 2026-11-09 오너(#216): 둘째 줄 위아래 간격이 달랐다(셋째 줄 앞에 4pt를 더 띄웠고, 그 줄의 `개인 사전 열기` 버튼이 줄을 키웠다).
            // 버튼을 빼고(개인 사전은 설정에서 찾는다) 네 줄을 한 간격으로 쌓는다. 줄마다 띠 전체 폭을 쓴다.
            VStack(alignment: .leading, spacing: adviceLineGap) {
                Text("렌즈 → lens · 옷 → clothes · 세탁기 → washing machine")
                    .font(AppFont.font(size: adviceTitleSize - 1, weight: .medium))
                Text("앱에 준비된 단어만 바꿔요. 그냥 Space로는 한글 그대로예요.")
                    .font(AppFont.font(size: adviceBodySize))
                suggestDictionaryLine
                // 2026-11-09 오너(#216, 4차): 터미널 안내는 단축키를 처음 소개하는 4페이지에만 둔다.
            }.feedbackPanel(.information, fills: true)
        }
    }

    private var slashStep: some View {
        practiceBands(.slash) {
            VStack(alignment: .leading, spacing: adviceLineGap) {
                Text("/help → Space → 다시 한글 입력")
                    .font(AppFont.font(size: adviceTitleSize, weight: .semibold))
                // 2026-11-08 오너(#201): 키 이름은 맥 자판 표기(Return·delete)가 아니라 표준 이름(Enter·Backspace)으로 쓴다.
                // 닫는 괄호로 끝나는 동작은 그대로 두고 문장에서만 뺐다(설정 설명과 같은 말).
                // 2026-11-09 오너(#216): 첫 문장이 어색했다(`/는 그대로 남고, 뒤에는 즉시 영어가 나와요.`). 하는 일만 쉽게 쓴다.
                Text("/를 치고 나서 글을 입력하면 영어가 나와요.\nSpace나 Enter를 누르거나 Backspace로 /를 지우면 한글로 돌아와요.")
                    .font(AppFont.font(size: adviceBodySize)).lineSpacing(AppFont.lineSpacing)
                HStack {
                    Text("기본으로 켜져 있어요.\n설정에서 끌 수 있어요.")
                        .font(AppFont.font(size: adviceNoteSize))
                    Spacer(minLength: 4)
                    Button(maru: "슬래시 설정", size: adviceNoteSize) { onSettings(.shortcuts) }
                        .font(AppFont.font(size: adviceNoteSize))
                }
            }.feedbackPanel(.advice, fills: true)
        }
    }

    // 2026-11-05 (#145): 큰 창의 도움말 띠는 남는 높이를 받아 넓다. 글자도 한 단계 키워 띠가 비어 보이지 않게 한다.
    private var adviceTitleSize: CGFloat { compact ? 16 : 18 }
    private var adviceBodySize: CGFloat { compact ? 14 : 15 }
    private var adviceNoteSize: CGFloat { compact ? 13 : 14 }
    /// 2026-11-09 오너(#216): 도움말 칸 안의 줄 사이(제목 → 문장, 문장 → 문장)는 모두 이 간격이다.
    /// 한 Text 안의 줄 간격(`AppFont.lineSpacing`)과 같게 둬서 따로 쓴 줄과 이어 쓴 줄이 구분되지 않게 한다.
    private var adviceLineGap: CGFloat { AppFont.lineSpacing }

    /// 2026-11-09 오너(#216): 설정 변환 단축키 카드와 같은 문장, 같은 빨간 글씨(`RevertKey.terminalLimitNotice`).
    /// 4차에서 단축키를 처음 소개하는 4페이지에만 남겼다(1·5페이지는 뺐다 — "너무 많다").
    /// 터미널은 입력기를 못 받는 곳이 아니라 이미 들어간 글자를 바꿀 수 없는 곳이다(2026-07-28 실측, #30). 예전 4페이지의 네 줄 설명(`terminalLimitNote`)은 지웠다.
    // 2026-11-13 (#227, 리뷰 app-ui-F-5): 시스템 초록·주황·빨강 글자는 밝은 화면에서 대비가 2~3.6:1이었다. 같은 계열의 진한 상태색(`FeedbackStatus`, 4.5:1 이상)을 쓴다.
    private var terminalShortcutNote: some View {
        Label(shortcut.terminalLimitNotice, systemImage: "terminal")
            .labelStyle(AdviceLabelStyle())
            .font(AppFont.font(size: adviceNoteSize))
            .foregroundStyle(FeedbackStatus.warning.color(in: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 2026-11-07 (#187): 개인 사전에는 한글 → 영어 규칙을 넣을 수 없다(`PersonalDictionary.isEnglishEntry`는 영문만 받는다).
    /// 예전 문구 "나만의 변환 규칙은…"은 넣을 수 있는 것처럼 읽혔다. 단어 제안이 같은 탭 아래에 있다.
    /// 2026-11-09 오너(#216): `개인 사전 열기` 버튼을 뺐다 — 안내에서 설정으로 보내지 않고, 개인 사전은 설정에서 찾게 둔다. 문장은 남긴다.
    private var suggestDictionaryLine: some View {
        Text("없는 단어는 개인 사전에서 제안해 주세요.")
            .font(AppFont.font(size: adviceNoteSize))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lessonDisabled(_ lesson: PracticeLesson) -> Bool {
        lesson.isDisabled(autoEnabled: autoEnabled, phoneticEnabled: phoneticEnabled, slashEnabled: slashEnabled)
    }
    private func hasPracticeWarning(_ lesson: PracticeLesson) -> Bool {
        sourceError != nil || lessonDisabled(lesson)
    }

    /// 2026-11-05 오너(#145): 입력칸이 카드 가로를 다 채운다(1·2페이지 띠와 같은 폭). 그동안(#115) 손글씨 안내를
    /// 입력칸 왼쪽에 두느라 칸이 좁았다. 이제 맨 위 줄 = 손글씨 안내 + 선택 상태, 그 아래 입력칸, 맨 아래 줄 = 안내 문장 + 비우기.
    private func practice(_ lesson: PracticeLesson) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .leading) {
                    OnboardingSketchHint(text: lesson.hint)
                        .opacity(practiceStage == .empty || lesson == .slash ? 1 : 0)
                    if practiceStage != .empty && lesson != .slash {
                        HStack(alignment: .center, spacing: 10) {
                            Text(cueTitle(lesson)).font(OnboardingHandwriting.font())
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if showPracticeKey(lesson) { keycap(practiceKey(lesson)) }
                        }
                    }
                }
                .frame(height: compact ? 40 : 46, alignment: .leading)
                .foregroundStyle(OnboardingRiso.ink(for: colorScheme))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: practiceStage)
                Spacer(minLength: 0)
                FeedbackStatusLabel(complete: selectedHaneul,
                    completedText: "하늘키보드 선택됨", pendingText: "하늘키보드를 선택해 주세요")
                    .font(AppFont.font(size: 14)).fixedSize()
                if !selectedHaneul {
                    Button(maru: "하늘키보드 선택") {
                        if selectHaneul() { focusRequest = UUID() }
                    }.disabled(!core.imeInstalled).fixedSize()
                }
                if compact { clearPracticeButton }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(OnboardingRiso.yellow.opacity(0.65)).offset(x: 3, y: 4)
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.14) : Color(red: 1, green: 0.99, blue: 0.96))
                OnboardingPracticeField(focusRequest: focusRequest, resetRequest: resetRequest,
                                        accessibilityName: lesson.accessibilityName,
                                        placeholder: "", inputSessionRequest: inputSessionRequest,
                                        onProgressChange: { [observedPage = pageID] stage in
                                            // 전환 중 퇴장하는 입력칸의 늦은 알림이 새 화면을 바꾸지 않게 한다.
                                            guard pageID == observedPage else { return }
                                            practiceStage = stage
                                        })
                    .transaction { $0.animation = nil }
                    .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(OnboardingRiso.cyan.opacity(0.60), lineWidth: 1.3))
            // 2026-11-05 오너(#145): 입력칸은 모든 페이지·모든 창에서 같은 크기여야 하고 글자에 비해 크면 안 된다.
            // 72 = 23pt 한 줄 + 위아래 여백. 잠깐 입력칸이 남는 높이를 받게 했다가 이 지적으로 되돌렸다.
            .frame(height: Self.practiceFieldHeight)
            .padding(.trailing, 3).padding(.bottom, 4)     // 노란 그림자까지 아래 띠 오른쪽 끝에 맞춘다
            // 작은 창(780)에서는 이 줄을 뺀다. 같은 내용이 부제목과 손글씨 안내에 있고, 넣으면 6페이지가 넘친다.
            if !compact {
                HStack(alignment: .center, spacing: 12) {
                    Text(practiceMessage(lesson)).font(AppFont.font(size: 15))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    clearPracticeButton
                }
            }
            if hasPracticeWarning(lesson) {
                VStack(alignment: .leading, spacing: 6) {
                    if (lesson == .automatic || lesson == .reversal) && !autoEnabled {
                        Text("현재 이 앱의 자동 변환이 꺼져 있어요.")
                    }
                    // 2026-11-10 오너(#216, 6차): `미리 친 단어 한/영 바꾸기` 토글이 없어져 그 경고도 뺐다.
                    if lesson == .registeredWord && !phoneticEnabled {
                        Text("카메라를 camera로 바꾸는 기능이 꺼져 있어요.\n설정에서 ‘한글 단어를 영어로 바꾸기’를 켜 주세요.")
                    }
                    if lesson == .slash && !slashEnabled {
                        Text("슬래시 영어 입력이 꺼져 있어요.\n설정에서 켜고 연습해 주세요.")
                    }
                    if let sourceError {
                        Text(sourceError).foregroundStyle(FeedbackStatus.warning.color(in: colorScheme))
                    }
                    if lessonDisabled(lesson) {
                        // 2026-11-07 (#189): 꺼진 항목이 있는 메뉴로 바로 보낸다. 자동 변환이 꺼진 게 먼저다(되돌리기 연습은 둘 다 꺼질 수 있다).
                        Button(maru: "설정 열기") { onSettings(lesson.settingsTab(autoEnabled: autoEnabled)) }
                    }
                }.font(AppFont.font(size: 14)).feedbackPanel(.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var clearPracticeButton: some View {
        Button("비우기", systemImage: "arrow.counterclockwise") { resetRequest = UUID() }
            .buttonStyle(OnboardingRisoButtonStyle(prominent: false)).fixedSize()
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
            case .reverted: return "한글로 바꿨어요. 한 번 더 누르면 영어로 돌아가요."
            case .converted: return "영어로 바꿨어요. 다시 눌러 한글로 바꿔 보세요."
            default: return lesson == .registeredWord
                ? "카메라를 입력한 뒤 \(shortcut.displayName)를 눌러보세요."
                : "apple을 입력하고 Space → \(shortcut.displayName)를 눌러보세요."
            }
        }
        switch practiceStage {
        case .converted: return "영어로 바꿨어요. 계속 한글로 입력할 수 있어요."
        case .english: return "영어가 입력됐어요. 한글 모드에서 입력하면 자동 변환을 체험해요."
        case .readyToCommit: return "이제 Space를 누르면 영어 단어를 확인해요."
        case .other: return "자유롭게 입력해도 좋아요. 단어를 쓴 뒤 Space를 눌러보세요."
        default: return "apple을 입력하고 Space를 눌러보세요."
        }
    }

    private func exampleWord(_ word: String, tint: Color) -> some View {
        // 2026-11-09 오너(#216): 칩의 위아래 여백이 제목 줄을 키워 제목과 아래 문장 사이가 다른 칸보다 4pt쯤 넓었다(캡처 실측).
        // 여백은 바탕 상자에만 주고 줄 높이에는 넣지 않는다. 상자는 위아래 2pt만 넘친다(4pt면 아래 문장에 붙어 보였다).
        Text(word).font(AppFont.font(size: 16, weight: .medium))
            .padding(.horizontal, 10)
            .background { RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.12)).padding(.vertical, -2) }
    }
    private func keycap(_ title: String) -> some View {
        Text(title).font(AppFont.font(size: 15, weight: .semibold))
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
            Text(number).font(OnboardingRiso.titleFont(size: compact ? 18 : 21))
            Image(systemName: symbol).font(.system(size: compact ? 20 : 27, weight: .medium))
                .symbolRenderingMode(.monochrome).foregroundStyle(.primary)
                .frame(width: compact ? 40 : 52, height: compact ? 36 : 50)
                .background(tint.opacity(colorScheme == .dark ? 0.23 : 0.20), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppFont.font(size: compact ? 15 : 17, weight: .semibold))
                Text(detail).font(AppFont.font(size: compact ? 13 : 14)).lineSpacing(AppFont.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func refresh() {
        core.refreshIMEStatus()
        refreshSelection()
        let defaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)
        shortcut = RevertKey.resolve(rawValue: defaults?.string(forKey: RevertKey.defaultsKey))
        phoneticEnabled = defaults?.object(forKey: RevertKey.phoneticKey) as? Bool ?? RevertKey.phoneticDefault
        slashEnabled = defaults?.object(forKey: SlashEnglishSession.defaultsKey) as? Bool
            ?? SlashEnglishSession.defaultEnabled
        autoEnabled = AutoConvertPolicy.allowed(
            globalEnabled: defaults?.object(forKey: HaneulDefaultsKey.autoEnglishEnabled) as? Bool ?? true,
            disabledIDs: defaults?.stringArray(forKey: AutoConvertPolicy.disabledAppsKey) ?? [],
            clientBundleID: Bundle.main.bundleIdentifier)
    }
    private func refreshSelection() {
        selectedHaneul = InputSwitcher.currentSourceID() == InputSwitcher.koreanModeID
        guard selectedHaneul else { return }
        sourceError = nil
        // 2026-11-05 (#146): 하늘키보드를 골랐는데 입력기가 안 떠 있으면(시스템이 띄우다 실패한 경우) 직접 띄우고 세션을 다시 잇는다.
        // 설치·교체·제거 중에는 입력기를 일부러 멈춘 상태라 건드리지 않는다.
        guard ready else { return }
        Task {
            if await IMEInstaller.launchIMEIfNeeded() { inputSessionRequest = UUID() }
        }
    }
    @discardableResult private func selectHaneul() -> Bool {
        let success = InputSwitcher.selectKorean()
        refreshSelection()
        sourceError = success || selectedHaneul ? nil : "하늘키보드를 선택하지 못했어요.\n키보드 설정에서 입력 소스를 추가해 주세요."
        return success || selectedHaneul
    }
}

/// 2026-11-09 오너(#216): 도움말 칸의 아이콘 줄. 기본 Label은 아이콘 때문에 줄이 2pt쯤 높아져(캡처 실측) 위아래 간격이 다른 줄과 달랐고,
/// 아이콘 폭(키보드·자물쇠)이 달라 글자 시작점도 어긋났다. 아이콘을 글자 기준선에 맞추고 같은 폭 칸에 넣는다.
private struct AdviceLabelStyle: LabelStyle {
    static let iconWidth: CGFloat = 20
    static let spacing: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
            // 높이 0 틀: 아이콘은 같은 자리에 그려지지만 줄 높이에는 들어가지 않는다. 아이콘 줄만 1.5pt 더 떨어지던 것(캡처 실측)을 막는다.
            configuration.icon.frame(width: Self.iconWidth).frame(height: 0)
            configuration.title
        }
    }
}

private extension OnboardingInstallPanel {
    var symbol: String {
        switch self {
        case .checking: "keyboard"
        case .ready: "checkmark.circle"
        case .actionNeeded: "exclamationmark.triangle.fill"
        }
    }
    var iconStatus: FeedbackStatus {
        switch self {
        case .checking: .pending
        case .ready: .success
        case .actionNeeded: .warning
        }
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

/// 안내 연습 페이지의 화면 문구. 판단은 `OnboardingLesson`(AppUIDecisions)에 있다.
private extension OnboardingLesson {
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
        case .automatic: "영어 자동 변환 연습"
        case .reversal: "되돌리기 연습"
        case .registeredWord: "한글 단어를 영어로 바꾸기 연습"
        case .slash: "슬래시 영어 입력 연습"
        }
    }
}

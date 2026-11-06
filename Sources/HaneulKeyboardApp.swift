import SwiftUI
import AppKit
import Carbon

@main
struct HaneulKeyboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // (메뉴바 좌상단 버그 수정) SwiftUI MenuBarExtra → AppKit NSStatusItem 전환.
        // MenuBarExtra의 커스텀/동적 label에서 메뉴가 화면 좌상단(0,0)에 뜨던 문제를
        // NSStatusItem + NSMenu(팝업 위치가 OS 표준이라 견고)로 근본 해결한다.
        // 검증된 설정 화면은 SwiftUI Settings로 그대로 두고, 시작하기(onboarding)는
        // AppDelegate가 NSWindow로 연다(MenuBarExtra 제거로 openWindow를 못 쓰므로).
        Settings {
            SettingsView(core: appDelegate.core)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let core = AppCore()
    /// 2026-11-06 (#154): 설정에서 아이콘을 끄면 nil이다.
    private var statusItem: NSStatusItem?
    private var launchedAsLoginItem = false
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var supportWindow: NSWindow?
    private var updateNoticeWindow: NSWindow?
    /// 2026-11-06 (#156): 닫으면 설정 창을 놓아주므로 다시 열 때 이어 줄 값만 따로 둔다(앱이 떠 있는 동안만).
    private var settingsFrame: NSRect?
    private var lastSettingsTab = SettingsTab.inputFeatures
    // deinit(nonisolated)에서 해제하므로 actor 격리에서 제외.
    nonisolated(unsafe) private var sourceObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 응용 프로그램 폴더 밖이면 옮긴다(App Translocation 방지) — 메뉴바 생성보다 먼저.
        AppMover.moveToApplicationsIfNeeded()
        // (#32) 옮기기 판단이 끝난 뒤에야 "내가 여기 있다"를 IME에 기록한다 — 옮겨서 재실행되면
        // 새 인스턴스가 다시 기록하고, 옮기지 않고 종료하면 여기까지 오지 않는다.
        AppCore.recordMainAppPathForIME()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        noteLaunchEvent()
        // (멀티모니터 좌상단 버그 — 근본 수정) status item 생성을 다음 런루프로 지연한다.
        // 재부팅 직후 메뉴바 레이아웃이 끝나기 전에 status item을 만들면 button의 window
        // 좌표가 (0,0)으로 잡혀 statusItem.menu 자동 팝업이 메뉴를 화면 좌상단에 띄웠다.
        // 메뉴바가 준비된 뒤 생성하면 좌표가 정상이라, 기본 메뉴바 앱과 동일한 자동 팝업
        // 으로 메뉴가 아이콘 바로 아래에 정확히 뜬다(수동 popUp의 위치 오차·메뉴바 침범도
        // 사라진다).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyMenuBarIconPreference()
            switch MenuBarIconDecision.launchWindow(
                onboardingDone: UserDefaults.standard.bool(forKey: "haneul.hasCompletedOnboarding"),
                iconVisible: self.menuBarIconVisible,
                launchedAsLoginItem: self.launchedAsLoginItem) {
            case .onboarding: self.showOnboarding()
            case .settings: self.showSettings(tab: .appManagement)
            case .none: break
            }
        }

        // 2026-11-06 (#154): 메뉴바 아이콘을 꺼도 메뉴에 있던 일은 설정에서 할 수 있어야 한다.
        NotificationCenter.default.addObserver(self, selector: #selector(applyMenuBarIconPreference),
                                               name: .haneulMenuBarIconChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showOnboarding),
                                               name: .haneulOnboardingRequested, object: nil)

        core.updater.onUpdateAvailable = { [weak self] update in
            self?.showUpdateNotice(update)
        }
        // 실행 시/정기 틱에 마지막 성공 확인에서 24시간 경과 여부와 OFF 설정을 확인한다.
        // 토글 OFF면 네트워크에 나가지 않는다. 결과는 표시만 — 설치는 사용자 클릭.
        core.updater.startAutomaticChecks()

        // 입력 소스 변경 알림은 메뉴바 도움말·접근성 설명과 실제 상태 갱신에만 사용한다.
        sourceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main이라 항상 메인 스레드에서 실행 — main actor로 안전하게 진입.
            MainActor.assumeIsolated {
                self?.core.refreshLanguage()
                self?.updateButtonDescription()
            }
        }
    }

    /// 2026-11-05 (#142): 메뉴바 아이콘에 기대지 않는다(HIG "Avoid relying on the presence of menu bar extras").
    /// macOS 26부터 사용자가 시스템 설정 → 메뉴 막대에서 아이콘을 끌 수 있다. 실행 중에 앱을 다시 열면 설정으로 안내한다.
    /// 2026-11-06 (#154): 설정에서 아이콘을 꺼 둔 상태라면 다시 켜는 항목이 있는 앱 관리로 바로 간다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(tab: menuBarIconVisible ? nil : .appManagement) }
        return true
    }

    /// 2026-11-06 (#154): 로그인 항목으로 떴는지 시스템의 실행 이벤트로 본다. 실측: WillFinish에서는 이벤트가 비어 있고
    /// DidFinish 안에서만 읽힌다. 그래서 비동기 블록에 들어가기 전에 확인한다.
    private func noteLaunchEvent() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return }
        let source = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        if source == OSType(keyAELaunchedAsLogInItem) { launchedAsLoginItem = true }
    }

    private var menuBarIconVisible: Bool {
        MenuBarIconDecision.isVisible(storedValue: UserDefaults.standard.object(forKey: MenuBarIconDecision.defaultsKey))
    }

    /// 2026-11-06 (#154): 아이콘을 끄면 항목 자체를 지운다. 켤 때는 메뉴바가 이미 준비된 뒤라 바로 만들어도 좌표가 정상이다.
    @objc private func applyMenuBarIconPreference() {
        if menuBarIconVisible {
            if statusItem == nil { setupStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            // 2026-10-09: 사용자 확정 처마/ㅎ. 안내 화면과 같은 템플릿을 쓴다.
            button.image = HaneulStatusIcon.image
            button.imagePosition = .imageOnly
            button.title = ""
            updateButtonDescription()
        }
        let menu = NSMenu()
        // Keep explicit busy-state disabling when AppKit updates the menu.
        menu.autoenablesItems = false
        menu.delegate = self          // 열 때마다 menuNeedsUpdate로 동적 재구성
        statusItem.menu = menu        // 기본 앱과 동일한 자동 팝업 — 아이콘 바로 아래에 정확히
    }

    deinit {
        if let sourceObserver {
            DistributedNotificationCenter.default.removeObserver(sourceObserver)
        }
    }

    private func updateButtonDescription() {
        let language = InputSwitcher.isKoreanActive() ? "한국어" : "영어"
        statusItem?.button?.toolTip = "하늘키보드 · 현재 \(language)"
        statusItem?.button?.setAccessibilityLabel("하늘키보드, 현재 \(language)")
    }

    // MARK: - NSMenuDelegate (메뉴 열 때마다 현재 상태로 재구성)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        core.refreshLanguage()
        core.refreshIMEStatus()
        let hasCompleted = UserDefaults.standard.bool(forKey: "haneul.hasCompletedOnboarding")
        let version = Updater.currentVersion

        addDisabled(menu, "하늘키보드 \(version)")
        addDisabled(menu, core.isKoreanActive ? "현재: 한국어" : "현재: 영어")
        menu.addItem(.separator())

        if !hasCompleted {
            add(menu, "시작하기...", #selector(showOnboarding))
            menu.addItem(.separator())
        }

        // 2026-11-05 오너(#142): "영어로 전환"을 뺐다. 한영 전환은 Caps Lock과 시스템 입력 메뉴가 맡는다.
        if core.imeDisabled {
            // (#32) 번들은 있는데 시스템 설정에서 입력 소스를 뺀 상태 — 한 번에 되살린다.
            add(menu, "한글 입력기가 꺼져 있음 — 다시 켜기", #selector(reenableIME))
        } else if !core.imeInstalled {
            addDisabled(menu, "한글 입력기(IME) 미설치 — 설정에서 설치 권장")
        }

        // 2026-10-24: 메뉴와 알림 모두 기존 버전·업데이트 화면으로 안내한다.
        if case .available(let update) = core.updater.phase {
            add(menu, "새 버전 \(update.tag) — \(SettingsTab.update.title)…", #selector(openUpdateSettings))
        }

        menu.addItem(.separator())
        add(menu, "설정...", #selector(openSettings))
        // 2026-11-05 오너(#142): "새 버전 확인…"을 뺐다. 설정 → 버전·업데이트의 「지금 확인」이 같은 일을 한다.
        add(menu, SupportView.title + "…", #selector(openSupport))
        if hasCompleted {
            add(menu, "시작하기 다시 보기...", #selector(showOnboarding))
        }
        // 2026-11-05 오너(#142): 종료의 뜻을 분명히 한다 — 메뉴바 앱만 꺼진다. 입력기는 별도 프로세스라 계속 동작한다.
        let quitItem = add(menu, "메뉴바 앱 종료", #selector(quit), key: "q")
        quitItem.toolTip = "메뉴바 아이콘만 사라져요. 한글 입력과 영타 변환은 그대로 동작해요. 응용 프로그램 폴더에서 다시 열 수 있어요."
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func reenableIME() {
        Task { [weak self] in
            guard let self else { return }
            if let error = await core.reenableIME() {
                // 메뉴 항목은 결과를 보여 줄 곳이 없다 — 실패를 삼키지 않고 알린다(리뷰 M-3).
                let alert = NSAlert()
                alert.messageText = "한글 입력기를 다시 켜지 못했어요"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
            updateButtonDescription()
        }
    }

    @objc private func openSettings() {
        showSettings(tab: nil)
    }

    @objc private func openUpdateSettings() {
        showSettings(tab: .update)
    }

    private func showUpdateNotice(_ update: AvailableUpdate) {
        updateNoticeWindow?.close()
        let window = UpdateNoticeWindow.make(version: update.tag, currentVersion: Updater.currentVersion) { [weak self] in
            self?.showSettings(tab: .update)
        }
        window.delegate = self
        updateNoticeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showSettings(tab: SettingsTab?) {
        // SwiftUI Settings scene을 selector(showSettingsWindow:)로 여는 방식이
        // macOS 26에서 동작하지 않아(메뉴 클릭 무반응), 설정도 onboarding과 동일하게
        // NSWindow + NSHostingController로 직접 띄운다.
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            if let tab {
                NotificationCenter.default.post(name: .haneulSettingsTabRequested, object: tab)
            }
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(
            core: core, initialTab: tab ?? lastSettingsTab,
            onTabChange: { [weak self] in self?.lastSettingsTab = $0 }))
        let win = NSWindow(contentViewController: hosting)
        // 2026-09-21 (#60): 제목 문구는 `SettingsView.windowTitle` 한 곳에서 정한다.
        win.title = SettingsView.windowTitle
        // 2026-11-05 (#135): 안내 창처럼 그림이 맨 위까지 올라간다. 제목은 띠 안에 적혀 있어 막대 글자는 숨긴다.
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        // 위치만 옮기면 안 된다. 창 높이가 내용이 놓일 때 32pt 늘어 열 때마다 내려갔다(실측). 크기까지 통째로 되돌린다.
        if let settingsFrame { win.setFrame(settingsFrame, display: false) } else { win.center() }
        win.delegate = self
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func openSupport() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = supportWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = SupportWindow.make()
        win.delegate = self
        supportWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// 2026-11-06 (#156): 앱은 창 없이 뒤에 남으므로 닫은 창을 쥐고 있지 않는다. 닫는 도중에 놓지 않게 다음 차례로 미룬다.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in self?.releaseClosedWindow(closing) }
    }

    private func releaseClosedWindow(_ window: NSWindow) {
        // 전체 제거 중이면 결과 창이 이 창에 뜨고 앱 종료도 거기서 이어지므로 놓지 않는다.
        if window === settingsWindow, !core.isRemovingProduct {
            settingsFrame = window.frame
            settingsWindow = nil
        }
        if window === onboardingWindow { onboardingWindow = nil }
        if window === supportWindow { supportWindow = nil }
        if window === updateNoticeWindow { updateNoticeWindow = nil }
    }

    @objc private func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = onboardingWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            return
        }
        // (review-0712 P3-6) 온보딩 "완료"가 이 창을 실제로 닫도록 클로저를
        // 넘긴다. 수동 NSWindow라 SwiftUI dismiss()는 동작하지 않는다.
        // isReleasedWhenClosed = false라 close() 후에도 재사용할 수 있다.
        let win = OnboardingWindow.make(rootView: OnboardingView(
            core: core,
            onSettings: { [weak self] in self?.showSettings(tab: $0) },
            onSupport: { [weak self] in self?.openSupport() },
            onComplete: { [weak self] in self?.onboardingWindow?.close() }))
        win.delegate = self
        onboardingWindow = win
        win.makeKeyAndOrderFront(nil)
    }
}

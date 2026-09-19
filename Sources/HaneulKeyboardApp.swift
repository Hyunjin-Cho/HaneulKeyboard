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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let core = AppCore()
    private var statusItem: NSStatusItem!
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
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
        // (멀티모니터 좌상단 버그 — 근본 수정) status item 생성을 다음 런루프로 지연한다.
        // 재부팅 직후 메뉴바 레이아웃이 끝나기 전에 status item을 만들면 button의 window
        // 좌표가 (0,0)으로 잡혀 statusItem.menu 자동 팝업이 메뉴를 화면 좌상단에 띄웠다.
        // 메뉴바가 준비된 뒤 생성하면 좌표가 정상이라, 기본 메뉴바 앱과 동일한 자동 팝업
        // 으로 메뉴가 아이콘 바로 아래에 정확히 뜬다(수동 popUp의 위치 오차·메뉴바 침범도
        // 사라진다).
        DispatchQueue.main.async { [weak self] in
            self?.setupStatusItem()
        }

        // 입력 소스 변경 알림 → 메뉴바 한/A 글자 + core 상태 갱신.
        sourceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main이라 항상 메인 스레드에서 실행 — main actor로 안전하게 진입.
            MainActor.assumeIsolated {
                self?.core.refreshLanguage()
                self?.updateButtonTitle()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble",
                                   accessibilityDescription: "HaneulKeyboard")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            updateButtonTitle()
        }
        let menu = NSMenu()
        menu.delegate = self          // 열 때마다 menuNeedsUpdate로 동적 재구성
        statusItem.menu = menu        // 기본 앱과 동일한 자동 팝업 — 아이콘 바로 아래에 정확히
    }

    deinit {
        if let sourceObserver {
            DistributedNotificationCenter.default.removeObserver(sourceObserver)
        }
    }

    private func updateButtonTitle() {
        statusItem?.button?.title = InputSwitcher.isKoreanActive() ? " 한" : " A"
    }

    // MARK: - NSMenuDelegate (메뉴 열 때마다 현재 상태로 재구성)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        core.refreshLanguage()
        core.refreshIMEStatus()
        let hasCompleted = UserDefaults.standard.bool(forKey: "haneul.hasCompletedOnboarding")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        addDisabled(menu, "HaneulKeyboard \(version)")
        addDisabled(menu, core.isKoreanActive ? "현재: 한국어" : "현재: 영어")
        menu.addItem(.separator())

        if !hasCompleted {
            add(menu, "시작하기...", #selector(showOnboarding))
            menu.addItem(.separator())
        }

        add(menu, core.isKoreanActive ? "영어로 전환" : "한국어로 전환", #selector(toggleLanguage))

        if core.imeDisabled {
            // (#32) 번들은 있는데 시스템 설정에서 입력 소스를 뺀 상태 — 한 번에 되살린다.
            add(menu, "한글 입력기가 꺼져 있음 — 다시 켜기", #selector(reenableIME))
        } else if !core.imeInstalled {
            addDisabled(menu, "한글 입력기(IME) 미설치 — 설정에서 설치 권장")
        }

        menu.addItem(.separator())
        add(menu, "설정...", #selector(openSettings))
        if hasCompleted {
            add(menu, "시작하기 다시 보기...", #selector(showOnboarding))
        }
        add(menu, "HaneulKeyboard 종료", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func toggleLanguage() {
        core.toggleLanguage()
        updateButtonTitle()
    }

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
            updateButtonTitle()
        }
    }

    @objc private func openSettings() {
        // SwiftUI Settings scene을 selector(showSettingsWindow:)로 여는 방식이
        // macOS 26에서 동작하지 않아(메뉴 클릭 무반응), 설정도 onboarding과 동일하게
        // NSWindow + NSHostingController로 직접 띄운다.
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(core: core))
        let win = NSWindow(contentViewController: hosting)
        win.title = "HaneulKeyboard 설정"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = onboardingWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        // (review-0712 P3-6) 온보딩 "완료"가 이 창을 실제로 닫도록 클로저를
        // 넘긴다. 수동 NSWindow라 SwiftUI dismiss()는 동작하지 않는다.
        // isReleasedWhenClosed = false라 close() 후에도 재사용할 수 있다.
        let hosting = NSHostingController(rootView: OnboardingView(core: core) { [weak self] in
            self?.onboardingWindow?.close()
        })
        let win = NSWindow(contentViewController: hosting)
        win.title = "HaneulKeyboard 시작하기"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false   // 재사용 위해 닫혀도 해제 안 함
        win.center()
        onboardingWindow = win
        win.makeKeyAndOrderFront(nil)
    }
}

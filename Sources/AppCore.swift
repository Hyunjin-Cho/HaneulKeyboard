import AppKit
import Carbon
import Foundation

@Observable
final class AppCore {
    private(set) var isKoreanActive: Bool = InputSwitcher.isKoreanActive()
    private(set) var imeInstalled: Bool = IMEInstaller.isInstalled

    private var sourceObserver: NSObjectProtocol?

    init() {
        sourceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLanguage()
        }

        autoInstallIMEIfNeeded()
    }

    private func autoInstallIMEIfNeeded() {
        guard !IMEInstaller.isInstalled else { return }
        DispatchQueue.main.async { [weak self] in
            do {
                try IMEInstaller.install()
                self?.refreshIMEStatus()
                haneulLog("HaneulKeyboard: auto-installed IME to \(IMEInstaller.installURL.path)")
            } catch {
                haneulLog("HaneulKeyboard: auto-install failed — \(error.localizedDescription)")
            }
        }
    }

    deinit {
        if let observer = sourceObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }

    func refreshLanguage() {
        let current = InputSwitcher.isKoreanActive()
        if current != isKoreanActive {
            isKoreanActive = current
        }
    }

    func refreshIMEStatus() {
        let current = IMEInstaller.isInstalled
        if current != imeInstalled {
            imeInstalled = current
        }
    }

    func toggleLanguage() {
        InputSwitcher.toggle()
        refreshLanguage()
    }
}

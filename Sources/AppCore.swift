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

        ensureIMEActive()
    }

    /// Guarantees install + TIS ACTIVATION on every app launch.
    ///
    /// macOS 26 only shows an IME in the input-source picker after
    /// TISEnableInputSource runs inside a signed GUI app — the install
    /// script (CLI) cannot do that, so this app is the activation vehicle.
    /// A previous version skipped entirely when already installed, which
    /// left script-installed bundles invisible in the picker (2026-06-06).
    /// install() is idempotent: already-active → no-op (no list bloat);
    /// system install present → no copy, just register/enable as needed.
    private func ensureIMEActive() {
        DispatchQueue.main.async { [weak self] in
            do {
                let url = try IMEInstaller.install()
                self?.refreshIMEStatus()
                haneulLog("HaneulKeyboard: IME ensured active at \(url.path)")
            } catch IMEInstallError.bundleNotFound {
                haneulLog("HaneulKeyboard: IME bundle not found — ensure skipped")
            } catch {
                haneulLog("HaneulKeyboard: IME ensure failed — \(error.localizedDescription)")
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

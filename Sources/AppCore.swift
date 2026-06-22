import AppKit
import Carbon
import Foundation

@Observable
@MainActor
final class AppCore {
    private(set) var isKoreanActive: Bool = InputSwitcher.isKoreanActive()
    private(set) var imeInstalled = false
    private(set) var imeActivationError: Error?

    // deinit(nonisolated)에서 removeObserver로 해제하므로 actor 격리에서 제외.
    nonisolated(unsafe) private var sourceObserver: NSObjectProtocol?

    init() {
        sourceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLanguage() }
        }

        ensureIMEActive()
    }

    /// Guarantees TIS REGISTRATION/ENABLE on every app launch, without copying
    /// a new bundle into ~/Library/Input Methods.
    ///
    /// macOS 26 only shows an IME in the input-source picker after
    /// TISEnableInputSource runs inside a signed GUI app — the install
    /// script (CLI) cannot do that, so this app remains the activation vehicle.
    /// Learned 2026-06-06: removing this startup enable call regresses picker
    /// visibility for system-domain installs done by build_notarize_install.sh.
    /// So we keep register/enable here, but move bundle copying behind explicit
    /// consent buttons in Settings/Onboarding.
    private func ensureIMEActive() {
        Task { [weak self] in
            do {
                guard let result = try await IMEInstaller.activateInstalled() else {
                    await self?.updateIMEStatus()
                    haneulLog("HaneulKeyboard: no installed IME bundle found — activation skipped")
                    return
                }
                self?.imeActivationError = nil
                await self?.updateIMEStatus()
                haneulLog("HaneulKeyboard: IME ensured active at \(result.url.path)")
            } catch IMEInstallError.bundleNotFound {
                haneulLog("HaneulKeyboard: IME bundle not found — ensure skipped")
            } catch {
                self?.imeActivationError = error
                self?.imeInstalled = false
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
        Task { [weak self] in
            await self?.updateIMEStatus()
        }
    }

    private func updateIMEStatus() async {
        let current = await IMEInstaller.isInstalled()
        if current != imeInstalled { imeInstalled = current }
    }

    func toggleLanguage() {
        InputSwitcher.toggle()
        refreshLanguage()
    }
}

import AppKit
import Carbon
import Foundation

@Observable
@MainActor
final class AppCore {
    private(set) var isKoreanActive: Bool = InputSwitcher.isKoreanActive()
    private(set) var imeInstalled = false
    private(set) var imeActivationError: Error?

    // 입력 소스 변경 관찰은 AppDelegate가 단독으로 한다(거기서 core.refreshLanguage()
    // 를 호출). AppCore가 중복 관찰하면 actor 격리 경고만 늘어 제거했다.
    init() {
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

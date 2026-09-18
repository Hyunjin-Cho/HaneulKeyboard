import AppKit
import Carbon
import Foundation

@Observable
@MainActor
final class AppCore {
    private(set) var isKoreanActive: Bool = InputSwitcher.isKoreanActive()
    private(set) var imeInstalled = false
    /// 번들은 있는데 입력 소스가 꺼져 있음(시스템 설정에서 뺀 경우). (#32)
    private(set) var imeDisabled = false
    private(set) var imeActivationError: Error?

    /// IME가 "메인 앱이 아직 있는가"를 판단할 때 쓰는 기록 — 앱이 실행될 때마다 IME
    /// 설정 도메인에 자기 경로와 파일 번호(inode)를 남긴다. IME는 이 경로(와 같은 이름·
    /// 같은 inode의 휴지통 사본)를 먼저 보고, 없으면 LaunchServices·표준 폴더를 뒤진다.
    /// 호출 시점: `AppMover`가 /Applications로 옮긴 **뒤**(옮기면 재실행되어 새 인스턴스가
    /// 올바른 경로를 기록하고, 옮기지 않고 종료하면 곧 사라질 translocation 경로를 남기지
    /// 않는다 — 리뷰 M-1). (#32, 2026-09-19)
    static func recordMainAppPathForIME() {
        let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")
        let url = Bundle.main.bundleURL.standardizedFileURL
        imeDefaults?.set(url.path, forKey: "haneul.mainAppPath")
        if let fileID = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int {
            imeDefaults?.set(fileID, forKey: "haneul.mainAppFileID")
        } else {
            imeDefaults?.removeObject(forKey: "haneul.mainAppFileID")
        }
    }

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
        let state = await IMEInstaller.installationState()
        let ready = state == .ready
        let disabled = state == .installedDisabled
        if ready != imeInstalled { imeInstalled = ready }
        if disabled != imeDisabled { imeDisabled = disabled }
    }

    /// 꺼진 입력 소스를 다시 켠다 — 설치 버튼과 같은 경로(TISEnableInputSource, GUI 앱 컨텍스트).
    /// 번들을 새로 복사하지는 않는다. 실패는 호출자(메뉴)가 사용자에게 보여 준다(리뷰 M-3). (#32)
    func reenableIME() async -> Error? {
        var failure: Error?
        do {
            _ = try await IMEInstaller.activateInstalled()
            imeActivationError = nil
        } catch {
            imeActivationError = error
            failure = error
        }
        await updateIMEStatus()
        return failure
    }

    func toggleLanguage() {
        InputSwitcher.toggle()
        refreshLanguage()
    }
}

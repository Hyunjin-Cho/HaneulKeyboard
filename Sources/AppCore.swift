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
    /// 2026-09-21 (#19): 설치된 IME가 임베드본보다 오래됐는데 자동 갱신을 못 했다(root 소유
    /// 설치본이거나 갱신 실패). 설정의 「업데이트」 절이 "IME 갱신 필요" 안내를 띄우는 폴백.
    private(set) var imeRefreshNeeded = false
    /// 자동 업데이트(#19). 스케줄 시작은 `AppDelegate.applicationDidFinishLaunching`에서.
    let updater = Updater()

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
                // 2026-09-21 (#19): 설치된 IME 빌드번호 < 임베드본이면 설정의 "IME 설치" 버튼과
                // 같은 경로(`installBundle`: IME 정지 → staging → 원자 교체 → LaunchServices·TIS
                // 등록·활성화)로 갱신한다. "시작 시 복사 금지"(H-01)의 예외는 **딱 이 조건**이다.
                // ⚠️ 2026-09-21 (#19 보안 검토 P3-3 주석 정정): 종전 주석은 "자동 업데이트로 앱이
                // 교체된 뒤 첫 실행"이라고 적었지만, 코드는 업데이트 여부를 보지 않는다 — 두 빌드
                // 번호만 비교하므로 **설치본이 낡아 있는 동안은 매 실행마다** 이 경로를 탄다
                // (예: 사용자가 IME만 옛 버전으로 되돌려 둔 경우). 로직은 그대로 두고 설명만 맞춘다.
                // root 소유 설치본(/Library/Input Methods)은 `installBundle`이 복사하지 않으므로
                // 여기서 안내 폴백으로 돌린다. 사용자 클릭 없이 TIS 활성화가 되는지는 실기기 체크리스트.
                let builds = IMEInstaller.imeBuildNumbersForRefresh()
                if UpdateDecision.shouldRefreshIME(installedBuild: builds.installed, bundledBuild: builds.bundled) {
                    if builds.installedURL == IMEInstaller.systemInstallURL {
                        self?.imeRefreshNeeded = true
                        haneulLog("HaneulKeyboard: installed IME build \(builds.installed ?? -1) < bundled \(builds.bundled ?? -1) but install is system-domain (root) — manual refresh needed")
                    } else {
                        do {
                            let result = try await IMEInstaller.installBundle()
                            self?.imeRefreshNeeded = false
                            self?.imeActivationError = nil
                            await self?.updateIMEStatus()
                            haneulLog("HaneulKeyboard: IME refreshed to bundled build \(builds.bundled ?? -1) at \(result.url.path) (was \(builds.installed ?? -1))")
                            return
                        } catch {
                            self?.imeRefreshNeeded = true
                            haneulLog("HaneulKeyboard: IME refresh failed — \(error.localizedDescription); falling back to activation of installed build")
                        }
                    }
                }
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
        // 2026-09-21 (#19): "IME 갱신 필요" 안내는 매번 디스크를 다시 보고 정한다. 사용자가
        // 안내대로 직접 다시 설치하면(설정의 IME 설치/제거 버튼 → refreshIMEStatus) 빌드번호가
        // 맞춰지므로 안내가 그 자리에서 사라져야 한다 — 한 번 켜지면 재실행 전까지 남던 버그.
        let builds = IMEInstaller.imeBuildNumbersForRefresh()
        let stale = UpdateDecision.shouldRefreshIME(installedBuild: builds.installed, bundledBuild: builds.bundled)
        if !stale && imeRefreshNeeded { imeRefreshNeeded = false }
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

    /// 한↔영 전환. 실패(영문 자판 없음·우리 입력 소스 꺼짐)를 호출자가 알 수 있게 돌려준다.
    /// 2026-09-20 (#45, 리뷰 F-5): 종전엔 반환값을 버려 메뉴가 조용히 실패했다.
    @discardableResult
    func toggleLanguage() -> Bool {
        let switched = InputSwitcher.toggle()
        refreshLanguage()
        return switched
    }
}

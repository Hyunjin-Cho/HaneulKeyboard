import AppKit
import Carbon
import Foundation

@Observable
@MainActor
final class AppCore {
    /// 2026-11-07 (#177, 리뷰 app-ui-F-7): 한국어/영어 이진 값이 아니라 지금 입력 소스가 하늘키보드인지·무엇인지를 담는다.
    private(set) var inputSource = AppCore.currentInputSource()
    private(set) var imeInstalled = false
    /// 2026-11-07 (#177, 리뷰 app-ui-F-1): 입력기 상태를 실제로 한 번이라도 읽었는가. `imeInstalled`의 기본값 false는 "읽기 전"일 뿐
    /// "미설치"가 아니다 — 읽기 전에 메뉴를 열면 `IMEStatusPresentation`이 "확인 중"으로 보인다.
    private(set) var imeStatusKnown = false
    /// 번들은 있는데 입력 소스가 꺼져 있음(시스템 설정에서 뺀 경우). (#32)
    private(set) var imeDisabled = false
    private(set) var imeActivationError: Error?
    private(set) var imeSettingsRefreshWarning: String?
    /// 2026-09-21 (#19): 설치된 IME가 임베드본보다 오래됐는데 자동 갱신을 못 했다(root 소유
    /// 설치본이거나 갱신 실패). 설정의 「업데이트」 절이 "IME 갱신 필요" 안내를 띄우는 폴백.
    private(set) var imeRefreshNeeded = false
    /// 2026-11-07 (#177, 리뷰 app-ui-F-3): 갱신이 필요한데 낡은 입력기가 시스템 영역(/Library/Input Methods, root 소유)에 있어
    /// 앱이 직접 바꿀 수 없다. 설치 버튼은 재등록만 하고 끝나므로, 화면이 막다른 길이 되지 않게 "앱 관리에서 제거 뒤 다시 설치"로 안내한다.
    private(set) var imeRefreshBlockedBySystemInstall = false
    /// 설치/시작 시 자동 갱신을 한 번에 하나만 진행한다. 안내창과 설정이 공유한다.
    let operationGate: ProductOperationGate
    private(set) var removalPendingExit = false
    var isPreparingIME: Bool { operationGate.operation != nil || removalPendingExit }
    var isRemovingProduct: Bool { operationGate.operation == .removingProduct || removalPendingExit }
    /// 2026-11-07 (#177, 리뷰 app-ui-F-4): 제거가 메인 스레드 밖에서 돌게 되어, 그 사이 메뉴에서 앱을 끝낼 수 있게 되었다.
    /// 제거 도중에 끝나면 반쯤 지워진 채 남으므로 메뉴가 "메뉴바 앱 종료"를 막는 데 쓴다. 제거가 끝나고 종료를 기다리는 동안은 해당 없다.
    var isRemovalInProgress: Bool {
        operationGate.operation == .removingInputMethod || operationGate.operation == .removingProduct
    }
    private(set) var imeOnDisk = false
    private(set) var lastInputRemovalReport: RemovalReport?
    private var statusRefreshGeneration = 0
    /// 2026-11-07 (#177): 결과가 실제로 반영된 가장 최근 읽기 번호. 더 늦게 시작한 읽기에 밀린 읽기는 반영되지 않는다.
    private var statusAppliedGeneration = 0
    /// 자동 업데이트(#19). 스케줄 시작은 `AppDelegate.applicationDidFinishLaunching`에서.
    let updater: Updater

    /// IME가 "메인 앱이 아직 있는가"를 판단할 때 쓰는 기록 — 앱이 실행될 때마다 IME
    /// 설정 도메인에 자기 경로와 파일 번호(inode)를 남긴다. IME는 이 경로(와 같은 이름·
    /// 같은 inode의 휴지통 사본)를 먼저 보고, 없으면 LaunchServices·/Applications·~/Applications를 본다.
    /// 호출 시점: `AppMover`가 /Applications로 옮긴 **뒤**(옮기면 재실행되어 새 인스턴스가
    /// 올바른 경로를 기록하고, 옮기지 않고 종료하면 곧 사라질 translocation 경로를 남기지
    /// 않는다 — 리뷰 M-1). (#32, 2026-09-19)
    static func recordMainAppPathForIME() {
        // 2026-11-07 (#177, 리뷰 app-ui-F-8): 도메인·키 이름은 상수 한 곳에서 온다(값은 그대로).
        let imeDefaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)
        let url = Bundle.main.bundleURL.standardizedFileURL
        imeDefaults?.set(url.path, forKey: HaneulDefaultsKey.mainAppPath)
        if let fileID = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int {
            imeDefaults?.set(fileID, forKey: HaneulDefaultsKey.mainAppFileID)
        } else {
            imeDefaults?.removeObject(forKey: HaneulDefaultsKey.mainAppFileID)
        }
    }

    /// 지금 입력 소스를 분류한다(분류 규칙은 `InputSourceDescription`).
    static func currentInputSource() -> InputSourceDescription {
        InputSourceDescription.classify(sourceID: InputSwitcher.currentSourceID(),
                                        localizedName: InputSwitcher.currentSourceLocalizedName(),
                                        haneulID: InputSwitcher.koreanModeID)
    }

    // 입력 소스 변경 관찰은 AppDelegate가 단독으로 한다(거기서 core.refreshInputSource()
    // 를 호출). AppCore가 중복 관찰하면 actor 격리 경고만 늘어 제거했다.
    // 2026-11-07 (#177, 리뷰 app-ui-F-1): 입력 소스가 켜짐/꺼짐으로 바뀌는 알림과 앱 활성화도 같은 곳(AppDelegate)에서 받아
    // `refreshIMEStatus()`를 부른다. 예전엔 안내 창에만 있어, 안내가 닫혀 있으면 메뉴·설정이 갱신 전 값을 그렸다.
    init(activateIMEOnLaunch: Bool = true) {
        let gate = ProductOperationGate()
        operationGate = gate
        updater = Updater(operationGate: gate)
        if activateIMEOnLaunch { ensureIMEActive() }
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
    func ensureIMEActive() {
        guard let token = operationGate.begin(.activating) else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { self.operationGate.finish(token) }
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
                        self.imeRefreshNeeded = true
                        self.imeRefreshBlockedBySystemInstall = true
                        haneulLog("HaneulKeyboard: installed IME build \(builds.installed ?? -1) < bundled \(builds.bundled ?? -1) but install is system-domain (root) — manual refresh needed")
                    } else {
                        do {
                            let result = try await IMEInstaller.installBundle()
                            self.imeRefreshNeeded = false
                            self.imeActivationError = nil
                            self.imeSettingsRefreshWarning = result.settingsRefreshWarning
                            await self.updateIMEStatus()
                            haneulLog("HaneulKeyboard: IME refreshed to bundled build \(builds.bundled ?? -1) at \(result.url.path) (was \(builds.installed ?? -1))")
                            return
                        } catch {
                            self.imeRefreshNeeded = true
                            haneulLog("HaneulKeyboard: IME refresh failed — \(error.localizedDescription); falling back to activation of installed build")
                        }
                    }
                }
                guard let result = try await IMEInstaller.activateInstalled() else {
                    await self.updateIMEStatus()
                    haneulLog("HaneulKeyboard: no installed IME bundle found — activation skipped")
                    return
                }
                self.imeActivationError = nil
                self.imeSettingsRefreshWarning = result.settingsRefreshWarning
                await self.updateIMEStatus()
                haneulLog("HaneulKeyboard: IME ensured active at \(result.url.path)")
            } catch IMEInstallError.bundleNotFound {
                haneulLog("HaneulKeyboard: IME bundle not found — ensure skipped")
            } catch {
                self.imeActivationError = error
                self.imeInstalled = false
                haneulLog("HaneulKeyboard: IME ensure failed — \(error.localizedDescription)")
            }
        }
    }

    /// 사용자 버튼에서 호출하는 공통 설치 경로. 시작 시 자동 갱신과 겹치지 않는다.
    func installIME() async -> Error? {
        guard !removalPendingExit, let token = operationGate.begin(.installing) else { return ProductOperationError.busy }
        defer { operationGate.finish(token) }
        do {
            let result = try await IMEInstaller.installBundle()
            imeActivationError = nil
            imeSettingsRefreshWarning = result.settingsRefreshWarning
            await updateIMEStatus()
            return nil
        } catch {
            imeActivationError = error
            await updateIMEStatus()
            return error
        }
    }

    /// 2026-10-10 (#88): 앱 관리에서도 설치/갱신과 같은 실행 잠금을 공유한다.
    /// 2026-11-07 (#177, 리뷰 app-ui-F-4): 제거의 ps·lsregister·defaults 대기는 메인 스레드 밖에서 돈다(`Uninstaller`). 그동안 UI가
    /// 멈추지 않고, 작업권을 잡은 직후라 "입력기를 관리하는 중…" 표시가 먼저 그려진다.
    func uninstallIME() async -> Error? {
        guard !removalPendingExit, let token = operationGate.begin(.removingInputMethod) else { return ProductOperationError.busy }
        defer { operationGate.finish(token) }
        let report = await IMEInstaller.uninstall()
        lastInputRemovalReport = report
        await updateIMEStatus()
        if report.complete { imeActivationError = nil; imeSettingsRefreshWarning = nil; return nil }
        return IMEInstallError.uninstallFailed(report.statusText)
    }

    func removeFullProduct() async -> Uninstaller.Outcome {
        guard !removalPendingExit, let token = operationGate.begin(.removingProduct) else {
            return Uninstaller.Outcome(report: .blocked(mode: .wholeProduct, reason: ProductOperationError.busy.localizedDescription))
        }
        defer { operationGate.finish(token) }
        guard updater.pauseForRemoval() else {
            return Uninstaller.Outcome(report: .blocked(mode: .wholeProduct, reason: "업데이트 교체가 진행 중이에요. 끝난 뒤 다시 시도해 주세요"))
        }
        // 2026-11-07 (#177, 리뷰 app-ui-F-4): 예전엔 `Task.yield()`로 진행 표시를 먼저 그리게 했지만 같은 런루프 턴에 재개될 수 있었다.
        // 이제 제거 순서 전체가 메인 스레드 밖에서 돌아(관리자 암호창·입력 소스 조작만 메인으로 돌아온다) 메인이 비어 표시가 그려진다.
        // 작업권은 await 구간에도 유지된다.
        let result = await Uninstaller.run()
        removalPendingExit = result.fullyRemoved
        if !result.fullyRemoved { updater.resumeAfterRemoval(); await updateIMEStatus() }
        return result
    }

    func refreshInputSource() {
        let current = Self.currentInputSource()
        if current != inputSource {
            inputSource = current
        }
    }

    func refreshIMEStatus() {
        Task { [weak self] in
            await self?.updateIMEStatus()
        }
    }

    /// 2026-11-07 (#177, 리뷰 app-ui-F-1): 열려 있는 메뉴가 갱신이 끝난 뒤 칸을 다시 그리려고 완료를 기다린다.
    /// 앱 활성화·입력 소스 알림이 같은 때 새 읽기를 시작하면 내 읽기는 반영되지 않고 끝난다(`updateIMEStatus`의 세대 확인) —
    /// 그러면 가장 늦게 시작한 읽기가 반영될 때까지 잠깐(최대 2초) 더 기다린다. 아니면 메뉴가 읽기 전 값으로 그려진다.
    func refreshIMEStatusAndWait() async {
        await updateIMEStatus()
        var waits = 0
        while statusAppliedGeneration < statusRefreshGeneration, waits < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            waits += 1
        }
    }

    private func updateIMEStatus() async {
        statusRefreshGeneration += 1
        let generation = statusRefreshGeneration
        let state = await IMEInstaller.installationState()
        guard generation == statusRefreshGeneration else { return }
        statusAppliedGeneration = generation
        imeOnDisk = [RemovalObservation.userIME, RemovalObservation.systemIME].contains { RemovalObservation.absence(at: $0) != .alreadyAbsent }
        let ready = state == .ready
        let disabled = state == .installedDisabled
        if ready != imeInstalled { imeInstalled = ready }
        if disabled != imeDisabled { imeDisabled = disabled }
        // 2026-09-21 (#19): "IME 갱신 필요" 안내는 매번 디스크를 다시 보고 정한다. 사용자가
        // 안내대로 직접 다시 설치하면(설정의 IME 설치/제거 버튼 → refreshIMEStatus) 빌드번호가
        // 맞춰지므로 안내가 그 자리에서 사라져야 한다 — 한 번 켜지면 재실행 전까지 남던 버그.
        let builds = IMEInstaller.imeBuildNumbersForRefresh()
        let stale = UpdateDecision.shouldRefreshIME(installedBuild: builds.installed, bundledBuild: builds.bundled)
        if stale != imeRefreshNeeded { imeRefreshNeeded = stale }
        let blocked = stale && builds.installedURL == IMEInstaller.systemInstallURL
        if blocked != imeRefreshBlockedBySystemInstall { imeRefreshBlockedBySystemInstall = blocked }
        if !imeStatusKnown { imeStatusKnown = true }
    }

    /// 꺼진 입력 소스를 다시 켠다 — 설치 버튼과 같은 경로(TISEnableInputSource, GUI 앱 컨텍스트).
    /// 번들을 새로 복사하지는 않는다. 실패는 호출자(메뉴)가 사용자에게 보여 준다(리뷰 M-3). (#32)
    func reenableIME() async -> Error? {
        guard !removalPendingExit, let token = operationGate.begin(.activating) else { return ProductOperationError.busy }
        defer { operationGate.finish(token) }
        var failure: Error?
        do {
            let result = try await IMEInstaller.activateInstalled()
            imeActivationError = nil
            imeSettingsRefreshWarning = result?.settingsRefreshWarning
        } catch {
            imeActivationError = error
            failure = error
        }
        await updateIMEStatus()
        return failure
    }
}

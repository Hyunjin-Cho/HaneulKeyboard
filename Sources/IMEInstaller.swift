import AppKit
import Carbon
import Foundation
import Security

enum IMEInstaller {
    static let bundleName = "HaneulKeyboardIM.app"
    /// IME 번들 ID이자 설정(defaults) 도메인 이름. 2026-09-20 (#46): 공유 비활성화 함수용으로 추가.
    /// 2026-11-07 (#177, 리뷰 app-ui-F-8): 앱 쪽의 같은 리터럴(이 파일 안 `registerWithTIS`·`tisActivationState`와
    /// 설정 화면 여러 곳)을 모두 이 상수로 모았다. 값은 그대로다(입력기 Info.plist·사용자 저장소와 같아야 한다).
    static let imeBundleID = "com.hyunjincho.inputmethod.haneul"

    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/\(bundleName)")
    }

    /// System-wide install path — where scripts/build_notarize_install.sh
    /// puts the IME. When this exists it is the CANONICAL install; creating
    /// a second copy in the user domain produces duplicate rows in the
    /// System Settings input-source list (learned 2026-06-06).
    static var systemInstallURL: URL {
        URL(fileURLWithPath: "/Library/Input Methods/\(bundleName)")
    }

    /// IME bundle that ships next to the main app — both Debug builds land in
    /// the same DerivedData/Products folder, and a released app would carry
    /// the IME inside its Contents/Helpers folder. We probe both.
    static var bundledIMEURL: URL? {
        let embedded = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(bundleName)")
        var candidates: [URL] = []
        #if DEBUG
        // 개발 편의(Debug 전용): 두 타겟이 같은 DerivedData/Products 폴더에
        // 떨어지므로 sibling 번들도 후보로 본다. Release에서는 신뢰 경계
        // 때문에 내장 Helper만 허용한다 (H-01 — 앱 서명 범위 밖 코드 차단).
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        candidates.append(parent.appendingPathComponent(bundleName))
        #endif
        candidates.append(embedded)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct ActivationResult: Sendable {
        let url: URL
        let settingsRefreshWarning: String?
        init(url: URL, settingsRefreshWarning: String? = nil) {
            self.url = url
            self.settingsRefreshWarning = settingsRefreshWarning
        }
    }

    /// A bundle on disk is only a candidate. Call `isInstalled()` when
    /// reporting user-visible installation state; it also verifies TIS state.
    static func isInstalled() async -> Bool {
        await installationState() == .ready
    }

    /// 사용자에게 보여줄 설치 상태 3단계. (#32, 2026-09-19)
    /// 예전엔 `isInstalled()`의 Bool 하나라, 사용자가 시스템 설정에서 입력 소스를 "-"로
    /// 뺀 경우도 "미설치"로 표시됐다. 번들은 있는데 꺼진 상태를 구분해 메뉴에서 바로
    /// 다시 켤 수 있게 한다(역방향 연동).
    enum InstallationState: Equatable {
        case notInstalled
        /// 신뢰할 수 있는 번들은 있지만 TIS에서 활성(enabled)이 아님.
        case installedDisabled
        case ready
    }

    static func installationState() async -> InstallationState {
        let trustedBundleExists = await Task.detached(priority: .utility) {
            installedBundleURL().map { isTrustedIMEBundle(at: $0) } ?? false
        }.value
        guard trustedBundleExists else { return .notInstalled }
        let state = await MainActor.run { tisActivationState() }
        // TIS가 우리를 아예 모르면(등록 자체가 없음) "꺼짐"이 아니라 미설치로 본다 —
        // 설치 버튼 경로가 등록까지 한다. (리뷰 M-3)
        guard state.known else { return .notInstalled }
        return state.enabled ? .ready : .installedDisabled
    }

    /// Apple이 발급한 인증서로 서명됐고 메인 앱과 같은 Team인지 확인한다.
    /// 포크는 자기 Team으로 서명한 메인 앱/IME를 사용할 수 있다.
    static func isTrustedIMEBundle(at url: URL) -> Bool {
        isSameTeamSignedBundle(at: url)
    }

    /// Debug도 기본 검증. 미서명 개발 테스트는 haneul.debugSkipTeamCheck 명시 허용이 필요하다.
    static func isSameTeamSignedBundle(at url: URL) -> Bool {
        BundleTrust.isSameTeamSignedBundle(at: url)
    }

    /// 번들의 빌드 번호(CFBundleVersion, 단조증가 정수). 버전 비교용. 문자열
    /// 비교는 "10" < "9" 오류가 나므로 정수로 파싱한다. nil = 추출 실패. (H-03)
    static func buildNumber(at url: URL) -> Int? {
        BundleInfoFile.buildNumber(at: url)
    }

    /// 2026-09-21 (#19): 자동 업데이트로 앱이 교체된 뒤 첫 실행에서 "설치된 IME가 임베드본보다
    /// 오래됐는가"를 `AppCore`가 판단하는 데 쓰는 재료. 판단 자체는
    /// `UpdateDecision.shouldRefreshIME`(테스트 대상)에 있다. 설치본이 없으면 전부 nil.
    /// `installedURL`이 `systemInstallURL`이면 root 소유라 앱이 스스로 갈 수 없다.
    static func imeBuildNumbersForRefresh() -> (installed: Int?, bundled: Int?, installedURL: URL?) {
        guard let installed = installedBundleURL() else { return (nil, nil, nil) }
        return (buildNumber(at: installed), bundledIMEURL.flatMap(buildNumber(at:)), installed)
    }

    /// 시스템 도메인이 기준일 때도 사용자 잔재 삭제 실패를 성공으로 처리하지 않는다.
    private static func removeUserDomainLeftover() throws {
        try stopIMEProcess()
        let (target, state) = RemovalObservation.capture(installURL, identifier: imeBundleID)
        guard state.reachedGoal else { throw IMEInstallError.uninstallFailed(state.text) }
        if let target {
            let result = RemovalObservation.remove(target)
            guard result.reachedGoal else { throw IMEInstallError.uninstallFailed(result.text) }
        }
        let registration = RemovalObservation.unregister([installURL], identifier: imeBundleID)
        guard registration.reachedGoal else { throw IMEInstallError.uninstallFailed(registration.text) }
    }

    /// 설치 교체도 실제 프로세스 종료를 재확인한다. 조회 실패·다른 실행본은 교체를 중단한다.
    static func stopIMEProcess() throws {
        let state = RemovalObservation.stopIMEProcesses()
        guard state.reachedGoal else { throw IMEInstallError.uninstallFailed(state.text) }
    }

    /// 실행 중인 IME를 멈춘 뒤 trusted source를 staging에 복사하고 원자 교체한다.
    /// staging 준비나 교체가 실패하면 기존 설치본은 그대로 남는다.
    private static func atomicallyReplaceIMEBundle(at destination: URL, with source: URL) throws {
        try stopIMEProcess()
        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
    }

    @discardableResult
    static func installBundle() async throws -> ActivationResult {
        let url = try await Task.detached(priority: .userInitiated) {
            try installBundleOnDisk()
        }.value
        let result = try await activateBundle(at: url)
        await launchIMEIfNeeded()
        return result
    }

    /// 2026-11-05 (#146): 입력기 프로세스를 우리가 먼저 띄운다.
    /// 오너 첫 설치 로그(2026-11-05 21:27): 앱 안에서 하늘키보드를 고른 순간 시스템 imklaunchagent가
    /// `LaunchInputMethod() Error, status=-50`으로 입력기를 못 띄웠고 재시도도 없었다. 그래서 안내 입력칸에서
    /// 한글이 안 쳐졌다. 18초 뒤 메모를 열자 그 요청으로 입력기가 떴고, 돌아오니 쳐졌다.
    /// 입력기는 시작할 때 IMKServer가 연결 주소를 스스로 등록한다(같은 로그의 `setIMKXPCEndpoint`).
    /// 그래서 먼저 띄워 두면 실패한 경로를 타지 않는다. -50이 왜 나는지는 시스템 내부라 확인하지 못했다.
    /// 실행 중이면 아무것도 하지 않는다. 신뢰 검증을 통과한 설치본만 띄운다. 실제로 띄웠을 때만 true.
    @MainActor private static var launchInFlight = false

    @MainActor @discardableResult
    static func launchIMEIfNeeded() async -> Bool {
        guard !launchInFlight,
              NSRunningApplication.runningApplications(withBundleIdentifier: imeBundleID).isEmpty else { return false }
        launchInFlight = true
        defer { launchInFlight = false }
        let trusted = await Task.detached(priority: .userInitiated) { () -> URL? in
            guard let url = installedBundleURL(), isTrustedIMEBundle(at: url) else { return nil }
            return url
        }.value
        guard let trusted else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: trusted, configuration: configuration)
            // 같은 로그에서 프로세스 시작부터 연결 주소 등록까지 0.8초였다. 등록 뒤에 입력칸 세션을 다시 잇게 기다린다.
            try? await Task.sleep(for: .seconds(1))
            return true
        } catch {
            haneulLog("HaneulKeyboard: 입력기 먼저 띄우기 실패 — \(error.localizedDescription)")
            return false
        }
    }

    private static func installBundleOnDisk() throws -> URL {
        // A system-domain install (from the build script) is canonical.
        // NEVER lay a second copy in the user domain on top of it — that's
        // exactly what produced the duplicated input-source rows. Instead,
        // clean any user-domain leftover and just (re)activate the canonical
        // bundle with TIS.
        if FileManager.default.fileExists(atPath: systemInstallURL.path) {
            guard isTrustedIMEBundle(at: systemInstallURL) else {
                throw IMEInstallError.installedBundleUntrusted(systemInstallURL.path)
            }
            if FileManager.default.fileExists(atPath: installURL.path) {
                // (H-03 엣지) user-domain 잔재를 지우기 전에 IME를 정지한다 —
                // 실행 중인 번들을 삭제하면 강제 종료/불안정 위험이 있다. system이
                // canonical이므로 정지 후 잔재를 제거하고, 아래 system 번들
                // 재등록/활성화에서 IMK가 새로 기동한다. (leftover가 있을 때만
                // 정지하므로 평상시 실행 경로엔 영향 없음.)
                try removeUserDomainLeftover()
            }
            try registerWithLaunchServices(at: systemInstallURL)
            return systemInstallURL
        }

        let source = try trustedBundledIMEURL()

        let inputMethodsDir = installURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: inputMethodsDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: installURL.path) {
            // (H-02) 이미 깔린 user-domain 번들도 재등록 직전에 다시 신뢰 검증한다.
            // 손상/타 Team 번들이면 TIS에 넣지 말고, 우리가 들고 온 trusted
            // embedded copy로 교체한 뒤에만 계속 진행한다.
            if !isTrustedIMEBundle(at: installURL) {
                try atomicallyReplaceIMEBundle(at: installURL, with: source)
                unregisterFromLaunchServices(at: installURL)
                try registerWithLaunchServices(at: installURL)
                return installURL
            }
            // (H-03) 버전 가드 — 설치된 IME가 같거나 최신이면 복사하지 않고
            // 재등록/활성화만 한다. 이게 (a)구버전 앱의 다운그레이드 방지 +
            // (b)매 실행 비원자 교체 제거 + (c)실행 중인 IME를 안 건드림을 모두
            // 해결한다. 빌드 번호(CFBundleVersion)는 정수로 비교한다("10" < "9"
            // 같은 문자열 비교 오류 방지).
            let installedBuild = buildNumber(at: installURL)
            let bundledBuild = buildNumber(at: source)
            if let installedBuild, let bundledBuild, installedBuild >= bundledBuild {
                try registerWithLaunchServices(at: installURL)
                return installURL
            }
            // 진짜 업그레이드(번들 > 설치본) 또는 버전 정보 손상 → 교체한다.
            // 실행 중인 IME 번들을 그대로 바꾸면 OS가 강제 종료할 수 있으므로,
            // 프로세스를 확실히 종료한 뒤(종료 확인) staging에 복사해 원자 교체한다.
            try atomicallyReplaceIMEBundle(at: installURL, with: source)
        } else {
            // 첫 설치 — 교체할 기존본이 없으니 바로 복사.
            try FileManager.default.copyItem(at: source, to: installURL)
        }
        try registerWithLaunchServices(at: installURL)
        return installURL
    }

    @discardableResult
    static func install() async throws -> ActivationResult {
        try await installBundle()
    }

    /// 앱 시작 시에는 "복사"를 절대 하지 않는다. macOS 26 picker 가시성 회귀를
    /// 막기 위해 GUI 앱 안에서 TIS register/enable은 계속 수행하되, 디스크에
    /// 새 번들을 만드는 행위는 명시적 설치 버튼 경로로만 제한한다. (H-01)
    @discardableResult
    static func activateInstalled() async throws -> ActivationResult? {
        let url = try await Task.detached(priority: .utility) {
            try prepareInstalledBundle()
        }.value
        guard let url else { return nil }
        return try await activateBundle(at: url)
    }

    private static func prepareInstalledBundle() throws -> URL? {
        if FileManager.default.fileExists(atPath: systemInstallURL.path) {
            guard isTrustedIMEBundle(at: systemInstallURL) else {
                throw IMEInstallError.installedBundleUntrusted(systemInstallURL.path)
            }
            if FileManager.default.fileExists(atPath: installURL.path) {
                try removeUserDomainLeftover()
            }
            try registerWithLaunchServices(at: systemInstallURL)
            return systemInstallURL
        }

        guard FileManager.default.fileExists(atPath: installURL.path) else {
            return nil
        }

        if !isTrustedIMEBundle(at: installURL) {
            let source = try trustedBundledIMEURL()
            try atomicallyReplaceIMEBundle(at: installURL, with: source)
            unregisterFromLaunchServices(at: installURL)
        }
        try registerWithLaunchServices(at: installURL)
        return installURL
    }

    // 2026-11-08 (#201): 입력기만 지우는 `uninstall()`을 없앴다(설정의 '입력기 제거' 버튼 삭제). 지우기는 전체 제거(`Uninstaller.run()`)만 한다.

    /// `do shell script ... with administrator privileges` — shows the
    /// standard macOS admin password dialog. Throws if the user cancels.
    /// (internal: Uninstaller's 전체 제거 reuses this for the system bundle.)
    static func removeWithAdminPrivileges(target: RemovalTarget) throws {
        guard let team = BundleTrust.teamIdentifier(at: Bundle.main.bundleURL) else {
            throw IMEInstallError.uninstallFailed("제품 Team을 확인하지 못해 관리자 삭제를 중단했어요")
        }
        let command = RemovalAdminScript(target: target, team: team)
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: command.appleScriptSource) else {
            throw IMEInstallError.uninstallFailed("관리자 권한 요청 스크립트 생성 실패")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -128 { throw RemovalCancelled() }
            throw IMEInstallError.uninstallFailed("관리자 삭제 실패 또는 대상 변경: \(errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류")")
        }
    }

    @MainActor static func openInputSourcesSettings() {
        Task {
            let trustedBundleExists = await Task.detached(priority: .utility) {
                installedBundleURL().map { isTrustedIMEBundle(at: $0) } ?? false
            }.value
            do { try await InputSourceSettings.open(refreshInputMethodList: trustedBundleExists) }
            catch {
                let alert = NSAlert()
                alert.messageText = "키보드 설정을 확인해 주세요"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "확인")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private static func trustedBundledIMEURL() throws -> URL {
        guard let source = bundledIMEURL else {
            throw IMEInstallError.bundleNotFound
        }

        // (H-01) 외부 코드를 사용자 입력기로 채택하지 않도록, 복사 전에 후보
        // 번들이 메인 앱과 같은 Team으로 서명됐는지 검증한다.
        guard isTrustedIMEBundle(at: source) else {
            throw IMEInstallError.untrustedBundle
        }
        return source
    }

    @discardableResult
    @MainActor
    private static func activateBundle(at url: URL) async throws -> ActivationResult {
        try await registerWithTIS(at: url)
        let warning = await InputSourceSettings.refreshAfterRegistration()
        return ActivationResult(url: url, settingsRefreshWarning: warning)
    }

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

    private static func registerWithLaunchServices(at url: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsregisterPath)
        task.arguments = ["-f", "-R", "-trusted", url.path]
        try task.run()
        task.waitUntilExit()
        // (위생-1) 실패를 조용히 삼키지 않고 로그로 남긴다. lsregister 실패는
        // TIS 등록(핵심)과 별개라 치명적이진 않지만 진단 가능해야 한다.
        if task.terminationStatus != 0 {
            haneulLog("HaneulKeyboard: lsregister 등록 실패 (status=\(task.terminationStatus)) — \(url.path)")
        }
    }

    /// Removes a stale copy from the LaunchServices database so it stops
    /// appearing as an extra row in the input-source list.
    private static func unregisterFromLaunchServices(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsregisterPath)
        task.arguments = ["-u", url.path]
        try? task.run()
        task.waitUntilExit()
    }

    /// McBopomofo's InputSourceHelper pattern (MIT, learned 2026-05-17):
    /// register the bundle, then enumerate to find every input mode under our
    /// bundle ID and call TISEnableInputSource on each. macOS 12+ silently
    /// rejects the IME in the picker if TISEnableInputSource is not called
    /// from inside a signed+notarized GUI NSApplication context — which is
    /// exactly what this main app provides when launched by the user.
    ///
    /// IDEMPOTENT BY CONTRACT (2026-06-06): repeated TISRegisterInputSource /
    /// TISEnableInputSource calls pile DUPLICATE instances into Tahoe's
    /// input-source cache — the user's enabled list ballooned to 597 rows.
    /// So: register only if TIS doesn't already know our bundle, enable only
    /// modes that are currently disabled, and nudge only when something
    /// actually changed.
    @MainActor
    private static func registerWithTIS(at url: URL) async throws {
        let bundleID = imeBundleID
        if !tisKnowsBundle(bundleID) {
            let status = TISRegisterInputSource(url as CFURL)
            guard status == noErr else {
                throw IMEInstallError.tisRegistrationFailed(status)
            }
        }
        let newlyEnabled = enableAllModes(forBundleID: bundleID)
        if newlyEnabled > 0 {
            nudgeMenuBarPicker(forBundleID: bundleID)
        }
        let initialState = tisActivationState()
        guard initialState.known else { throw IMEInstallError.tisRegistrationMissing }
        if initialState.enabled { return }

        // TISEnableInputSource 성공 뒤 enabled 플래그가 TIS 캐시에 늦게 반영될
        // 수 있다. 짧게 재폴링해 정상 설치를 활성화 실패로 오인하지 않는다.
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(50))
            if tisActivationState().enabled { return }
        }
        throw IMEInstallError.tisEnableFailed
    }

    private struct TISActivationState {
        let known: Bool
        let enabled: Bool
        var isReady: Bool { known && enabled }
    }

    @MainActor
    private static func tisActivationState() -> TISActivationState {
        let bundleID = imeBundleID
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return TISActivationState(known: false, enabled: false)
        }
        var known = false
        var enabled = false
        for source in all {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { continue }
            let sourceBundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            guard sourceBundleID == bundleID else { continue }
            known = true
            guard let modePtr = TISGetInputSourceProperty(source, kTISPropertyInputModeID),
                  Unmanaged<CFString>.fromOpaque(modePtr).takeUnretainedValue() as String == InputSwitcher.koreanModeID,
                  let capablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(capablePtr).takeUnretainedValue()),
                  let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { continue }
            let value = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            enabled = enabled || CFBooleanGetValue(value)
        }
        return TISActivationState(known: known, enabled: enabled)
    }

    private static func installedBundleURL() -> URL? {
        if FileManager.default.fileExists(atPath: systemInstallURL.path) { return systemInstallURL }
        if FileManager.default.fileExists(atPath: installURL.path) { return installURL }
        return nil
    }

    /// True if TIS already has any input source for our bundle — calling
    /// TISRegisterInputSource again in that state duplicates cache entries.
    private static func tisKnowsBundle(_ targetBundleID: String) -> Bool {
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        for source in all {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { continue }
            let bundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            if bundleID == targetBundleID { return true }
        }
        return false
    }

    /// Enables only modes that are currently DISABLED; already-enabled modes
    /// are left untouched. Returns how many were newly enabled.
    @discardableResult
    private static func enableAllModes(forBundleID targetBundleID: String) -> Int {
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return 0
        }
        var enabledCount = 0
        for source in all {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID),
                  let _ = TISGetInputSourceProperty(source, kTISPropertyInputModeID) else {
                continue
            }
            let bundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            guard bundleID == targetBundleID else { continue }

            // Skip modes that are already enabled — re-enabling is what
            // multiplies rows in the System Settings list.
            if let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                let isEnabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
                if CFBooleanGetValue(isEnabled) { continue }
            }

            if TISEnableInputSource(source) == noErr {
                enabledCount += 1
            }
        }
        return enabledCount
    }

    /// 우리 bundle ID의 모든 입력 소스(모드 포함)에 `TISDisableInputSource`. 하나라도 성공하면 true.
    /// 2026-09-20 (#46, 리뷰 F-2): 전체 제거(`Uninstaller.run`)와 설정의 "IME 제거"(`uninstall`)가
    /// 이 하나를 쓴다 — 종전엔 Uninstaller만 private 사본을 갖고 있어 "IME 제거"가 비활성화를
    /// 건너뛰었다. `enableAllModes`와 짝. IME 프로세스 쪽 `OrphanWatcher.disableOwnInputSources`는
    /// 별도 타겟이라 중복이 의도적이다(#32). 호출 계약: TIS 호출이므로 메인 스레드에서 부른다.
    /// GUI 앱 컨텍스트에서 실제로 꺼지는지는 실기기(체크리스트)로 확정한다.
    @discardableResult
    static func disableAllModes(forBundleID targetBundleID: String) -> Bool {
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        var anyDisabled = false
        for source in all {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { continue }
            let bundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            guard bundleID == targetBundleID else { continue }
            if TISDisableInputSource(source) == noErr { anyDisabled = true }
        }
        return anyDisabled
    }

    /// Fix for "first install needs a second app launch before menu-bar picker
    /// shows the IME". `TISEnableInputSource` updates the system input-source
    /// list (visible in System Settings) but TextInputMenuAgent — the daemon
    /// that draws the top-of-screen Korean/English (한/A) picker — doesn't always reflect the
    /// new source on the first install. A flip-flop select (briefly select
    /// our mode, then immediately revert) is the strongest documented signal
    /// that nudges TextInputMenuAgent into refreshing its menu.
    ///
    /// `killall TextInputMenuAgent` is blocked on macOS 26 Tahoe; flip-flop
    /// is the only userspace path that works without a reboot.
    private static func nudgeMenuBarPicker(forBundleID targetBundleID: String) {
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        var ourMode: TISInputSource?
        for source in all {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID),
                  TISGetInputSourceProperty(source, kTISPropertyInputModeID) != nil else {
                continue
            }
            let bundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            if bundleID == targetBundleID {
                ourMode = source
                break
            }
        }
        guard let ourMode else {
            haneulLog("HaneulKeyboard: nudge — our IME mode not found in TIS list (skip)")
            return
        }

        // 2026-09-20 (#42, 리뷰 F-7): 암시적 언랩 제거 — TIS가 현재 자판을 못 돌려주는
        // 드문 상태에서 설치 도중 크래시하지 않게 InputSwitcher.currentSourceID와 같은
        // 옵셔널 처리로 통일한다. 되돌릴 원본이 없으면 nudge 자체를 건너뛴다(선택만 하고
        // 못 되돌리면 사용자의 활성 입력 소스가 바뀐 채 남는다).
        guard let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            haneulLog("HaneulKeyboard: nudge — current input source unavailable (skip)")
            return
        }
        let selectStatus = TISSelectInputSource(ourMode)
        haneulLog("HaneulKeyboard: nudge — selected our IME (status=\(selectStatus))")

        // Revert on next run loop tick so TextInputMenuAgent gets two events
        // back-to-back (select-ours, select-original). The user perceives no
        // active-input-source change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let revertStatus = TISSelectInputSource(original)
            haneulLog("HaneulKeyboard: nudge — reverted to original source (status=\(revertStatus))")
        }
    }
}

enum IMEInstallError: LocalizedError {
    case bundleNotFound
    case untrustedBundle
    case installedBundleUntrusted(String)
    case tisRegistrationFailed(OSStatus)
    case tisRegistrationMissing
    case tisEnableFailed
    case nothingToRemove
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "HaneulKeyboardIM.app을 찾을 수 없어요. 메인 앱과 같은 폴더(또는 Contents/Helpers)에 입력기 번들이 있어야 해요. (HaneulKeyboardIM.app not found — the IME bundle must sit next to the main app or under Contents/Helpers.)"
        case .untrustedBundle:
            return "입력기 번들의 서명을 믿을 수 없어요. 메인 앱과 같은 개발자(Team)로 서명된 HaneulKeyboardIM.app만 설치할 수 있어요. (Refusing to install an IME bundle not signed by the same Team as the main app.)"
        case .installedBundleUntrusted(let path):
            return "설치된 입력기 번들의 서명을 확인하지 못했어요: \(path). 믿을 수 있는 HaneulKeyboardIM.app으로 다시 설치한 뒤 다시 시도해 주세요. (Refusing to register an installed IME bundle whose signature or Team no longer matches the main app.)"
        case .tisRegistrationFailed(let status):
            return "입력기는 설치됐지만 입력 소스로 등록하지 못했어요. (TISRegisterInputSource: \(status))"
        case .tisRegistrationMissing:
            return "입력기는 설치됐지만 macOS 입력 소스 목록에 보이지 않아요. 다시 설치하거나 로그아웃한 뒤 다시 시도해 주세요."
        case .tisEnableFailed:
            return "입력기는 등록됐지만 켜지지 않았어요. 시스템 설정의 키보드 입력 소스에서 HaneulKeyboard를 켜 주세요."
        case .nothingToRemove:
            return "지울 입력기가 없어요. (이미 지워졌어요.)"
        case .uninstallFailed(let reason):
            return "IME 제거 실패: \(reason)"
        }
    }
}

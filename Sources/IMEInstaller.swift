import AppKit
import Carbon
import Foundation
import Security

enum IMEInstaller {
    static let bundleName = "HaneulKeyboardIM.app"

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
    }

    /// A bundle on disk is only a candidate. Call `isInstalled()` when
    /// reporting user-visible installation state; it also verifies TIS state.
    static func isInstalled() async -> Bool {
        let trustedBundleExists = await Task.detached(priority: .utility) {
            installedBundleURL().map { isTrustedIMEBundle(at: $0) } ?? false
        }.value
        guard trustedBundleExists else { return false }
        return await MainActor.run { tisActivationState().isReady }
    }

    /// (H-01) 설치 후보 IME 번들을 신뢰할 수 있는가.
    /// Release: ① 코드 서명이 유효하고 ② 메인 앱과 **같은 Team Identifier**로
    /// 서명됐을 때만 true. Team ID를 하드코딩하지 않고 메인 앱 자신의 Team을
    /// 기준으로 삼으므로, 오픈소스를 포크해 자기 인증서로 빌드한 경우에도
    /// (메인 앱+IME가 같은 Team이면) 정상 동작하고, 우리와 다른 Team의 외부
    /// 번들만 거부된다. Debug: 미서명 개발 빌드를 위해 검사를 건너뛴다.
    static func isTrustedIMEBundle(at url: URL) -> Bool {
        #if DEBUG
        return true
        #else
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else {
            return false
        }
        guard let myTeam = teamIdentifier(at: Bundle.main.bundleURL),
              let candidateTeam = teamIdentifier(at: url),
              myTeam == candidateTeam else {
            return false
        }
        return true
        #endif
    }

    /// 번들의 코드 서명에서 Team Identifier를 읽는다. 미서명/추출 실패 시 nil.
    private static func teamIdentifier(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return nil
        }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else {
            return nil
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 번들의 빌드 번호(CFBundleVersion, 단조증가 정수). 버전 비교용. 문자열
    /// 비교는 "10" < "9" 오류가 나므로 정수로 파싱한다. nil = 추출 실패. (H-03)
    private static func buildNumber(at url: URL) -> Int? {
        guard let bundle = Bundle(url: url),
              let s = bundle.infoDictionary?["CFBundleVersion"] as? String,
              let n = Int(s) else { return nil }
        return n
    }

    /// (H-03) 실행 중인 IME 프로세스를 확실히 종료한다 — 업그레이드 교체 전 호출.
    /// killall은 반환돼도 실제 종료를 보장하지 않고 이름 매칭이 부정확하므로,
    /// bundle ID로 정확히 찾아 terminate한 뒤 종료를 확인한다(최대 ~1.5초 폴링,
    /// 안 죽으면 forceTerminate). IMK가 다음 입력 때 새 번들로 재기동한다.
    /// 호출 계약: 종료 폴링과 `onMainThread`의 동기 hop 때문에 메인 스레드에서
    /// 동기 호출하면 안 된다. 호출자는 반드시 백그라운드 작업에서 실행한다.
    static func stopIMEProcess() {
        assert(!Thread.isMainThread, "stopIMEProcess() must run off the main thread")
        let imeBundleID = "com.hyunjincho.inputmethod.haneul"
        let running: [NSRunningApplication] = onMainThread {
            NSRunningApplication.runningApplications(withBundleIdentifier: imeBundleID)
        }
        guard !running.isEmpty else { return }
        onMainThread { for app in running { app.terminate() } }
        let processIDs = running.map(\.processIdentifier)
        let deadline = Date(timeIntervalSinceNow: 1.5)
        while Date() < deadline {
            if processIDs.allSatisfy({ kill($0, 0) != 0 }) {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        onMainThread {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: imeBundleID) {
                app.forceTerminate()
            }
        }
    }

    private static func onMainThread<T>(_ body: @escaping () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }

    /// 실행 중인 IME를 멈춘 뒤 trusted source를 staging에 복사하고 원자 교체한다.
    /// staging 준비나 교체가 실패하면 기존 설치본은 그대로 남는다.
    private static func atomicallyReplaceIMEBundle(at destination: URL, with source: URL) throws {
        stopIMEProcess()
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
        return try await activateBundle(at: url)
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
                stopIMEProcess()
                try? FileManager.default.removeItem(at: installURL)
                unregisterFromLaunchServices(at: installURL)
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
                stopIMEProcess()
                try? FileManager.default.removeItem(at: installURL)
                unregisterFromLaunchServices(at: installURL)
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

    @MainActor
    static func uninstall() async throws {
        _ = InputSwitcher.selectEnglish()

        let hasSystemInstall = FileManager.default.fileExists(atPath: systemInstallURL.path)
        let hasUserInstall = FileManager.default.fileExists(atPath: installURL.path)
        guard hasSystemInstall || hasUserInstall else {
            throw IMEInstallError.nothingToRemove
        }

        await Task.detached(priority: .userInitiated) {
            stopIMEProcess()
        }.value

        // System-domain install is root-owned — ask for admin rights via the
        // standard macOS password prompt. (The old code only handled the
        // user-domain path and silently did NOTHING for system installs.)
        // NSAppleScript의 관리자 인증 UI는 메인 액터에서 띄운다.
        if hasSystemInstall {
            try removeWithAdminPrivileges(path: systemInstallURL.path)
        }

        try await Task.detached(priority: .userInitiated) {
            if hasSystemInstall {
                unregisterFromLaunchServices(at: systemInstallURL)
            }
            if hasUserInstall {
                try FileManager.default.removeItem(at: installURL)
                unregisterFromLaunchServices(at: installURL)
            }
        }.value
    }

    /// `do shell script ... with administrator privileges` — shows the
    /// standard macOS admin password dialog. Throws if the user cancels.
    /// (internal: Uninstaller's 전체 제거 reuses this for the system bundle.)
    static func removeWithAdminPrivileges(path: String) throws {
        // (보안) path를 admin 셸 명령에 안전하게 넣는다. 예전 코드는 셸 작은따옴표만
        // 이스케이프하고, 이를 감싸는 AppleScript 문자열 리터럴의 큰따옴표(")·역슬래시(\)는
        // 처리하지 않아, 따옴표가 든 경로명(/Applications에서 bundle ID로 찾은 동적 경로 등)으로
        // admin 명령이 주입될 수 있었다. 이제 두 계층을 분리한다:
        //   1) AppleScript 문자열 리터럴용 이스케이프(역슬래시 먼저, 그다음 큰따옴표)
        //   2) 셸 인용은 AppleScript `quoted form of`에 위임
        let asLiteral = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"/bin/rm -rf \" & quoted form of \"\(asLiteral)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw IMEInstallError.uninstallFailed("관리자 권한 요청 스크립트 생성 실패")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"
            throw IMEInstallError.uninstallFailed(message)
        }
    }

    static func openInputSourcesSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Text") {
            NSWorkspace.shared.open(url)
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
        return ActivationResult(url: url)
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
        let bundleID = "com.hyunjincho.inputmethod.haneul"
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
        let bundleID = "com.hyunjincho.inputmethod.haneul"
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
            guard TISGetInputSourceProperty(source, kTISPropertyInputModeID) != nil,
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

        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
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
            return "HaneulKeyboardIM.app을 찾을 수 없습니다. 메인 앱과 같은 폴더(또는 Contents/Helpers)에 IME 번들이 있어야 합니다. (HaneulKeyboardIM.app not found — the IME bundle must sit next to the main app or under Contents/Helpers.)"
        case .untrustedBundle:
            return "IME 번들의 서명을 신뢰할 수 없습니다. 메인 앱과 동일한 개발자(Team)로 서명된 HaneulKeyboardIM.app만 설치할 수 있습니다. (Refusing to install an IME bundle not signed by the same Team as the main app.)"
        case .installedBundleUntrusted(let path):
            return "설치된 IME 번들의 서명/Team 검증에 실패했습니다: \(path). 신뢰할 수 있는 HaneulKeyboardIM.app으로 다시 설치한 뒤 재시도하세요. (Refusing to register an installed IME bundle whose signature or Team no longer matches the main app.)"
        case .tisRegistrationFailed(let status):
            return "IME 번들은 설치됐지만 입력 소스 등록에 실패했습니다. (TISRegisterInputSource: \(status))"
        case .tisRegistrationMissing:
            return "IME 번들은 설치됐지만 macOS 입력 소스 목록에서 확인되지 않습니다. 다시 설치하거나 로그아웃 후 재시도하세요."
        case .tisEnableFailed:
            return "IME는 등록됐지만 활성화되지 않았습니다. 시스템 설정의 키보드 입력 소스에서 HaneulKeyboard를 활성화하세요."
        case .nothingToRemove:
            return "제거할 IME가 없습니다. (이미 제거되었습니다.)"
        case .uninstallFailed(let reason):
            return "IME 제거 실패: \(reason)"
        }
    }
}

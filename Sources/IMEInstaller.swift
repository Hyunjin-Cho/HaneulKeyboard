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

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: systemInstallURL.path)
            || FileManager.default.fileExists(atPath: installURL.path)
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

    @discardableResult
    static func install() throws -> URL {
        // A system-domain install (from the build script) is canonical.
        // NEVER lay a second copy in the user domain on top of it — that's
        // exactly what produced the duplicated input-source rows. Instead,
        // clean any user-domain leftover and just (re)activate the canonical
        // bundle with TIS.
        if FileManager.default.fileExists(atPath: systemInstallURL.path) {
            if FileManager.default.fileExists(atPath: installURL.path) {
                try? FileManager.default.removeItem(at: installURL)
                unregisterFromLaunchServices(at: installURL)
            }
            try registerWithLaunchServices(at: systemInstallURL)
            registerWithTIS(at: systemInstallURL)
            return systemInstallURL
        }

        guard let source = bundledIMEURL else {
            throw IMEInstallError.bundleNotFound
        }

        // (H-01) 외부 코드를 사용자 입력기로 채택하지 않도록, 복사 전에 후보
        // 번들이 메인 앱과 같은 Team으로 서명됐는지 검증한다.
        guard isTrustedIMEBundle(at: source) else {
            throw IMEInstallError.untrustedBundle
        }

        let inputMethodsDir = installURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: inputMethodsDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: installURL.path) {
            try FileManager.default.removeItem(at: installURL)
        }

        try FileManager.default.copyItem(at: source, to: installURL)
        try registerWithLaunchServices(at: installURL)
        registerWithTIS(at: installURL)
        return installURL
    }

    static func uninstall() throws {
        var removedAny = false

        // System-domain install is root-owned — ask for admin rights via the
        // standard macOS password prompt. (The old code only handled the
        // user-domain path and silently did NOTHING for system installs.)
        if FileManager.default.fileExists(atPath: systemInstallURL.path) {
            try removeWithAdminPrivileges(path: systemInstallURL.path)
            unregisterFromLaunchServices(at: systemInstallURL)
            removedAny = true
        }

        if FileManager.default.fileExists(atPath: installURL.path) {
            try FileManager.default.removeItem(at: installURL)
            unregisterFromLaunchServices(at: installURL)
            removedAny = true
        }

        if !removedAny {
            throw IMEInstallError.nothingToRemove
        }
    }

    /// `do shell script ... with administrator privileges` — shows the
    /// standard macOS admin password dialog. Throws if the user cancels.
    /// (internal: Uninstaller's 전체 제거 reuses this for the system bundle.)
    static func removeWithAdminPrivileges(path: String) throws {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let source = "do shell script \"rm -rf '\(escaped)'\" with administrator privileges"
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
    private static func registerWithTIS(at url: URL) {
        let bundleID = "com.hyunjincho.inputmethod.haneul"
        if !tisKnowsBundle(bundleID) {
            _ = TISRegisterInputSource(url as CFURL)
        }
        let newlyEnabled = enableAllModes(forBundleID: bundleID)
        if newlyEnabled > 0 {
            nudgeMenuBarPicker(forBundleID: bundleID)
        }
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
    case nothingToRemove
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "HaneulKeyboardIM.app을 찾을 수 없습니다. 메인 앱과 같은 폴더(또는 Contents/Helpers)에 IME 번들이 있어야 합니다. (HaneulKeyboardIM.app not found — the IME bundle must sit next to the main app or under Contents/Helpers.)"
        case .untrustedBundle:
            return "IME 번들의 서명을 신뢰할 수 없습니다. 메인 앱과 동일한 개발자(Team)로 서명된 HaneulKeyboardIM.app만 설치할 수 있습니다. (Refusing to install an IME bundle not signed by the same Team as the main app.)"
        case .nothingToRemove:
            return "제거할 IME가 없습니다. (이미 제거되었습니다.)"
        case .uninstallFailed(let reason):
            return "IME 제거 실패: \(reason)"
        }
    }
}

import AppKit
import Carbon
import Foundation

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
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        let candidates = [
            parent.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(bundleName)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: systemInstallURL.path)
            || FileManager.default.fileExists(atPath: installURL.path)
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
        guard FileManager.default.fileExists(atPath: installURL.path) else { return }
        try FileManager.default.removeItem(at: installURL)
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

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "HaneulKeyboardIM.app을 찾을 수 없습니다. 메인 앱과 같은 폴더(또는 Contents/Helpers)에 IME 번들이 있어야 합니다. (HaneulKeyboardIM.app not found — the IME bundle must sit next to the main app or under Contents/Helpers.)"
        }
    }
}

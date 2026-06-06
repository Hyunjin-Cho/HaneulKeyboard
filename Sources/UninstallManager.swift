import AppKit
import Carbon
import Foundation

/// Best-effort full removal of HaneulKeyboard's footprint.
///
/// macOS sandboxes a lot of input-source state away from us, so a "clean
/// install" really needs four things to happen:
///   1. The user's running IME process exits.
///   2. The bundle on disk is removed.
///   3. LaunchServices forgets the bundle so picker entries don't reappear.
///   4. The user removes the input source from System Settings (we can't
///      do this for them — macOS only lets the user manipulate enabled
///      input sources via the GUI picker).
///
/// `Uninstaller.run()` does 1–3 automatically and returns a status object
/// describing what still needs the user's manual help.
enum Uninstaller {
    struct Outcome {
        let killedProcess: Bool
        let removedBundle: Bool
        let unregisteredLS: Bool
        let clearedUserDefaults: Bool
        /// True if the user still has the input source enabled in System
        /// Settings — we can detect this even after removing the bundle.
        let stillEnabledInPicker: Bool
    }

    private static let bundleID = "com.hyunjincho.inputmethod.haneul"
    private static let imeBundleName = "HaneulKeyboardIM.app"
    private static let imeProcessName = "HaneulKeyboardIM"
    private static let mainAppDomain = "com.hyunjincho.haneulkeyboard"

    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/\(imeBundleName)")
    }

    /// System-domain install (root-owned) — where the build script installs.
    static var systemInstallURL: URL {
        URL(fileURLWithPath: "/Library/Input Methods/\(imeBundleName)")
    }

    @discardableResult
    static func run() -> Outcome {
        let killed = killIMEProcess()
        let removed = removeBundle()
        let unregistered = unregisterFromLaunchServices()
        let cleared = clearUserDefaults()
        let stillEnabled = isInputSourceStillEnabled()

        return Outcome(
            killedProcess: killed,
            removedBundle: removed,
            unregisteredLS: unregistered,
            clearedUserDefaults: cleared,
            stillEnabledInPicker: stillEnabled
        )
    }

    // MARK: - Steps

    private static func killIMEProcess() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [imeProcessName]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func removeBundle() -> Bool {
        var ok = true
        // System-domain bundle (root-owned): admin password prompt.
        // The old code only checked the user domain and reported success
        // while the real install stayed behind (2026-06-06 bug).
        if FileManager.default.fileExists(atPath: systemInstallURL.path) {
            do {
                try IMEInstaller.removeWithAdminPrivileges(path: systemInstallURL.path)
            } catch {
                ok = false
            }
        }
        if FileManager.default.fileExists(atPath: installURL.path) {
            do {
                try FileManager.default.removeItem(at: installURL)
            } catch {
                ok = false
            }
        }
        return ok
    }

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

    private static func unregisterFromLaunchServices() -> Bool {
        var ok = true
        for url in [systemInstallURL, installURL] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lsregisterPath)
            task.arguments = ["-u", url.path]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                ok = false
            }
        }
        return ok
    }

    private static func clearUserDefaults() -> Bool {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("haneul.") }
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
        // Also clean the explicit main-app suite if one exists separately.
        if let suite = UserDefaults(suiteName: mainAppDomain) {
            for key in suite.dictionaryRepresentation().keys {
                suite.removeObject(forKey: key)
            }
        }
        // The IME helper has its own defaults domain (separate process,
        // separate bundle id) — clear its haneul.* keys too.
        if let imeSuite = UserDefaults(suiteName: bundleID) {
            for key in imeSuite.dictionaryRepresentation().keys where key.hasPrefix("haneul.") {
                imeSuite.removeObject(forKey: key)
            }
        }
        // Learned prediction data (word frequencies) lives in Application
        // Support — PRIVACY.md promises 전체 제거 deletes it.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HaneulKeyboard")
        try? FileManager.default.removeItem(at: appSupport)
        return true
    }

    /// Walks every TIS input source and checks if any matches our bundle ID
    /// and is currently in the enabled list. macOS won't let us flip the
    /// enabled flag off programmatically (it requires picker interaction),
    /// so this is purely a status check we surface to the user.
    private static func isInputSourceStillEnabled() -> Bool {
        guard let all = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        for src in all {
            guard let bidPtr = TISGetInputSourceProperty(src, kTISPropertyBundleID) else { continue }
            let bid = Unmanaged<CFString>.fromOpaque(bidPtr).takeUnretainedValue() as String
            guard bid == bundleID else { continue }
            if let enabledPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsEnabled) {
                let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
                if CFBooleanGetValue(enabled) {
                    return true
                }
            }
        }
        return false
    }
}

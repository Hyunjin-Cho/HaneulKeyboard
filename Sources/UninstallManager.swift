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

    /// 메인 앱 bundle identifier — 파일명이 바뀌어도(Renamed.app) 우리 제품을
    /// 식별하는 기준. (M-07)
    private static let mainAppBundleID = "com.hyunjincho.haneulkeyboard"

    /// (M-07) 제거 대상 메인 앱 번들들. 하드코딩 경로(/Applications/HaneulKeyboard.app)
    /// 대신 우리 bundle ID로 식별 — 사용자가 파일명을 바꿔 옮겼어도(Renamed.app)
    /// 찾아낸다. 현재 실행 번들 + /Applications에서 우리 ID를 가진 .app을 모은다.
    /// (자동이동=사용자 소유, build script=root 소유 → 후자는 admin 프롬프트 필요.)
    static func mainAppURLs() -> [URL] {
        var urls = Set<URL>()
        if Bundle.main.bundleIdentifier == mainAppBundleID {
            urls.insert(Bundle.main.bundleURL.standardizedFileURL)
        }
        let appsDir = URL(fileURLWithPath: "/Applications")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: appsDir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension == "app" {
                if Bundle(url: url)?.bundleIdentifier == mainAppBundleID {
                    urls.insert(url.standardizedFileURL)
                }
            }
        }
        return Array(urls)
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
        // (#11/M-07) 메인 앱 본체 (/Applications) — 기존 코드는 IME 번들만 지우고
        // 메인 앱을 안 지워 Launchpad에 남았다(중복/잔재의 핵심 원인). 이제
        // bundle ID로 식별한 모든 설치본(파일명 바뀐 것 포함)을 지운다. root
        // 소유면 일반 삭제가 실패하므로 admin 프롬프트로 재시도.
        for app in mainAppURLs() {
            guard FileManager.default.fileExists(atPath: app.path) else { continue }
            do {
                try FileManager.default.removeItem(at: app)
            } catch {
                do {
                    try IMEInstaller.removeWithAdminPrivileges(path: app.path)
                } catch {
                    ok = false
                }
            }
        }
        return ok
    }

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

    private static func unregisterFromLaunchServices() -> Bool {
        var ok = true
        for url in mainAppURLs() + [systemInstallURL, installURL] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lsregisterPath)
            task.arguments = ["-u", url.path]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                // (위생-1) lsregister -u 종료코드를 반영 — 미등록 경로엔 0을
                // 반환하므로(idempotent) nonzero는 실제 실패다.
                if task.terminationStatus != 0 { ok = false }
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
        // (M-06) 삭제 실패를 성공으로 보고하지 않는다 — 예전엔 try?로 버리고
        // 무조건 true를 반환해 잔재가 남아도 "모두 삭제"로 표시됐다.
        var ok = true
        if FileManager.default.fileExists(atPath: appSupport.path) {
            do {
                try FileManager.default.removeItem(at: appSupport)
            } catch {
                ok = false
            }
        }
        return ok
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

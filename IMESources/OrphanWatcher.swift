import AppKit
import Carbon
import Foundation
import os.log

/// 메인 앱이 지워지면 IME도 스스로 정리한다 — "2개가 다 연결되어 있어야 한다". (#32, 2026-09-19)
///
/// 판단은 `OrphanDecision`(순수 함수·테스트 대상)이 하고, 여기는 **관찰과 실행**만 한다.
///
/// 호출 계약: `checkIfDue()`는 `activateServer`에서 부른다. 한/영 전환 경로를 절대 막지
/// 않도록 즉시 반환하고 실제 조회는 utility 큐에서 한다(전환 순간의 동기 작업이 CapsLock
/// 지연을 만들었던 2026-06-19 예측입력 사고의 재발 금지). 조회는 60초에 한 번으로 제한.
final class OrphanWatcher {
    static let shared = OrphanWatcher()

    static let mainAppBundleID = "com.hyunjincho.haneulkeyboard"
    static let imeBundleID = "com.hyunjincho.inputmethod.haneul"
    /// 메인 앱이 실행될 때마다 IME 설정 도메인에 기록하는 자기 경로와 파일 번호(inode) (`AppCore`).
    static let recordedAppPathKey = "haneul.mainAppPath"
    static let recordedAppFileIDKey = "haneul.mainAppFileID"

    /// 조회 주기(스로틀). 활성화가 아무리 잦아도 이 간격보다 자주 LaunchServices를 묻지 않는다.
    private let checkInterval: TimeInterval = 60
    /// 휴지통에서 본 뒤 정리까지의 유예 — "제자리에 놓기"로 되돌릴 시간 (리뷰 B-1).
    private let trashedConfirmationInterval: TimeInterval = 120
    /// 어디에도 없을 때의 유예 — 앱 교체·볼륨 마운트·LaunchServices 갱신 지연 같은
    /// 일시적 부재를 정리로 오인하지 않게 길게 둔다 (리뷰 H-1).
    private let missingConfirmationInterval: TimeInterval = 1800

    private let queue = DispatchQueue(label: "com.hyunjincho.inputmethod.haneul.orphan", qos: .utility)
    private let log = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "orphan")
    // 아래 상태는 전부 `queue` 전용.
    private var lastCheck: Date?
    private var previousAbsentAt: Date?
    private var removalStarted = false
    private var loggedOutsideUserDomain = false

    /// 활성화 때마다 호출 — 스로틀에 걸리면 아무 일도 하지 않는다.
    func checkIfDue() {
        queue.async { [self] in
            let now = Date()
            if let last = lastCheck, now.timeIntervalSince(last) < checkInterval { return }
            lastCheck = now
            check(now: now)
        }
    }

    /// 프로세스 기동 직후 1회. 기동 비용(사전 preload와 겹침)에 얹히지 않게 잠깐 뒤에 돈다.
    func scheduleInitialCheck(after delay: TimeInterval = 5) {
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            let now = Date()
            lastCheck = now
            check(now: now)
        }
    }

    // MARK: - 관찰

    private var bundleURL: URL { Bundle.main.bundleURL.standardizedFileURL }
    private var userInputMethodsDir: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods").path
    }

    private func check(now: Date) {
        guard !removalStarted else { return }
        // 사용자 도메인 설치본이 아니면(시스템 도메인·개발 빌드) 감시하지 않는다 — 지우지도
        // 못하면서 입력 소스만 끄고 종료하는 상태를 만들지 않기 위해 (리뷰 M-4).
        guard OrphanDecision.mayDeleteBundle(bundlePath: bundleURL.path, userInputMethodsDir: userInputMethodsDir) else {
            if !loggedOutsideUserDomain {
                loggedOutsideUserDomain = true
                log.log("orphan: bundle outside user domain — watcher disabled")
            }
            return
        }
        let presence = OrphanDecision.classify(candidatePaths: candidatePaths()) {
            FileManager.default.fileExists(atPath: $0)
        }
        if presence == .present {
            previousAbsentAt = nil
            return
        }
        let confirmed = OrphanDecision.shouldSelfRemove(
            current: presence, previousAbsentAt: previousAbsentAt, now: now,
            trashedInterval: trashedConfirmationInterval, missingInterval: missingConfirmationInterval)
        if !confirmed {
            if previousAbsentAt == nil { previousAbsentAt = now }
            log.log("orphan: main app \(presence == .trashed ? "in the Trash" : "not found", privacy: .public) — waiting before self-removal")
            return
        }
        log.log("orphan: main app \(presence == .trashed ? "in the Trash" : "not found", privacy: .public) on repeated observations")
        #if DEBUG
        // 개발 빌드는 판단만 로그로 남기고 정리는 하지 않는다. 설치본은 항상 Release다
        // (Tahoe가 ad-hoc 서명을 거부).
        log.log("orphan: DEBUG build — self-removal skipped")
        #else
        removalStarted = true
        selfRemove()
        #endif
    }

    /// 앱이 있을 법한 경로 전부. 싼 것부터 보고, 살아 있는 복사본이 하나라도 있으면 스캔은 생략.
    private func candidatePaths() -> [String] {
        var paths: [String] = []
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let recordedFileID = defaults.object(forKey: Self.recordedAppFileIDKey) as? Int

        // 1) 메인 앱이 기록한 자기 경로 + 그 이름의 휴지통 사본. 휴지통 사본은 bundle ID와
        //    기록된 inode가 맞을 때만 후보로 인정한다(옛 버전 사본에 속지 않게 — 리뷰 H-1).
        if let recorded = defaults.string(forKey: Self.recordedAppPathKey), !recorded.isEmpty {
            paths.append(recorded)
            let name = URL(fileURLWithPath: recorded).lastPathComponent
            for trash in fm.urls(for: .trashDirectory, in: .userDomainMask) {
                let candidate = trash.appendingPathComponent(name)
                guard fm.fileExists(atPath: candidate.path) else { continue }
                let accepted = OrphanDecision.acceptsTrashedCopy(
                    bundleIDMatches: Self.bundleIdentifier(at: candidate) == Self.mainAppBundleID,
                    recordedFileID: recordedFileID,
                    candidateFileID: Self.fileID(at: candidate))
                if accepted { paths.append(candidate.path) }
            }
        }
        // 2) LaunchServices가 아는 모든 복사본 (파일명이 바뀌어도 bundle ID로 찾는다).
        paths += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Self.mainAppBundleID).map(\.path)

        let alive = paths.contains { fm.fileExists(atPath: $0) && !OrphanDecision.isInTrash($0) }
        if alive { return paths }

        // 3) 표준 위치 스캔 — 위에서 못 찾았을 때만. /Applications·~/Applications는 하위 폴더
        //    한 단계까지(Utilities 등에 넣어 두는 사용자가 있다 — AppMoveDecision.isAlreadyInPlace가
        //    하위 폴더도 제자리로 인정한다), 그 밖 흔한 폴더는 최상위만 본다.
        let home = fm.homeDirectoryForCurrentUser
        let twoLevel = ["/Applications", home.appendingPathComponent("Applications").path]
        let oneLevel = ["Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0).path }
        for dir in twoLevel { paths += Self.scanForMainApp(in: dir, depth: 2) }
        for dir in oneLevel { paths += Self.scanForMainApp(in: dir, depth: 1) }
        return paths
    }

    /// `dir` 아래에서 우리 bundle ID의 .app을 찾는다(깊이 제한). `.app` 안으로는 들어가지 않는다.
    private static func scanForMainApp(in dir: String, depth: Int) -> [String] {
        guard depth > 0, let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var found: [String] = []
        for entry in entries where !entry.hasPrefix(".") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                if bundleIdentifier(at: url) == mainAppBundleID { found.append(url.path) }
            } else if depth > 1 {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    found += scanForMainApp(in: url.path, depth: depth - 1)
                }
            }
        }
        return found
    }

    /// Info.plist를 직접 읽는다 — `Bundle(url:)`은 프로세스 수명 동안 캐시에 남아 스캔마다
    /// 쌓인다(리뷰 L-3).
    private static func bundleIdentifier(at appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleIdentifier"]) as? String
    }

    private static func fileID(at url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int
    }

    // MARK: - 실행

    /// 순서: ① ABC로 전환(우리가 사라져도 입력이 멈추지 않게 — **실패하면 여기서 중단**, 리뷰 H-4)
    /// ② 입력 소스 비활성화 시도 ③ 자기 번들 삭제 + LaunchServices 등록 해제 ④ 설정 정리 ⑤ 종료.
    /// ②가 실패해도 ③으로 다음 로그인 때 목록에서 사라진다(전체 제거와 같은 한계).
    private func selfRemove() {
        let bundleURL = self.bundleURL
        DispatchQueue.main.async { [self] in
            // TIS는 메인 스레드에서.
            let switched = Self.selectASCIICapableSource()
            guard switched else {
                // ABC를 입력 소스에서 빼 둔 사용자 등 — 우리가 선택된 채 사라지면 다음 키가 갈
                // 곳이 없다. 아무것도 지우지 않고 다음 기회(60초 뒤)에 다시 시도한다.
                log.log("orphan: could not switch to an ASCII-capable source — self-removal deferred")
                queue.async { self.removalStarted = false }
                return
            }
            let disabled = Self.disableOwnInputSources()
            log.log("orphan: switched to ABC; TISDisableInputSource=\(disabled, privacy: .public)")

            queue.async { [self] in
                do {
                    try FileManager.default.removeItem(at: bundleURL)
                    log.log("orphan: removed own bundle at \(bundleURL.path, privacy: .private)")
                } catch {
                    log.log("orphan: bundle removal failed — \(error.localizedDescription, privacy: .public)")
                }
                Self.unregisterFromLaunchServices(bundleURL)
                Self.clearLeftovers()
                // 현재 활성화 처리와 로그 flush가 끝날 시간을 준 뒤 종료. 번들이 없으므로 다시 뜨지 않는다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    exit(0)
                }
            }
        }
    }

    /// 우리 bundle ID의 모든 입력 소스(모드 포함)에 `TISDisableInputSource`. 하나라도 성공하면 true.
    /// 2026-09-19 (#32): 프로그램 비활성화가 GUI 전용이라는 종전 기록은 CLI 컨텍스트 실험이었다 —
    /// IME 프로세스 컨텍스트에서의 결과는 로그(`orphan`)로 실기기에서 확인한다.
    private static func disableOwnInputSources() -> Bool {
        guard let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        var anyDisabled = false
        for source in all {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { continue }
            let bundleID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            guard bundleID == imeBundleID else { continue }
            if TISDisableInputSource(source) == noErr { anyDisabled = true }
        }
        return anyDisabled
    }

    /// ABC(없으면 현재 ASCII 가능 자판)로 전환. 우리 IME가 선택된 채 사라지면 다음 키가
    /// 갈 곳이 없으므로 먼저 옮겨 둔다.
    private static func selectASCIICapableSource() -> Bool {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
           let abc = list.first {
            return TISSelectInputSource(abc) == noErr
        }
        if let fallback = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            return TISSelectInputSource(fallback) == noErr
        }
        return false
    }

    private static func unregisterFromLaunchServices(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath:
            "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister")
        task.arguments = ["-u", url.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    /// 남기는 흔적을 정리한다. 범위: IME 도메인·메인 앱 도메인의 `haneul.*` 키와
    /// `~/Library/Application Support/HaneulKeyboard`(구 예측입력 잔재). 전체 제거
    /// (`Uninstaller.clearUserDefaults`)는 메인 앱 도메인의 **모든** 키까지 지우는데, 여기는
    /// 앱이 이미 없는 상황이라 우리 접두어 키만 지운다(리뷰 M-2 — 범위 차이를 명시).
    private static func clearLeftovers() {
        let ime = UserDefaults.standard
        for key in ime.dictionaryRepresentation().keys where key.hasPrefix("haneul.") {
            ime.removeObject(forKey: key)
        }
        if let app = UserDefaults(suiteName: mainAppBundleID) {
            for key in app.dictionaryRepresentation().keys where key.hasPrefix("haneul.") {
                app.removeObject(forKey: key)
            }
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HaneulKeyboard")
        if FileManager.default.fileExists(atPath: appSupport.path) {
            try? FileManager.default.removeItem(at: appSupport)
        }
    }
}

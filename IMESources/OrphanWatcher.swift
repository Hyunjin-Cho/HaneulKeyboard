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
        guard let presence = observePresence() else {
            previousAbsentAt = nil
            log.log("orphan: observation unavailable — self-removal deferred; settings preserved")
            return
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
    private func candidatePaths() -> [String]? {
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
        //    2026-09-20 (#47, 리뷰 F-1): 이 중 휴지통 안 경로는 1단계와 같은 bundle ID + inode 검사를
        //    통과해야 후보가 된다 — 옛 버전 사본이 `.trashed`(2분 유예)로 잘못 요약되지 않게.
        let known: [String]
        switch RemovalObservation.registrations(for: Self.mainAppBundleID) {
        case .paths(let urls): known = urls.map(\.path)
        case .unknown: return nil
        }
        paths += OrphanDecision.filterTrashedCandidates(known) { path in
            let url = URL(fileURLWithPath: path)
            return OrphanDecision.acceptsTrashedCopy(
                bundleIDMatches: Self.bundleIdentifier(at: url) == Self.mainAppBundleID,
                recordedFileID: recordedFileID,
                candidateFileID: Self.fileID(at: url))
        }

        let alive = paths.contains { fm.fileExists(atPath: $0) && !OrphanDecision.isInTrash($0) }
        if alive { return paths }

        // 3) 표준 위치 스캔 — 위에서 못 찾았을 때만. /Applications·~/Applications는 하위 폴더
        //    한 단계까지(Utilities 등에 넣어 두는 사용자가 있다 — AppMoveDecision.isAlreadyInPlace가
        //    하위 폴더도 제자리로 인정한다), 그 밖 흔한 폴더는 최상위만 본다.
        let home = fm.homeDirectoryForCurrentUser
        let twoLevel = ["/Applications", home.appendingPathComponent("Applications").path]
        let oneLevel = ["Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0).path }
        for (dirs, depth) in [(twoLevel, 2), (oneLevel, 1)] {
            for dir in dirs {
                guard let found = Self.scanForMainApp(in: dir, depth: depth) else { return nil }
                paths += found
            }
        }
        return paths
    }

    /// `dir` 아래에서 우리 bundle ID의 .app을 찾는다(깊이 제한). `.app` 안으로는 들어가지 않는다.
    private static func scanForMainApp(in dir: String, depth: Int) -> [String]? {
        guard depth > 0 else { return [] }
        let entries: [String]
        do { entries = try FileManager.default.contentsOfDirectory(atPath: dir) }
        catch { return RemovalObservation.isMissing(error) ? [] : nil }
        var found: [String] = []
        for entry in entries where !entry.hasPrefix(".") {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                if bundleIdentifier(at: url) == mainAppBundleID { found.append(url.path) }
            } else if depth > 1 {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    guard let nested = scanForMainApp(in: url.path, depth: depth - 1) else { return nil }
                    found += nested
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

    /// 존재 조회 오류는 missing으로 바꾸지 않는다. 링크/불명확한 대상은 보수적으로 보존한다.
    private func observePresence() -> OrphanDecision.AppPresence? {
        guard let paths = candidatePaths() else { return nil }
        var existing = Set<String>()
        for path in paths {
            switch RemovalObservation.absence(at: URL(fileURLWithPath: path)) {
            case .alreadyAbsent: break
            case .failed: existing.insert(path)
            default: return nil
            }
        }
        return OrphanDecision.classify(candidatePaths: paths) { existing.contains($0) }
    }

    // MARK: - 실행

    /// 2026-10-11 B안: 개인 사전·설정은 항상 보존. 파일 제거 실패 시 종료하지 않고 재시도한다.
    private func selfRemove() {
        let ownURL = bundleURL
        guard RemovalObservation.absence(at: RemovalObservation.systemIME) == .alreadyAbsent,
              let presence = observePresence(), presence != .present else {
            removalStarted = false; previousAbsentAt = nil; return
        }
        let (target, identity) = RemovalObservation.capture(ownURL, identifier: Self.imeBundleID)
        guard identity.reachedGoal, let target else {
            log.log("orphan: identity check failed; bundle and settings preserved")
            removalStarted = false; return
        }
        DispatchQueue.main.async { [self] in
            let input = RemovalObservation.secureInput()
            guard input.reachedGoal else {
                log.log("orphan: safe input unavailable; bundle and settings preserved")
                queue.async { self.removalStarted = false }
                return
            }
            queue.async { [self] in
                let report = OrphanRemovalSequence.run(operations: .init(
                    recheck: {
                        guard RemovalObservation.absence(at: RemovalObservation.systemIME) == .alreadyAbsent,
                              let presence = self.observePresence(), presence != .present else {
                            return .preserved("메인 앱 부재를 다시 확인하지 못했어요")
                        }
                        return .verified
                    },
                    remove: { RemovalObservation.remove(target) },
                    unregister: { RemovalObservation.unregister([ownURL], identifier: Self.imeBundleID) }
                ))
                self.log.log("orphan: \(report.statusText, privacy: .private)")
                guard report.succeeded("ime") else { self.removalStarted = false; return }
                // 실제 파일 부재가 확인된 경우만 종료. 등록 오류가 있으면 로그에 남긴다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
            }
        }
    }
}

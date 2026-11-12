import Foundation

/// 2026-11-07 (#176): 설치·업데이트·제거 흐름의 회귀 검사. 임시 폴더 fixture와 주입된 동작만 쓴다.
/// 실제 설치 경로·설정 도메인·입력기 프로세스는 건드리지 않는다.
@MainActor enum InstallFlowTests {
    static func run(_ check: (Bool, String) -> Void) async {
        imeTargetBoundary(check)
        processScope(check)
        let fm = FileManager.default
        // 관리자 스크립트가 조상 링크를 거부하므로 /var → /private/var를 푼 실제 경로에서 돌린다.
        guard let resolved = realpath(fm.temporaryDirectory.path, nil) else {
            check(false, "설치 흐름 검사 준비: 임시 폴더 경로를 풀지 못함")
            return
        }
        defer { free(resolved) }
        let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("haneul-install-flow-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            try buildNumbersAfterReplacement(in: root.appendingPathComponent("builds"), check)
            try appPlacement(in: root.appendingPathComponent("placement"), check)
            try await relaunchCleanup(in: root.appendingPathComponent("relaunch"), check)
            try adminRemovalIdentity(in: root.appendingPathComponent("admin"), check)
            try realProcessList(in: root.appendingPathComponent("process"), check)
        } catch {
            check(false, "설치 흐름 검사 준비·실행 실패: \(error)")
        }
        updateRefusalMessage(check)
        appHandoff(check)
        orphanProtectedFolders(check)
        launchSequence(check)
        launchOrder(check)
    }

    /// 리뷰 2.3절: 관리자 제거는 삭제 직전 신원 확인이다. Finder로 복사한 앱의 최상위 FinderInfo 때문에 막히면 안 되고,
    /// 서명 유효성·Team 요구사항·inode·번들 ID는 그대로 봐야 한다.
    /// Apple 서명 fixture가 없어 ad-hoc 서명 번들에 실제 codesign을 돌리되 `-R=` 요구사항만 뺀다. 요구사항 자체는 `real-codesign`이 본다.
    private static func adminRemovalIdentity(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let identifier = RemovalObservation.imeID
        let team = RemovalCommand.officialTeam
        func signedBundle(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "app", "CFBundlePackageType": "APPL"]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
            let code = url.appendingPathComponent("Contents/MacOS/app")
            try "#!/bin/sh\nexit 0\n".write(to: code, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: code.path)
            check(tool("/usr/bin/codesign", ["--force", "--sign", "-", url.path]) == 0, "관리자 제거 fixture: ad-hoc 서명 \(name)")
            return url
        }
        let codesignLog = root.appendingPathComponent("codesign.log")
        let wrapper = root.appendingPathComponent("codesign-no-requirement.sh")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" >> \(shellQuoted(codesignLog.path))
        count=$#
        while [ "$count" -gt 0 ]; do
            argument=$1
            shift
            case "$argument" in
                -R=*) ;;
                *) set -- "$@" "$argument" ;;
            esac
            count=$((count - 1))
        done
        exec /usr/bin/codesign "$@"
        """.write(to: wrapper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        func runScript(_ url: URL, codesign: String) -> Int32? {
            guard let target = RemovalObservation.capture(url, identifier: identifier, trust: { _ in true }).0 else { return nil }
            return tool("/bin/bash", ["-c", RemovalAdminScript(target: target, team: team).shellCommand(codesign: codesign)])
        }

        let finder = try signedBundle("finder-copy.app")
        let finderInfo = (Data(count: 8) + Data([0x01, 0x00]) + Data(count: 22)).map { String(format: "%02x", $0) }.joined()
        check(tool("/usr/bin/xattr", ["-wx", "com.apple.FinderInfo", finderInfo, finder.path]) == 0, "관리자 제거 fixture: FinderInfo 붙임")
        check(tool("/usr/bin/codesign", ["--verify", "--strict", "--all-architectures", finder.path]) != 0,
              "관리자 제거 fixture: FinderInfo가 있으면 실제 codesign --strict가 거부")
        check(runScript(finder, codesign: wrapper.path) == 0 && !fm.fileExists(atPath: finder.path),
              "관리자 제거: Finder로 복사한 앱(최상위 FinderInfo)을 막지 않음")
        let log = (try? String(contentsOf: codesignLog, encoding: .utf8)) ?? ""
        let arguments = log.components(separatedBy: "\n")
        check(arguments.contains("--verify") && arguments.contains("--all-architectures") && !arguments.contains("--strict"),
              "관리자 제거: 서명 유효성은 보되 --strict는 쓰지 않음")
        check(arguments.contains("-R=anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""),
              "관리자 제거: Apple 인증서 사슬·번들 ID·Team 요구사항 유지")

        let tampered = try signedBundle("tampered.app")
        try "#!/bin/sh\nexit 1\n".write(to: tampered.appendingPathComponent("Contents/MacOS/app"), atomically: true, encoding: .utf8)
        check(runScript(tampered, codesign: wrapper.path) == 77 && fm.fileExists(atPath: tampered.path), "관리자 제거: 서명이 깨진 번들은 지우지 않음")

        let renamed = try signedBundle("other-id.app")
        guard let renamedTarget = RemovalObservation.capture(renamed, identifier: identifier, trust: { _ in true }).0 else {
            check(false, "관리자 제거 fixture: 대상 확인 실패")
            return
        }
        let other = ["CFBundleIdentifier": "com.example.other", "CFBundleExecutable": "app", "CFBundlePackageType": "APPL"]
        let otherData = try PropertyListSerialization.data(fromPropertyList: other, format: .xml, options: 0)
        let handle = try FileHandle(forWritingTo: renamed.appendingPathComponent("Contents/Info.plist"))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: otherData)
        try handle.close()
        check(tool("/bin/bash", ["-c", RemovalAdminScript(target: renamedTarget, team: team).shellCommand(codesign: wrapper.path)]) == 76
                && fm.fileExists(atPath: renamed.path), "관리자 제거: 인증 뒤 번들 ID 재확인 유지")

        let adHoc = try signedBundle("real-codesign.app")
        check(runScript(adHoc, codesign: "/usr/bin/codesign") == 77 && fm.fileExists(atPath: adHoc.path),
              "관리자 제거: 실제 codesign이 Apple 서명이 아닌 번들을 거부")

    }

    /// 리뷰 B-P3-3: 순수 함수만이 아니라 실제 `ps` 출력에서 현재 계정 필터까지 이어지는지 본다.
    /// `/bin/sleep`을 입력기 실행 파일 이름의 링크로 띄운다. 복사하면 OS가 바로 죽인다(실측 -9). 조회만 하고 종료 함수는 부르지 않는다.
    private static func realProcessList(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let fake = root.appendingPathComponent("HaneulKeyboardIM")
        try fm.createSymbolicLink(at: fake, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let task = Process()
        task.executableURL = fake
        task.arguments = ["30"]
        try task.run()
        defer { task.terminate(); task.waitUntilExit() }
        let pid = task.processIdentifier
        func found(_ result: Result<[(pid_t, String)], Error>) -> Bool {
            guard case .success(let list) = result else { return false }
            return list.contains { $0.0 == pid && $0.1.hasSuffix("/HaneulKeyboardIM") }
        }
        var direct = false
        for _ in 0..<40 where !direct {
            direct = found(RemovalObservation.imeProcesses())
            if !direct { Thread.sleep(forTimeInterval: 0.05) }
        }
        check(direct, "프로세스: 실제 ps 출력에서 내 입력기 실행본을 찾음")
        check(found(RemovalObservation.ProcessControl().list()), "프로세스: 종료 경로의 기본 조회도 같은 목록을 씀")
    }

    /// 2026-11-13 (#226, 리뷰 install-update-F-7): 설치본이 이미 실행 중이면 앱 이동이 인스턴스를 하나 더 띄우지 않는다.
    private static func appHandoff(_ check: (Bool, String) -> Void) {
        typealias Instance = AppHandoffDecision.Instance
        let destination = "/Applications/HaneulKeyboard.app"
        let me: pid_t = 100
        let installed = Instance(pid: 200, bundlePath: destination, terminated: false)
        let elsewhere = Instance(pid: 300, bundlePath: "/Users/someone/Downloads/HaneulKeyboard.app", terminated: false)
        let ended = Instance(pid: 400, bundlePath: destination, terminated: true)
        let selfCopy = Instance(pid: me, bundlePath: destination, terminated: false)
        func action(_ replaced: Bool, _ others: [Instance]) -> AppHandoffDecision.Action {
            AppHandoffDecision.action(replacedInstalledCopy: replaced, others: others, destinationPath: destination, selfPID: me)
        }
        check(action(true, []) == .openNew && action(false, []) == .openNew, "앱 이동: 실행 중인 설치본이 없으면 새로 연다")
        check(action(true, [installed]) == .quitThenOpen([200]), "앱 이동: 교체한 설치본이 옛 코드로 실행 중이면 끝낸 뒤 연다")
        check(action(false, [installed]) == .activate(200), "앱 이동: 기존 최신 버전이 이미 실행 중이면 새로 띄우지 않고 앞으로")
        check(action(true, [elsewhere, ended, selfCopy]) == .openNew && action(false, [elsewhere, ended, selfCopy]) == .openNew,
              "앱 이동: 다른 위치의 사본·끝난 인스턴스·자기 자신은 셈하지 않음")
        check(action(true, [Instance(pid: 201, bundlePath: destination + "/", terminated: false)]) == .quitThenOpen([201]),
              "앱 이동: 경로 표기 차이(끝의 /)는 같은 설치본")
        check(action(true, [Instance(pid: 202, bundlePath: nil, terminated: false)]) == .openNew, "앱 이동: 경로를 모르는 인스턴스는 끄지 않음")

        var ticks = 0
        check(AppHandoffDecision.waitUntilTerminated(timeout: 1, step: 0.25, isTerminated: { ticks >= 2 }, pause: { _ in ticks += 1 }),
              "앱 이동: 끝날 때까지 기다림")
        ticks = 0
        check(!AppHandoffDecision.waitUntilTerminated(timeout: 1, step: 0.25, isTerminated: { false }, pause: { _ in ticks += 1 }) && ticks == 4,
              "앱 이동: 끝나지 않으면 정해진 시간 뒤 포기(새로 띄우지 않음)")
        let mover = (try? String(contentsOfFile: "Sources/AppMover.swift", encoding: .utf8)) ?? ""
        check(mover.contains("handOff(to: destURL, replacedInstalledCopy: false") && mover.contains("handOff(to: destURL, replacedInstalledCopy: true")
              && mover.components(separatedBy: "createsNewApplicationInstance = true").count - 1 == 1,
              "앱 이동: 두 갈래 모두 같은 넘겨주기 판단을 거침")
    }

    /// 2026-11-13 (#226, 리뷰 install-update-F-8): 입력기의 고아 관찰은 보호 폴더 안 경로의 존재를 확인하지 않는다(권한 창 가능성 차단).
    /// 보호 폴더 밖에서 살아 있는 사본을 찾으면 나머지는 보지 않고, 보호 폴더 안 경로만 남으면 '있을 수 있음'으로 정리를 미룬다.
    private static func orphanProtectedFolders(_ check: (Bool, String) -> Void) {
        let home = "/Users/fixture"
        let roots = [home + "/Desktop", home + "/Documents", home + "/Downloads"]
        func protected(_ path: String) -> Bool { OrphanDecision.isProtectedLocation(path, protectedRoots: roots) }
        let realHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        check(OrphanDecision.protectedRoots() == ["Desktop", "Documents", "Downloads"].map { realHome + "/" + $0 },
              "고아 관찰: 보호 폴더는 시스템이 알려 주는 이 계정의 데스크탑·문서·다운로드")
        for path in [home + "/Downloads/HaneulKeyboard.app", home + "/Desktop/x/HaneulKeyboard.app", home + "/Documents/HaneulKeyboard.app",
                     home + "/Downloads/../Downloads/HaneulKeyboard.app"] {
            check(protected(path), "고아 관찰: 보호 폴더 \(path)")
        }
        for path in ["/Applications/HaneulKeyboard.app", home + "/Applications/HaneulKeyboard.app", home + "/DownloadsOld/HaneulKeyboard.app",
                     home + "/.Trash/HaneulKeyboard.app", "/Users/other/Downloads/HaneulKeyboard.app"] {
            check(!protected(path), "고아 관찰: 보호 폴더 아님 \(path)")
        }
        let installed = "/Applications/HaneulKeyboard.app"
        let downloads = home + "/Downloads/HaneulKeyboard.app"
        let trashed = home + "/.Trash/HaneulKeyboard.app"
        func observe(_ paths: [String], existing: Set<String>, unreadable: Set<String> = []) -> (OrphanDecision.AppPresence?, [String]) {
            var probed: [String] = []
            let presence = OrphanDecision.observe(candidatePaths: paths, isProtected: protected) { path in
                probed.append(path)
                return unreadable.contains(path) ? nil : existing.contains(path)
            }
            return (presence, probed)
        }
        let normal = observe([downloads, installed], existing: [installed, downloads])
        check(normal.0 == .present && normal.1 == [installed], "고아 관찰: 평소(설치본 있음)에는 다운로드 폴더 사본을 확인하지 않음")
        let gone = observe([installed, downloads], existing: [])
        check(gone.0 == nil && gone.1 == [installed], "고아 관찰: 설치본이 없어도 보호 폴더는 열지 않고 '있을 수 있음'으로 정리 미룸")
        check(observe([installed, trashed], existing: [trashed]).0 == .trashed, "고아 관찰: 휴지통에만 있으면 trashed")
        check(observe([installed], existing: []).0 == .missing, "고아 관찰: 어디에도 없으면 missing")
        check(observe([installed], existing: [], unreadable: [installed]).0 == nil, "고아 관찰: 읽지 못하면 관찰 불가")
        let trashFirst = observe([trashed, installed], existing: [trashed, installed])
        check(trashFirst.0 == .present && trashFirst.1 == [installed], "고아 관찰: 휴지통 밖을 먼저 보고 살아 있으면 바로 present")
        check(observe([installed, installed], existing: []).1 == [installed], "고아 관찰: 같은 경로는 한 번만 확인")
        check(observe([downloads], existing: [downloads]).1.isEmpty, "고아 관찰: 기록된 경로가 보호 폴더여도 열지 않음")
        // 자기 정리의 두 번 관찰·유예 규칙은 그대로다.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        check(!OrphanDecision.shouldSelfRemove(current: .missing, previousAbsentAt: now.addingTimeInterval(-1799), now: now, trashedInterval: 120, missingInterval: 1800)
              && OrphanDecision.shouldSelfRemove(current: .missing, previousAbsentAt: now.addingTimeInterval(-1800), now: now, trashedInterval: 120, missingInterval: 1800)
              && !OrphanDecision.shouldSelfRemove(current: .trashed, previousAbsentAt: nil, now: now, trashedInterval: 120, missingInterval: 1800),
              "고아 관찰: 30분·두 번 관찰 규칙 유지")
        let watcher = (try? String(contentsOfFile: "IMESources/OrphanWatcher.swift", encoding: .utf8)) ?? ""
        check(watcher.contains("OrphanDecision.observe(") && watcher.contains("isProtectedLocation"), "고아 관찰: 입력기가 같은 판단을 씀")
    }

    /// install-update-F-9: 옮기기 결과에 따라 입력기를 건드릴지 정한다. 곧 끝나는 인스턴스는 건드리지 않는다.
    private static func launchSequence(_ check: (Bool, String) -> Void) {
        let staying: [AppMoveOutcome] = [.alreadyInPlace, .blockedByOtherApp, .moveFailed]
        for outcome in AppMoveOutcome.allCases {
            var events: [String] = []
            AppLaunchSequence.run(moveApp: { events.append("move"); return outcome },
                                  recordAppPath: { events.append("record") },
                                  activateIME: { events.append("activate") })
            let keepsRunning = staying.contains(outcome)
            check(AppLaunchSequence.shouldActivateIME(after: outcome) == keepsRunning, "앱 시작 \(outcome): 입력기 갱신 판단")
            check(events == ["move", "record"] + (keepsRunning ? ["activate"] : []), "앱 시작 \(outcome): 옮기기 판단 → 경로 기록 → 입력기 갱신 순서")
        }
    }

    private static func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @discardableResult
    private static func tool(_ executable: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return -1
        }
        task.waitUntilExit()
        return task.terminationStatus
    }

    private static func makeBundle(_ url: URL, build: String = "107", identifier: String = AppMoveDecision.mainAppBundleID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleVersion": build, "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data("code".utf8).write(to: url.appendingPathComponent("Contents/MacOS/app"))
    }

    /// install-update-F-1: 교체·삭제·재설치 뒤에는 같은 경로에서 새 빌드 번호를 읽어야 한다.
    /// `Bundle(url:)` 캐시로 옛 빌드를 읽으면 갱신이 성공해도 "입력기 갱신 필요"가 앱이 끝날 때까지 남았다.
    private static func buildNumbersAfterReplacement(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for (label, read) in [("입력기", IMEInstaller.buildNumber(at:)), ("앱 이동", AppMover.buildNumber(at:))] {
            let installed = root.appendingPathComponent("\(label).app")
            try makeBundle(installed, build: "106")
            check(read(installed) == 106, "빌드 번호 \(label): 교체 전")
            let incoming = root.appendingPathComponent(".\(label).incoming")
            try makeBundle(incoming, build: "107")
            _ = try fm.replaceItemAt(installed, withItemAt: incoming)
            check(read(installed) == 107, "빌드 번호 \(label): 교체 뒤 같은 프로세스에서 새 값")
            try fm.removeItem(at: installed)
            check(read(installed) == nil, "빌드 번호 \(label): 삭제 뒤 없음")
            try makeBundle(installed, build: "108")
            check(read(installed) == 108, "빌드 번호 \(label): 재설치 뒤 새 값")
            try makeBundle(installed, build: "숫자 아님")
            check(read(installed) == nil, "빌드 번호 \(label): 정수가 아니면 없음")
        }
        check(UpdateDecision.shouldRefreshIME(installedBuild: AppMover.buildNumber(at: root.appendingPathComponent("없음.app")), bundledBuild: 107) == false,
              "빌드 번호: 못 읽으면 갱신하지 않음")
    }

    private static let quarantine = "com.apple.quarantine"
    private static func setQuarantine(_ url: URL) {
        let value = "0181;66000000;Safari;"
        _ = setxattr(url.path, quarantine, value, value.utf8.count, 0, 0)
    }
    private static func hasQuarantine(_ url: URL) -> Bool { getxattr(url.path, quarantine, nil, 0, 0, 0) >= 0 }

    /// install-update-F-3·F-10: 복사본을 staging에서 검증·격리 해제한 뒤에만 정본 경로에 놓는다.
    private static func appPlacement(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        func leftovers(_ directory: URL) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.contains("staging") }
        }
        func codeFile(_ app: URL) -> URL { app.appendingPathComponent("Contents/MacOS/app") }

        // 첫 복사: 격리된 원본 → 목적지는 격리 없음, 원본은 그대로, staging 안 남음
        let first = root.appendingPathComponent("first")
        try fm.createDirectory(at: first, withIntermediateDirectories: true)
        let source = first.appendingPathComponent("source.app")
        try makeBundle(source, build: "107")
        setQuarantine(source); setQuarantine(codeFile(source))
        check(hasQuarantine(source) && hasQuarantine(codeFile(source)), "앱 이동: 격리 fixture 준비")
        let destination = first.appendingPathComponent("HaneulKeyboard.app")
        var verified: [URL] = []
        var events: [String] = []
        var placedDuringVerify = true
        try AppMover.placeCopy(of: source, at: destination, verify: { url in
            verified.append(url); events.append("verify")
            placedDuringVerify = fm.fileExists(atPath: destination.path)
            return fm.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
        }, stripQuarantine: { url in
            events.append("strip"); Updater.stripQuarantine(at: url)
        })
        check(verified.count == 1 && verified.first != source && verified.first != destination, "앱 이동: 원본이 아니라 복사본을 검증")
        check(!placedDuringVerify, "앱 이동: 검증이 끝나기 전에는 정본 경로에 없음")
        check(events == ["verify", "strip"], "앱 이동: 서명 확인 뒤 격리 해제")
        check(AppMover.buildNumber(at: destination) == 107, "앱 이동: 첫 복사 정상 배치")
        check(!hasQuarantine(destination) && !hasQuarantine(codeFile(destination)), "앱 이동: 목적지 번들·내부 파일의 격리 해제")
        check(hasQuarantine(source), "앱 이동: 원본의 격리 속성은 건드리지 않음")
        check(leftovers(first).isEmpty, "앱 이동: 첫 복사 뒤 staging 없음")

        // 교체: 옛 번들의 격리가 새 번들로 옮아오지 않는다
        let replace = root.appendingPathComponent("replace")
        try fm.createDirectory(at: replace, withIntermediateDirectories: true)
        let existing = replace.appendingPathComponent("HaneulKeyboard.app")
        try makeBundle(existing, build: "106")
        setQuarantine(existing); setQuarantine(codeFile(existing))
        try AppMover.placeCopy(of: source, at: existing, verify: { _ in true })
        check(AppMover.buildNumber(at: existing) == 107 && !hasQuarantine(existing) && !hasQuarantine(codeFile(existing)),
              "앱 이동: 교체 뒤에도 격리 없음")
        check(leftovers(replace).isEmpty, "앱 이동: 교체 뒤 staging 없음")

        // 복사본 검증 실패: 첫 설치는 아무것도 안 남고, 교체는 옛 앱이 그대로다
        let rejected = root.appendingPathComponent("rejected")
        try fm.createDirectory(at: rejected, withIntermediateDirectories: true)
        let rejectedDestination = rejected.appendingPathComponent("HaneulKeyboard.app")
        var stripped = false
        var thrown = false
        do {
            try AppMover.placeCopy(of: source, at: rejectedDestination, verify: { _ in false }, stripQuarantine: { _ in stripped = true })
        } catch { thrown = (error as? AppMoveError) == .untrustedCopy }
        check(thrown && !fm.fileExists(atPath: rejectedDestination.path) && leftovers(rejected).isEmpty, "앱 이동: 검증 실패한 첫 복사는 남기지 않음")
        check(!stripped, "앱 이동: 검증 실패한 복사본의 격리를 벗기지 않음")
        try makeBundle(rejectedDestination, build: "106")
        thrown = false
        do { try AppMover.placeCopy(of: source, at: rejectedDestination, verify: { _ in false }) }
        catch { thrown = (error as? AppMoveError) == .untrustedCopy }
        check(thrown && AppMover.buildNumber(at: rejectedDestination) == 106 && leftovers(rejected).isEmpty, "앱 이동: 검증 실패한 교체는 옛 앱 보존")

        // 복사 중 실패: 반쪽 앱이 정본 경로에 남으면 다음 시도가 "다른 앱이 있어요"로 막힌다
        let partial = root.appendingPathComponent("partial")
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let brokenSource = partial.appendingPathComponent("source.app")
        try makeBundle(brokenSource)
        let unreadable = brokenSource.appendingPathComponent("Contents/zzz-locked")
        try Data("x".utf8).write(to: unreadable)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        let partialDestination = partial.appendingPathComponent("HaneulKeyboard.app")
        var failed = false
        do { try AppMover.placeCopy(of: brokenSource, at: partialDestination, verify: { _ in true }) } catch { failed = true }
        check(failed, "앱 이동: 복사 실패를 오류로 돌려줌")
        check(!fm.fileExists(atPath: partialDestination.path), "앱 이동: 복사 실패 뒤 정본 경로에 반쪽 앱 없음")
        check(leftovers(partial).isEmpty, "앱 이동: 복사 실패 뒤 staging 없음")
    }

    /// install-update-F-7: `NSApp.terminate`는 돌아오지 않아 defer가 돌지 않는다. 재실행 전에 작업 폴더가 없어야 한다.
    private static func relaunchCleanup(in root: URL, _ check: (Bool, String) -> Void) async throws {
        let fm = FileManager.default
        let work = root.appendingPathComponent("HaneulKeyboardUpdate-fixture")
        try fm.createDirectory(at: work.appendingPathComponent("extract"), withIntermediateDirectories: true)
        try Data("zip".utf8).write(to: work.appendingPathComponent("update.zip"))
        var existed = true
        await Updater.relaunchCleaningUp(workDir: work) { existed = fm.fileExists(atPath: work.path) }
        check(!existed, "업데이트: 재실행 전에 임시 작업 폴더를 지움")
        struct Boom: Error {}
        var propagated = false
        do { try await Updater.relaunchCleaningUp(workDir: work) { throw Boom() } } catch { propagated = error is Boom }
        check(propagated, "업데이트: 재실행 실패는 그대로 올라감")
        let updater = (try? String(contentsOfFile: "Sources/Updater.swift", encoding: .utf8)) ?? ""
        check(updater.contains("Self.relaunchCleaningUp(workDir: workDir)"), "업데이트: 설치 경로가 정리 후 재실행을 씀")
    }

    /// install-update-F-5: 사용자가 읽고 고칠 수 있게 정확한 조건을 적는다.
    private static func updateRefusalMessage(_ check: (Bool, String) -> Void) {
        for running in ["/Applications/Utilities/HaneulKeyboard.app", "/Applications/하늘키보드.app"] {
            let text = UpdateError.notInApplications(running).errorDescription ?? ""
            check(text.contains(AppMoveDecision.destinationURL().path), "업데이트 거부: 필요한 정확한 경로 \(running)")
            check(text.contains(running), "업데이트 거부: 지금 위치 \(running)")
            check(text.contains("하위 폴더") && text.contains("이름"), "업데이트 거부: 고칠 방법 \(running)")
            check(text.hasSuffix("요."), "업데이트 거부: 해요체 \(running)")
        }
    }

    /// install-update-F-9: 판단은 `launchSequence`가 실제로 돌려 본다. 앱 시작 코드는 시험 빌드에 못 넣어, 그 함수를 거치는지만 원문으로 본다.
    private static func launchOrder(_ check: (Bool, String) -> Void) {
        let app = (try? String(contentsOfFile: "Sources/HaneulKeyboardApp.swift", encoding: .utf8)) ?? ""
        check(app.contains("let core = AppCore(activateIMEOnLaunch: false)"), "앱 시작: 코어를 만들 때 입력기를 건드리지 않음")
        check(app.contains("AppLaunchSequence.run("), "앱 시작: 옮기기 판단과 입력기 갱신을 한 순서로 묶음")
        check(app.components(separatedBy: "ensureIMEActive").count - 1 == 1, "앱 시작: 입력기 갱신을 그 순서 밖에서 부르지 않음")
    }

    /// install-update-F-4: 다른 계정의 입력기 프로세스가 교체·제거를 막지 않는다.
    private static func processScope(_ check: (Bool, String) -> Void) {
        let me = uid_t(501), other = uid_t(502)
        let userPath = RemovalObservation.userIME.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM").path
        let systemPath = RemovalObservation.systemIME.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM").path
        let otherHomePath = "/Users/다른 계정/Library/Input Methods/HaneulKeyboardIM.app/Contents/MacOS/HaneulKeyboardIM"
        let output = """
            1     0 /sbin/launchd
          100   \(me) \(userPath)
          200 \(other) \(otherHomePath)
          300 \(other) \(systemPath)
          400   \(me) /Applications/HaneulKeyboard.app/Contents/MacOS/HaneulKeyboard
          500   \(me) /tmp/HaneulKeyboardIMHelper
        깨진 줄
          abc   \(me) \(userPath)
          600   xyz \(userPath)
        """
        let parsed = RemovalObservation.parseIMEProcesses(output)
        check(parsed.map(\.pid) == [100, 200, 300], "프로세스: 입력기 실행본만 고르고 깨진 줄은 건너뜀")
        check(parsed.first { $0.pid == 200 }?.path == otherHomePath, "프로세스: 경로의 공백을 보존")
        let own = RemovalObservation.ownIMEProcesses(parsed, currentUID: me)
        check(own.map(\.0) == [100] && own.first?.1 == userPath, "프로세스: 현재 계정의 입력기만 센다")
        check(RemovalObservation.ownIMEProcesses(parsed, currentUID: 503).isEmpty, "프로세스: 내 입력기가 없으면 비어 있음")

        // 리뷰 B-P3-3: 조회 함수가 실제 현재 계정(getuid)으로 거르는 연결까지 본다.
        let current = getuid()
        let connected = RemovalObservation.imeProcesses(list: {
            .success([RemovalObservation.IMEProcess(pid: 100, uid: current, path: userPath),
                      RemovalObservation.IMEProcess(pid: 200, uid: current &+ 1, path: otherHomePath),
                      RemovalObservation.IMEProcess(pid: 300, uid: current &+ 1, path: systemPath)])
        })
        if case .success(let list) = connected {
            check(list.map(\.0) == [100], "프로세스: 조회 함수가 다른 계정 실행본을 뺌")
        } else { check(false, "프로세스: 조회 함수가 목록을 돌려줌") }
        struct ListFailure: Error {}
        if case .failure = RemovalObservation.imeProcesses(list: { .failure(ListFailure()) }) {
            check(true, "프로세스: 조회 실패를 그대로 올림")
        } else { check(false, "프로세스: 조회 실패를 빈 목록으로 숨기지 않음") }

        let notice = RemovalObservation.otherAccountNotice(parsed, currentUID: me, removingSystemIME: true)
        check(notice != nil && notice?.reachedGoal == false && notice?.text.contains("다른 계정") == true,
              "프로세스: 시스템 입력기를 다른 계정이 쓰면 알림")
        check(RemovalObservation.otherAccountNotice(parsed, currentUID: me, removingSystemIME: false) == nil,
              "프로세스: 시스템 입력기를 지우지 않으면 알리지 않음")
        check(RemovalObservation.otherAccountNotice(parsed.filter { $0.pid != 300 }, currentUID: me, removingSystemIME: true) == nil,
              "프로세스: 다른 계정 자기 폴더의 입력기는 우리와 무관")

        struct Boom: Error {}
        func stop(_ snapshots: [Result<[(pid_t, String)], Error>], errors: [Int32: Int32] = [:]) -> (RemovalState, [(pid_t, Int32)]) {
            var signals: [(pid_t, Int32)] = []
            var remaining = snapshots
            var control = RemovalObservation.ProcessControl()
            control.list = { remaining.count > 1 ? remaining.removeFirst() : remaining[0] }
            control.signal = { pid, signal in
                signals.append((pid, signal))
                return errors[signal] ?? (signal == 0 ? ESRCH : 0)
            }
            control.pause = { _ in }
            return (RemovalObservation.stopIMEProcesses(control: control), signals)
        }
        let mine: [(pid_t, String)] = [(100, userPath)]
        let clean = stop([.success(mine), .success([]), .success([])])
        check(clean.0 == .removed && clean.1.first?.1 == SIGTERM, "프로세스: 내 입력기는 종료 후 제거됨으로 보고")
        check(!clean.1.contains { $0.1 == SIGKILL }, "프로세스: 정상 종료되면 강제 종료하지 않음")
        check(stop([.success([])]).0 == .alreadyAbsent, "프로세스: 실행본이 없으면 이미 없음")
        check(stop([.failure(Boom())]).0.reachedGoal == false, "프로세스: 목록 조회 실패를 없음으로 보지 않음")
        let foreign = stop([.success([(700, "/tmp/HaneulKeyboardIM")])])
        check(foreign.1.isEmpty && foreign.0.reachedGoal == false, "프로세스: 내 계정의 다른 위치 실행본은 건드리지 않고 멈춤")
        let denied = stop([.success(mine)], errors: [SIGTERM: EPERM, 0: EPERM])
        check(denied.0.reachedGoal == false && denied.0.text.contains("권한"), "프로세스: 종료 권한이 없으면 그 이유를 말함")
        check(denied.1.filter { $0.1 == SIGTERM }.count == 1 && !denied.1.contains { $0.1 == SIGKILL },
              "프로세스: 권한이 없으면 기다리거나 강제 종료하지 않음")
        let stubborn = stop([.success(mine), .success(mine), .success([])], errors: [0: 0])
        check(stubborn.0 == .removed && stubborn.1.contains { $0.0 == 100 && $0.1 == SIGKILL }, "프로세스: 안 끝나면 같은 실행본만 강제 종료")

        let noticed = RemovalSequence.run(mode: .wholeProduct, operations: .init(
            prepare: { .verified }, secureInput: { .verified }, stopProcesses: { .alreadyAbsent },
            removeInputMethods: { [RemovalStep(id: "ime", title: "시스템 입력기", state: .removed)] },
            verifyInputMethods: { [RemovalStep(id: "ime", title: "부재", state: .alreadyAbsent)] },
            unregister: { .removed }, observeInputSources: { .verified }, clearSettings: { .removed },
            removeMainApps: { .removed }, otherAccountNotice: { .needsUserAction("다른 계정") }))
        check(noticed.complete && noticed.steps.filter { $0.id == "other-accounts" }.count == 1,
              "프로세스: 다른 계정 안내는 제거를 막지 않고 보고서에 한 번 남음")
    }

    /// security-overlap-F-4 (2): 입력기 바이너리에는 프로세스 종료·ps·defaults 실행 코드가 없어야 한다.
    /// 입력기가 자기 정리에 쓰는 lsregister 호출은 남아 있어야 한다.
    private static func imeTargetBoundary(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        func text(_ path: String) -> String {
            (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
        }
        let imeFiles = ["IMESources", "Shared"].flatMap { directory in
            ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)) ?? [])
                .filter { $0.hasSuffix(".swift") }
                .map { "\(directory)/\($0)" }
        } + ["Sources/BundleTrust.swift"]
        check(imeFiles.count > 3, "입력기 경계: 입력기 소스를 찾음")
        for forbidden in ["kill(", "/bin/ps", "/usr/bin/defaults", "NSRunningApplication", "CFPreferencesSetValue"] {
            let offenders = imeFiles.filter { text($0).contains(forbidden) }
            check(offenders.isEmpty, "입력기 경계: \(forbidden) 없음 \(offenders)")
        }
        let shared = text("Shared/RemovalObservation.swift")
        check(shared.contains("lsregister") && shared.contains("\"-u\""), "입력기 경계: 자기 정리의 lsregister 호출은 유지")
        check(imeFiles.map { text($0).components(separatedBy: "Process()").count - 1 }.reduce(0, +) == 1,
              "입력기 경계: 프로세스 실행은 lsregister 한 곳뿐")

        let project = text("project.yml")
        guard let start = project.range(of: "\n  HaneulKeyboardIM:\n"),
              let end = project.range(of: "\n    info:", range: start.upperBound..<project.endIndex) else {
            check(false, "입력기 경계: project.yml에서 입력기 타깃을 찾지 못함")
            return
        }
        let imeTarget = project[start.upperBound..<end.lowerBound]
        check(!imeTarget.contains("- path: Sources\n") && !imeTarget.contains("RemovalMainAppOperations"),
              "입력기 경계: 메인 앱 전용 파일이 입력기 타깃에 없음")
        check(project.contains("      - path: Sources\n"), "입력기 경계: 메인 앱 타깃은 Sources 폴더를 통째로 포함")
        let mainOnly = text("Sources/RemovalMainAppOperations.swift")
        check(mainOnly.contains("stopIMEProcesses") && mainOnly.contains("clearProductSettings"),
              "입력기 경계: 프로세스 종료·설정 정리는 메인 앱 전용 파일에 있음")
        let listed = text("scripts/uninstall.sh") + text("scripts/run_updater_tests.sh")
        check(listed.components(separatedBy: "RemovalMainAppOperations.swift").count - 1 == 2,
              "입력기 경계: 복구 CLI·테스트 컴파일 목록에 메인 앱 전용 파일 포함")
    }
}

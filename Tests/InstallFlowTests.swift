import Foundation

/// 2026-11-07 (#176): 설치·업데이트·제거 흐름의 회귀 검사. 임시 폴더 fixture와 주입된 동작만 쓴다.
/// 실제 설치 경로·설정 도메인·입력기 프로세스는 건드리지 않는다.
@MainActor enum InstallFlowTests {
    static func run(_ check: (Bool, String) -> Void) async {
        imeTargetBoundary(check)
        processScope(check)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("haneul-install-flow-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            try buildNumbersAfterReplacement(in: root.appendingPathComponent("builds"), check)
            try appPlacement(in: root.appendingPathComponent("placement"), check)
            try await relaunchCleanup(in: root.appendingPathComponent("relaunch"), check)
        } catch {
            check(false, "설치 흐름 검사 준비·실행 실패: \(error)")
        }
        updateRefusalMessage(check)
        launchOrder(check)
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
        try await Updater.relaunchCleaningUp(workDir: work) { existed = fm.fileExists(atPath: work.path) }
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

    /// install-update-F-9: 옮기기를 거절할 복사본이 입력기를 교체하면 안 된다. 앱 시작 코드는 시험 빌드에 못 넣어 원문 순서로 본다.
    private static func launchOrder(_ check: (Bool, String) -> Void) {
        let app = (try? String(contentsOfFile: "Sources/HaneulKeyboardApp.swift", encoding: .utf8)) ?? ""
        check(app.contains("let core = AppCore(activateIMEOnLaunch: false)"), "앱 시작: 코어를 만들 때 입력기를 건드리지 않음")
        guard let start = app.range(of: "func applicationWillFinishLaunching"),
              let end = app.range(of: "func applicationDidFinishLaunching", range: start.upperBound..<app.endIndex) else {
            check(false, "앱 시작: applicationWillFinishLaunching을 찾지 못함")
            return
        }
        let body = app[start.upperBound..<end.lowerBound]
        if let mover = body.range(of: "AppMover.moveToApplicationsIfNeeded()"),
           let activation = body.range(of: "core.ensureIMEActive()") {
            check(mover.upperBound <= activation.lowerBound, "앱 시작: 옮기기 판단 뒤에 입력기 갱신")
        } else {
            check(false, "앱 시작: 옮기기 판단과 입력기 갱신 호출을 찾지 못함")
        }
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

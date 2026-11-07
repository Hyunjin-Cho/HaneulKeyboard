import Foundation

/// 2026-11-07 (#176): 설치·업데이트·제거 흐름의 회귀 검사. 임시 폴더 fixture와 주입된 동작만 쓴다.
/// 실제 설치 경로·설정 도메인·입력기 프로세스는 건드리지 않는다.
@MainActor enum InstallFlowTests {
    static func run(_ check: (Bool, String) -> Void) async {
        imeTargetBoundary(check)
        processScope(check)
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

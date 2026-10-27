import Foundation

/// 공통 제품 순서를 그대로 실행한다. 개인 데이터 대신 임시 폴더·독립 defaults 도메인만 쓴다.
@MainActor enum UninstallTests {
    static func run(_ check: (Bool, String) -> Void) {
        let cases = ["success", "already-absent", "prepare-unknown", "input-unknown", "process-unknown", "cancel", "file-failed", "reappeared", "late-reappeared", "registration-unknown", "source-enabled", "source-unknown", "settings-failed", "main-failed"]
        for mode in [RemovalReport.Mode.wholeProduct, .inputMethod, .commandLine] {
            for scenario in cases {
                var events: [String] = []; var verification = 0
                let original = ["haneul.personalDict.force": ["x9q"], "haneul.personalDict.block": ["apple"], "haneul.recentReverts": ["fixture"], "haneul.disabledAppBundleIDs": ["fixture.app"]]
                var settings = original
                let absent = scenario == "already-absent"
                let op = RemovalSequence.Operations(
                    prepare: { events.append("prepare"); return scenario == "prepare-unknown" ? .unknown("조회 실패") : .verified },
                    secureInput: { events.append("input"); return scenario == "input-unknown" ? .unknown("조회 실패") : .verified },
                    stopProcesses: { events.append("process"); return scenario == "process-unknown" ? .unknown("조회 실패") : .alreadyAbsent },
                    removeInputMethods: {
                        events.append("ime")
                        let state: RemovalState = scenario == "cancel" ? .cancelled("암호창 취소") : scenario == "file-failed" ? .failed("권한 거부") : absent ? .alreadyAbsent : .removed
                        return [RemovalStep(id: "ime", title: "사용자 입력기", state: state), RemovalStep(id: "ime", title: "시스템 입력기", state: .alreadyAbsent)]
                    },
                    verifyInputMethods: {
                        events.append("verify"); verification += 1
                        return [RemovalStep(id: "ime", title: "파일 부재 재확인", state: scenario == "reappeared" || scenario == "late-reappeared" && verification == 2 ? .failed("새 파일 발견") : .alreadyAbsent)]
                    },
                    unregister: { events.append("registration"); return scenario == "registration-unknown" ? .unknown("조회 실패") : .alreadyAbsent },
                    observeInputSources: { events.append("sources"); return scenario == "source-enabled" ? .needsUserAction("설정에서 제거") : scenario == "source-unknown" ? .unknown("조회 실패") : .verified },
                    clearSettings: { events.append("settings"); if scenario == "settings-failed" { return .failed("저장 실패") }; settings.removeAll(); return .removed },
                    removeMainApps: { events.append("main"); return scenario == "main-failed" ? .failed("권한 거부") : .removed }
                )
                let report = RemovalSequence.run(mode: mode, operations: op)
                let prefix = "제거 \(mode.rawValue)/\(scenario)"
                let preFailure = ["prepare-unknown", "input-unknown", "process-unknown", "cancel", "file-failed", "reappeared", "registration-unknown", "source-enabled", "source-unknown"].contains(scenario)
                let blocksSettings = preFailure || scenario == "late-reappeared"
                if mode == .inputMethod {
                    check(settings == original && !events.contains("settings") && !events.contains("main"), "\(prefix): 입력기만 제거하면 설정/앱 보존")
                    check(report.complete == !preFailure, "\(prefix): 입력기 범위에서만 완료 판정")
                } else {
                    check(events.contains("settings") == !blocksSettings, "\(prefix): 파일·실행·등록·소스 관문 뒤에만 설정 정리")
                    check(settings == (blocksSettings || scenario == "settings-failed" ? original : [:]), "\(prefix): 실패/취소/불명 상태의 개인 데이터 보존")
                    let mainExpected = mode == .wholeProduct && !blocksSettings && scenario != "settings-failed"
                    check(events.contains("main") == mainExpected, "\(prefix): 필수 정리 실패 시 메인 앱 삭제 미호출")
                    let complete = !blocksSettings && scenario != "settings-failed" && (mode == .commandLine || scenario != "main-failed")
                    check(report.complete == complete, "\(prefix): 정확한 범위 완료")
                    if mode == .wholeProduct {
                        let outcome = UninstallOutcome(report: report)
                        check(outcome.fullyRemoved == complete && outcome.keptMainAppForRetry == !complete, "\(prefix): UI 종료/재시도 판정")
                    } else { check(RemovalCommand.exitCode(report) == (complete ? 0 : 1), "\(prefix): CLI 실패는 nonzero") }
                }
                if ["cancel", "file-failed"].contains(scenario) {
                    check(!events.contains("registration"), "\(prefix): 파일 실패 때 등록 해제 미호출")
                }
                if scenario == "success" && mode == .wholeProduct {
                    check(events == ["prepare", "input", "process", "ime", "process", "verify", "registration", "sources", "verify", "process", "settings", "main"], "\(prefix): 실제 순서·C1 직전 재조회")
                }
            }
        }
        for state in [RemovalState.failed("권한 거부"), .cancelled("취소"), .unknown("조회 실패"), .removed, .alreadyAbsent] {
            var registered = false
            let report = OrphanRemovalSequence.run(operations: .init(recheck: { .verified }, remove: { state }, unregister: { registered = true; return .removed }))
            check(registered == state.reachedGoal && report.succeeded("ime") == state.reachedGoal, "자동 정리 \(state.text): 실패 시 등록 해제/종료 관문 닫힘")
            check(report.steps.contains { $0.id == "settings" && !$0.required && !$0.state.reachedGoal }, "자동 정리 \(state.text): 설정 항상 보존")
        }
        var removed = false
        let restored = OrphanRemovalSequence.run(operations: .init(recheck: { .unknown("앱 복원/조회 실패") }, remove: { removed = true; return .removed }, unregister: { .removed }))
        check(!removed && !restored.complete, "자동 정리: 최종 관찰 불명 때 파일 삭제 미호출")
        fileAndPreferenceChecks(check)
        let gate = ProductOperationGate()
        let install = gate.begin(.installing)!
        check(gate.begin(.removingProduct) == nil && gate.begin(.updating) == nil, "작업권: 설치 도중 제거/업데이트 차단")
        gate.finish(UUID()); check(gate.operation == .installing, "작업권: 다른 작업의 토큰으로 반납 불가")
        gate.finish(install); check(gate.begin(.removingProduct) != nil, "작업권: 완료 뒤 제거 재시도 가능")
    }

    private static func fileAndPreferenceChecks(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".tmp").appendingPathComponent("HaneulRemovalTests-\(UUID().uuidString)")
        let id = "com.hyunjincho.inputmethod.haneul"
        let trust: (URL) -> Bool = { _ in true } // OS 서명만 대체. 제품 ID/path/inode/삭제는 실제 함수.
        func fixture(_ name: String, identifier: String = "com.hyunjincho.inputmethod.haneul") throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
            try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data("keep executable bytes".utf8).write(to: url.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM"))
            return url
        }
        func contents(_ url: URL) throws -> [Data] {
            try ["Contents/Info.plist", "Contents/MacOS/HaneulKeyboardIM"].map {
                try Data(contentsOf: url.appendingPathComponent($0))
            }
        }
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let absent = root.appendingPathComponent("absent.app")
            check(RemovalObservation.capture(absent, identifier: id, trust: trust).1 == .alreadyAbsent, "파일: 이미 없는 번들은 정상 목표")
            let broken = root.appendingPathComponent("no-info.app"); try fm.createDirectory(at: broken, withIntermediateDirectories: true)
            check(!RemovalObservation.capture(broken, identifier: id, trust: trust).1.reachedGoal, "파일: Info 읽기 실패를 없음으로 취급하지 않음")
            let foreign = try fixture("foreign.app", identifier: "other.product")
            check(!RemovalObservation.capture(foreign, identifier: id, trust: trust).1.reachedGoal && fm.fileExists(atPath: foreign.path), "파일: 다른 제품 ID 보존")
            let owned = try fixture("owned.app")
            let (initialTarget, initialState) = RemovalObservation.capture(owned, identifier: id, trust: trust)
            guard let captured = initialTarget else { check(false, "파일 fixture 확인: \(initialState.text)"); return }
            check(!RemovalObservation.capture(owned, identifier: id, trust: { _ in false }).1.reachedGoal, "파일: 손상 서명/다른 Team 차단")
            let link = root.appendingPathComponent("link.app"); try fm.createSymbolicLink(at: link, withDestinationURL: owned)
            check(!RemovalObservation.capture(link, identifier: id, trust: trust).1.reachedGoal, "파일: 번들 symlink 차단")
            let dangling = root.appendingPathComponent("dangling.app"); try fm.createSymbolicLink(at: dangling, withDestinationURL: absent)
            check(RemovalObservation.absence(at: dangling) != .alreadyAbsent, "파일: 깨진 링크도 존재로 취급")
            let parent = root.appendingPathComponent("parent-link"); try fm.createSymbolicLink(at: parent, withDestinationURL: root)
            check(!RemovalObservation.capture(parent.appendingPathComponent("owned.app"), identifier: id, trust: trust).1.reachedGoal, "파일: 조상 symlink 차단")
            try fm.moveItem(at: owned, to: root.appendingPathComponent("original.app")); _ = try fixture("owned.app")
            check(!RemovalObservation.remove(captured, trust: trust).reachedGoal && fm.fileExists(atPath: owned.path), "파일: 같은 경로의 교체된 inode를 지우지 않음")
            let swappedAdmin = RemovalAdminScript(target: captured, team: RemovalCommand.officialTeam)
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/bash"); task.arguments = ["-c", swappedAdmin.shellCommand()]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            try task.run(); task.waitUntilExit()
            check(task.terminationStatus == 75 && fm.fileExists(atPath: owned.path), "관리자: 인증 후 실행기의 inode 재검증이 대상 교체 차단")
            let fresh = RemovalObservation.capture(owned, identifier: id, trust: trust).0!
            var unexpectedAdmin = false
            check(RemovalObservation.remove(fresh, admin: { _ in unexpectedAdmin = true }, trust: trust) == .removed && RemovalObservation.absence(at: owned) == .alreadyAbsent, "파일: 삭제 호출 뒤 실제 부재 재확인")
            check(!unexpectedAdmin, "파일: 일반 권한으로 지울 수 있으면 관리자 요청 없음")
            let denied = try fixture("denied.app")
            let protected = RemovalObservation.capture(denied, identifier: id, trust: trust).0!
            let originalContents = try contents(denied)
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
            let failure = RemovalObservation.remove(protected, trust: trust)
            check(!failure.reachedGoal && fm.fileExists(atPath: denied.path), "파일: 실제 권한 거부를 실패로 보고")
            check((try? contents(denied)) == originalContents, "권한 거부: 폴더뿐 아니라 Info와 실행 파일 바이트도 보존")
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

            let ioFailure = try fixture("io-failure.app")
            let ioTarget = RemovalObservation.capture(ioFailure, identifier: id, trust: trust).0!
            let beforeIO = try contents(ioFailure)
            var retriedWithAdmin = false
            let ioResult = RemovalObservation.remove(ioTarget, admin: { _ in retriedWithAdmin = true }, trust: trust,
                removeItem: { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) })
            check(!ioResult.reachedGoal && !retriedWithAdmin, "삭제 시작 후 I/O 오류: 관리자 재시도로 넘어가지 않음")
            check((try? contents(ioFailure)) == beforeIO, "삭제 호출 실패를 관리자 취소/성공으로 숨기지 않음")

            // 2026-10-12 #90: removeItem 실패 뒤 관리자 요청은 이미 번들 내용을 지울 수 있다.
            // 상위 폴더와 내부 디렉터리 각각의 권한 거부에서, 인증 전에 내용을 보존한다.
            for internalDenial in [false, true] {
                for scenario in ["cancel", "admin-failed", "admin-no-op", "admin-success"] {
                    let app = try fixture("permission-\(internalDenial)-\(scenario).app")
                    let target = RemovalObservation.capture(app, identifier: id, trust: trust).0!
                    let before = try contents(app)
                    let restricted = internalDenial ? app.appendingPathComponent("Contents/MacOS") : root
                    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: restricted.path)
                    defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path) }
                    if scenario == "cancel" {
                        let noAdmin = RemovalObservation.remove(target, trust: trust)
                        check(!noAdmin.reachedGoal && (try? contents(app)) == before,
                              "관리자 없는 자동 정리: 부모/내부 권한 거부 시 번들 내용 보존")
                    }
                    var adminCalls = 0
                    var sameTargetAtAdmin = false
                    var intactAtAdmin = false
                    let result = RemovalObservation.remove(target, admin: { received in
                        adminCalls += 1
                        sameTargetAtAdmin = received.fileNumber == target.fileNumber && received.device == target.device
                        intactAtAdmin = (try? contents(app)) == before
                        if scenario == "cancel" { throw RemovalCancelled() }
                        if scenario == "admin-failed" { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
                        if scenario == "admin-success" {
                            // 실제 인증창 대신 임시 폴더의 권한만 복구해 승인 후 삭제를 실행한다.
                            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)
                            try fm.removeItem(at: received.url)
                        }
                    }, trust: trust)
                    let label = "권한 거부 \(internalDenial ? "내부" : "부모")/\(scenario)"
                    check(adminCalls == 1, "\(label): 삭제를 시도하기 전에 관리자 경로 선택")
                    check(sameTargetAtAdmin, "\(label): 처음 검증한 대상만 관리자에게 전달")
                    check(intactAtAdmin, "\(label): 관리자 요청 시점에 번들 전체 보존")
                    if scenario == "admin-success" {
                        check(result == .removed && RemovalObservation.absence(at: app) == .alreadyAbsent, "\(label): 승인 후 부재 확인")
                    } else {
                        check(!result.reachedGoal && (try? contents(app)) == before, "\(label): 실패/취소 시 내부 파일 보존")
                        let recaptured = RemovalObservation.capture(app, identifier: id, trust: trust).0
                        check(recaptured?.fileNumber == target.fileNumber, "\(label): 서명 검사의 입력과 재시도 대상 보존")
                        if scenario == "cancel" {
                            if case .cancelled = result { check(true, "\(label): 취소로 보고") }
                            else { check(false, "\(label): 취소로 보고") }
                        }
                        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)
                        check(RemovalObservation.remove(target, trust: trust) == .removed, "\(label): 같은 대상으로 제거 재시도 성공")
                    }
                }
            }
            let outside = root.appendingPathComponent("external"); try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            let sentinel = outside.appendingPathComponent("HaneulKeyboard/sentinel"); try fm.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("keep".utf8).write(to: sentinel)
            let linkedBundle = try fixture("internal-link.app")
            try fm.createSymbolicLink(at: linkedBundle.appendingPathComponent("Contents/external-link"), withDestinationURL: outside)
            let linkedTarget = RemovalObservation.capture(linkedBundle, identifier: id, trust: trust).0!
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: outside.path)
            var linkAdmin = false
            let linkResult = RemovalObservation.remove(linkedTarget, admin: { _ in linkAdmin = true }, trust: trust)
            check(linkResult == .removed && !linkAdmin, "번들 내부 링크: 바깥 폴더 권한을 따라 관리자 요청하지 않음")
            check((try? Data(contentsOf: sentinel)) == Data("keep".utf8), "번들 내부 링크: 외부 파일 내용 보존")
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: outside.path)
            let supportLink = root.appendingPathComponent("Application Support"); try fm.createSymbolicLink(at: supportLink, withDestinationURL: outside)
            let suite = "haneul.removal-tests.\(UUID().uuidString)"
            let domains = [suite + ".main", suite + ".ime", suite + ".global"]
            defer { for name in domains { UserDefaults.standard.removePersistentDomain(forName: name) } }
            let guarded = RemovalObservation.clearProductSettings(mainDomain: domains[0], inputDomain: domains[1], globalDomain: domains[2], supportURL: supportLink.appendingPathComponent("HaneulKeyboard"))
            check(!guarded.reachedGoal && fm.fileExists(atPath: sentinel.path), "설정: 부모 symlink 바깥 파일 보존")
            for name in domains { let defaults = UserDefaults(suiteName: name)!; defaults.set(["fixture"], forKey: "haneul.personalDict.force"); defaults.set(1, forKey: "haneul.fixture.v2"); defaults.synchronize() }
            let global = UserDefaults(suiteName: domains[2])!; global.set("preserve", forKey: "other.setting"); global.synchronize()
            let support = root.appendingPathComponent("settings"); try fm.createDirectory(at: support, withIntermediateDirectories: true); try Data("legacy".utf8).write(to: support.appendingPathComponent("old-data"))
            let cleared = RemovalObservation.clearProductSettings(mainDomain: domains[0], inputDomain: domains[1], globalDomain: domains[2], supportURL: support)
            check(cleared.reachedGoal && RemovalObservation.absence(at: support) == .alreadyAbsent, "설정: 실제 독립 도메인/옛 폴더 정리·재조회")
            if case .success(let remaining) = RemovalObservation.storedPreferences(domains[2]) {
                check(remaining.count == 1 && remaining["other.setting"] as? String == "preserve", "설정: 점·숫자를 포함한 모든 haneul.* 제거, 다른 키 보존")
            } else { check(false, "설정: 별도 프로세스 재조회") }
            check(RemovalObservation.clearProductSettings(mainDomain: domains[0], inputDomain: domains[1], globalDomain: domains[2], supportURL: support) == .alreadyAbsent, "설정: 빈/없는 도메인·폴더의 재시도 정상")
            let badPreferences = root.appendingPathComponent("bad-preferences"); try fm.createDirectory(at: badPreferences, withIntermediateDirectories: true)
            let badDomain = domains[0] + ".bad"
            try Data("broken plist".utf8).write(to: badPreferences.appendingPathComponent(badDomain + ".plist"))
            if case .failure = RemovalObservation.storedPreferences(badDomain, preferencesDirectory: badPreferences) { check(true, "설정: 손상 plist를 이미 없음으로 오판하지 않음") }
            else { check(false, "설정: 손상 plist를 이미 없음으로 오판하지 않음") }
            check(RemovalObservation.unregister([absent], identifier: suite) == .alreadyAbsent, "등록: 미등록 경로는 조회로 부재 확인, exit1을 임의 성공 처리하지 않음")
        } catch { check(false, "임시 파일/설정 검사 준비: \(error)") }
    }
}

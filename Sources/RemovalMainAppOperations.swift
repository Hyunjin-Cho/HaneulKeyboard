import AppKit
import Foundation

/// 2026-11-07 (#176): 메인 앱과 복구 CLI만 쓰는 제거 동작 — 입력기 프로세스 조회·종료, 다른 앱 인스턴스 확인,
/// defaults 실행과 개인 설정 정리. 키 입력을 보는 입력기 바이너리에 쓰지 않는 프로세스 실행·종료 코드를 남기지 않으려고
/// `Shared/RemovalObservation.swift`에서 떼어 왔다. `Sources` 폴더는 메인 앱 타깃에만 들어간다(project.yml).
/// 컴파일 목록: `scripts/uninstall.sh`, `scripts/run_updater_tests.sh`.
extension RemovalObservation {
    struct IMEProcess: Equatable, Sendable {
        let pid: pid_t
        let uid: uid_t
        let path: String
    }

    /// `ps -axo pid=,uid=,comm=` 출력에서 입력기 실행본만 고른다. 경로에 공백이 있어도 된다.
    static func parseIMEProcesses(_ output: String) -> [IMEProcess] {
        output.split(separator: "\n").compactMap { line in
            let pieces = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard pieces.count == 3, let pid = pid_t(pieces[0]), let uid = uid_t(pieces[1]) else { return nil }
            let executable = String(pieces[2])
            guard URL(fileURLWithPath: executable).lastPathComponent == "HaneulKeyboardIM" else { return nil }
            return IMEProcess(pid: pid, uid: uid, path: executable)
        }
    }

    /// 2026-11-07 (#176, 리뷰 install-update-F-4): 현재 계정의 실행본만 센다. `ps -a`는 다른 계정 것까지 절대 경로로 보여 줘서,
    /// 빠른 사용자 전환으로 함께 로그인한 계정의 입력기가 "다른 위치의 실행본"이 되어 교체·제거를 그 계정이 로그아웃할 때까지 막았다.
    static func ownIMEProcesses(_ all: [IMEProcess], currentUID: uid_t) -> [(pid_t, String)] {
        all.filter { $0.uid == currentUID }.map { ($0.pid, $0.path) }
    }

    /// ps의 조회 실패도 드러낸다.
    private static func listIMEProcesses() -> Result<[IMEProcess], Error> {
        let task = Process(); let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps"); task.arguments = ["-axo", "pid=,uid=,comm="]
        task.standardOutput = out; task.standardError = FileHandle.nullDevice
        do {
            try task.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            guard task.terminationStatus == 0, let value = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "RemovalObservation", code: 1)
            }
            return .success(parseIMEProcesses(value))
        } catch { return .failure(error) }
    }

    /// bundle ID만 같은 다른 실행본은 자동 종료하지 않는다.
    static func imeProcesses() -> Result<[(pid_t, String)], Error> {
        listIMEProcesses().map { ownIMEProcesses($0, currentUID: getuid()) }
    }

    /// 실제 프로세스 대신 시험에서 바꿔 끼우는 경계. `signal`은 kill(2)의 errno(성공이면 0)를 돌려준다.
    struct ProcessControl {
        var list: () -> Result<[(pid_t, String)], Error> = { imeProcesses() }
        var signal: (pid_t, Int32) -> Int32 = { kill($0, $1) == 0 ? 0 : errno }
        var pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    }

    static func stopIMEProcesses(control: ProcessControl = ProcessControl()) -> RemovalState {
        let processes: [(pid_t, String)]
        switch control.list() {
        case .failure: return .unknown("입력기 프로세스 목록을 읽지 못했어요")
        case .success(let found): processes = found
        }
        let allowed = [userIME, systemIME].map { $0.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM").path }
        guard processes.allSatisfy({ allowed.contains($0.1) && $0.0 != getpid() }) else {
            return .preserved("다른 위치의 입력기 실행본을 종료한 뒤 다시 시도해 주세요")
        }
        for (pid, _) in processes where control.signal(pid, SIGTERM) == EPERM {
            // 2026-11-07 (#176): 다른 계정 것은 위에서 걸렀으니 드문 경로다. 기다려도 소용없으니 이유를 바로 말한다.
            return .preserved("입력기 실행본을 종료할 권한이 없어요. 그 실행본을 띄운 계정에서 로그아웃한 뒤 다시 시도해 주세요")
        }
        for _ in 0..<20 {
            if processes.allSatisfy({ control.signal($0.0, 0) == ESRCH }) { break }
            control.pause(0.05)
        }
        // PID 재사용을 피하기 위해 강제 종료 직전에 실행 경로를 다시 대조한다.
        if case .success(let survivors) = control.list() {
            for (pid, path) in survivors where processes.contains(where: { $0.0 == pid && $0.1 == path }) { _ = control.signal(pid, SIGKILL) }
        }
        for _ in 0..<10 {
            switch control.list() {
            case .failure: return .unknown("실행 종료를 재확인하지 못했어요")
            case .success(let remaining):
                if remaining.isEmpty { return processes.isEmpty ? .alreadyAbsent : .removed }
            }
            control.pause(0.05)
        }
        return .failed("입력기 실행이 남아 있어요. 종료한 뒤 다시 시도해 주세요")
    }

    /// 2026-11-07 (#176): 시스템 영역 입력기를 다른 계정이 쓰는 중이면 이 계정에서는 종료할 수 없다(kill EPERM).
    /// 제거를 막지는 않되 그 계정의 입력기가 언제 끝나는지 알린다. 다른 계정 자기 폴더의 입력기는 우리가 지우지 않으니 알리지 않는다.
    static func otherAccountNotice(_ all: [IMEProcess], currentUID: uid_t, removingSystemIME: Bool) -> RemovalState? {
        guard removingSystemIME else { return nil }
        let systemPath = systemIME.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM").path
        guard all.contains(where: { $0.uid != currentUID && $0.path == systemPath }) else { return nil }
        return .needsUserAction("다른 계정에서 이 입력기를 쓰고 있어요. 이 계정에서는 종료할 수 없으니 그 계정에서 로그아웃하면 끝나요")
    }

    /// 조회에 실패하면 알리지 않는다. 실패 자체는 `stopIMEProcesses`가 먼저 드러낸다.
    static func otherAccountNotice(removingSystemIME: Bool) -> RemovalState? {
        guard case .success(let all) = listIMEProcesses() else { return nil }
        return otherAccountNotice(all, currentUID: getuid(), removingSystemIME: removingSystemIME)
    }

    @MainActor static func otherMainInstance() -> RemovalState {
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainID).contains(where: { $0.processIdentifier != getpid() && !$0.isTerminated }) {
            return .preserved("다른 하늘키보드 앱을 종료한 뒤 다시 시도해 주세요")
        }
        return .verified
    }

    /// 별도 defaults 프로세스의 export를 사용해 영구 저장 상태를 다시 읽는다.
    static func storedPreferences(_ domain: String, preferencesDirectory: URL? = nil) -> Result<[String: Any], Error> {
        // CFPreferences가 손상된 파일을 빈 도메인처럼 돌려주는 경우를 성공으로 숨기지 않는다.
        let directory = preferencesDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let plist = directory.appendingPathComponent((domain == "NSGlobalDomain" ? ".GlobalPreferences" : domain) + ".plist")
        let safe = pathSafety(plist)
        guard safe.reachedGoal else { return .failure(NSError(domain: "RemovalObservation.Preferences.Path", code: 1)) }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: plist.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) is [String: Any] else {
                return .failure(NSError(domain: "RemovalObservation.Preferences.Plist", code: 1))
            }
        } catch { if !isMissing(error) { return .failure(error) } }
        let task = Process(); let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults"); task.arguments = ["export", domain, "-"]
        task.standardOutput = out; task.standardError = FileHandle.nullDevice
        do {
            try task.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            guard task.terminationStatus == 0, let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw NSError(domain: "RemovalObservation.Preferences", code: Int(task.terminationStatus))
            }
            return .success(dict)
        } catch { return .failure(error) }
    }
    static func clearProductSettings(mainDomain: String = mainID, inputDomain: String = imeID,
                                     globalDomain: String = "NSGlobalDomain", supportURL: URL? = nil) -> RemovalState {
        let support = supportURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HaneulKeyboard")
        let safe = pathSafety(support)
        guard safe.reachedGoal else { return safe }
        var hasSupport = false
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: support.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else { return .preserved("설정 디렉터리가 제품 폴더가 아니에요: \(support.path)") }
            hasSupport = true
        } catch { if !isMissing(error) { return .unknown("설정 폴더를 읽지 못했어요: \(support.path)") } }
        // 어느 도메인이든 읽기 실패면 쓰기를 시작하지 않는다. 없는 도메인은 export의 빈 plist로 확인한다.
        var originals: [(String, [String: Any])] = []
        for domain in [mainDomain, inputDomain, globalDomain] {
            guard case .success(let original) = storedPreferences(domain) else { return .unknown("삭제 전 설정을 읽지 못했어요: \(domain)") }
            originals.append((domain, original))
        }
        var changed = hasSupport
        for (name, original) in originals {
            let cfDomain = name == "NSGlobalDomain" ? kCFPreferencesAnyApplication : name as CFString
            let keys = original.keys.filter { name != globalDomain || $0.hasPrefix("haneul.") }
            changed = changed || !keys.isEmpty
            for key in keys { CFPreferencesSetValue(key as CFString, nil, cfDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) }
            guard CFPreferencesSynchronize(cfDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                return .failed("개인 설정의 저장 상태를 정리하지 못했어요")
            }
            guard case .success(let remaining) = storedPreferences(name) else { return .unknown("설정 정리를 재확인하지 못했어요") }
            guard !remaining.keys.contains(where: { name != globalDomain || $0.hasPrefix("haneul.") }) else {
                return .failed("개인 설정이 남아 있어요. 이 앱에서 전체 제거를 다시 시도해 주세요")
            }
            if name == globalDomain {
                let unrelated = original.filter { !$0.key.hasPrefix("haneul.") }
                guard NSDictionary(dictionary: unrelated).isEqual(to: remaining.filter { !$0.key.hasPrefix("haneul.") }) else {
                    return .unknown("다른 전역 설정이 바뀌어 정리 확인을 중단했어요")
                }
            }
        }
        if hasSupport {
            let safe = pathSafety(support)
            guard safe.reachedGoal else { return safe }
            do {
                try FileManager.default.removeItem(at: support)
                guard absence(at: support) == .alreadyAbsent else { return .failed("기존 설정 디렉터리가 남아 있어요") }
            } catch { return .failed("개인 설정 키는 정리됐지만 옛 설정 폴더를 지우지 못했어요: \(support.path)") }
        }
        return changed ? .removed : .alreadyAbsent
    }
}

import AppKit
import Carbon
import CoreServices
import Foundation
import Darwin

struct RemovalTarget: Sendable {
    let url: URL
    let identifier: String
    let fileNumber: UInt64
    let device: UInt64
}

struct RemovalCancelled: LocalizedError {
    var errorDescription: String? { "관리자 권한 요청을 취소했어요" }
}

/// 2026-10-11: 같은 정책을 쓰되 실제 OS 관측 오류는 숨기지 않는다.
enum RemovalObservation {
    static let mainID = "com.hyunjincho.haneulkeyboard"
    static let imeID = "com.hyunjincho.inputmethod.haneul"
    static let userIME = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/HaneulKeyboardIM.app")
    static let systemIME = URL(fileURLWithPath: "/Library/Input Methods/HaneulKeyboardIM.app")
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

    static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
            || error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }
    static func absence(at url: URL) -> RemovalState {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return .failed("파일이 남아 있어요: \(url.path)") }
        catch { return isMissing(error) ? .alreadyAbsent : .unknown("경로를 읽지 못했어요: \(url.path)") }
    }

    static func pathSafety(_ url: URL) -> RemovalState {
        var current = url
        while current.path != "/" {
            do {
                if try FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType == .typeSymbolicLink {
                    return .preserved("연결된 경로는 자동으로 지우지 않아요: \(current.path)")
                }
            } catch { if !isMissing(error) { return .unknown("경로를 읽지 못했어요: \(current.path)") } }
            current.deleteLastPathComponent()
        }
        return .verified
    }

    static func verifyInputMethods(_ urls: [URL] = [userIME, systemIME]) -> [RemovalStep] {
        urls.map { RemovalStep(id: "ime", title: "입력기 파일 부재 재확인", state: absence(at: $0), target: $0.path) }
    }

    /// 끊어진 링크도 존재로 취급하고, 링크 및 조상 링크를 따라 지우지 않는다.
    static func capture(_ url: URL, identifier: String,
                        trust: (URL) -> Bool = { BundleTrust.isSameTeamSignedBundle(at: $0) }) -> (RemovalTarget?, RemovalState) {
        let fm = FileManager.default
        var bundleExists = false
        do {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            bundleExists = true
            guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                return (nil, .preserved("디렉터리 또는 제품 번들이 아니에요: \(url.path)"))
            }
            let safe = pathSafety(url)
            guard safe.reachedGoal else { return (nil, safe) }
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == identifier else {
                return (nil, .preserved("제품 ID가 다르거나 읽을 수 없어요: \(url.path)"))
            }
            guard trust(url) else { return (nil, .preserved("제품 서명이 손상됐거나 Team을 확인하지 못했어요: \(url.path)")) }
            guard let inode = attrs[.systemFileNumber] as? NSNumber, let device = attrs[.systemNumber] as? NSNumber else {
                return (nil, .unknown("파일 식별자를 확인하지 못했어요: \(url.path)"))
            }
            return (RemovalTarget(url: url, identifier: identifier, fileNumber: inode.uint64Value, device: device.uint64Value), .verified)
        } catch {
            return (nil, !bundleExists && isMissing(error) ? .alreadyAbsent : .unknown("제거 대상을 읽지 못했어요: \(url.path)"))
        }
    }

    static func remove(_ target: RemovalTarget, admin: ((RemovalTarget) throws -> Void)? = nil,
                       trust: (URL) -> Bool = { BundleTrust.isSameTeamSignedBundle(at: $0) },
                       removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> RemovalState {
        let (current, state) = capture(target.url, identifier: target.identifier, trust: trust)
        if state == .alreadyAbsent { return state }
        guard let current, state.reachedGoal else { return state }
        guard current.fileNumber == target.fileNumber && current.device == target.device else {
            return .preserved("삭제 직전에 대상이 바뀌었어요: \(target.url.path)")
        }
        // 2026-10-12 #90: removeItem은 일부 내용을 지운 뒤 실패할 수 있다.
        // 재귀 삭제를 권한 검사로 쓰지 않고, 번들 전체를 읽기 전용으로 먼저 확인한다.
        let canRemoveLocally = canRemoveWithoutAdmin(target.url)
        let (latest, latestState) = capture(target.url, identifier: target.identifier, trust: trust)
        if latestState == .alreadyAbsent { return latestState }
        guard let latest, latestState.reachedGoal else { return latestState }
        guard latest.fileNumber == target.fileNumber && latest.device == target.device else {
            return .preserved("권한 확인 중 제거 대상이 바뀌었어요: \(target.url.path)")
        }
        do {
            if canRemoveLocally {
                // 권한은 검사 뒤에도 바뀔 수 있다. 실제 삭제가 실패하면 그대로 실패로
                // 보고하고, 이미 변경됐을 수 있는 번들로 관리자 인증을 다시 요청하지 않는다.
                try removeItem(target.url)
            } else {
                guard let admin else { return .preserved("제거 권한이 없어 파일을 보존했어요: \(target.url.path)") }
                try admin(target)
            }
            let remaining = absence(at: target.url)
            return remaining == .alreadyAbsent ? .removed : remaining
        } catch is RemovalCancelled { return .cancelled("관리자 권한 요청을 취소했어요") }
        catch { return .failed("삭제하지 못했어요: \(target.url.path) (\(error.localizedDescription))") }
    }

    /// 권한 조회는 삭제 성공의 보장이 아니라 실행 경로 선택이다. 링크의 대상은 순회하지 않는다.
    private static func canRemoveWithoutAdmin(_ url: URL) -> Bool {
        let fm = FileManager.default
        func writableDirectory(_ directory: URL) -> Bool {
            fm.isWritableFile(atPath: directory.path) && fm.isExecutableFile(atPath: directory.path)
        }
        func canRemoveEntry(_ item: URL) -> Bool {
            guard writableDirectory(item.deletingLastPathComponent()), fm.isDeletableFile(atPath: item.path),
                  let attributes = try? fm.attributesOfItem(atPath: item.path) else { return false }
            if attributes[.type] as? FileAttributeType == .typeDirectory {
                return writableDirectory(item) && fm.isReadableFile(atPath: item.path)
            }
            return true
        }
        guard canRemoveEntry(url) else { return false }
        var unreadable = false
        guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            unreadable = true
            return false
        }) else { return false }
        for case let item as URL in entries {
            guard canRemoveEntry(item) else { return false }
        }
        return !unreadable
    }

    enum Registration {
        case paths([URL]), unknown(String)
    }
    /// deprecated API를 사용해 오류를 함께 얻는다. NSWorkspace의 빈 배열과 조회 실패를 구분한다.
    static func registrations(for identifier: String) -> Registration {
        var error: Unmanaged<CFError>?
        if let list = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, &error)?.takeRetainedValue() as? [URL] {
            return .paths(list.map(\.standardizedFileURL))
        }
        if let error = error?.takeRetainedValue() {
            let code = CFErrorGetCode(error)
            if code == Int(kLSApplicationNotFoundErr) { return .paths([]) }
            return .unknown("앱 등록을 조회하지 못했어요 (\(code))")
        }
        return .unknown("앱 등록 조회가 결과 없이 끝났어요")
    }
    static func unregister(_ urls: [URL], identifier: String) -> RemovalState {
        var removed = false
        for url in urls {
            switch registrations(for: identifier) {
            case .unknown(let reason): return .unknown(reason)
            case .paths(let paths):
                guard paths.contains(url.standardizedFileURL) else { continue }
            }
            let task = Process(); let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: lsregister); task.arguments = ["-u", url.path]
            task.standardOutput = pipe; task.standardError = pipe
            do {
                try task.run(); _ = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            } catch { return .failed("시스템 등록 해제 명령을 실행하지 못했어요") }
            switch registrations(for: identifier) {
            case .unknown(let reason): return .unknown(reason)
            case .paths(let paths):
                if paths.contains(url.standardizedFileURL) {
                    return .failed("등록이 남아 있어요: \(url.path) (명령 결과 \(task.terminationStatus))")
                }
                removed = true // nonzero라도 정확한 경로의 부재를 재조회한 경우에만 목표 달성.
            }
        }
        return removed ? .removed : .alreadyAbsent
    }

    @MainActor static func inputSources() -> [TISInputSource]? {
        TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]
    }
    static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let p = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    static func flag(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let p = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
    }
    static func isOurs(_ source: TISInputSource) -> Bool {
        property(source, kTISPropertyBundleID) == imeID || (property(source, kTISPropertyInputSourceID)?.hasPrefix(imeID) ?? false)
    }
    @MainActor static func secureInput() -> RemovalState {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              property(current, kTISPropertyInputSourceID) != nil else { return .unknown("현재 입력 소스를 읽지 못했어요") }
        if isOurs(current) {
            guard let sources = inputSources(), let fallback = sources.first(where: {
                !isOurs($0) && flag($0, kTISPropertyInputSourceIsEnabled) == true && flag($0, kTISPropertyInputSourceIsASCIICapable) == true
            }), TISSelectInputSource(fallback) == noErr,
                  let selected = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), !isOurs(selected) else {
                return .failed("영문 입력 소스로 전환하지 못했어요. 입력 소스에서 영문 자판을 선택한 뒤 다시 시도해 주세요")
            }
        }
        guard let sources = inputSources() else { return .unknown("입력 소스 목록을 조회하지 못했어요") }
        for source in sources where isOurs(source) && flag(source, kTISPropertyInputSourceIsEnabled) == true {
            _ = TISDisableInputSource(source)
        }
        return observeInputSources()
    }
    struct InputSourceSnapshot {
        var id: String?
        var bundleID: String?
        var type: String?
        var enabled: Bool?
        var selected: Bool?
    }

    /// TextInputSources.h: 자식 모드는 자신과 부모가 모두 enabled일 때만 선택 가능하다.
    /// 부모를 끈 뒤에도 남는 자식 enabled 플래그를 실제 활성 입력기로 오인하지 않는다.
    static func inputSourceState(_ sources: [InputSourceSnapshot], currentID: String?) -> RemovalState {
        guard let currentID else { return .unknown("현재 입력 소스를 확인하지 못했어요") }
        guard !currentID.hasPrefix(imeID) else {
            return .needsUserAction("영문이나 다른 입력 소스로 전환한 뒤 다시 시도해 주세요")
        }
        let ours = sources.filter { $0.bundleID == imeID || ($0.id?.hasPrefix(imeID) ?? false) }
        let parents = ours.filter {
            $0.id == imeID && $0.bundleID == imeID
                && $0.type == kTISTypeKeyboardInputMethodModeEnabled as String
        }
        for source in ours {
            guard let enabled = source.enabled else { return .unknown("입력 소스 활성 상태를 확인하지 못했어요") }
            if !enabled { continue }
            if source.id == imeID + ".korean", source.bundleID == imeID,
               source.type == kTISTypeKeyboardInputMode as String,
               source.selected == false, parents.count == 1, parents[0].enabled == false {
                continue
            }
            return .needsUserAction("시스템 설정 → 키보드 → 입력 소스에서 하늘키보드를 제거한 뒤 다시 시도해 주세요")
        }
        return ours.isEmpty ? .alreadyAbsent : .verified
    }

    @MainActor static func observeInputSources() -> RemovalState {
        guard let sources = inputSources() else { return .unknown("입력 소스 목록을 조회하지 못했어요") }
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let snapshots = sources.map {
            InputSourceSnapshot(id: property($0, kTISPropertyInputSourceID),
                bundleID: property($0, kTISPropertyBundleID), type: property($0, kTISPropertyInputSourceType),
                enabled: flag($0, kTISPropertyInputSourceIsEnabled), selected: flag($0, kTISPropertyInputSourceIsSelected))
        }
        return inputSourceState(snapshots, currentID: current.flatMap { property($0, kTISPropertyInputSourceID) })
    }

    /// ps의 조회 실패도 드러내고, bundle ID만 같은 다른 실행본은 자동 종료하지 않는다.
    static func imeProcesses() -> Result<[(pid_t, String)], Error> {
        let task = Process(); let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps"); task.arguments = ["-axo", "pid=,comm="]
        task.standardOutput = out; task.standardError = FileHandle.nullDevice
        do {
            try task.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            guard task.terminationStatus == 0, let value = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "RemovalObservation", code: 1)
            }
            let matches = value.split(separator: "\n").compactMap { line -> (pid_t, String)? in
                let pieces = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard pieces.count == 2, let pid = pid_t(pieces[0]) else { return nil }
                let executable = String(pieces[1])
                return URL(fileURLWithPath: executable).lastPathComponent == "HaneulKeyboardIM" ? (pid, executable) : nil
            }
            return .success(matches)
        } catch { return .failure(error) }
    }
    static func stopIMEProcesses() -> RemovalState {
        let processes: [(pid_t, String)]
        switch imeProcesses() {
        case .failure: return .unknown("입력기 프로세스 목록을 읽지 못했어요")
        case .success(let found): processes = found
        }
        let allowed = [userIME, systemIME].map { $0.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM").path }
        guard processes.allSatisfy({ allowed.contains($0.1) && $0.0 != getpid() }) else {
            return .preserved("다른 위치의 입력기 실행본을 종료한 뒤 다시 시도해 주세요")
        }
        for (pid, _) in processes { _ = kill(pid, SIGTERM) }
        for _ in 0..<20 {
            if processes.allSatisfy({ kill($0.0, 0) != 0 && errno == ESRCH }) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // PID 재사용을 피하기 위해 강제 종료 직전에 실행 경로를 다시 대조한다.
        if case .success(let survivors) = imeProcesses() {
            for (pid, path) in survivors where processes.contains(where: { $0.0 == pid && $0.1 == path }) { _ = kill(pid, SIGKILL) }
        }
        for _ in 0..<10 {
            switch imeProcesses() {
            case .failure: return .unknown("실행 종료를 재확인하지 못했어요")
            case .success(let remaining):
                if remaining.isEmpty { return processes.isEmpty ? .alreadyAbsent : .removed }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return .failed("입력기 실행이 남아 있어요. 종료한 뒤 다시 시도해 주세요")
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

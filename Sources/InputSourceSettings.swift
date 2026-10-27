import AppKit
import Darwin
import Foundation

/// 2026-10-12 (#92): macOS 26/27의 키보드 설정은 등록 API와 별도의 입력기 목록 캐시를 쓴다.
/// 실제 재현: TIS/타사 저장 목록에는 하늘이 있지만 오래된 kbdx에는 없어서 설정창에서 누락.
/// 입력기·Apple 설정은 건드리지 않고, 현재 사용자의 정확한 생성 캐시 파일만 갱신한다.
enum InputSourceSettingsCache {
    static let directoryName = "com.apple.Keyboard-Settings.extension"
    static let fileName = "com.apple.IntlDataCache.le.kbdx"
    static let inputMethodID = "com.hyunjincho.inputmethod.haneul"
    enum State: Sendable { case absent, current, stale }
    private struct Identity: Equatable {
        let inode: UInt64, device: UInt64, size: Int
        let modified: Date
    }

    static func systemURL() throws -> URL {
        let count = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard count > 1, count < 16_384 else { throw RefreshError.unsafeCache }
        var buffer = [CChar](repeating: 0, count: count)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, count) == count else { throw RefreshError.unsafeCache }
        return try cacheURL(systemDirectory: String(cString: buffer))
    }

    /// 2026-10-18: Foundation은 /private/var를 다시 /var로 줄여 반환한다.
    /// OS가 준 루트만 POSIX 실제 경로로 바꾸고, 그 아래 연결 경로는 기존 검사로 차단한다.
    static func cacheURL(systemDirectory: String) throws -> URL {
        guard let resolved = realpath(systemDirectory, nil) else { throw RefreshError.unsafeCache }
        defer { free(resolved) }
        let base = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        return base.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(fileName)
    }

    private static func capture(_ url: URL) throws -> Identity? {
        guard url.lastPathComponent == fileName, url.deletingLastPathComponent().lastPathComponent == directoryName,
              RemovalObservation.pathSafety(url) == .verified else { throw RefreshError.unsafeCache }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let inode = attrs[.systemFileNumber] as? NSNumber,
                  let device = attrs[.systemNumber] as? NSNumber,
                  let size = attrs[.size] as? NSNumber, size.intValue <= 16_777_216,
                  let modified = attrs[.modificationDate] as? Date else { throw RefreshError.unsafeCache }
            return Identity(inode: inode.uint64Value, device: device.uint64Value, size: size.intValue, modified: modified)
        } catch {
            if RemovalObservation.isMissing(error) { return nil }
            throw error
        }
    }

    private static func containsInputMethod(_ data: Data) -> Bool {
        data.range(of: Data(inputMethodID.utf8)) != nil
            || inputMethodID.data(using: .utf16LittleEndian).map { data.range(of: $0) != nil } == true
    }

    static func state(at url: URL) throws -> State {
        guard let before = try capture(url) else { return .absent }
        let data = try Data(contentsOf: url)
        guard try capture(url) == before else { throw RefreshError.cacheChanged }
        return containsInputMethod(data) ? .current : .stale
    }

    @discardableResult static func invalidateIfStale(at url: URL) throws -> Bool {
        guard let before = try capture(url) else { return false }
        let data = try Data(contentsOf: url)
        guard !containsInputMethod(data) else { return false }
        guard try capture(url) == before else { throw RefreshError.cacheChanged }
        try FileManager.default.removeItem(at: url)
        guard try capture(url) == nil else { throw RefreshError.cacheChanged }
        return true
    }

    enum RefreshError: LocalizedError {
        case unsafeCache, cacheChanged, settingsBusy, openFailed
        var errorDescription: String? {
            switch self {
            case .unsafeCache, .cacheChanged:
                "키보드 설정의 입력기 목록을 안전하게 새로고치지 못했어요. 로그아웃 후 다시 확인해 주세요."
            case .settingsBusy:
                "시스템 설정이 닫히지 않았어요. 시스템 설정을 ⌘Q로 종료한 뒤 ‘키보드 설정 열기’를 다시 눌러 주세요."
            case .openFailed:
                "키보드 설정을 열지 못했어요. 시스템 설정 → 키보드 → 텍스트 입력을 열어 주세요."
            }
        }
    }
}

@MainActor enum InputSourceSettings {
    private static let settingsID = "com.apple.systempreferences"
    private static let pendingKey = "haneul.inputSourceSettingsNeedsReload"
    private static var isOpening = false

    /// 새 설치뿐 아니라 등록된 입력기의 시작 시 복구에도 적용한다. 이미 최신인 목록은 보존한다.
    static func refreshAfterRegistration() async -> String? {
        guard #available(macOS 26.0, *) else { return nil }
        do {
            let changed = try await Task.detached(priority: .utility) {
                try InputSourceSettingsCache.invalidateIfStale(at: InputSourceSettingsCache.systemURL())
            }.value
            if changed && !NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).isEmpty {
                UserDefaults.standard.set(true, forKey: pendingKey)
            }
            return nil
        } catch {
            haneulLog("HaneulKeyboard: input-source settings refresh failed — \(error.localizedDescription)")
            return "입력기는 준비됐지만 설정 목록 갱신을 마치지 못했어요. \(error.localizedDescription)"
        }
    }

    /// 사용자가 설정 열기를 눌렀을 때만 오래된 설정창을 정상 종료하고 다시 연다. 강제 종료하지 않는다.
    static func open(refreshInputMethodList: Bool) async throws {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        if #available(macOS 26.0, *), refreshInputMethodList {
            let stale = try await Task.detached(priority: .utility) {
                try InputSourceSettingsCache.state(at: InputSourceSettingsCache.systemURL()) == .stale
            }.value
            if stale || UserDefaults.standard.bool(forKey: pendingKey) {
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: settingsID)
                for application in running where !application.isTerminated {
                    guard application.terminate() else { throw InputSourceSettingsCache.RefreshError.settingsBusy }
                }
                for _ in 0..<30 {
                    if running.allSatisfy(\.isTerminated) { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard running.allSatisfy(\.isTerminated) else { throw InputSourceSettingsCache.RefreshError.settingsBusy }
                _ = try await Task.detached(priority: .utility) {
                    try InputSourceSettingsCache.invalidateIfStale(at: InputSourceSettingsCache.systemURL())
                }.value
                UserDefaults.standard.removeObject(forKey: pendingKey)
            }
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Text"),
              NSWorkspace.shared.open(url) else { throw InputSourceSettingsCache.RefreshError.openFailed }
    }
}

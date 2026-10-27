import Foundation

/// 오래된 설정 목록은 갱신하되 개인 데이터·최신 캐시·연결된 경로는 보존한다.
enum InputSourceSettingsTests {
    static func run(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".tmp/InputSourceSettingsTests-\(UUID().uuidString)")
        let directory = root.appendingPathComponent(InputSourceSettingsCache.directoryName)
        let cache = directory.appendingPathComponent(InputSourceSettingsCache.fileName)
        defer { try? fm.removeItem(at: root) }
        do {
            let systemCache = try InputSourceSettingsCache.systemURL()
            check(RemovalObservation.pathSafety(systemCache) == .verified,
                  "입력기 목록: macOS /var 별칭은 실제 경로로 계산해 정상 캐시를 거부하지 않음")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let personal = root.appendingPathComponent("personalDictionary.json")
            let savedSources = directory.appendingPathComponent("AppleEnabledThirdPartyInputSources.plist")
            let unrelated = Data("preserve my settings".utf8)
            try unrelated.write(to: personal)
            try unrelated.write(to: savedSources)
            check(try InputSourceSettingsCache.state(at: cache) == .absent, "입력기 목록: 생성 전 캐시는 없음으로 구분")
            check(try !InputSourceSettingsCache.invalidateIfStale(at: cache), "입력기 목록: 없는 캐시를 만들거나 삭제하지 않음")

            try Data("old list without Haneul".utf8).write(to: cache)
            check(try InputSourceSettingsCache.state(at: cache) == .stale, "입력기 목록: 입력기 ID가 없는 오래된 목록 확인")
            check(try InputSourceSettingsCache.invalidateIfStale(at: cache) && !fm.fileExists(atPath: cache.path), "입력기 목록: 생성 캐시 한 파일만 갱신")
            check(try Data(contentsOf: personal) == unrelated && Data(contentsOf: savedSources) == unrelated,
                  "입력기 목록: 개인 사전와 실제 입력 소스 저장 목록 보존")

            for encoding in [String.Encoding.utf8, .utf16LittleEndian] {
                let data = InputSourceSettingsCache.inputMethodID.data(using: encoding)!
                try data.write(to: cache)
                check(try InputSourceSettingsCache.state(at: cache) == .current, "입력기 목록: 최신 \(encoding.rawValue) 캐시 식별")
                check(try !InputSourceSettingsCache.invalidateIfStale(at: cache) && Data(contentsOf: cache) == data,
                      "입력기 목록: 최신 \(encoding.rawValue) 캐시를 반복 삭제하지 않음")
            }

            try fm.removeItem(at: cache)
            try fm.createSymbolicLink(at: cache, withDestinationURL: personal)
            expectPreserved(cache, check: check, name: "대상 링크")
            check(try Data(contentsOf: personal) == unrelated, "입력기 목록: 링크 대상 개인 데이터 보존")
            try fm.removeItem(at: cache)
            try fm.createDirectory(at: cache, withIntermediateDirectories: false)
            expectPreserved(cache, check: check, name: "예상 밖 디렉터리")
            try fm.removeItem(at: cache)

            let actual = root.appendingPathComponent("actual")
            try fm.createDirectory(at: actual, withIntermediateDirectories: true)
            let linkedCache = actual.appendingPathComponent(InputSourceSettingsCache.fileName)
            try Data("stale cache".utf8).write(to: linkedCache)
            try fm.removeItem(at: directory)
            try fm.createSymbolicLink(at: directory, withDestinationURL: actual)
            expectPreserved(cache, check: check, name: "조상 링크")
            check(fm.fileExists(atPath: linkedCache.path), "입력기 목록: 조상 링크 너머의 파일 보존")

            let unexpected = root.appendingPathComponent("user-preferences.plist")
            try unrelated.write(to: unexpected)
            expectPreserved(unexpected, check: check, name: "허용 범위 밖 파일")
            check(try Data(contentsOf: unexpected) == unrelated, "입력기 목록: 정확한 캐시 이름 외 파일 보존")
        } catch { check(false, "입력기 목록 fixture 실행 실패: \(error)") }
    }

    private static func expectPreserved(_ url: URL, check: (Bool, String) -> Void, name: String) {
        do { _ = try InputSourceSettingsCache.invalidateIfStale(at: url); check(false, "입력기 목록: \(name) 차단") }
        catch { check(true, "입력기 목록: \(name) 차단") }
    }
}

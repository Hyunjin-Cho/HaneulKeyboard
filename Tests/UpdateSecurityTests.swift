import Foundation

/// 실제 URLSession delegate 경로에 여러 청크/헤더/취소/리다이렉트를 주입한다.
final class TransferStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var chunks: [Data] = [Data([1, 2, 3, 4])]
        var length: Int? = nil
        var redirect: URL? = nil
        var failure: Bool = false
        var hold: Bool = false
    }
    private static let lock = NSLock()
    private static var reply = Reply()
    private static var emitted = 0
    private static var started = 0
    private let state = NSLock()
    private var stopped = false
    static var chunksSent: Int { lock.withLock { emitted } }
    static var requests: Int { lock.withLock { started } }
    static func set(_ value: Reply) { lock.withLock { reply = value; emitted = 0; started = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock { Self.started += 1; return Self.reply }
        if reply.hold { return }
        if let target = reply.redirect, request.url!.path != "/target" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }
        let headers = reply.length.map { ["Content-Length": String($0)] }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        send(reply, index: 0)
    }
    private func send(_ reply: Reply, index: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in
            guard !state.withLock({ stopped }) else { return }
            if index < reply.chunks.count {
                Self.lock.withLock { Self.emitted += 1 }
                client?.urlProtocol(self, didLoad: reply.chunks[index])
                send(reply, index: index + 1)
            } else if reply.failure {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() { state.withLock { stopped = true } }
}

@MainActor enum UpdateSecurityTests {
    static func run(_ check: (Bool, String) -> Void) async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransferStub.self]
        config.timeoutIntervalForResource = 2
        let request = URLRequest(url: URL(string: "https://api.github.com/test")!)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("update.zip")
        let chunk = Data([1, 2, 3, 4])
        func receive(limit: Int = 8, destination: URL? = nil) async throws -> (Data, HTTPURLResponse) {
            try await UpdateTransport.receive(request, configuration: config, limit: limit, destination: destination)
        }
        for length in [nil, 8] as [Int?] {
            TransferStub.set(.init(chunks: [chunk, chunk], length: length))
            do {
                let result = try await receive()
                check(result.0 == chunk + chunk && result.1.statusCode == 200, "JSON 정확한 한도 허용 (length=\(String(describing: length)))")
            } catch { check(false, "정상 JSON: \(error)") }
        }
        let streamChunk = Data(repeating: 1, count: 64 * 1024)
        let streamLimit = 128 * 1024
        for length in [nil, 64 * 1024, 1024 * 1024] as [Int?] {
            for disk in [false, true] {
                TransferStub.set(.init(chunks: Array(repeating: streamChunk, count: 40), length: length))
                do {
                    _ = try await receive(limit: streamLimit, destination: disk ? file : nil)
                    check(false, "상한 초과 거부")
                } catch UpdateError.responseTooLarge(let limit) {
                    check(limit == streamLimit, "헤더/실수신 상한 초과 거부 (length=\(String(describing: length)), disk=\(disk))")
                } catch { check(false, "상한 초과 오류 종류: \(error)") }
                check(!FileManager.default.fileExists(atPath: file.path), "실패한 부분 파일 삭제")
                check(TransferStub.chunksSent < 40, "전체 응답 전 수신 중단")
            }
        }
        TransferStub.set(.init(chunks: [chunk, chunk], length: 8))
        do {
            let result = try await receive(destination: file)
            check(result.0.isEmpty && (try? Data(contentsOf: file)) == chunk + chunk, "ZIP은 메모리 대신 파일로 저장")
            let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) as? Int
            check(mode == 0o600, "임시 ZIP 사용자 전용 권한")
        } catch { check(false, "정상 ZIP: \(error)") }
        do { _ = try await receive(destination: file); check(false, "기존 파일 거부") }
        catch { check((try? Data(contentsOf: file)) == chunk + chunk, "기존 파일 보존") }
        try? FileManager.default.removeItem(at: file)
        TransferStub.set(.init(chunks: [chunk], failure: true))
        do { _ = try await receive(destination: file); check(false, "네트워크 오류 전달") }
        catch { check(!FileManager.default.fileExists(atPath: file.path), "통신 실패 후 부분 파일 정리") }

        TransferStub.set(.init(hold: true))
        let pending = Task { try await receive(destination: file) }
        for _ in 0..<200 where TransferStub.requests == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        check(TransferStub.requests == 1, "취소 테스트 실제 요청 시작")
        pending.cancel()
        do { _ = try await pending.value; check(false, "진행 중 취소 전달") }
        catch is CancellationError { check(!FileManager.default.fileExists(atPath: file.path), "취소 시 파일 정리") }
        catch { check(false, "취소 오류 종류: \(error)") }
        for _ in 0..<20 {
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await receive(destination: file)
            }
            do { _ = try await cancelled.value; check(false, "시작 직전 취소") }
            catch is CancellationError { check(!FileManager.default.fileExists(atPath: file.path), "시작 직전 취소 안전") }
            catch { check(false, "시작 직전 취소 오류: \(error)") }
        }
        for address in ["http://api.github.com/test", "https://example.com/test"] {
            do {
                _ = try await UpdateTransport.receive(URLRequest(url: URL(string: address)!), configuration: config, limit: 8)
                check(false, "허용 외 주소 거절")
            } catch UpdateError.redirectBlocked { check(true, "허용 외 주소 거절") }
            catch { check(false, "주소 오류 종류: \(error)") }
        }
        for target in ["https://release-assets.githubusercontent.com/target", "https://example.com/target", "http://github.com/target"] {
            TransferStub.set(.init(redirect: URL(string: target)!))
            do {
                let result = try await receive()
                check(target.hasPrefix("https://release-assets.") && result.0 == chunk, "허용 HTTPS 리다이렉트")
            } catch UpdateError.redirectBlocked {
                check(!target.hasPrefix("https://release-assets."), "외부/HTTP 리다이렉트 거절")
            } catch { check(false, "리다이렉트 오류: \(error)") }
        }

        // 실제 Updater의 실패 상태/마지막 성공 정보 보존도 확인한다.
        let suite = "haneul.security-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = Date(timeIntervalSince1970: 1)
        defaults.set(previous, forKey: Updater.lastCheckKey)
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let updater = Updater(defaults: defaults, session: session)
        var notices = 0
        updater.onUpdateAvailable = { _ in notices += 1 }
        TransferStub.set(.init(chunks: [Data(repeating: 0, count: UpdateDecision.maxReleaseMetadataBytes + 1)]))
        await updater.checkNow()
        if case .failed = updater.phase { check(true, "Updater 초과 응답 실패 표시") }
        else { check(false, "Updater 초과 응답 실패 표시") }
        check(updater.lastCheck == previous && notices == 0, "초과 응답은 성공 기록/알림 갱신 안 함")
        let release: [String: Any] = [
            "tag_name": "2099.99", "draft": false, "prerelease": false,
            "html_url": "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/2099.99",
            "assets": [["name": "HaneulKeyboard_2099.99.zip", "size": 100,
                        "browser_download_url": "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/2099.99/HaneulKeyboard_2099.99.zip"]]
        ]
        TransferStub.set(.init(chunks: [try! JSONSerialization.data(withJSONObject: release)]))
        await updater.checkNow()
        check(updater.latestVersion == "2099.99" && notices == 1, "크기 초과 실패 뒤 정상 확인/알림 복구")

        check(!BundleTrust.allowsUnsignedDevelopment(defaults: defaults), "Debug도 기본 서명 검사")
        defaults.set("owner/test", forKey: Updater.repositoryOverrideKey)
        check(Updater.repository(defaults: defaults) == UpdateDecision.defaultRepository, "추가 허용 없는 저장소 override 무시")
        defaults.set(true, forKey: Updater.allowUnofficialRepositoryKey)
        defaults.set(true, forKey: BundleTrust.debugSkipTeamCheckKey)
        #if DEBUG
        check(BundleTrust.allowsUnsignedDevelopment(defaults: defaults), "Debug 명시 허용 시에만 검사 생략")
        check(Updater.repository(defaults: defaults) == "owner/test", "Debug 명시 허용 시 시험 저장소")
        #else
        check(!BundleTrust.allowsUnsignedDevelopment(defaults: defaults), "Release는 검사 생략 설정 무시")
        check(Updater.repository(defaults: defaults) == UpdateDecision.defaultRepository, "Release는 저장소 설정 모두 무시")
        #endif
        defaults.set("bad/repo/path", forKey: Updater.repositoryOverrideKey)
        check(Updater.repository(defaults: defaults) == UpdateDecision.defaultRepository, "허용해도 잘못된 저장소 거절")
        defaults.set(false, forKey: BundleTrust.debugSkipTeamCheckKey)
        check(BundleTrust.requirement(for: "6RH6FXY82P") != nil, "Apple Team requirement 컴파일")
        for team in ["", "short", "6RH6FXY82P\" or true", "6rh6fxy82p"] {
            check(BundleTrust.requirement(for: team) == nil, "잘못된 Team/requirement 주입 거절")
        }
        check(!BundleTrust.isAppleSignedBundle(at: directory, matchingTeam: "6RH6FXY82P"), "서명 없는 후보 거절")
        check(!BundleTrust.isSameTeamSignedBundle(at: directory, host: directory, defaults: defaults), "서명 없는 호스트 거절")
        if let path = ProcessInfo.processInfo.environment["HANEUL_SIGNED_FIXTURE"] {
            let app = URL(fileURLWithPath: path)
            check(BundleTrust.isAppleSignedBundle(at: app, matchingTeam: "6RH6FXY82P"), "실제 Developer ID 앱 허용")
            check(!BundleTrust.isAppleSignedBundle(at: app, matchingTeam: "AAAAAAAAAA"), "다른 Team 거부")
            let ime = app.appendingPathComponent("Contents/Helpers/HaneulKeyboardIM.app")
            check(BundleTrust.isSameTeamSignedBundle(at: ime, host: app, defaults: defaults), "실제 동일 Team 메인 앱/IME 허용")
            check(!BundleTrust.isSameTeamSignedBundle(at: directory, host: app, defaults: defaults), "서명된 호스트도 미서명 IME 거절")
            let damaged = directory.appendingPathComponent("Damaged.app")
            do {
                try FileManager.default.copyItem(at: ime, to: damaged)
                let executable = damaged.appendingPathComponent("Contents/MacOS/HaneulKeyboardIM")
                let handle = try FileHandle(forWritingTo: executable)
                try handle.seek(toOffset: 4096)
                try handle.write(contentsOf: Data(repeating: 0xFF, count: 64))
                try handle.close()
                check(!BundleTrust.isAppleSignedBundle(at: damaged, matchingTeam: "6RH6FXY82P"), "Team이 같아도 훼손된 서명 거절")
            } catch { check(false, "손상 서명 fixture: \(error)") }
        }
    }
}

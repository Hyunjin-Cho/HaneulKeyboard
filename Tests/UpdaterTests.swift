import AppKit
import Foundation

/// 실제 Updater에 응답만 주입한다. 인터넷·다운로드·설치는 실행하지 않는다.
final class UpdateReleaseStub: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var statusCode = 200
    private static var requests = 0
    private static var hold = false
    private static var pending: (() -> Void)?

    static var requestCount: Int { lock.withLock { requests } }
    static var hasPendingResponse: Bool { lock.withLock { pending != nil } }
    static func holdNextResponse() { lock.withLock { hold = true } }
    static func releaseResponse() {
        let completion = lock.withLock { () -> (() -> Void)? in
            hold = false
            let completion = pending
            pending = nil
            return completion
        }
        completion?()
    }
    static func respond(tag: String = "2099.1", asset: Bool = true,
                        draft: Bool = false, prerelease: Bool = false, status: Int = 200) {
        let object: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/tag/\(tag)",
            "assets": asset ? [["name": "HaneulKeyboard_\(tag).zip", "size": 100,
                "browser_download_url": "https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/download/\(tag)/HaneulKeyboard_\(tag).zip"]] : []
        ]
        lock.withLock {
            responseData = try! JSONSerialization.data(withJSONObject: object)
            statusCode = status
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, status) = Self.lock.withLock {
            Self.requests += 1
            return (Self.responseData, Self.statusCode)
        }
        let completion = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        let held = Self.lock.withLock {
            guard Self.hold else { return false }
            Self.pending = completion
            return true
        }
        if !held { completion() }
    }
    override func stopLoading() {}
}

@main @MainActor enum UpdaterTests {
    static var passed = 0
    static var failed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }

    static func main() async {
        let suite = "haneul.updater-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateReleaseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var notices: [String] = []
        var updater = Updater(defaults: defaults, session: session, now: { clock })
        updater.onUpdateAvailable = { notices.append($0.tag) }
        check(updater.autoCheckEnabled, "기본 자동 확인 ON")
        check(updater.latestVersion == nil && updater.lastCheck == nil, "첫 실행 미확인")
        UpdateReleaseStub.respond()
        await updater.checkNow(forced: false)
        check(notices == ["2099.1"], "새 버전 자동 안내")
        check(updater.latestVersion == "2099.1", "최신 버전 표시")
        check(updater.lastCheck == clock, "성공 확인 시각 저장")
        check(defaults.string(forKey: Updater.lastNotifiedVersionKey) == "2099.1", "알린 버전 저장")
        if case .available = updater.phase { check(true, "설치는 시작하지 않고 사용 가능 상태") }
        else { check(false, "설치는 시작하지 않고 사용 가능 상태") }

        let firstCount = UpdateReleaseStub.requestCount
        clock.addTimeInterval(24 * 60 * 60 - 1)
        await updater.checkNow(forced: false)
        check(UpdateReleaseStub.requestCount == firstCount, "24시간 전 요청 없음")
        clock.addTimeInterval(1)
        await updater.checkNow(forced: false)
        check(UpdateReleaseStub.requestCount == firstCount + 1, "24시간 경계에 요청")
        check(notices.count == 1, "같은 버전 자동 알림 반복 없음")

        updater = Updater(defaults: defaults, session: session, now: { clock })
        updater.onUpdateAvailable = { notices.append($0.tag) }
        check(updater.latestVersion == "2099.1" && updater.lastCheck == clock, "재실행 정보 복원")
        clock.addTimeInterval(24 * 60 * 60)
        UpdateReleaseStub.respond(tag: "2099.01")
        await updater.checkNow(forced: false)
        check(notices.count == 1, "재실행·동등한 태그 표기에도 중복 알림 없음")

        updater.setAutoCheckEnabled(false)
        clock.addTimeInterval(24 * 60 * 60)
        let offCount = UpdateReleaseStub.requestCount
        await updater.checkNow(forced: false)
        check(UpdateReleaseStub.requestCount == offCount, "OFF면 요청 없음")
        await updater.checkNow(forced: true)
        check(UpdateReleaseStub.requestCount == offCount + 1 && notices.count == 2,
              "OFF라도 지금 확인하면 요청·안내")
        await updater.checkNow(forced: true)
        check(notices.count == 3, "수동 확인은 같은 버전도 다시 안내")
        check(!Updater(defaults: defaults, session: session).autoCheckEnabled, "OFF 설정 보존")

        updater.setAutoCheckEnabled(true)
        clock.addTimeInterval(24 * 60 * 60)
        UpdateReleaseStub.respond(tag: "2099.2")
        await updater.checkNow(forced: false)
        check(notices.last == "2099.2" && notices.count == 4, "다른 새 버전 다시 안내")

        let successDate = updater.lastCheck
        clock.addTimeInterval(24 * 60 * 60)
        for status in [403, 404, 429, 500] {
            UpdateReleaseStub.respond(status: status)
            await updater.checkNow(forced: false)
            if case .failed = updater.phase { check(true, "HTTP \(status) 실패 표시") }
            else { check(false, "HTTP \(status) 실패 표시") }
            check(updater.lastCheck == successDate && updater.latestVersion == "2099.2",
                  "HTTP \(status) 실패는 마지막 성공 정보 보존")
        }
        check(notices.count == 4, "오류에는 새 버전 안내 없음")
        UpdateReleaseStub.respond(tag: "2099.3")
        await updater.checkNow(forced: false)
        check(notices.last == "2099.3" && notices.count == 5, "실패 뒤 다음 확인에서 정상 복구")

        UpdateReleaseStub.respond(tag: Updater.currentVersion)
        await updater.checkNow()
        check(updater.phase == .upToDate && notices.count == 5, "현재 버전이면 팝업 없음")
        UpdateReleaseStub.respond(tag: "2099.4", asset: false)
        await updater.checkNow()
        check(updater.latestVersion == "2099.4" && notices.count == 5, "설치 파일 없으면 팝업 없음")
        if case .failed = updater.phase { check(true, "더 새 태그만 있으면 최신이라고 오표시하지 않음") }
        else { check(false, "더 새 태그만 있으면 최신이라고 오표시하지 않음") }

        for flags in [(true, false), (false, true)] {
            UpdateReleaseStub.respond(draft: flags.0, prerelease: flags.1)
            await updater.checkNow()
            if case .failed = updater.phase { check(true, "초안/사전 배포 거절") }
            else { check(false, "초안/사전 배포 거절") }
        }
        UpdateReleaseStub.respond(tag: "bad-tag")
        await updater.checkNow()
        check(updater.latestVersion == "2099.4" && notices.count == 5, "잘못된 버전으로 캐시/알림 갱신 안 함")

        defaults.removeObject(forKey: Updater.lastNotifiedVersionKey)
        defaults.removeObject(forKey: Updater.lastCheckKey)
        updater = Updater(defaults: defaults, session: session, now: { clock })
        UpdateReleaseStub.respond(tag: "2099.5")
        await updater.checkNow(forced: false)
        check(defaults.string(forKey: Updater.lastNotifiedVersionKey) == nil, "창 연결 없으면 알렸다고 기록하지 않음")
        updater.onUpdateAvailable = { notices.append($0.tag) }
        clock.addTimeInterval(24 * 60 * 60)
        await updater.checkNow(forced: false)
        check(notices.last == "2099.5", "창 연결 후 안내 가능")

        // 동시에 호출해도 첫 요청이 완료되기 전에는 두 번째 요청을 시작하지 않는다.
        let countBeforeConcurrent = UpdateReleaseStub.requestCount
        let concurrentUpdater = updater
        UpdateReleaseStub.holdNextResponse()
        let first = Task { await concurrentUpdater.checkNow() }
        while UpdateReleaseStub.requestCount == countBeforeConcurrent { await Task.yield() }
        await concurrentUpdater.checkNow()
        check(UpdateReleaseStub.requestCount == countBeforeConcurrent + 1, "동시 확인 중복 요청 방지")
        // startLoading의 요청 수 증가 직후에도 확인할 수 있으므로 pending 등록까지 양보한다.
        while !UpdateReleaseStub.hasPendingResponse { await Task.yield() }
        UpdateReleaseStub.releaseResponse()
        await first.value
        await UpdateSecurityTests.run { check($0, $1) }
        print("Updater: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

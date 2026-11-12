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

/// 2026-11-13 (#226, 리뷰 install-update-F-5): 시험이 쓰는 설정 도메인은 고정 이름이다. 예전엔 실행마다 UUID 이름을 써서
/// `removePersistentDomain` 뒤에도 남는 빈 plist(42바이트)가 실행 횟수만큼 ~/Library/Preferences에 쌓였고(1,512개),
/// `main`이 `exit()`로 끝나 defer가 돌지 않아 updater 계열 세 도메인은 값이 든 채 남았다. `SlashEnglishTests`(2026-11-07)와 같은 방식이다:
/// 시작할 때 비워 앞서 중단된 실행의 값이 섞이지 않게 하고, 끝날 때 `exit` 앞에서 직접 비운다.
/// 같은 Mac에서 이 시험을 동시에 두 번 돌리지 않는다(두 실행이 같은 도메인을 쓴다).
enum TestPreferenceDomains {
    static let prefix = "com.hyunjincho.haneulkeyboard."
    static let updater = prefix + "updater-tests"
    static let inline = prefix + "updater-inline-tests"
    static let offDuringCheck = prefix + "updater-off-during-check"
    static let security = prefix + "update-security-tests"
    static let removal = [prefix + "removal-tests.main", prefix + "removal-tests.ime", prefix + "removal-tests.global"]
    static var all: [String] { [updater, inline, offDuringCheck, security] + removal }

    /// 지운 뒤 같은 이름으로 새로 만든 저장소를 돌려준다.
    static func fresh(_ name: String) -> UserDefaults {
        clear(name)
        return UserDefaults(suiteName: name)!
    }
    static func clear(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
    static func clearAll() { all.forEach(clear) }
}

/// 2026-11-13 (#226, 리뷰 install-update-F-5): 임시 번들은 현재 폴더의 `.tmp`가 아니라 시스템 임시 폴더의 실제 경로(`/var` → `/private/var`)에 만든다.
/// 저장소 루트가 아닌 곳에서 돌려도 대상 저장소에 흔적을 남기지 않는다. 경로 검사가 조상 링크를 거부하므로 링크를 푼 경로를 쓴다.
func resolvedTemporaryRoot(_ name: String) -> URL? {
    guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else { return nil }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("\(name)-\(UUID().uuidString)")
}

@main @MainActor enum UpdaterTests {
    static var passed = 0
    static var failed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
    }

    static func main() async {
        TestPreferenceDomains.clearAll()
        let suite = TestPreferenceDomains.updater
        let defaults = TestPreferenceDomains.fresh(suite)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateReleaseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        // 2026-11-08 (#201): 자동 확인은 매월 1일 기준이다(예전 24시간). 시간을 '다음 달 1일 0시'로 옮겨 확인할 때를 만든다.
        func nextMonthStart(_ date: Date) -> Date {
            UpdateDecision.checkCalendar.date(byAdding: .month, value: 1,
                to: UpdateDecision.startOfMonth(containing: date))!
        }
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
        clock = nextMonthStart(clock).addingTimeInterval(-1)
        await updater.checkNow(forced: false)
        check(UpdateReleaseStub.requestCount == firstCount, "다음 달 1일 전에는 요청 없음")
        clock.addTimeInterval(1)
        await updater.checkNow(forced: false)
        check(UpdateReleaseStub.requestCount == firstCount + 1, "매월 1일 경계에 요청")
        check(notices.count == 1, "같은 버전 자동 알림 반복 없음")

        updater = Updater(defaults: defaults, session: session, now: { clock })
        updater.onUpdateAvailable = { notices.append($0.tag) }
        check(updater.latestVersion == "2099.1" && updater.lastCheck == clock, "재실행 정보 복원")
        clock = nextMonthStart(clock)
        UpdateReleaseStub.respond(tag: "2099.01")
        await updater.checkNow(forced: false)
        check(notices.count == 1, "재실행·동등한 태그 표기에도 중복 알림 없음")

        updater.setAutoCheckEnabled(false)
        clock = nextMonthStart(clock)
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
        clock = nextMonthStart(clock)
        UpdateReleaseStub.respond(tag: "2099.2")
        await updater.checkNow(forced: false)
        check(notices.last == "2099.2" && notices.count == 4, "다른 새 버전 다시 안내")

        let successDate = updater.lastCheck
        clock = nextMonthStart(clock)
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
        clock = nextMonthStart(clock)
        await updater.checkNow(forced: false)
        check(notices.last == "2099.5", "창 연결 후 안내 가능")

        // 2026-10-24: 버전·업데이트의 직접 확인은 화면에 결과를 남기고 팝업을 겹쳐 띄우지 않는다.
        let inlineDefaults = TestPreferenceDomains.fresh(TestPreferenceDomains.inline)
        var inlineNotices: [String] = []
        var inlineUpdater = Updater(defaults: inlineDefaults, session: session, now: { clock })
        inlineUpdater.onUpdateAvailable = { inlineNotices.append($0.tag) }
        inlineUpdater.setAutoCheckEnabled(false)
        UpdateReleaseStub.respond(tag: "2099.6")
        await inlineUpdater.checkNow(forced: true, showNotice: false)
        check(inlineNotices.isEmpty, "설정 직접 확인: 알림 OFF여도 조회하지만 팝업 없음")
        if case .available(let available) = inlineUpdater.phase {
            check(available.tag == "2099.6", "설정 직접 확인: 같은 화면의 설치 가능 상태에 결과 전달")
        } else { check(false, "설정 직접 확인: 결과 상태 유실") }
        check(inlineDefaults.string(forKey: Updater.lastNotifiedVersionKey) == "2099.6", "설정에 표시한 버전도 알림 이력에 기록")
        await inlineUpdater.checkNow(forced: true, showNotice: false)
        check(inlineNotices.isEmpty, "설정 직접 확인 반복에도 팝업 없음")
        inlineUpdater.setAutoCheckEnabled(true)
        inlineUpdater = Updater(defaults: inlineDefaults, session: session, now: { clock })
        inlineUpdater.onUpdateAvailable = { inlineNotices.append($0.tag) }
        clock = nextMonthStart(clock)
        await inlineUpdater.checkNow(forced: false)
        check(inlineNotices.isEmpty, "설정에서 확인한 버전은 재실행 후 자동 알림도 중복 없음")
        clock = nextMonthStart(clock)
        UpdateReleaseStub.respond(tag: "2099.7")
        await inlineUpdater.checkNow(forced: false)
        check(inlineNotices == ["2099.7"], "다른 새 버전의 자동 알림은 유지")

        // 2026-10-25 (#83): 조회 중 알림을 OFF로 바꾸면 늦은 응답도 창을 띄우지 않는다.
        let offDuringCheckDefaults = TestPreferenceDomains.fresh(TestPreferenceDomains.offDuringCheck)
        let offDuringCheckUpdater = Updater(defaults: offDuringCheckDefaults, session: session, now: { clock })
        var offDuringCheckNotices: [String] = []
        offDuringCheckUpdater.onUpdateAvailable = { offDuringCheckNotices.append($0.tag) }
        UpdateReleaseStub.respond(tag: "2099.8")
        UpdateReleaseStub.holdNextResponse()
        let automaticCheck = Task { await offDuringCheckUpdater.checkNow(forced: false) }
        while !UpdateReleaseStub.hasPendingResponse { await Task.yield() }
        offDuringCheckUpdater.setAutoCheckEnabled(false)
        UpdateReleaseStub.releaseResponse()
        await automaticCheck.value
        check(offDuringCheckNotices.isEmpty, "조회 중 OFF: 늦은 자동 응답으로 알리지 않음")
        check(offDuringCheckDefaults.string(forKey: Updater.lastNotifiedVersionKey) == nil,
              "조회 중 OFF: 표시하지 않은 버전을 알림 이력에 넣지 않음")
        check(offDuringCheckUpdater.latestVersion == "2099.8" && offDuringCheckUpdater.lastCheck == clock,
              "조회 중 OFF: 이미 받은 최신 정보는 설정에 보존")
        if case .available = offDuringCheckUpdater.phase {
            check(true, "조회 중 OFF: 다운로드·설치 없이 사용 가능 상태 유지")
        } else { check(false, "조회 중 OFF: 다운로드·설치 없이 사용 가능 상태 유지") }
        await offDuringCheckUpdater.checkNow(forced: true, showNotice: false)
        check(offDuringCheckNotices.isEmpty && offDuringCheckDefaults.string(forKey: Updater.lastNotifiedVersionKey) == "2099.8",
              "조회 중 OFF 뒤 직접 확인: 같은 설정 화면에만 결과 표시")

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
        // 제거 직전에 보낸 HTTP 응답을 나중에 받아도 정리된 설정을 다시 쓰지 않는다.
        let raceGate = ProductOperationGate()
        let raceUpdater = Updater(defaults: defaults, session: session, now: { clock }, operationGate: raceGate)
        let beforeRace = UpdateReleaseStub.requestCount
        UpdateReleaseStub.respond(tag: "2099.9"); UpdateReleaseStub.holdNextResponse()
        let pending = Task { await raceUpdater.checkNow() }
        while !UpdateReleaseStub.hasPendingResponse { await Task.yield() }
        let removal = raceGate.begin(.removingProduct)!
        check(raceUpdater.pauseForRemoval(), "제거: 진행 중 조회를 무효화하고 쓰기 정지")
        for key in [Updater.lastCheckKey, Updater.latestVersionKey, Updater.lastNotifiedVersionKey] { defaults.removeObject(forKey: key) }
        UpdateReleaseStub.releaseResponse(); await pending.value
        check(defaults.object(forKey: Updater.lastCheckKey) == nil && defaults.object(forKey: Updater.latestVersionKey) == nil, "제거: 늦은 HTTP 응답이 삭제된 설정을 다시 쓰지 않음")
        raceUpdater.setAutoCheckEnabled(false)
        check(raceUpdater.autoCheckEnabled, "제거: 설정 버튼 쓰기도 일시 정지")
        await raceUpdater.checkNow()
        check(UpdateReleaseStub.requestCount == beforeRace + 1, "제거: 새로운 HTTP 조회 시작 차단")
        raceGate.finish(removal); raceUpdater.resumeAfterRemoval(); await raceUpdater.checkNow()
        check(defaults.string(forKey: Updater.latestVersionKey) == "2099.9", "제거 실패: updater 재개 가능")
        let inputRemoval = raceGate.begin(.removingInputMethod)!
        await raceUpdater.installAvailableUpdate()
        check(raceGate.operation == .removingInputMethod, "업데이트: IME 제거 작업권을 뺏지 않음")
        raceGate.finish(inputRemoval)
        await UpdateSecurityTests.run { check($0, $1) }
        UpdateReplacementTests.run { check($0, $1) }
        UninstallTests.run { check($0, $1) }
        InputSourceSettingsTests.run { check($0, $1) }
        await InstallFlowTests.run { check($0, $1) }
        // `exit`는 defer를 돌리지 않는다. 시험 도메인은 여기서 직접 비운다.
        TestPreferenceDomains.clearAll()
        print("Updater: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

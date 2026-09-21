import AppKit
import Foundation

/// 자동 업데이트 — GitHub 최신 릴리스 확인 → zip 다운로드 → 검증 → `/Applications` 교체 →
/// 재실행. (2026-09-21, #19 — 오너 결정: Sparkle 대신 직접 구현. 서드파티 바이너리
/// 프레임워크를 IME 앱에 싣지 않는다. 흐름은 exelban/stats Updater를 참고했고 코드는 새로 썼다.)
///
/// 보안 경계 — 이 파일은 **인터넷에서 받은 파일로 앱을 갈아끼운다.** 그래서:
/// - 검증(`UpdateVerification` 5종) 전에는 어떤 파일도 `/Applications`에 닿지 않는다.
/// - 옛 번들을 먼저 지우지 않는다 — 새 번들을 옆(staging)에 놓고 원자 교체. 어느 단계가
///   실패해도 기존 앱이 그대로 남는다.
/// - 외부 명령은 전부 `Process` 인자 배열로 넘긴다(셸 문자열 조립 금지). 유일한 예외는
///   root 소유 설치본의 관리자 프롬프트인데, `IMEInstaller.removeWithAdminPrivileges`와
///   같은 방식(AppleScript 리터럴 이스케이프 + `quoted form of`)으로 경로를 감싼다.
/// - HTTPS만, 리다이렉트는 `UpdateDecision.allowedHosts` 안에서만 따라간다.
/// - 나가는 데이터는 요청 헤더(`Accept`·`User-Agent: HaneulKeyboard/<버전>`)뿐이다.
///   키 입력·설정·사전 어떤 것도 보내지 않는다. (PRIVACY.md 「자동 업데이트」 절)
/// - 자동 확인은 "새 버전 있음"을 **표시만** 한다. 설치는 사용자가 [업데이트]를 눌러야 한다.
///
/// 판단(버전 비교·자산 선택·throttle·검증 합성·교체 전략)은 `UpdateDecisions.swift`의
/// 순수 함수에 있고 테스트 하네스가 검증한다. 여기는 그 판단을 실행하는 손발이다.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case downloading
        case verifying
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 마지막으로 서버에 **성공적으로** 물어본 시각. 실패한 시도는 갱신하지 않아 다음 정기
    /// 틱(1시간)에 다시 시도한다.
    private(set) var lastCheck: Date?
    private(set) var autoCheckEnabled: Bool

    static let autoCheckKey = "haneul.updateAutoCheck"
    static let lastCheckKey = "haneul.updateLastCheck"
    #if DEBUG
    /// Debug 전용 시험 훅 — `defaults write com.hyunjincho.haneulkeyboard haneul.updateRepoOverride
    /// Hyunjin-Cho/HaneulKeyboard-updatetest` 로 조회 저장소를 바꿔 실제 릴리스 없이 끝까지
    /// 시험한다. Release 빌드에는 이 키를 읽는 코드가 아예 없다.
    static let repositoryOverrideKey = "haneul.updateRepoOverride"
    #endif

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var busy = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 기본 ON(오너 결정). 키가 없으면 true.
        autoCheckEnabled = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date

        let config = URLSessionConfiguration.ephemeral   // 디스크 캐시·쿠키 없음
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 10 * 60
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }

    // MARK: - 설정

    func setAutoCheckEnabled(_ enabled: Bool) {
        autoCheckEnabled = enabled
        defaults.set(enabled, forKey: Self.autoCheckKey)
        haneulLog("HaneulKeyboard: update auto-check \(enabled ? "on" : "off")")
    }

    // 2026-09-21 (#19): 다운로드는 `nonisolated`한 정적 함수에서 돌므로 요청 조립·버전 읽기도
    // 메인 액터 밖에서 쓸 수 있어야 한다. `Bundle.main.infoDictionary`는 읽기 전용이라 안전.
    nonisolated static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    nonisolated static var currentBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    /// 조회할 저장소. Release = 고정값. Debug = defaults 덮어쓰기 허용(형식이 맞을 때만).
    static var repository: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: repositoryOverrideKey),
           UpdateDecision.isValidRepository(override) {
            return override
        }
        #endif
        return UpdateDecision.defaultRepository
    }

    // MARK: - 자동 확인 스케줄

    /// 앱 실행 시 1회(24시간 throttle) + 이후 1시간마다 "24시간이 지났나"를 본다.
    /// 24시간짜리 타이머 하나 대신 1시간 틱을 쓰는 이유: 잠자기에서 깬 뒤나 네트워크 실패
    /// 뒤에도 한 시간 안에 따라잡는다(`lastCheck`는 성공 시에만 갱신). 토글이 OFF면 틱은
    /// 돌아도 `shouldCheckNow`가 false라 네트워크에 나가지 않는다.
    func startAutomaticChecks() {
        guard timer == nil else { return }
        // 첫 확인은 조금 늦춘다 — AppMover가 옮기고 재실행하는 경우 곧 종료될 인스턴스가
        // 헛되이 요청하지 않게, 그리고 메뉴바·IME 활성화가 먼저 끝나게.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            await self?.checkIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkIfDue()
            }
        }
    }

    private func checkIfDue() async {
        guard UpdateDecision.shouldCheckNow(
            autoCheckEnabled: autoCheckEnabled, lastCheck: lastCheck, now: Date(), forced: false
        ) else { return }
        await checkNow(forced: false)
    }

    // MARK: - 확인

    /// 최신 릴리스를 조회해 `phase`를 갱신한다. `forced`는 "지금 확인" 버튼(토글 OFF여도 실행).
    func checkNow(forced: Bool = true) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        phase = .checking
        do {
            let release = try await fetchLatestRelease()
            let now = Date()
            lastCheck = now
            defaults.set(now, forKey: Self.lastCheckKey)
            if let update = UpdateDecision.availableUpdate(currentVersion: Self.currentVersion, release: release) {
                phase = .available(update)
                haneulLog("HaneulKeyboard: update available — \(update.tag) (current \(Self.currentVersion))")
            } else {
                phase = .upToDate
                haneulLog("HaneulKeyboard: update check — up to date (latest \(release.tag), current \(Self.currentVersion))")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            haneulLog("HaneulKeyboard: update check failed — \(message)")
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = UpdateDecision.latestReleaseURL(repository: Self.repository) else {
            throw UpdateError.badRepository(Self.repository)
        }
        let (data, response) = try await session.data(for: Self.request(for: url))
        guard let http = response as? HTTPURLResponse else { throw UpdateError.malformedResponse }
        switch http.statusCode {
        case 200:
            guard let release = UpdateDecision.parseRelease(data) else { throw UpdateError.malformedResponse }
            return release
        case 300...399:
            throw UpdateError.redirectBlocked(http.value(forHTTPHeaderField: "Location") ?? "?")
        case 404:
            throw UpdateError.noRelease(Self.repository)
        case 403, 429:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.httpStatus(http.statusCode)
        }
    }

    nonisolated private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HaneulKeyboard/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    // MARK: - 설치

    /// 사용자가 [업데이트]를 눌렀을 때. 다운로드 → 해제 → 검증 → 교체 → 재실행.
    /// 어느 단계가 실패해도 `/Applications`의 기존 앱은 그대로다.
    func installAvailableUpdate() async {
        guard case .available(let update) = phase, !busy else { return }
        busy = true
        defer { busy = false }

        let destination = AppMoveDecision.destinationURL()
        let running = Bundle.main.bundleURL.standardizedFileURL.path
        guard UpdateDecision.isRunningFromDestination(bundlePath: running, destinationPath: destination.path) else {
            phase = .failed(UpdateError.notInApplications(running).errorDescription ?? "")
            return
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HaneulKeyboardUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            phase = .downloading
            let zipURL = workDir.appendingPathComponent(update.asset.name)
            try await Self.download(update.asset, session: session, to: zipURL)

            phase = .verifying
            let currentVersion = Self.currentVersion
            let currentBuild = Self.currentBuild
            let verifiedApp = try await Task.detached(priority: .userInitiated) {
                try Self.extractAndVerify(zip: zipURL, workDir: workDir,
                                          currentVersion: currentVersion, currentBuild: currentBuild)
            }.value
            haneulLog("HaneulKeyboard: update \(update.tag) verified — bundle ID, Team, codesign, Gatekeeper, version")

            phase = .installing
            let strategy = Self.replaceStrategy(for: destination)
            switch strategy {
            case .userAtomic:
                try await Task.detached(priority: .userInitiated) {
                    try Self.replaceAtomically(destination: destination, with: verifiedApp)
                }.value
            case .adminPrompt:
                // NSAppleScript의 관리자 인증 UI는 메인 액터에서 띄운다(IMEInstaller.uninstall과 동일).
                try Self.replaceWithAdminPrivileges(destination: destination, with: verifiedApp)
            }
            haneulLog("HaneulKeyboard: update \(update.tag) installed at \(destination.path) (\(strategy)) — relaunching")
            relaunch(at: destination)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            haneulLog("HaneulKeyboard: update install failed — \(message)")
        }
    }

    /// 완료 핸들러 안에서 임시 파일을 옮긴다 — 핸들러가 돌아오면 URLSession이 임시 파일을
    /// 지우므로, async `download(for:)`의 반환값에 기대지 않는다.
    nonisolated private static func download(_ asset: ReleaseAsset, session: URLSession, to destination: URL) async throws {
        guard UpdateDecision.isAllowedURL(asset.downloadURL) else {
            throw UpdateError.redirectBlocked(asset.downloadURL.absoluteString)
        }
        let request = request(for: asset.downloadURL)
        let http: HTTPURLResponse = try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { tmp, response, error in
                if let error {
                    continuation.resume(throwing: UpdateError.network(error.localizedDescription))
                    return
                }
                guard let tmp, let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: UpdateError.malformedResponse)
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tmp, to: destination)
                } catch {
                    continuation.resume(throwing: UpdateError.network(error.localizedDescription))
                    return
                }
                continuation.resume(returning: http)
            }
            task.resume()
        }
        guard http.statusCode == 200 else {
            if (300...399).contains(http.statusCode) {
                throw UpdateError.redirectBlocked(http.value(forHTTPHeaderField: "Location") ?? "?")
            }
            throw UpdateError.httpStatus(http.statusCode)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int ?? 0
        guard size > 0, size <= UpdateDecision.maxAssetBytes else { throw UpdateError.badSize(size) }
        if asset.size > 0, asset.size != size { throw UpdateError.sizeMismatch(expected: asset.size, actual: size) }
    }

    /// zip 해제 → 다섯 가지 검증 → (통과 시) quarantine 제거. 통과한 번들 URL을 돌려준다.
    /// 여기까지는 전부 임시 폴더 안이다.
    nonisolated private static func extractAndVerify(
        zip: URL, workDir: URL, currentVersion: String, currentBuild: Int?
    ) throws -> URL {
        let fm = FileManager.default
        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let ditto = run("/usr/bin/ditto", ["-x", "-k", zip.path, extractDir.path])
        guard ditto.status == 0 else { throw UpdateError.extractFailed(ditto.output) }

        // 배포 zip은 `ditto -c -k --keepParent`로 만들어 최상위가 HaneulKeyboard.app 하나다.
        let app = extractDir.appendingPathComponent(AppMoveDecision.destinationName)
        guard fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else {
            throw UpdateError.extractFailed("zip 안에 \(AppMoveDecision.destinationName)이 없음")
        }

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let verification = UpdateVerification(
            bundleIDMatches: info?["CFBundleIdentifier"] as? String == UpdateDecision.appBundleID,
            sameTeamSigned: IMEInstaller.isSameTeamSignedBundle(at: app),
            // 2026-09-21 (#19 보안 검토 P1-1): 인자에 `-R=` 요구사항이 들어간다 —
            // "서명이 일관한가"에 더해 **"애플이 발급한 인증서 사슬로, 우리 Team이 서명했는가"**
            // 까지 OS가 판정한다. 사유·실측은 `UpdateDecision.codesignRequirement` 주석.
            codesignValid: run("/usr/bin/codesign", UpdateDecision.codesignArguments(appPath: app.path)).status == 0,
            notarizationAccepted: run("/usr/sbin/spctl", ["-a", "-t", "exec", app.path]).status == 0,
            versionIncreases: UpdateDecision.isVersionIncrease(
                currentVersion: currentVersion, currentBuild: currentBuild,
                newVersion: info?["CFBundleShortVersionString"] as? String,
                newBuild: (info?["CFBundleVersion"] as? String).flatMap(Int.init)
            )
        )
        guard verification.passed else { throw UpdateError.verificationFailed(verification.failures) }

        // 검증을 통과한 우리 번들이므로 격리 속성을 벗긴다(App Translocation 방지). URLSession
        // 다운로드엔 보통 quarantine이 붙지 않지만(LSFileQuarantineEnabled 미설정) 붙어 있어도
        // 되게 — 없으면 xattr가 비영으로 끝나므로 결과는 무시한다.
        let xattr = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        if xattr.status != 0 && !xattr.output.isEmpty && !xattr.output.contains("No such xattr") {
            haneulLog("HaneulKeyboard: update — quarantine strip returned \(xattr.status): \(xattr.output)")
        }
        return app
    }

    nonisolated private static func replaceStrategy(for destination: URL) -> UpdateDecision.ReplaceStrategy {
        let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let owner = (attrs?[.ownerAccountID] as? NSNumber)?.uint32Value
        let parentWritable = FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
        return UpdateDecision.replaceStrategy(destinationOwnerUID: owner, currentUID: getuid(), parentWritable: parentWritable)
    }

    /// 사용자 소유 설치본 — `AppMover`와 같은 순서: 같은 볼륨의 staging에 복사 → `replaceItemAt`
    /// 으로 한 번에 교체. 복사 도중 실패해도 기존 앱은 그대로다.
    nonisolated private static func replaceAtomically(destination: URL, with source: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.copyItem(at: source, to: staging)
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } catch {
            throw UpdateError.replaceFailed(error.localizedDescription)
        }
    }

    /// root 소유 설치본(빌드 스크립트의 sudo 설치) — 표준 관리자 암호 창. 순서는 같다:
    /// staging 복사 → 옛 번들을 옆으로 → 새 번들 제자리 → 옛 번들 삭제. `mv`는 같은 볼륨이라
    /// rename이고, 어느 단계가 실패하면 `&&` 사슬이 멈춰 옛 번들이 남는다(옆으로 옮겨진 채일
    /// 수 있어 그 경우 경로를 안내한다).
    /// 경로 인용은 `IMEInstaller.removeWithAdminPrivileges`와 동일한 두 계층(AppleScript
    /// 리터럴 이스케이프 + `quoted form of`).
    @MainActor
    private static func replaceWithAdminPrivileges(destination: URL, with source: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let token = UUID().uuidString
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).update-\(token)")
        let old = parent.appendingPathComponent(".\(destination.lastPathComponent).old-\(token)")
        func quoted(_ path: String) -> String {
            let literal = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "quoted form of \"\(literal)\""
        }
        let command = [
            "\"/usr/bin/ditto \" & \(quoted(source.path)) & \" \" & \(quoted(staging.path))",
            "\" && /bin/mv \" & \(quoted(destination.path)) & \" \" & \(quoted(old.path))",
            "\" && /bin/mv \" & \(quoted(staging.path)) & \" \" & \(quoted(destination.path))",
            "\" && /bin/rm -rf \" & \(quoted(old.path))",
        ].joined(separator: " & ")
        let script = "do shell script \(command) with administrator privileges"
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw UpdateError.replaceFailed("관리자 권한 요청 스크립트 생성 실패")
        }
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"
            if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: destination.path) {
                throw UpdateError.replaceFailed("\(message) — 기존 앱은 \(old.path)에 남아 있어요")
            }
            throw UpdateError.replaceFailed(message)
        }
    }

    /// `AppMover`와 같은 패턴 — 교체된 번들을 새 인스턴스로 열고 현재 인스턴스를 종료한다.
    /// 열기에 실패하면 종료하지 않는다(메뉴바 앱이 설명 없이 사라지지 않게).
    private func relaunch(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    let message = UpdateError.relaunchFailed(error.localizedDescription).errorDescription ?? ""
                    self?.phase = .failed(message)
                    haneulLog("HaneulKeyboard: update relaunch failed — \(error.localizedDescription)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Process

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (task.terminationStatus, output)
    }
}

/// 리다이렉트를 허용 호스트(HTTPS) 안으로만 따라간다. 밖으로 나가려 하면 따라가지 않고
/// 3xx 응답을 그대로 끝내 호출자가 `redirectBlocked`로 처리한다.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url, UpdateDecision.isAllowedURL(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

enum UpdateError: LocalizedError {
    case badRepository(String)
    case network(String)
    case httpStatus(Int)
    case rateLimited
    case noRelease(String)
    case redirectBlocked(String)
    case malformedResponse
    case badSize(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case extractFailed(String)
    case verificationFailed([String])
    case notInApplications(String)
    case replaceFailed(String)
    case relaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .badRepository(let repo):
            return "업데이트 저장소 설정이 잘못됐어요 (\(repo))"
        case .network(let reason):
            return "네트워크 오류 — \(reason)"
        case .httpStatus(let code):
            return "서버 응답 오류 (HTTP \(code))"
        case .rateLimited:
            return "GitHub 요청 한도에 걸렸어요. 잠시 뒤 다시 시도해 주세요."
        case .noRelease(let repo):
            return "릴리스를 찾을 수 없어요 (\(repo))"
        case .redirectBlocked(let target):
            return "허용되지 않은 주소로의 이동을 차단했어요 (\(target))"
        case .malformedResponse:
            return "서버 응답을 이해할 수 없어요"
        case .badSize(let size):
            return "받은 파일 크기가 이상해요 (\(size) bytes)"
        case .sizeMismatch(let expected, let actual):
            return "받은 파일 크기가 릴리스 정보와 달라요 (기대 \(expected), 실제 \(actual))"
        case .extractFailed(let reason):
            return "압축 해제 실패 — \(reason)"
        case .verificationFailed(let failures):
            return "검증 실패로 설치하지 않았어요: " + failures.joined(separator: ", ")
        case .notInApplications(let path):
            return "자동 업데이트는 응용 프로그램 폴더(/Applications)에 설치된 앱에서만 할 수 있어요. 지금 실행 위치: \(path)"
        case .replaceFailed(let reason):
            return "앱 교체 실패 — 기존 앱은 그대로예요. (\(reason))"
        case .relaunchFailed(let reason):
            return "새 버전은 설치됐지만 다시 열지 못했어요 — 응용 프로그램 폴더의 HaneulKeyboard를 직접 실행해 주세요. (\(reason))"
        }
    }
}

import AppKit
import Foundation

/// 새 버전 알림과 사용자 선택 설치 — 자동 확인은 알림만, 설치 버튼은 다운로드 → 검증 → 앱 교체.
/// (2026-10-24 명칭·설정 화면 통합; 2026-09-21, #19 — 오너 결정: Sparkle 대신 직접 구현. 서드파티 바이너리
/// 프레임워크를 IME 앱에 싣지 않는다. 흐름은 exelban/stats Updater를 참고했고 코드는 새로 썼다.)
///
/// 보안 경계 — 이 파일은 **인터넷에서 받은 파일로 앱을 갈아끼운다.** 그래서:
/// - 검증(`UpdateVerification` 5종 + 안내한 릴리스와의 버전 대조, 2026-11-13 #226) 전에는 어떤 파일도 `/Applications`에 닿지 않는다.
///   ZIP은 풀기 전에 목록(항목 수·크기·경로)을 보고, 푸는 동안에도 쌓인 양·시간을 지켜본다(`UpdateArchive`).
/// - 옛 번들을 먼저 지우지 않는다 — 새 번들을 옆(staging)에 놓고 교체한다. 관리자
///   교체 실패 시 원래 위치로 복구하며, 복구까지 실패하면 남은 백업·복원 경로를 안내한다.
/// - 외부 명령은 전부 `Process` 인자 배열로 넘긴다(셸 문자열 조립 금지). 유일한 예외는
///   root 소유 설치본의 관리자 프롬프트다. 경로의 POSIX 인용 + 전체 명령의 AppleScript
///   리터럴 이스케이프로 보호한다(`UpdateReplacementScript`).
/// - HTTPS만, 리다이렉트는 `UpdateDecision.allowedHosts` 안에서만 따라간다.
/// - 나가는 데이터는 요청 헤더뿐이다. 앱이 넣는 헤더는 `Accept`·`User-Agent: HaneulKeyboard/<버전>` 둘이고,
///   URLSession이 표준 헤더(`Accept-Language` — 사용자 언어 순서, `Accept-Encoding`, `Connection`, `Host`)를 덧붙인다
///   (2026-11-13 #226 실측: 같은 요청·세션 설정으로 127.0.0.1 서버에 보내 받은 헤더. HTTPS·HTTP/2에서의 차이는 확인 못 함).
///   키 입력·설정·사전 어떤 것도 보내지 않는다. (PRIVACY.md 「새 버전 알림과 설치」 절)
/// - 자동 확인은 "새 버전 있음"을 **표시만** 한다. 설치는 사용자가 [새 버전 설치]를 눌러야 한다.
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
    private(set) var latestVersion: String?

    /// AppDelegate가 실제 알림 창에 연결한다. 설치는 이 콜백에서 시작하지 않는다.
    @ObservationIgnored var onUpdateAvailable: ((AvailableUpdate) -> Void)?
    @ObservationIgnored private var lastNotifiedVersion: CalVer?

    static let autoCheckKey = "haneul.updateAutoCheck"
    static let lastCheckKey = "haneul.updateLastCheck"
    static let latestVersionKey = "haneul.updateLatestVersion"
    static let lastNotifiedVersionKey = "haneul.updateLastNotifiedVersion"
    static let repositoryOverrideKey = "haneul.updateRepoOverride"
    static let allowUnofficialRepositoryKey = "haneul.updateAllowUnofficialRepo"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private let operationGate: ProductOperationGate
    @ObservationIgnored private var removalPaused = false
    @ObservationIgnored private var responseEpoch = 0
    @ObservationIgnored private var wasScheduled = false

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, now: @escaping () -> Date = Date.init, operationGate: ProductOperationGate? = nil) {
        self.operationGate = operationGate ?? ProductOperationGate()
        self.defaults = defaults
        self.now = now
        // 기본 ON(오너 결정). 키가 없으면 true.
        autoCheckEnabled = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        latestVersion = defaults.string(forKey: Self.latestVersionKey).flatMap { CalVer($0)?.text }
        lastNotifiedVersion = defaults.string(forKey: Self.lastNotifiedVersionKey).flatMap(CalVer.init)

        self.session = session ?? URLSession(configuration: Self.sessionConfiguration())
    }

    /// 업데이트 요청의 세션 설정. 2026-11-13 (#226, 리뷰 install-update-F-10): 실제로 나가는 헤더를 127.0.0.1 로컬 서버로 잡아 보는
    /// 측정 도구가 앱과 같은 설정을 쓰도록 떼어 냈다. 값은 그대로다.
    nonisolated static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral   // 디스크 캐시·쿠키 없음
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 10 * 60
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return config
    }

    // MARK: - 설정

    func setAutoCheckEnabled(_ enabled: Bool) {
        guard !removalPaused else { return }
        autoCheckEnabled = enabled
        defaults.set(enabled, forKey: Self.autoCheckKey)
        haneulLog("HaneulKeyboard: update auto-check \(enabled ? "on" : "off")")
    }

    // 2026-09-21 (#19): 다운로드는 `nonisolated`한 정적 함수에서 돌므로 요청 조립·버전 읽기도
    // 메인 액터 밖에서 쓸 수 있어야 한다. `Bundle.main.infoDictionary`는 읽기 전용이라 안전.
    nonisolated static var currentVersion: String {
        UpdateDecision.releaseVersion(info: Bundle.main.infoDictionary) ?? "0.0"
    }

    nonisolated static var currentBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    /// Debug도 별도 허용을 켜야 시험 저장소를 사용한다. Release는 항상 공식 저장소다.
    static var repository: String { repository(defaults: .standard) }

    static func repository(defaults: UserDefaults) -> String {
        #if DEBUG
        if defaults.bool(forKey: allowUnofficialRepositoryKey),
           let override = defaults.string(forKey: repositoryOverrideKey),
           UpdateDecision.isValidRepository(override) {
            return override
        }
        #endif
        return UpdateDecision.defaultRepository
    }

    // MARK: - 자동 확인 스케줄

    /// 앱 실행 시 + 이후 1시간마다 확인할 때가 됐는지 본다(마지막 성공 확인이 이번 달 1일보다 앞인가 — 2026-11-08 #201, 예전엔 24시간).
    /// 긴 타이머 하나 대신 1시간 틱을 쓰는 이유: 잠자기에서 깬 뒤나 네트워크 실패
    /// 뒤에도 한 시간 안에 따라잡는다(`lastCheck`는 성공 시에만 갱신). 토글이 OFF면 틱은
    /// 돌아도 `shouldCheckNow`가 false라 네트워크에 나가지 않는다.
    func startAutomaticChecks() {
        guard timer == nil, !removalPaused else { return }
        wasScheduled = true
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
        await checkNow(forced: false)
    }

    /// 조회 응답이 뒤늦게 도착해도 전체 제거 중/이후 설정을 다시 쓰지 않는다.
    func pauseForRemoval() -> Bool {
        switch phase { case .downloading, .verifying, .installing: return false; default: break }
        removalPaused = true; responseEpoch += 1
        timer?.invalidate(); timer = nil
        if phase == .checking { phase = .idle }
        return true
    }
    func resumeAfterRemoval() {
        removalPaused = false; responseEpoch += 1
        if wasScheduled { startAutomaticChecks() }
    }

    // MARK: - 확인

    /// 최신 릴리스를 조회해 `phase`를 갱신한다. `forced`는 토글 OFF/주기와 무관한 직접 확인.
    /// 2026-10-24: 설정의 직접 확인은 showNotice=false로 같은 화면에 결과를 표시한다.
    func checkNow(forced: Bool = true, showNotice: Bool = true) async {
        guard !busy, !removalPaused, operationGate.operation == nil, UpdateDecision.shouldCheckNow(
            autoCheckEnabled: autoCheckEnabled, lastCheck: lastCheck, now: now(),
            forced: forced
        ) else { return }
        busy = true
        defer { busy = false }
        phase = .checking
        let epoch = responseEpoch
        do {
            let release = try await fetchLatestRelease()
            guard epoch == responseEpoch, !removalPaused else { return }
            guard let releaseVersion = CalVer(release.tag) else { throw UpdateError.malformedResponse }
            let checkedAt = now()
            lastCheck = checkedAt
            defaults.set(checkedAt, forKey: Self.lastCheckKey)
            latestVersion = releaseVersion.text
            defaults.set(latestVersion, forKey: Self.latestVersionKey)
            if let update = UpdateDecision.availableUpdate(currentVersion: Self.currentVersion, release: release) {
                phase = .available(update)
                haneulLog("HaneulKeyboard: update available — \(update.tag) (current \(Self.currentVersion))")
                // 설정에 결과를 표시한 버전도 알림 이력에 포함해 나중의 중복 팝업을 막는다.
                if !showNotice {
                    lastNotifiedVersion = update.version
                    defaults.set(update.tag, forKey: Self.lastNotifiedVersionKey)
                // 조회 중 OFF로 바꾼 경우에도 응답 시점의 설정을 지킨다.
                } else if (forced || autoCheckEnabled),
                          (forced || lastNotifiedVersion != update.version), let onUpdateAvailable {
                    lastNotifiedVersion = update.version
                    defaults.set(update.tag, forKey: Self.lastNotifiedVersionKey)
                    onUpdateAvailable(update)
                }
            } else if let current = CalVer(Self.currentVersion), current < releaseVersion {
                // 더 새 태그가 있지만 안전하게 받을 자산이 없으면 '최신 버전'이라고 표시하지 않는다.
                phase = .failed("새 버전 \(release.tag)의 설치 파일이 아직 준비되지 않았어요.")
            } else {
                phase = .upToDate
                haneulLog("HaneulKeyboard: update check — up to date (latest \(release.tag), current \(Self.currentVersion))")
            }
        } catch {
            guard epoch == responseEpoch, !removalPaused else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            haneulLog("HaneulKeyboard: update check failed — \(message)")
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let repository = Self.repository(defaults: defaults)
        guard let url = UpdateDecision.latestReleaseURL(repository: repository) else {
            throw UpdateError.badRepository(repository)
        }
        let (data, http) = try await UpdateTransport.receive(Self.request(for: url),
            configuration: session.configuration, limit: UpdateDecision.maxReleaseMetadataBytes)
        switch http.statusCode {
        case 200:
            guard let release = UpdateDecision.parseRelease(data) else { throw UpdateError.malformedResponse }
            return release
        case 300...399:
            throw UpdateError.redirectBlocked(http.value(forHTTPHeaderField: "Location") ?? "?")
        case 404:
            throw UpdateError.noRelease(repository)
        case 403, 429:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.httpStatus(http.statusCode)
        }
    }

    /// 앱이 직접 넣는 헤더는 `Accept`·`User-Agent` 둘이다. URLSession이 표준 헤더를 덧붙인다(2026-11-13 #226 실측 — PRIVACY 9번 대조는 F 묶음).
    /// 2026-11-13 (#226): 측정 도구가 같은 요청을 쓰도록 private을 뗐다.
    nonisolated static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HaneulKeyboard/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    // MARK: - 설치

    /// 사용자가 [업데이트]를 눌렀을 때. 다운로드 → 해제 → 검증 → 교체 → 재실행.
    /// 교체 실패 시 기존 앱을 복구한다. 복구까지 실패하면 백업과 원래 경로를 안내한다.
    func installAvailableUpdate() async {
        guard case .available(let update) = phase, !busy, !removalPaused else { return }
        guard let token = operationGate.begin(.updating) else {
            phase = .failed(ProductOperationError.busy.localizedDescription); return
        }
        busy = true
        defer { busy = false; operationGate.finish(token) }

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
            let releaseTag = update.tag
            let verified = try await Task.detached(priority: .userInitiated) {
                try Self.extractAndVerify(zip: zipURL, workDir: workDir,
                                          currentVersion: currentVersion, currentBuild: currentBuild, releaseTag: releaseTag)
            }.value
            haneulLog("HaneulKeyboard: update \(update.tag) verified — archive limits, bundle ID, Team, codesign, Gatekeeper, version, release tag")

            phase = .installing
            let strategy = Self.replaceStrategy(for: destination)
            switch strategy {
            case .userAtomic:
                try await Task.detached(priority: .userInitiated) {
                    try Self.replaceAtomically(destination: destination, with: verified)
                }.value
            case .adminPrompt:
                // NSAppleScript의 관리자 인증 UI는 메인 액터에서 띄운다(IMEInstaller.uninstall과 동일).
                try Self.replaceWithAdminPrivileges(destination: destination, with: verified)
            }
            haneulLog("HaneulKeyboard: update \(update.tag) installed at \(destination.path) (\(strategy)) — relaunching")
            try await Self.relaunchCleaningUp(workDir: workDir) { try await relaunch(at: destination) }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            haneulLog("HaneulKeyboard: update install failed — \(message)")
        }
    }

    /// 수신 도중 ZIP 크기를 제한하고 디스크로 흘려 쓴다. 실패/취소 시 부분 파일을 지운다.
    nonisolated private static func download(_ asset: ReleaseAsset, session: URLSession, to destination: URL) async throws {
        let (_, http) = try await UpdateTransport.receive(request(for: asset.downloadURL),
            configuration: session.configuration, limit: UpdateDecision.maxAssetBytes, destination: destination)
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

    /// 검증을 통과한 번들과 그때 읽은 정체. 2026-11-07 (#176): 관리자 경로가 인증 뒤 복사본을 이 값과 대조한다.
    /// 임시 폴더의 파일은 같은 사용자 권한의 코드가 바꿀 수 있으므로 나중에 다시 읽지 않고 검증 시점의 값을 들고 다닌다.
    /// 2026-11-13 (#226): 시험이 조립부를 실제로 돌릴 수 있게 private을 뗐다. 사용자 경로 교체도 이 값과 대조한다.
    struct VerifiedUpdate: Sendable {
        let app: URL
        let identity: UpdateReplacementScript.VerifiedIdentity
    }

    /// 실제 Apple 서명이 있어야 통과하는 세 검사. 2026-11-13 (#226, 리뷰 install-update-F-6): 예전엔 조립부(`extractAndVerify`)가
    /// 시험에서 한 번도 실행되지 않았다. 시험이 임시 ZIP으로 조립 순서를 실제로 돌리도록 이 셋만 바꿔 끼울 수 있게 했다.
    /// 목록·해제 상한, 링크 검사, 번들 ID·버전 상승·릴리스 대조는 바꿔 끼우지 않는다. 제품은 항상 `live`다.
    struct BundleChecks: Sendable {
        var sameTeamSigned: @Sendable (URL) -> Bool
        var codesignValid: @Sendable (URL) -> Bool
        var notarizationAccepted: @Sendable (URL) -> Bool

        static let live = BundleChecks(
            sameTeamSigned: { IMEInstaller.isSameTeamSignedBundle(at: $0) },
            // 2026-09-21 (#19 보안 검토 P1-1): 인자에 `-R=` 요구사항이 들어간다 —
            // "서명이 일관한가"에 더해 **"애플이 발급한 인증서 사슬로, 우리 Team이 서명했는가"**
            // 까지 OS가 판정한다. 사유·실측은 `UpdateDecision.codesignRequirement` 주석.
            codesignValid: { Updater.run("/usr/bin/codesign", UpdateDecision.codesignArguments(appPath: $0.path)).status == 0 },
            notarizationAccepted: { Updater.run("/usr/sbin/spctl", ["-a", "-t", "exec", $0.path]).status == 0 })
    }

    /// 목록 검사 → 지켜보며 풀기 → 검증(다섯 가지 + 안내한 릴리스와의 버전 대조) → (통과 시) quarantine 제거. 통과한 번들을 돌려준다.
    /// 여기까지는 전부 임시 폴더 안이다. `limits`·`checks`는 시험에서만 바꾼다.
    nonisolated static func extractAndVerify(
        zip: URL, workDir: URL, currentVersion: String, currentBuild: Int?, releaseTag: String,
        limits: ArchiveLimits = .release, checks: BundleChecks = .live
    ) throws -> VerifiedUpdate {
        let fm = FileManager.default
        // 2026-11-13 (#226, 리뷰 security-overlap-C-2): 풀기 전에 목록(항목 수·풀린 크기·경로)을 보고, 푸는 동안에도 상한을 지킨다.
        try inspectArchive(zip, limits: limits)
        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try extractGuarded(zip: zip, into: extractDir, limits: limits, log: workDir.appendingPathComponent("extract.log"))

        // 배포 zip은 `ditto -c -k --keepParent`로 만들어 최상위가 HaneulKeyboard.app 하나다.
        let app = extractDir.appendingPathComponent(AppMoveDecision.destinationName)

        // 🔒 2026-09-21 (#19 보안 검토 P3-1): **아래 어떤 검사보다 먼저** 푼 결과가 추출 폴더
        // 안의 실제 디렉터리인지 본다. 심볼릭 링크면 `fileExists`부터 codesign·spctl까지 전부
        // 링크가 가리키는 바깥 번들에 적용돼 통과해 버린다. 사유·실측은
        // `UpdateDecision.isSafeExtractedApp` 주석. 읽기 실패는 링크로 간주(fail-closed).
        let appValues = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard UpdateDecision.isSafeExtractedApp(
            isSymbolicLink: appValues?.isSymbolicLink ?? true,
            isDirectory: appValues?.isDirectory ?? false,
            resolvedAppPath: app.resolvingSymlinksInPath().standardizedFileURL.path,
            resolvedExtractDirPath: extractDir.resolvingSymlinksInPath().standardizedFileURL.path
        ) else {
            throw UpdateError.verificationFailed(["압축을 푼 \(AppMoveDecision.destinationName)이 추출 폴더 안의 실제 앱 폴더가 아님(심볼릭 링크 등)"])
        }

        guard fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else {
            throw UpdateError.extractFailed("zip 안에 \(AppMoveDecision.destinationName)이 없음")
        }

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let bundleVersion = UpdateDecision.releaseVersion(info: info)
        let verification = UpdateVerification(
            bundleIDMatches: info?["CFBundleIdentifier"] as? String == UpdateDecision.appBundleID,
            sameTeamSigned: checks.sameTeamSigned(app),
            codesignValid: checks.codesignValid(app),
            notarizationAccepted: checks.notarizationAccepted(app),
            versionIncreases: UpdateDecision.isVersionIncrease(
                currentVersion: currentVersion, currentBuild: currentBuild,
                newVersion: bundleVersion,
                newBuild: (info?["CFBundleVersion"] as? String).flatMap(Int.init)
            )
        )
        // 2026-11-13 (#226, 리뷰 install-update-F-1): 받은 앱이 안내한 릴리스 그 버전인지도 본다. 다르면 서명·공증이 멀쩡한
        // 다른 정식 빌드라도 설치하지 않는다. `UpdateVerification`의 다섯 항목은 그대로 두고(그 구조를 쓰는 판단 시험이 있다) 실패 목록에 더한다.
        var failures = verification.failures
        if !UpdateDecision.bundleMatchesRelease(bundleVersion: bundleVersion, releaseTag: releaseTag) {
            failures.append("받은 앱의 버전(\(bundleVersion ?? "읽지 못함"))이 안내한 새 버전(\(releaseTag))과 다름")
        }
        guard failures.isEmpty else { throw UpdateError.verificationFailed(failures) }
        guard let version = info?["CFBundleShortVersionString"] as? String, let build = info?["CFBundleVersion"] as? String else {
            throw UpdateError.verificationFailed(["버전 정보를 읽지 못함"])
        }

        // 검증을 통과한 우리 번들이므로 격리 속성을 벗긴다(App Translocation 방지). URLSession
        // 다운로드엔 보통 quarantine이 붙지 않지만(LSFileQuarantineEnabled 미설정) 붙어 있어도 되게.
        stripQuarantine(at: app)
        return VerifiedUpdate(app: app, identity: .init(bundleID: UpdateDecision.appBundleID, version: version, build: build))
    }

    /// 풀기 전 목록 검사. 2026-11-13 (#226, 리뷰 security-overlap-C-2): ZIP 끝의 중앙 디렉터리만 읽어(최대 4MiB) 항목 수·풀린 크기 합계·경로를 본다.
    /// 판단은 `UpdateArchive`. 이 값은 ZIP이 스스로 적은 것이라 믿을 수 없어, 실제 상한은 `extractGuarded`가 지킨다.
    nonisolated static func inspectArchive(_ zip: URL, limits: ArchiveLimits) throws {
        do {
            let handle = try FileHandle(forReadingFrom: zip)
            defer { try? handle.close() }
            let size = Int(try handle.seekToEnd())
            let tailLength = min(size, UpdateArchive.tailBytes)
            try handle.seek(toOffset: UInt64(size - tailLength))
            let tail = [UInt8](try handle.read(upToCount: tailLength) ?? Data())
            guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: size) else {
                throw UpdateError.archiveRejected("ZIP 목록을 읽지 못함")
            }
            try handle.seek(toOffset: UInt64(location.offset))
            let directory = [UInt8](try handle.read(upToCount: location.size) ?? Data())
            guard directory.count == location.size,
                  let entries = UpdateArchive.entries(centralDirectory: directory, expectedCount: location.entries) else {
                throw UpdateError.archiveRejected("ZIP 목록을 읽지 못함")
            }
            if let problem = UpdateArchive.problem(entries, limits: limits) { throw UpdateError.archiveRejected(problem) }
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.archiveRejected("ZIP을 읽지 못함 (\(error.localizedDescription))")
        }
    }

    /// 지켜보며 푼다. 2026-11-13 (#226, 리뷰 security-overlap-C-2): ZIP이 적은 크기는 믿을 수 없다(실측: `ditto -x -k`가 1,000바이트로 적힌
    /// 항목을 64MiB 끝까지 풀었다). 그래서 짧은 간격으로 추출 폴더에 쌓인 양·항목 수·걸린 시간을 재고, 하나라도 상한을 넘으면 해제를 끊고
    /// 풀던 내용을 지운다. 넘은 순간과 끊는 순간 사이(간격 0.05초)에 조금 더 쓰일 수는 있지만 디스크를 끝없이 채우지는 못한다.
    /// `tool`·`arguments`는 시험에서만 바꾼다(천천히 쓰는 가짜 해제기로 끊는 동작을 본다).
    nonisolated static func extractGuarded(zip: URL, into directory: URL, limits: ArchiveLimits, log: URL,
                                           tool: String = "/usr/bin/ditto", arguments: [String]? = nil,
                                           interval: TimeInterval = 0.05) throws {
        let fm = FileManager.default
        // 출력이 파이프를 채워 해제기가 멈추지 않게 파일로 받는다.
        guard fm.createFile(atPath: log.path, contents: nil), let output = try? FileHandle(forWritingTo: log) else {
            throw UpdateError.extractFailed("압축 해제 기록 파일을 만들지 못함")
        }
        defer { try? output.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments ?? ["-x", "-k", zip.path, directory.path]
        task.standardOutput = output
        task.standardError = output
        let started = Date()
        do { try task.run() } catch { throw UpdateError.extractFailed(error.localizedDescription) }
        var stopReason: String?
        while task.isRunning {
            Thread.sleep(forTimeInterval: interval)
            let usage = diskUsage(of: directory, stopAfter: limits.entries)
            if let reason = UpdateArchive.extractionProblem(bytes: usage.bytes, items: usage.items,
                                                            elapsed: Date().timeIntervalSince(started), limits: limits) {
                stopReason = reason
                task.terminate()
                for _ in 0..<20 where task.isRunning { Thread.sleep(forTimeInterval: 0.05) }
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                break
            }
        }
        task.waitUntilExit()
        if stopReason == nil {
            // 간격 사이에 끝난 해제도 같은 상한으로 다시 본다.
            let usage = diskUsage(of: directory, stopAfter: limits.entries)
            stopReason = UpdateArchive.extractionProblem(bytes: usage.bytes, items: usage.items,
                                                         elapsed: Date().timeIntervalSince(started), limits: limits)
        }
        if let stopReason {
            for item in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
            haneulLog("HaneulKeyboard: update archive extraction stopped — \(stopReason)")
            throw UpdateError.archiveRejected(stopReason)
        }
        guard task.terminationStatus == 0 else {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw UpdateError.extractFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 추출 폴더의 일반 파일 크기 합계(논리 크기와 실제 할당 중 큰 값)와 항목 수. 항목이 `limit`을 넘으면 더 세지 않는다.
    nonisolated private static func diskUsage(of directory: URL, stopAfter limit: Int) -> (bytes: UInt64, items: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [],
                                                          errorHandler: { _, _ in true }) else { return (0, 0) }
        var bytes: UInt64 = 0
        var items = 0
        for case let url as URL in walker {
            items += 1
            if items > limit { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes &+= UInt64(max(values.fileSize ?? 0, values.totalFileAllocatedSize ?? 0))
        }
        return (bytes, items)
    }

    /// 없으면 xattr가 비영으로 끝날 수 있으므로 결과는 로그로만 남긴다. 2026-11-07 (#176): `AppMover`도 같은 방식으로 쓴다.
    nonisolated static func stripQuarantine(at app: URL) {
        let xattr = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        if xattr.status != 0 && !xattr.output.isEmpty && !xattr.output.contains("No such xattr") {
            haneulLog("HaneulKeyboard: quarantine strip returned \(xattr.status): \(xattr.output)")
        }
    }

    nonisolated private static func replaceStrategy(for destination: URL) -> UpdateDecision.ReplaceStrategy {
        let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let owner = (attrs?[.ownerAccountID] as? NSNumber)?.uint32Value
        let parentWritable = FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
        return UpdateDecision.replaceStrategy(destinationOwnerUID: owner, currentUID: getuid(), parentWritable: parentWritable)
    }

    /// 사용자 소유 설치본 — `AppMover`와 같은 순서: 같은 볼륨의 staging에 복사 → 복사본 재확인 → `replaceItemAt`
    /// 으로 한 번에 교체. 복사 도중이나 재확인에서 실패해도 기존 앱은 그대로다.
    /// 2026-11-13 (#226, 리뷰 install-update-F-9): 임시 폴더의 사본은 검증과 복사 사이에 같은 사용자 권한의 코드가 바꿀 수 있다. 관리자 경로(2026-11-07)처럼
    /// staging의 복사본이 검증 때 읽은 정체(번들 ID·버전·빌드)와 같고 서명(Apple 인증서 사슬·번들 ID·Team)이 온전할 때만 교체한다.
    /// macOS 앱 관리 보호가 응용 프로그램 폴더의 앱을 지킨다면 업데이터가 그 우회로가 되지 않게 하려는 것이다(보호가 실제로 적용되는지는 실기 확인 항목).
    /// 재확인 직후에 같은 사용자가 staging을 바꾸는 아주 짧은 틈은 남는다 — 그 사용자는 사용자 소유 설치본도 직접 고칠 수 있다.
    /// `verifyCopy`는 시험에서만 바꾼다.
    nonisolated static func replaceAtomically(
        destination: URL, with verified: VerifiedUpdate,
        verifyCopy: (URL, UpdateReplacementScript.VerifiedIdentity) -> Bool = { isIntactCopy(at: $0, identity: $1) }
    ) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.copyItem(at: verified.app, to: staging)
        } catch {
            throw UpdateError.replaceFailed(error.localizedDescription)
        }
        guard verifyCopy(staging, verified.identity) else {
            throw UpdateError.verificationFailed(["설치 직전에 복사본을 다시 확인했더니 달라져 있음"])
        }
        do {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } catch {
            throw UpdateError.replaceFailed(error.localizedDescription)
        }
    }

    /// 복사본이 검증 때 읽은 정체와 같은가 — 링크가 아닌 폴더이고 번들 ID·버전·빌드가 같다.
    nonisolated static func copyMatchesIdentity(at app: URL, identity: UpdateReplacementScript.VerifiedIdentity) -> Bool {
        guard let values = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              values.isSymbolicLink == false, values.isDirectory == true,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { return false }
        return info["CFBundleIdentifier"] as? String == identity.bundleID
            && info["CFBundleShortVersionString"] as? String == identity.version
            && info["CFBundleVersion"] as? String == identity.build
    }

    /// 정체에 더해 서명까지 — 관리자 교체 스크립트와 같은 요구사항(Apple 인증서 사슬·번들 ID·Team)과 깊은 엄격 검사.
    nonisolated static func isIntactCopy(at app: URL, identity: UpdateReplacementScript.VerifiedIdentity) -> Bool {
        guard copyMatchesIdentity(at: app, identity: identity) else { return false }
        let requirement = UpdateReplacementScript.codesignRequirement(bundleID: identity.bundleID)
        return run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", "-R=\(requirement)", app.path]).status == 0
    }

    /// root 소유 설치본 — staging 복사 → 옛 번들 백업 → 새 번들 배치.
    /// 새 번들 배치가 실패하면 같은 관리자 명령 안에서 백업을 원래 위치로 복구한다.
    /// 복구도 실패하면 백업을 보존하고 실제 백업·복원 경로를 안내한다(리뷰 F-1).
    /// 2026-11-07 (#176, 리뷰 security-overlap-F-3): 인증창이 떠 있는 동안 임시 폴더의 사본이 바뀔 수 있어, 권한 상승한 스크립트 안에서 복사본을 다시 검증한다.
    @MainActor
    private static func replaceWithAdminPrivileges(destination: URL, with verified: VerifiedUpdate) throws {
        let parent = destination.deletingLastPathComponent()
        let token = UUID().uuidString
        // 2026-11-13 (#226, 리뷰 security-overlap-C-1): staging은 응용 프로그램 폴더(관리자 그룹이 이름을 바꿀 수 있다)가 아니라
        // root만 이름을 바꿀 수 있는 자리(끈적이 비트가 있는 /private/tmp 아래, 스크립트가 root 소유 0700으로 만든다)에 둔다.
        // 백업은 복구할 수 있게 그대로 응용 프로그램 폴더에 둔다(/private/tmp는 재시동 때 비워진다).
        let staging = UpdateReplacementScript.privateStaging(token: token)
        let old = parent.appendingPathComponent(".\(destination.lastPathComponent).old-\(token)")
        let replacement = UpdateReplacementScript(source: verified.app, destination: destination,
                                                  staging: staging, backup: old, identity: verified.identity)
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: replacement.appleScriptSource) else {
            throw UpdateError.replaceFailed("관리자 권한 요청 스크립트 생성 실패")
        }
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"
            if FileManager.default.fileExists(atPath: old.path) {
                throw UpdateError.replaceRecoveryFailed(reason: message, backupPath: old.path,
                                                        destinationPath: destination.path)
            }
            throw UpdateError.replaceFailed(message)
        }
        if let notice = result.stringValue, !notice.isEmpty {
            haneulLog("HaneulKeyboard: update replacement — \(notice)")
        }
    }

    /// 2026-11-07 (#176, 리뷰 install-update-F-7): `NSApp.terminate`는 돌아오지 않아 `installAvailableUpdate`의 defer가 돌지 않는다.
    /// 그래서 업데이트가 성공할 때마다 ZIP과 풀린 앱이 임시 폴더에 남았다. 재실행 전에 지운다.
    static func relaunchCleaningUp(workDir: URL, relaunch: () async throws -> Void) async rethrows {
        try? FileManager.default.removeItem(at: workDir)
        try await relaunch()
    }

    /// `AppMover`와 같은 패턴 — 교체된 번들을 새 인스턴스로 열고 현재 인스턴스를 종료한다.
    /// 열기에 실패하면 종료하지 않는다(메뉴바 앱이 설명 없이 사라지지 않게).
    private func relaunch(at url: URL) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { continuation.resume(throwing: UpdateError.relaunchFailed(error.localizedDescription)) }
                else { continuation.resume() }
            }
        }
        NSApp.terminate(nil)
    }

    // MARK: - Process

    nonisolated fileprivate static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
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

enum UpdateError: LocalizedError {
    case badRepository(String)
    case network(String)
    case httpStatus(Int)
    case rateLimited
    case noRelease(String)
    case redirectBlocked(String)
    case malformedResponse
    case responseTooLarge(Int)
    case badSize(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case extractFailed(String)
    /// 2026-11-13 (#226): 풀기 전 목록 검사나 푸는 동안의 상한에 걸려 풀지 않았다.
    case archiveRejected(String)
    case verificationFailed([String])
    case notInApplications(String)
    case replaceFailed(String)
    case replaceRecoveryFailed(reason: String, backupPath: String, destinationPath: String)
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
        case .responseTooLarge(let limit):
            return "업데이트 응답이 허용 크기를 넘어서 중단했어요 (최대 \(limit) bytes)"
        case .badSize(let size):
            return "받은 파일 크기가 이상해요 (\(size) bytes)"
        case .sizeMismatch(let expected, let actual):
            return "받은 파일 크기가 릴리스 정보와 달라요 (기대 \(expected), 실제 \(actual))"
        case .extractFailed(let reason):
            return "압축 해제 실패 — \(reason)"
        case .archiveRejected(let reason):
            return "업데이트 파일이 이상해서 풀지 않았어요 — \(reason)"
        case .verificationFailed(let failures):
            return "검증 실패로 설치하지 않았어요: " + failures.joined(separator: ", ")
        case .notInApplications(let path):
            // 2026-11-07 (#176, 리뷰 install-update-F-5): 하위 폴더에 두거나 이름을 바꾼 앱도 응용 프로그램 폴더 안이라 예전 문구로는 이유를 알 수 없었다.
            return "새 버전 설치는 앱이 \(AppMoveDecision.destinationURL().path)에 있을 때만 할 수 있어요. 지금 실행 위치: \(path). 앱을 하위 폴더가 아닌 응용 프로그램 폴더 바로 아래로 옮기고 이름을 \(AppMoveDecision.destinationName)으로 바꾼 뒤 다시 열어 주세요."
        case .replaceFailed(let reason):
            return "앱 교체 실패 — \(reason)"
        case .replaceRecoveryFailed(let reason, let backupPath, let destinationPath):
            return """
            앱 교체 후 자동 복구를 마치지 못했어요. 기존 앱의 백업은 남겨뒀어요.
            백업: \(backupPath)
            복원할 위치: \(destinationPath)
            Finder의 ‘폴더로 이동’으로 백업을 찾은 뒤 원래 위치와 이름으로 되돌려 주세요(관리자 권한 필요).
            (\(reason))
            """
        case .relaunchFailed(let reason):
            return "새 버전은 설치됐지만 다시 열지 못했어요 — 응용 프로그램 폴더의 HaneulKeyboard를 직접 실행해 주세요. (\(reason))"
        }
    }
}

import Foundation

/// 2026-11-13 (#226): 업데이트 설치 조립부(내려받은 ZIP → 목록 검사 → 감시하며 풀기 → 검증 → 교체)를 임시 폴더의 가짜 번들로 실제로 돌린다.
/// - 리뷰 install-update-F-1: 받은 앱의 공개 버전이 안내한 릴리스 태그와 같아야 한다.
/// - 리뷰 security-overlap-C-2: 풀기 전에 항목 수·풀린 크기·경로를 보고, 푸는 동안에도 디스크에 쌓인 양과 시간을 지켜본다.
///   ZIP이 적은 크기는 믿을 수 없다 — 2026-11-13 실측에서 `ditto -x -k`는 1,000바이트로 적힌 항목을 64MiB 끝까지 풀었다.
/// - 리뷰 install-update-F-6: 서명·공증처럼 Apple 서명이 있어야 통과하는 검사만 바꿔 끼우고, 번들 정보·링크·버전 판단은 실제 코드로 돈다.
/// - 리뷰 install-update-F-9: 사용자 권한 교체도 staging의 복사본을 다시 확인한 뒤에만 교체한다.
/// 설치본·실제 응용 프로그램 폴더·네트워크는 건드리지 않는다.
@MainActor enum UpdateInstallTests {
    typealias Identity = UpdateReplacementScript.VerifiedIdentity

    static func run(_ check: (Bool, String) -> Void) {
        requestHeaders(check)
        releaseMatch(check)
        archiveDecisions(check)
        guard let root = resolvedTemporaryRoot("haneul-update-install") else {
            check(false, "업데이트 설치 검사 준비: 임시 폴더 경로를 풀지 못함")
            return
        }
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try extractionFlow(in: root.appendingPathComponent("extract"), check)
            try extractionGuard(in: root.appendingPathComponent("guard"), check)
            try userReplacement(in: root.appendingPathComponent("replace"), check)
        } catch {
            check(false, "업데이트 설치 검사 준비·실행 실패: \(error)")
        }
    }

    // MARK: - 판단

    /// 리뷰 install-update-F-10: 앱이 직접 넣는 헤더는 둘이다. URLSession이 덧붙이는 표준 헤더는 로컬 서버 측정으로 확인했다(2026-11-13).
    private static func requestHeaders(_ check: (Bool, String) -> Void) {
        let request = Updater.request(for: URL(string: "https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest")!)
        // 2026-11-13 (#226, 오너 결정 가): 언어 설정 순서가 나가지 않게 Accept-Language를 고정값 en으로 직접 넣는다.
        check(Set((request.allHTTPHeaderFields ?? [:]).keys) == ["Accept", "User-Agent", "Accept-Language"]
              && request.value(forHTTPHeaderField: "User-Agent") == "HaneulKeyboard/\(Updater.currentVersion)"
              && request.value(forHTTPHeaderField: "Accept-Language") == "en",
              "요청: 앱이 넣는 헤더는 Accept·User-Agent·Accept-Language(en, 고정) 셋")
        let config = Updater.sessionConfiguration()
        check(config.httpCookieAcceptPolicy == .never && !config.httpShouldSetCookies && (config.urlCache?.diskCapacity ?? 0) == 0 && config.httpAdditionalHeaders == nil,
              "요청: 쿠키·디스크 캐시·추가 헤더 없음")
    }

    private static func releaseMatch(_ check: (Bool, String) -> Void) {
        check(UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.01", releaseTag: "2026.12.01"), "릴리스 대조: 같은 버전")
        check(UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.1", releaseTag: "2026.12.01"), "릴리스 대조: 0 채움만 다른 표기는 같은 버전")
        check(UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.01_hotfix2", releaseTag: "2026.12.01_hotfix2"), "릴리스 대조: 핫픽스 번호까지 같음")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.11.20", releaseTag: "2026.12.01"), "릴리스 대조: 안내보다 낮은 정식 빌드 거부")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.01", releaseTag: "2026.12.01_hotfix1"), "릴리스 대조: 핫픽스 안내에 기본판 거부")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.01_hotfix1", releaseTag: "2026.12.01_hotfix2"), "릴리스 대조: 다른 핫픽스 번호 거부")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: "2027.01.01", releaseTag: "2026.12.01"), "릴리스 대조: 안내보다 높은 버전도 거부")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: nil, releaseTag: "2026.12.01"), "릴리스 대조: 번들 버전 못 읽음")
        check(!UpdateDecision.bundleMatchesRelease(bundleVersion: "2026.12.01", releaseTag: "v2026.12.01"), "릴리스 대조: 형식이 틀린 태그")
    }

    /// 가짜 중앙 디렉터리·끝 레코드를 바이트로 만든다. 압축 데이터는 넣지 않는다(목록 판단만 본다).
    static func zipBytes(_ entries: [(String, UInt32)], zip64: Bool = false, comment: [UInt8] = [], trailing: [UInt8] = []) -> [UInt8] {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        var data: [UInt8] = Array("local data".utf8)
        var directory: [UInt8] = []
        for (name, size) in entries {
            let bytes = Array(name.utf8)
            directory += [0x50, 0x4b, 0x01, 0x02] + le16(20) + le16(20) + le16(0x0800) + le16(8) + le16(0) + le16(0)
            directory += le32(0) + le32(zip64 ? 0xffff_ffff : size / 2) + le32(zip64 ? 0xffff_ffff : size)
            directory += le16(bytes.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + bytes
        }
        directory += trailing
        let offset = UInt32(data.count)
        data += directory
        data += [0x50, 0x4b, 0x05, 0x06] + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        data += le32(UInt32(directory.count)) + le32(offset) + le16(comment.count) + comment
        return data
    }

    static func parse(_ bytes: [UInt8]) -> [ZipEntry]? {
        let tail = Array(bytes.suffix(UpdateArchive.tailBytes))
        guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: bytes.count),
              location.offset + location.size <= bytes.count else { return nil }
        return UpdateArchive.entries(centralDirectory: Array(bytes[location.offset..<(location.offset + location.size)]),
                                     expectedCount: location.entries)
    }

    private static func archiveDecisions(_ check: (Bool, String) -> Void) {
        let limits = ArchiveLimits.release
        // 근거: 후보 111의 실제 ZIP(2026-11-13 실측) — 항목 221개, 풀린 크기 81,828,760바이트, ditto 0.20초.
        check(limits.entries >= 221 * 5 && limits.bytes >= 81_828_760 * 5 && limits.seconds >= 0.2 * 100, "ZIP 상한: 실제 릴리스의 몇 배 여유")
        check(limits.bytes > UInt64(UpdateDecision.maxAssetBytes), "ZIP 상한: 내려받기 상한보다 큼(정상 압축률 허용)")
        let app = "HaneulKeyboard.app/"
        let normal: [(String, UInt32)] = [(app, 0), (app + "Contents/", 0), (app + "Contents/Info.plist", 900),
                                          (app + "Contents/._MacOS", 120), (app + "Contents/MacOS/HaneulKeyboard", 4_000_000)]
        let entries = parse(zipBytes(normal))
        check(entries?.count == 5 && entries?.last?.uncompressedSize == 4_000_000, "ZIP 목록: 중앙 디렉터리의 이름·크기 읽기")
        check(entries.map { UpdateArchive.problem($0, limits: limits) } == .some(nil), "ZIP 목록: 정상 구성 통과")
        check(parse(zipBytes(normal, comment: Array("note".utf8))) == nil, "ZIP 목록: 주석이 붙은 ZIP 거부(배포 ZIP엔 없다)")
        check(parse(zipBytes(normal, zip64: true)) == nil, "ZIP 목록: ZIP64 표시는 거부")
        check(parse(zipBytes(normal, trailing: [0, 0, 0])) == nil, "ZIP 목록: 중앙 디렉터리 뒤 남는 바이트 거부")
        check(parse(Array(zipBytes(normal).dropLast(3))) == nil, "ZIP 목록: 잘린 끝 레코드 거부")
        check(parse(Array("not a zip".utf8)) == nil, "ZIP 목록: ZIP이 아니면 거부")

        func problem(_ list: [(String, UInt32)], _ limits: ArchiveLimits = .release) -> String? {
            guard let parsed = parse(zipBytes(list)) else { return "읽지 못함" }
            return UpdateArchive.problem(parsed, limits: limits)
        }
        for bad in ["../evil", "/abs/HaneulKeyboard.app/x", "HaneulKeyboard.app/../../x", "Other.app/Contents/x",
                    "HaneulKeyboard.appx/y", "__MACOSX/HaneulKeyboard.app/._x", "HaneulKeyboard.app/a\\..\\b", "HaneulKeyboard.app//x"] {
            check(problem(normal + [(bad, 1)]) != nil, "ZIP 목록: 앱 폴더 밖·이상한 경로 거부 \(bad)")
        }
        check(problem([]) != nil, "ZIP 목록: 빈 압축 거부")
        let many = (0..<2_001).map { (app + "f\($0)", UInt32(1)) }
        check(problem(many) != nil, "ZIP 목록: 항목 수 상한 초과 거부")
        check(problem(Array(many.prefix(2_000))) == nil, "ZIP 목록: 항목 수 상한까지는 허용")
        let huge = (0..<130).map { (app + "big\($0)", UInt32(4 * 1024 * 1024)) }   // 520MiB 선언
        check(problem(huge) != nil, "ZIP 목록: 풀린 크기 합계 상한 초과 거부")
        let small = ArchiveLimits(entries: 3, bytes: 10, seconds: 1)
        check(problem([(app + "a", 5), (app + "b", 5)], small) == nil && problem([(app + "a", 6), (app + "b", 5)], small) != nil,
              "ZIP 목록: 크기 상한 경계")

        check(UpdateArchive.extractionProblem(bytes: 10, items: 3, elapsed: 0.5, limits: small) == nil, "푸는 중: 상한 안이면 계속")
        check(UpdateArchive.extractionProblem(bytes: 11, items: 3, elapsed: 0.5, limits: small) != nil, "푸는 중: 디스크에 쌓인 크기 초과")
        check(UpdateArchive.extractionProblem(bytes: 1, items: 4, elapsed: 0.5, limits: small) != nil, "푸는 중: 항목 수 초과")
        check(UpdateArchive.extractionProblem(bytes: 1, items: 1, elapsed: 1.5, limits: small) != nil, "푸는 중: 시간 초과")
    }

    // MARK: - 풀기·검증 조립

    @discardableResult
    static func makeApp(_ url: URL, version: String, build: String, suffix: String? = nil,
                        identifier: String = AppMoveDecision.mainAppBundleID, payload: Int = 0) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                   "CFBundleVersion": build, "CFBundlePackageType": "APPL"]
        if let suffix { info["HaneulReleaseSuffix"] = suffix }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data("code".utf8).write(to: url.appendingPathComponent("Contents/MacOS/HaneulKeyboard"))
        if payload > 0 { try Data(count: payload).write(to: url.appendingPathComponent("Contents/payload")) }
        return url
    }

    @discardableResult
    static func tool(_ executable: String, _ arguments: [String], in directory: URL? = nil) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let directory { task.currentDirectoryURL = directory }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }

    /// 2026-11-13 (#226, 좁은 재검토 install P3-5): 중앙 목록과 파일 머리글의 이름이 다른 무압축 ZIP을 직접 만든다(리뷰어 zipcraft 17번과 같은 꼴).
    static func craftedZip(_ entries: [(local: String, central: String, data: Data)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xffff_ffff
            for b in bytes { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) } }
            return ~c
        }
        var body: [UInt8] = [], central: [UInt8] = []
        for entry in entries {
            let local = Array(entry.local.utf8), name = Array(entry.central.utf8), data = [UInt8](entry.data)
            let crc = crc32(data), size = UInt32(data.count), offset = UInt32(body.count)
            body += le32(0x0403_4b50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            body += le32(crc) + le32(size) + le32(size) + le16(local.count) + le16(0) + local + data
            let mode: UInt32 = entry.central.hasSuffix("/") ? 0o40755 : 0o100644
            central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(mode << 16) + le32(offset) + name
        }
        let directoryOffset = UInt32(body.count)
        body += central
        body += le32(0x0605_4b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(UInt32(central.count)) + le32(directoryOffset) + le16(0)
        return Data(body)
    }

    /// 배포 스크립트와 같은 `ditto -c -k --keepParent`로 만든다.
    static func zip(_ app: URL, to zip: URL) -> Bool {
        tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]) == 0
    }

    private struct Recorder: @unchecked Sendable {
        let lock = NSLock()
        final class Box: @unchecked Sendable { var calls: [String] = [] }
        let box = Box()
        func add(_ value: String) { lock.withLock { box.calls.append(value) } }
        var calls: [String] { lock.withLock { box.calls } }
    }

    private static func extractionFlow(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let recorder = Recorder()
        func checks(codesign: Bool = true) -> Updater.BundleChecks {
            Updater.BundleChecks(
                sameTeamSigned: { recorder.add("team:" + $0.path); return true },
                codesignValid: { recorder.add("codesign:" + $0.path); return codesign },
                notarizationAccepted: { recorder.add("spctl:" + $0.path); return true })
        }
        func attempt(_ name: String, version: String, build: String = "999", suffix: String? = nil, tag: String,
                     codesign: Bool = true, custom: Bool = false, prepare: (URL) throws -> Void = { _ in }) throws -> (Result<Updater.VerifiedUpdate, Error>, URL) {
            let case_ = root.appendingPathComponent(name)
            let source = case_.appendingPathComponent("src")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            let app = try makeApp(source.appendingPathComponent("HaneulKeyboard.app"), version: version, build: build, suffix: suffix)
            let archive = case_.appendingPathComponent("update.zip")
            if custom { try prepare(archive) } else { check(zip(app, to: archive), "조립 \(name): ZIP 준비") }
            let work = case_.appendingPathComponent("work")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let result = Result { try Updater.extractAndVerify(zip: archive, workDir: work, currentVersion: "2026.01.01",
                                                               currentBuild: 100, releaseTag: tag, checks: checks(codesign: codesign)) }
            return (result, work.appendingPathComponent("extract"))
        }
        func failures(_ result: Result<Updater.VerifiedUpdate, Error>) -> [String]? {
            if case .failure(UpdateError.verificationFailed(let list)) = result { return list }
            return nil
        }

        let (ok, extract) = try attempt("ok", version: "2099.01.01", tag: "2099.01.01")
        if case .success(let verified) = ok {
            check(verified.app.path == extract.appendingPathComponent("HaneulKeyboard.app").path, "조립: 추출 폴더 안의 앱을 돌려줌")
            check(verified.identity == Identity(bundleID: AppMoveDecision.mainAppBundleID, version: "2099.01.01", build: "999"),
                  "조립: 검증 때 읽은 정체를 들고 다님")
            let calls = recorder.calls
            check(calls.count == 3 && calls.allSatisfy { $0.hasSuffix("/extract/HaneulKeyboard.app") }, "조립: 서명·공증 검사는 푼 앱에만")
        } else { check(false, "조립: 정상 ZIP 통과 \(ok)") }

        // install-update-F-1: 서명·공증이 멀쩡한 정식 빌드라도 안내한 태그와 버전이 다르면 설치하지 않는다.
        let (older, _) = try attempt("older-release", version: "2099.01.01", tag: "2099.02.01")
        check(failures(older)?.contains { $0.contains("안내한 새 버전") } == true, "조립: 안내한 태그와 다른 버전의 앱 거부")
        let (hotfix, _) = try attempt("hotfix", version: "2099.02.01", suffix: "_hotfix1", tag: "2099.02.01_hotfix1")
        if case .success = hotfix { check(true, "조립: 공개 접미어까지 같은 핫픽스 통과") } else { check(false, "조립: 핫픽스 통과 \(hotfix)") }
        let (baseForHotfix, _) = try attempt("base-for-hotfix", version: "2099.02.01", tag: "2099.02.01_hotfix1")
        check(failures(baseForHotfix) != nil, "조립: 핫픽스 안내에 기본판 앱 거부")

        let (unsigned, _) = try attempt("codesign-fail", version: "2099.01.01", tag: "2099.01.01", codesign: false)
        check(failures(unsigned)?.contains("codesign 검증 실패") == true, "조립: 검증 하나가 실패하면 설치 금지")

        let (lower, _) = try attempt("not-newer", version: "2025.01.01", build: "50", tag: "2025.01.01")
        check(failures(lower)?.contains("버전이 현재보다 높지 않음") == true, "조립: 현재보다 낮은 버전 거부")

        // 리뷰 #19 P3-1: 최상위가 링크면 서명 검사를 시작하기 전에 거부한다.
        let before = recorder.calls.count
        let (linked, _) = try attempt("top-link", version: "2099.01.01", tag: "2099.01.01", custom: true) { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("linkzip")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: staging.appendingPathComponent("HaneulKeyboard.app"),
                                      withDestinationURL: archive.deletingLastPathComponent().appendingPathComponent("src/HaneulKeyboard.app"))
            check(tool("/usr/bin/zip", ["-q", "-y", "-r", archive.path, "HaneulKeyboard.app"], in: staging) == 0, "조립 top-link: 링크 ZIP 준비")
        }
        var linkRejected = failures(linked) != nil
        if case .failure(UpdateError.archiveRejected) = linked { linkRejected = true }
        check(linkRejected && recorder.calls.count == before, "조립: 최상위 링크는 서명 검사 전에 거부(목록 검사 또는 링크 검사)")

        // security-overlap-C-2: 목록에 앱 폴더 밖 항목이 있으면 풀지 않는다.
        let (outside, outsideExtract) = try attempt("outside", version: "2099.01.01", tag: "2099.01.01", custom: true) { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("outzip")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try makeApp(staging.appendingPathComponent("HaneulKeyboard.app"), version: "2099.01.01", build: "999")
            try Data("x".utf8).write(to: staging.appendingPathComponent("extra.txt"))
            check(tool("/usr/bin/zip", ["-q", "-r", archive.path, "HaneulKeyboard.app", "extra.txt"], in: staging) == 0, "조립 outside: ZIP 준비")
        }
        if case .failure(UpdateError.archiveRejected) = outside { check(true, "조립: 앱 폴더 밖 항목이 든 ZIP은 풀지 않음") }
        else { check(false, "조립: 앱 폴더 밖 항목 거부 \(outside)") }
        check(!fm.fileExists(atPath: outsideExtract.appendingPathComponent("HaneulKeyboard.app").path), "조립: 거부한 ZIP은 추출 폴더에 아무것도 없음")

        // 2026-11-13 (#226, 좁은 재검토 install P3-5): 목록엔 앱 안 이름, 파일 머리글엔 앱 밖 이름. 목록 검사는 지나지만 ditto는 머리글 이름으로 풀므로,
        // 풀린 맨 위를 보고 서명 검사 전에 거부한다. 같은 꼴에서 이름만 맞춘 ZIP은 이 검사를 지나 다음 단계(Info.plist 확인)까지 간다.
        let good = "HaneulKeyboard.app/Contents/Resources/aaaaaaaaaaaaaaaa.txt"
        let evil = "OUTSIDE_APP_" + String(repeating: "c", count: good.count - "OUTSIDE_APP_".count - 4) + ".txt"
        func craft(_ archive: URL, local last: String) throws {
            let app = try makeApp(archive.deletingLastPathComponent().appendingPathComponent("craft-src/HaneulKeyboard.app"), version: "2099.01.01", build: "999")
            let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            let dirs = ["HaneulKeyboard.app/", "HaneulKeyboard.app/Contents/", "HaneulKeyboard.app/Contents/Resources/"]
            try craftedZip(dirs.map { ($0, $0, Data()) } + [("HaneulKeyboard.app/Contents/Info.plist", "HaneulKeyboard.app/Contents/Info.plist", plist),
                                                            (last, good, Data("x".utf8))]).write(to: archive)
            check((try? Updater.inspectArchive(archive, limits: .release)) != nil, "조립 \(last == good ? "header-same" : "header-name"): 목록 검사는 통과하는 꼴")
        }
        let beforeHeader = recorder.calls.count
        let (header, headerExtract) = try attempt("header-name", version: "2099.01.01", tag: "2099.01.01", custom: true) { try craft($0, local: evil) }
        var headerReason = ""
        if case .failure(UpdateError.archiveRejected(let reason)) = header { headerReason = reason }
        check(headerReason.contains("맨 위") && recorder.calls.count == beforeHeader, "조립: 머리글 이름이 앱 밖인 ZIP은 풀린 맨 위를 보고 서명 검사 전에 거부")
        check(fm.fileExists(atPath: headerExtract.appendingPathComponent(evil).path), "조립 header-name: ditto는 머리글 이름으로 푼다(이 검사가 필요한 이유)")
        let (same, _) = try attempt("header-same", version: "2099.01.01", tag: "2099.01.01", custom: true) { try craft($0, local: good) }
        if case .success = same { check(true, "조립: 이름이 맞는 같은 꼴 ZIP은 맨 위 검사를 지남") } else { check(false, "조립: 이름이 맞는 ZIP \(same)") }
        check(UpdateArchive.extractedTopLevelProblem(["HaneulKeyboard.app"]) == nil
              && UpdateArchive.extractedTopLevelProblem(["HaneulKeyboard.app", ".hidden"]) != nil
              && UpdateArchive.extractedTopLevelProblem([]) != nil && UpdateArchive.extractedTopLevelProblem(["Other.app"]) != nil,
              "조립: 맨 위는 정확히 앱 폴더 하나(숨은 항목·빈 목록·다른 이름 거부)")

        let (missing, _) = try attempt("no-app", version: "2099.01.01", tag: "2099.01.01", custom: true) { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("emptyzip")
            try fm.createDirectory(at: staging.appendingPathComponent("HaneulKeyboard.app/Contents"), withIntermediateDirectories: true)
            check(zip(staging.appendingPathComponent("HaneulKeyboard.app"), to: archive), "조립 no-app: ZIP 준비")
        }
        if case .failure(UpdateError.extractFailed) = missing { check(true, "조립: Info.plist 없는 앱은 풀기 실패") }
        else { check(false, "조립: Info.plist 없는 앱 \(missing)") }
    }

    /// 실제 `ditto` 대신 천천히 쓰는 스크립트로, 상한을 넘는 순간 해제를 멈추는지 본다.
    private static func extractionGuard(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let writer = root.appendingPathComponent("slow-writer.sh")
        try """
        #!/bin/sh
        # $1 = mode, $2 = zip(쓰지 않음), $3 = 대상 폴더
        mkdir -p "$3/HaneulKeyboard.app/Contents"
        big=$(/usr/bin/head -c 65536 /dev/zero | /usr/bin/tr '\\0' 'a')
        i=0
        while [ $i -lt 400 ]; do
            case "$1" in
            bytes) printf '%s' "$big" > "$3/HaneulKeyboard.app/Contents/chunk$i" ;;
            items) : > "$3/HaneulKeyboard.app/Contents/item$i" ;;
            esac
            i=$((i + 1))
            /bin/sleep 0.01
        done
        """.write(to: writer, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: writer.path)
        let archive = root.appendingPathComponent("unused.zip")
        try Data().write(to: archive)
        for (mode, limits) in [("bytes", ArchiveLimits(entries: 10_000, bytes: 1024 * 1024, seconds: 60)),
                               ("items", ArchiveLimits(entries: 20, bytes: 1 << 30, seconds: 60)),
                               ("time", ArchiveLimits(entries: 10_000, bytes: 1 << 30, seconds: 0.5))] {
            let target = root.appendingPathComponent("out-\(mode)")
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let started = Date()
            var rejected = false
            do {
                try Updater.extractGuarded(zip: archive, into: target, limits: limits, log: root.appendingPathComponent("\(mode).log"),
                                           tool: writer.path, arguments: [mode, archive.path, target.path])
            } catch UpdateError.archiveRejected { rejected = true } catch {}
            let elapsed = Date().timeIntervalSince(started)
            check(rejected, "푸는 중 감시 \(mode): 상한을 넘으면 멈추고 거부")
            check(elapsed < 3, "푸는 중 감시 \(mode): 끝까지 기다리지 않고 바로 멈춤(\(String(format: "%.2f", elapsed))초)")
            check(((try? fm.contentsOfDirectory(atPath: target.path)) ?? ["?"]).isEmpty, "푸는 중 감시 \(mode): 풀던 내용을 지움")
        }
        // 정상 앱은 실제 ditto로 상한 안에서 풀린다.
        let app = try makeApp(root.appendingPathComponent("src/HaneulKeyboard.app"), version: "2099.01.01", build: "1", payload: 200_000)
        let good = root.appendingPathComponent("good.zip")
        check(zip(app, to: good), "푸는 중 감시: 정상 ZIP 준비")
        let out = root.appendingPathComponent("out-good")
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        do {
            try Updater.extractGuarded(zip: good, into: out, limits: .release, log: root.appendingPathComponent("good.log"))
            check(fm.fileExists(atPath: out.appendingPathComponent("HaneulKeyboard.app/Contents/payload").path), "푸는 중 감시: 정상 ZIP은 그대로 풂")
        } catch { check(false, "푸는 중 감시: 정상 ZIP \(error)") }

        // 크기를 작게 속인 ZIP: 목록 검사는 통과해도 실제로 쌓인 양으로 멈춘다(실제 ditto).
        let bomb = try makeApp(root.appendingPathComponent("bomb/HaneulKeyboard.app"), version: "2099.01.01", build: "1", payload: 8 * 1024 * 1024)
        let lying = root.appendingPathComponent("lying.zip")
        check(zip(bomb, to: lying) && understate(lying), "푸는 중 감시: 크기를 속인 ZIP 준비")
        let lyingOut = root.appendingPathComponent("out-lying")
        try fm.createDirectory(at: lyingOut, withIntermediateDirectories: true)
        let small = ArchiveLimits(entries: 2_000, bytes: 1024 * 1024, seconds: 60)
        var lyingRejected = false
        do {
            try Updater.inspectArchive(lying, limits: small)
            check(true, "푸는 중 감시: 속인 크기는 목록 검사를 통과(그래서 감시가 필요)")
            try Updater.extractGuarded(zip: lying, into: lyingOut, limits: small, log: root.appendingPathComponent("lying.log"))
        } catch UpdateError.archiveRejected { lyingRejected = true } catch { check(false, "푸는 중 감시: 속인 ZIP 오류 종류 \(error)") }
        check(lyingRejected, "푸는 중 감시: 크기를 속인 ZIP도 실제로 쌓인 양으로 거부")
        check(((try? fm.contentsOfDirectory(atPath: lyingOut.path)) ?? ["?"]).isEmpty, "푸는 중 감시: 속인 ZIP의 풀린 내용 삭제")
    }

    /// 중앙 디렉터리와 로컬 머리글의 '풀린 크기'를 1바이트로 고쳐 쓴다.
    static func understate(_ url: URL) -> Bool {
        guard var bytes = try? [UInt8](Data(contentsOf: url)) else { return false }
        let tail = Array(bytes.suffix(UpdateArchive.tailBytes))
        guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: bytes.count) else { return false }
        func put32(_ value: UInt32, at index: Int) { for i in 0..<4 { bytes[index + i] = UInt8((value >> (8 * UInt32(i))) & 0xff) } }
        func get16(_ index: Int) -> Int { Int(bytes[index]) | Int(bytes[index + 1]) << 8 }
        func get32(_ index: Int) -> Int { (0..<4).reduce(0) { $0 | Int(bytes[index + $1]) << (8 * $1) } }
        var position = location.offset
        for _ in 0..<location.entries {
            let local = get32(position + 42)
            if get32(position + 24) > 1 {
                put32(1, at: position + 24)
                if get32(local + 22) > 1 { put32(1, at: local + 22) }
            }
            position += 46 + get16(position + 28) + get16(position + 30) + get16(position + 32)
        }
        return (try? Data(bytes).write(to: url)) != nil
    }

    // MARK: - 사용자 권한 교체 (install-update-F-9)

    private static func userReplacement(in root: URL, _ check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = Identity(bundleID: AppMoveDecision.mainAppBundleID, version: "2099.01.01", build: "999")
        func marker(_ app: URL) -> String? { try? String(contentsOf: app.appendingPathComponent("Contents/MacOS/HaneulKeyboard"), encoding: .utf8) }
        func leftovers(_ dir: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.contains(".update-") } }

        for accept in [true, false] {
            let dir = root.appendingPathComponent(accept ? "accepted" : "rejected")
            let installed = try makeApp(dir.appendingPathComponent("Applications/HaneulKeyboard.app"), version: "2026.01.01", build: "100")
            try Data("old".utf8).write(to: installed.appendingPathComponent("Contents/MacOS/HaneulKeyboard"))
            let incoming = try makeApp(dir.appendingPathComponent("extract/HaneulKeyboard.app"), version: "2099.01.01", build: "999")
            try Data("new".utf8).write(to: incoming.appendingPathComponent("Contents/MacOS/HaneulKeyboard"))
            var verified: [URL] = []
            var installedDuringVerify: String?
            var thrown = false
            do {
                try Updater.replaceAtomically(destination: installed, with: Updater.VerifiedUpdate(app: incoming, identity: identity)) { copy, expected in
                    verified.append(copy)
                    installedDuringVerify = marker(installed)
                    return accept && expected == identity
                }
            } catch { thrown = true }
            let label = accept ? "통과" : "거부"
            check(verified.count == 1 && verified[0] != incoming && verified[0] != installed
                  && verified[0].deletingLastPathComponent() == installed.deletingLastPathComponent(),
                  "사용자 교체 \(label): 임시 폴더 원본이 아니라 응용 프로그램 폴더 옆 복사본을 다시 확인")
            check(installedDuringVerify == "old", "사용자 교체 \(label): 확인이 끝나기 전에는 설치본을 건드리지 않음")
            check(thrown == !accept, "사용자 교체 \(label): 확인 결과대로 진행")
            check(marker(installed) == (accept ? "new" : "old"), "사용자 교체 \(label): 설치본 내용")
            check(leftovers(installed.deletingLastPathComponent()).isEmpty, "사용자 교체 \(label): staging이 남지 않음")
        }

        // 기본 확인 함수: 정체(번들 ID·버전·빌드)가 다르거나 링크면 거부한다. 서명이 없는 가짜 번들은 codesign에서도 거부된다.
        let checkDir = root.appendingPathComponent("identity")
        let copy = try makeApp(checkDir.appendingPathComponent("copy.app"), version: "2099.01.01", build: "999")
        check(Updater.copyMatchesIdentity(at: copy, identity: identity), "복사본 정체: 같은 번들 ID·버전·빌드")
        for (field, other) in [("bundle", Identity(bundleID: "com.example.other", version: "2099.01.01", build: "999")),
                               ("version", Identity(bundleID: identity.bundleID, version: "2099.01.02", build: "999")),
                               ("build", Identity(bundleID: identity.bundleID, version: "2099.01.01", build: "998"))] {
            check(!Updater.copyMatchesIdentity(at: copy, identity: other), "복사본 정체: 다른 \(field) 거부")
        }
        let link = checkDir.appendingPathComponent("link.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: copy)
        check(!Updater.copyMatchesIdentity(at: link, identity: identity), "복사본 정체: 링크 거부")
        check(!Updater.isIntactCopy(at: copy, identity: identity), "복사본 확인: 서명 없는 번들은 실제 codesign이 거부")
    }
}

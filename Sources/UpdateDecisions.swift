import Foundation

/// 자동 업데이트(#19)의 **판단 부분**만 모아둔 Foundation 전용 순수 함수·값 타입. (2026-09-21)
///
/// 네트워크·zip 해제·서명 검사 실행·파일 교체·재실행은 AppKit/Security에 묶여 있어
/// `Updater.swift`에 있고 CI에서 돌릴 수 없다. 그래서 "어느 버전이 더 새 것인가 /
/// 어떤 자산을 받을 것인가 / 지금 확인할 때인가 / 검증을 통과했는가 / 어떻게 교체할
/// 것인가"라는 **결정**만 여기로 떼어냈다(`InstallDecisions.swift`와 같은 패턴).
/// 이 파일은 `scripts/run_ime_tests.sh`가 그대로 컴파일해 검증한다.
///
/// 원칙: 판단이 애매하면 **업데이트 없음 / 설치 금지** 쪽으로 닫는다(fail-closed).
/// 인터넷에서 받은 파일로 앱을 갈아끼우는 코드이므로, 형식이 조금이라도 어긋나면
/// 아무것도 하지 않는 것이 맞다.

// MARK: - CalVer

/// `YYYY.RR[.HH]` — 점으로 나뉜 각 칸은 **독립된 정수**(README「버전 체계」: `2026.02.10`이
/// `2026.02.09`보다 최신). 형식이 어긋나면 nil.
struct CalVer: Equatable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let release: Int
    /// 핫픽스 칸. 없으면 0 — `2026.08`과 `2026.08.0`은 같은 버전으로 본다.
    let hotfix: Int
    /// 표시용 원문(`2026.08`). 비교에는 쓰지 않는다.
    let text: String

    /// 허용: 숫자와 점만, 2칸 또는 3칸, 각 칸 1~6자리. `v2026.08`·`2026`·`2026.08.1.2`·
    /// `2026..08`·`2026.-1`은 전부 nil.
    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 6,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(part) else { return nil }
            numbers.append(n)
        }
        year = numbers[0]
        release = numbers[1]
        hotfix = numbers.count == 3 ? numbers[2] : 0
        self.text = text
    }

    static func == (a: CalVer, b: CalVer) -> Bool {
        a.year == b.year && a.release == b.release && a.hotfix == b.hotfix
    }

    static func < (a: CalVer, b: CalVer) -> Bool {
        (a.year, a.release, a.hotfix) < (b.year, b.release, b.hotfix)
    }

    var description: String { text }
}

// MARK: - 릴리스 정보 (GitHub API 응답에서 필요한 부분만)

struct ReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    /// API의 `size`(바이트). 모르면 0.
    let size: Int
}

struct ReleaseInfo: Equatable, Sendable {
    /// `tag_name` — 우리 릴리스는 tag = `MARKETING_VERSION`(예: `2026.07`).
    let tag: String
    let assets: [ReleaseAsset]
    /// 릴리스 페이지(`html_url`). 표시용.
    let pageURL: URL?
}

/// "업데이트 있음" 판정 결과 — 설치 단계가 필요로 하는 것만 담는다.
struct AvailableUpdate: Equatable, Sendable {
    let tag: String
    let version: CalVer
    let asset: ReleaseAsset
    let pageURL: URL?
}

// MARK: - 검증 결과 합성

/// 다운로드해 푼 번들이 설치해도 되는 것인가 — **다섯 가지가 전부 참일 때만**.
/// 하나라도 거짓이면 `/Applications`에 손대지 않는다.
struct UpdateVerification: Equatable, Sendable {
    /// `CFBundleIdentifier == com.hyunjincho.haneulkeyboard`
    var bundleIDMatches: Bool
    /// 실행 중인 앱과 같은 Team으로 유효하게 서명됨(`IMEInstaller.isSameTeamSignedBundle`).
    var sameTeamSigned: Bool
    /// `codesign --verify --deep --strict -R=<애플 앵커 + 우리 Team>` 종료코드 0
    /// (요구사항 문자열은 `UpdateDecision.codesignRequirement`). 2026-09-21 (#19 P1-1)
    var codesignValid: Bool
    /// `spctl -a -t exec` 종료코드 0(노타리 포함 Gatekeeper 승인).
    var notarizationAccepted: Bool
    /// 새 번들의 버전·빌드번호가 현재보다 큼(`UpdateDecision.isVersionIncrease`).
    var versionIncreases: Bool

    var failures: [String] {
        var list: [String] = []
        if !bundleIDMatches { list.append("번들 ID가 HaneulKeyboard가 아님") }
        if !sameTeamSigned { list.append("서명 Team이 현재 앱과 다름") }
        if !codesignValid { list.append("codesign 검증 실패") }
        if !notarizationAccepted { list.append("Gatekeeper(노타리) 거부") }
        if !versionIncreases { list.append("버전이 현재보다 높지 않음") }
        return list
    }

    var passed: Bool { failures.isEmpty }
}

// MARK: - 결정

enum UpdateDecision {
    /// 릴리스를 조회할 GitHub 저장소(`owner/name`). Debug 빌드는 `Updater`가 defaults 키
    /// `haneul.updateRepoOverride`로 바꿔 시험할 수 있다(Release에는 그 코드가 없다).
    static let defaultRepository = "Hyunjin-Cho/HaneulKeyboard"

    /// 교체 대상이 우리 앱인지 판별하는 기준 — `AppMoveDecision`과 같은 값.
    static let appBundleID = AppMoveDecision.mainAppBundleID

    /// 자동 확인 간격.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// 자산 크기 상한. 실제 배포 zip은 6MB 안팎이라 넉넉히 잡되, 디스크를 채우는 응답은 거른다.
    static let maxAssetBytes = 200 * 1024 * 1024

    /// 다운로드·리다이렉트를 허용하는 호스트. HTTPS만.
    /// 2026-09-21 실측: `github.com/…/releases/download/…` → 302 →
    /// `release-assets.githubusercontent.com`(objects.githubusercontent.com이 **아니다**).
    /// 둘 다 넣어 둔다 — GitHub가 자산 CDN을 바꿔도 한쪽은 맞게.
    static let allowedHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    /// 배포본을 서명한 Developer ID 인증서의 Team Identifier(`project.yml`의 `DEVELOPMENT_TEAM`).
    /// 아래 `codesignRequirement` 한 곳에서만 쓰며, 문자열 사본을 다른 데 만들지 않는다.
    ///
    /// 🔒 2026-09-21 (#19 보안 검토 P1-1): **여기만 하드코딩이다.**
    /// `IMEInstaller.isSameTeamSignedBundle`은 그대로 "실행 중인 앱 자신의 Team"과 비교한다
    /// (포크해서 자기 인증서로 빌드한 경우를 막지 않기 위한 설계). 반면 자동 업데이트는
    /// `defaultRepository` — 우리 저장소 — 에서만 받아오므로 서명자도 우리로 못박는 것이 맞다.
    static let signingTeamIdentifier = "6RH6FXY82P"

    /// `codesign --verify`에 함께 넘길 **요구사항**(`-R=`).
    ///
    /// 🔒 2026-09-21 (#19 보안 검토 P1-1): 종전에는 `--verify --deep --strict`만 돌려
    /// **"서명이 내부적으로 일관한가"**만 봤다. "누가 서명했나"는 `isSameTeamSignedBundle`의
    /// OU 문자열 비교뿐이었는데, OU 값은 인증서에 아무나 적을 수 있어 **자체 서명 인증서로
    /// 위조 가능**했다. `anchor apple generic`(= 애플이 발급한 인증서 사슬)과 팀 ID를 **OS
    /// 수준에서 한 요구사항으로 묶어** 그 구멍을 닫는다.
    /// 실측(2026-09-21, `/Applications/HaneulKeyboard.app`): 우리 설치본 exit 0 /
    /// 팀 ID를 다른 값으로 바꾸면 exit 3 (`code failed to satisfy specified code requirement(s)`).
    static var codesignRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(signingTeamIdentifier)\""
    }

    /// 위 요구사항까지 포함한 `codesign` 인자 배열. 순서 고정 — `-R=`은 `--strict` 뒤, 경로 앞.
    static func codesignArguments(appPath: String) -> [String] {
        ["--verify", "--deep", "--strict", "-R=\(codesignRequirement)", appPath]
    }

    /// `owner/name` 꼴만 허용(각 칸은 영숫자·`-`·`_`·`.`). URL에 그대로 끼워 넣으므로
    /// 슬래시·공백·`..` 같은 것은 거른다.
    static func isValidRepository(_ slug: String) -> Bool {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 100, part != ".", part != "..",
                  part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") })
            else { return false }
        }
        return true
    }

    /// `GET https://api.github.com/repos/<owner>/<name>/releases/latest`
    /// (draft·prerelease 제외는 이 엔드포인트가 보장한다).
    static func latestReleaseURL(repository: String) -> URL? {
        guard isValidRepository(repository) else { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// 배포 zip 이름 — `scripts/build_notarize_install.sh`가 만드는 `HaneulKeyboard_<버전>.zip`과
    /// 정확히 일치해야 한다(부분 일치·확장자만 보기 금지).
    static func assetName(forTag tag: String) -> String {
        "HaneulKeyboard_\(tag).zip"
    }

    /// HTTPS이고 허용 호스트일 때만 true.
    static func isAllowedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    /// GitHub 릴리스 JSON에서 필요한 필드만 꺼낸다. `tag_name`이 없거나 draft/prerelease가
    /// true면(엔드포인트가 걸러 주지만 응답이 이상하면) nil. 자산은 이름·URL이 온전한 것만.
    static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let tag = dict["tag_name"] as? String, !tag.isEmpty else { return nil }
        if dict["draft"] as? Bool == true || dict["prerelease"] as? Bool == true { return nil }
        var assets: [ReleaseAsset] = []
        for item in (dict["assets"] as? [[String: Any]]) ?? [] {
            guard let name = item["name"] as? String,
                  let urlString = item["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { continue }
            let size = item["size"] as? Int ?? 0
            assets.append(ReleaseAsset(name: name, downloadURL: url, size: max(0, size)))
        }
        let pageURL = (dict["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseInfo(tag: tag, assets: assets, pageURL: pageURL)
    }

    /// 이름이 `HaneulKeyboard_<tag>.zip`과 정확히 같고, URL이 허용 범위이며, 크기가 상한 안인
    /// 자산. 없으면 nil.
    static func selectAsset(in release: ReleaseInfo) -> ReleaseAsset? {
        let wanted = assetName(forTag: release.tag)
        return release.assets.first {
            $0.name == wanted && isAllowedURL($0.downloadURL) && $0.size <= maxAssetBytes
        }
    }

    /// 현재 버전 < 최신 tag 이고 받을 자산이 있을 때만 "업데이트 있음". 형식이 이상하면 nil.
    static func availableUpdate(currentVersion: String, release: ReleaseInfo) -> AvailableUpdate? {
        guard let current = CalVer(currentVersion),
              let latest = CalVer(release.tag),
              current < latest,
              let asset = selectAsset(in: release) else { return nil }
        return AvailableUpdate(tag: release.tag, version: latest, asset: asset, pageURL: release.pageURL)
    }

    /// 지금 서버에 물어봐도 되는가.
    /// - `forced`(사용자가 "지금 확인"을 누름): 토글·간격과 무관하게 true.
    /// - 토글 OFF: false — 자동으로는 네트워크에 나가지 않는다.
    /// - 마지막 확인이 없거나 24시간 이상 지났으면 true. 마지막 확인 시각이 미래면(시계가
    ///   뒤로 감) 24시간을 영영 못 채우므로 낡은 것으로 보고 true.
    static func shouldCheckNow(autoCheckEnabled: Bool, lastCheck: Date?, now: Date, forced: Bool) -> Bool {
        if forced { return true }
        guard autoCheckEnabled else { return false }
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    /// 새 번들이 현재보다 새 것인가 — 버전(CalVer)도 크고 빌드번호(CFBundleVersion)도 커야
    /// 한다. 어느 하나라도 못 읽으면 false(다운그레이드·같은 빌드 재설치 금지).
    static func isVersionIncrease(
        currentVersion: String, currentBuild: Int?,
        newVersion: String?, newBuild: Int?
    ) -> Bool {
        guard let current = CalVer(currentVersion),
              let newVersion, let incoming = CalVer(newVersion),
              let currentBuild, let newBuild else { return false }
        return current < incoming && currentBuild < newBuild
    }

    /// 재실행된 새 앱이 시작할 때 설치된 IME를 갈아야 하는가 — 설치본 빌드번호 < 임베드
    /// 빌드번호일 때만. 하나라도 못 읽으면 false(시작 시 복사 금지 원칙 H-01 유지).
    static func shouldRefreshIME(installedBuild: Int?, bundledBuild: Int?) -> Bool {
        guard let installedBuild, let bundledBuild else { return false }
        return installedBuild < bundledBuild
    }

    /// 자동 업데이트는 `/Applications/HaneulKeyboard.app`에서 실행 중일 때만 한다 — 다른
    /// 곳(다운로드 폴더·translocation)에서 실행 중이면 교체 대상과 실행 중인 앱이 달라진다.
    static func isRunningFromDestination(bundlePath: String, destinationPath: String) -> Bool {
        bundlePath == destinationPath
    }

    enum ReplaceStrategy: Equatable, Sendable {
        /// 사용자 소유 + 부모 폴더 쓰기 가능 → staging 복사 후 `replaceItemAt` 원자 교체.
        case userAtomic
        /// root 소유(빌드 스크립트 sudo 설치) 또는 부모 폴더 쓰기 불가 → 관리자 암호 프롬프트.
        case adminPrompt
    }

    /// 소유자를 못 읽으면 관리자 경로(실패해도 기존 앱이 남는 쪽).
    static func replaceStrategy(destinationOwnerUID: UInt32?, currentUID: UInt32, parentWritable: Bool) -> ReplaceStrategy {
        guard let destinationOwnerUID, destinationOwnerUID == currentUID, parentWritable else { return .adminPrompt }
        return .userAtomic
    }
}

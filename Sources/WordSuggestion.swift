import Foundation

/// 2026-09-21 (#55): 단어 제안 창구 — "이 단어도 변환됐으면 / 이건 변환되면 안 돼"를 GitHub
/// 이슈로 제안할 수 있게 **미리 채운 이슈 작성 페이지의 URL**을 만드는 순수 함수.
///
/// 원칙 세 가지:
///   1. **서버 0 · 전송 0.** 앱이 하는 일은 이 URL을 기본 브라우저로 여는 것뿐이다
///      (`WordSuggestionSettingsSection.openIssue` → `NSWorkspace.open`). 아무것도 보내지 않고,
///      내용 확인과 등록은 사용자가 GitHub에서 직접 한다(GitHub 계정 필요).
///   2. **URL에 들어가는 것은 사용자가 직접 적은 값, "최근 되돌린 변환"의 (한글 표기, 영어) 쌍,
///      앱·macOS 버전뿐.** 키스트로크·앞뒤 문맥·앱 이름은 넣지 않는다(PRIVACY.md 8번).
///   3. Foundation 전용 — `scripts/run_ime_tests.sh`가 그대로 컴파일해 인코딩·길이 상한을 검증한다.
///
/// 인코딩은 `URLQueryItem`에 맡기지 않는다. 2026-09-21 실측(macOS 27 SDK): `URLQueryItem`은
/// `+` `?` `/` `;` `:` `@` `'`를 그대로 두는데, GitHub(Rails)는 쿼리의 `+`를 공백으로 읽는다
/// (`a+b` → `a b`). 그래서 RFC 3986 비예약 문자(`A–Z a–z 0–9 - . _ ~`) 외에는 전부 UTF-8
/// 바이트별 `%XX`로 직접 인코딩해 `percentEncodedQuery`에 넣는다(줄바꿈 `%0A`, 한글 3바이트).
enum WordSuggestion {
    /// 제안 종류. rawValue는 표시용이 아니라 식별용 — 바꾸면 테스트가 잡는다.
    enum Kind: String, CaseIterable {
        /// "이 단어도 영어로 바뀌었으면" — `typed`(한글 모드 표기) → `expected`(기대한 영어).
        case add
        /// "이건 바뀌면 안 돼" — `typed`(친 글자)가 `expected`(원치 않는 영어)로 바뀌었다.
        case block

        /// 설정 Picker와 이슈 본문에 쓰는 이름.
        var displayName: String {
            switch self {
            case .add: return "변환 추가 제안"
            case .block: return "변환 금지 제안"
            }
        }

        /// 두 번째 값(`expected`)의 뜻 — 종류마다 다르다.
        var expectedLabel: String {
            switch self {
            case .add: return "기대한 결과"
            case .block: return "바뀐 결과 (원치 않음)"
            }
        }
    }

    /// 이슈 작성 페이지. `template` 파라미터는 붙이지 않는다 — 쿼리 `body`가 템플릿 본문을
    /// 이기는지 확신이 없어서(2026-09-21). `.github/ISSUE_TEMPLATE/word-suggestion.md`는
    /// 사람이 직접 이슈를 열 때용이다.
    static let newIssueURL = "https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/new"
    static let label = "enhancement"
    static let titlePrefix = "[단어 제안]"

    /// URL 전체 길이 상한. GitHub이 긴 URL을 거부하는 지점(8 KB 부근)보다 아래로 잡는다.
    static let maxURLLength = 8000
    /// `typed`·`expected` 한 값의 글자 수 상한 — 단어·짧은 문장을 위한 칸이다. 넘으면 자르고 `…`.
    static let maxFieldLength = 120
    /// 제목에 넣는 값의 글자 수 상한(GitHub 제목은 256자). 본문에는 전체가 들어간다.
    static let maxTitleFieldLength = 40
    static let truncationMarker = "…(길이 제한으로 잘림)"

    // MARK: - 공개 API

    /// 미리 채운 이슈 작성 URL. `typed`·`expected`가 (공백 제거 후) 비어 있으면 nil.
    /// `note`는 선택. `appVersion`·`osVersion`은 호출자가 넘긴 문자열을 그대로 적는다(빈 값이면
    /// "(알 수 없음)"). 결과는 항상 `maxURLLength` 이하 — 넘치면 `note`부터 잘라낸다.
    static func issueURL(
        typed: String, expected: String, kind: Kind,
        note: String = "", appVersion: String = "", osVersion: String = ""
    ) -> URL? {
        guard let typedLine = singleLine(typed), let expectedLine = singleLine(expected) else { return nil }
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = issueTitle(typed: typedLine, expected: expectedLine, kind: kind)

        func build(note: String) -> URL? {
            let body = issueBody(
                typed: typedLine, expected: expectedLine, kind: kind,
                note: note, appVersion: appVersion, osVersion: osVersion)
            return url(title: title, body: body)
        }
        func fits(_ url: URL?) -> Bool {
            guard let url else { return false }
            return url.absoluteString.count <= maxURLLength
        }

        if let full = build(note: noteText), fits(full) { return full }

        // 넘친다 — 메모를 앞에서부터 남기고 뒤를 잘라 표시(`truncationMarker`)를 붙인다.
        // 접두 길이가 길수록 URL도 길어지므로(단조) 맞는 최대 접두 길이를 이분 탐색한다.
        let chars = Array(noteText)
        func clipped(_ n: Int) -> URL? {
            let head = String(chars.prefix(n))
            return build(note: head.isEmpty ? truncationMarker : head + "\n" + truncationMarker)
        }
        guard fits(clipped(0)) else {
            // 메모를 다 잘라도 넘친다 — `maxFieldLength` 캡 때문에 생길 수 없는 경우
            // (테스트 "최악 입력도 상한 이내"가 보증). 그래도 잘못된 URL을 여느니 nil.
            return nil
        }
        var low = 0, high = chars.count  // low는 항상 맞는 길이
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(clipped(mid)) { low = mid } else { high = mid - 1 }
        }
        return clipped(low)
    }

    /// 제목: `[단어 제안] 메ㅔㅣㄷ → apple` / 금지 제안은 `… (변환 금지)`가 붙는다.
    static func issueTitle(typed: String, expected: String, kind: Kind) -> String {
        let t = clip(typed, to: maxTitleFieldLength)
        let e = clip(expected, to: maxTitleFieldLength)
        switch kind {
        case .add: return "\(titlePrefix) \(t) → \(e)"
        case .block: return "\(titlePrefix) \(t) → \(e) (변환 금지)"
        }
    }

    /// 본문(마크다운). 값은 표 대신 목록에 넣는다 — 사용자 메모에 `|`가 있어도 깨지지 않게.
    static func issueBody(
        typed: String, expected: String, kind: Kind,
        note: String, appVersion: String, osVersion: String
    ) -> String {
        let noteBlock = note.isEmpty ? "(없음)" : note
        return """
        ## 단어 제안 — \(kind.displayName)

        - **친 글자 (한글 모드에서 보인 표기):** \(typed)
        - **\(kind.expectedLabel):** \(expected)

        ### 메모
        \(noteBlock)

        ### 환경
        - 하늘키보드: \(appVersion.isEmpty ? "(알 수 없음)" : appVersion)
        - macOS: \(osVersion.isEmpty ? "(알 수 없음)" : osVersion)

        ### 확인
        - [ ] 이 기기에서는 설정 → 개인 사전(변환 추가 / 변환 금지)으로 먼저 해결했습니다.
        - [ ] 위 내용에 비밀번호나 개인정보가 들어 있지 않습니다.

        _하늘키보드 설정 → "단어 제안"에서 미리 채운 양식입니다. 앱은 아무것도 전송하지 않으며, 등록은 GitHub에서 사용자가 직접 합니다._
        """
    }

    // MARK: - 인코딩

    /// RFC 3986 비예약 문자(`A–Z a–z 0–9 - . _ ~`)만 남기고 나머지는 UTF-8 바이트별 `%XX`.
    static func percentEncoded(_ s: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(s.utf8.count * 3)
        for byte in s.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.append(byte)
            default:
                out.append(UInt8(ascii: "%"))
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func url(title: String, body: String) -> URL? {
        guard var components = URLComponents(string: newIssueURL) else { return nil }
        components.percentEncodedQuery =
            "title=\(percentEncoded(title))&body=\(percentEncoded(body))&labels=\(percentEncoded(label))"
        return components.url
    }

    // MARK: - 값 정리

    /// 줄바꿈을 공백으로 바꾸고 앞뒤 공백을 지운다. 비면 nil, `maxFieldLength`를 넘으면 자르고 `…`.
    static func singleLine(_ raw: String) -> String? {
        let joined = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return clip(joined, to: maxFieldLength)
    }

    private static func clip(_ s: String, to limit: Int) -> String {
        s.count > limit ? String(s.prefix(limit)) + "…" : s
    }
}

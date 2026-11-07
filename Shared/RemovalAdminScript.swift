import Foundation

/// 인증창이 닫힌 뒤, 권한 상승한 실행기 안에서 경로·inode/device·ID·서명을 재확인한다.
/// 2026-11-07 (#176, 독립 리뷰 2.3절): `codesign --strict`를 뺐다. Finder로 복사한 앱은 최상위 폴더의 FinderInfo 때문에 --strict에 걸려
/// 관리자 제거가 exit 77로 막혔다. 여기는 삭제 직전 신원 확인이라 서명 유효성과 Team 요구사항이면 충분하고, `BundleTrust`도 strict 없이 본다.
/// 업데이트 쪽 `UpdateReplacementScript`는 ZIP을 푼 사본이라 FinderInfo가 없어 --strict를 유지한다.
struct RemovalAdminScript {
    let target: RemovalTarget
    let team: String

    /// `codesign`은 시험에서만 바꾼다(Apple 서명 fixture가 없어 요구사항만 뺀 실제 codesign을 쓴다).
    func shellCommand(codesign: String = "/usr/bin/codesign") -> String {
        let quote = Self.quote
        var ancestors: [String] = []
        var url = target.url
        while url.path != "/" { ancestors.append(url.path); url.deleteLastPathComponent() }
        let checks = ancestors.map { "[ ! -L \(quote($0)) ] || exit 73" }.joined(separator: "\n")
        let requirement = "-R=anchor apple generic and identifier \"\(target.identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        return """
        set -eu
        \(checks)
        target=\(quote(target.url.path))
        [ -d "$target" ] || exit 74
        [ "$(/usr/bin/stat -f '%i:%d' "$target")" = \(quote("\(target.fileNumber):\(target.device)")) ] || exit 75
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")" = \(quote(target.identifier)) ] || exit 76
        \(quote(codesign)) --verify --all-architectures \(quote(requirement)) "$target" || exit 77
        # 서명 검사 중 경로가 바뀌는 경우도 최종 식별자로 차단한다.
        \(checks)
        [ "$(/usr/bin/stat -f '%i:%d' "$target")" = \(quote("\(target.fileNumber):\(target.device)")) ] || exit 75
        /bin/rm -rf -- "$target"
        [ ! -e "$target" ] && [ ! -L "$target" ]
        """
    }
    var appleScriptSource: String {
        let text = shellCommand().replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        return "do shell script \"\(text)\" with administrator privileges"
    }
    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

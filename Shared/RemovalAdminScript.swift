import Foundation

/// 인증창이 닫힌 뒤, 권한 상승한 실행기 안에서 경로·inode/device·ID·서명을 재확인한다.
struct RemovalAdminScript {
    let target: RemovalTarget
    let team: String

    func shellCommand() -> String {
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
        /usr/bin/codesign --verify --strict --all-architectures \(quote(requirement)) "$target" || exit 77
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

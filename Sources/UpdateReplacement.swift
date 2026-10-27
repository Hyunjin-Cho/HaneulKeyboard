import Foundation

/// 2026-10-11 리뷰 F-1: 관리자 교체에도 실패 시 원래 실행 경로로 되돌리는 단계를 둔다.
/// 실제 앱과 회귀 검사가 같은 명령을 사용한다. 검사에서만 명령 경로를 임시 스텁으로 바꾼다.
struct UpdateReplacementScript {
    struct Commands {
        var copy = "/usr/bin/ditto"
        var move = "/bin/mv"
        var remove = "/bin/rm"
    }

    let source: URL
    let destination: URL
    let staging: URL
    let backup: URL

    func shellCommand(commands: Commands = Commands()) -> String {
        let copy = Self.shellQuote(commands.copy)
        let move = Self.shellQuote(commands.move)
        let remove = Self.shellQuote(commands.remove)
        return """
        source=\(Self.shellQuote(source.path))
        destination=\(Self.shellQuote(destination.path))
        staging=\(Self.shellQuote(staging.path))
        backup=\(Self.shellQuote(backup.path))
        if ! \(copy) "$source" "$staging"; then
            \(remove) -rf "$staging"
            exit 1
        fi
        if ! \(move) "$destination" "$backup"; then
            \(remove) -rf "$staging"
            exit 1
        fi
        if \(move) "$staging" "$destination"; then
            # 새 앱 배치가 끝났으므로 백업 정리 실패는 교체 실패로 취급하지 않는다.
            if ! \(remove) -rf "$backup"; then
                printf '%s\\n' "새 앱은 설치됐지만 기존 앱 백업을 정리하지 못했어요: $backup"
            fi
        else
            # 다른 항목이 실행 경로에 생겼다면 덮어쓰거나 그 안에 백업을 넣지 않는다.
            if [ ! -e "$destination" ] && [ ! -L "$destination" ] && \(move) "$backup" "$destination"; then
                \(remove) -rf "$staging"
                printf '%s\\n' '새 앱을 배치하지 못해 기존 앱을 원래 위치로 복구했어요.' >&2
            else
                # 복구도 실패하면 백업과 staging을 모두 남겨 수동 복구에 쓴다.
                printf '%s\\n' '새 앱 배치와 기존 앱 복구가 실패했어요.' >&2
            fi
            exit 1
        fi
        """
    }

    var appleScriptSource: String {
        "do shell script \(Self.appleScriptLiteral(shellCommand())) with administrator privileges"
    }

    /// 경로는 POSIX 단일 인용, 전체 명령은 AppleScript 문자열 인용으로 각각 보호한다.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

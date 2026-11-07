import Foundation

/// 2026-10-11 리뷰 F-1: 관리자 교체에도 실패 시 원래 실행 경로로 되돌리는 단계를 둔다.
/// 실제 앱과 회귀 검사가 같은 명령을 사용한다. 검사에서만 명령 경로를 임시 스텁으로 바꾼다.
///
/// 2026-11-07 (#176, 리뷰 security-overlap-F-3): 권한 상승한 뒤 복사본을 다시 검증하고 통과할 때만 교체한다. `RemovalAdminScript`와 같은 생각이다.
/// 사용자 임시 폴더의 사본은 인증창이 떠 있는 동안(시간 제한 없음) 같은 사용자 권한의 코드가 바꿀 수 있어, 예전처럼 그대로 복사하면
/// 일반 계정이 스스로는 못 쓰는 /Applications에 검증 안 된 코드가 들어갔다. 그래서:
/// - 소유자 전용(0700) staging 폴더를 먼저 만들고 그 안으로 복사한다. 복사 중에도 일반 사용자는 들어올 수 없어 검증 뒤에 못 바꾼다.
/// - 복사본의 번들 ID·버전·빌드(사용자 권한 검증 때 읽은 값과 일치)와 서명(Apple 인증서 사슬·번들 ID·Team)을 본다.
/// - setuid·setgid·그룹/다른 사용자 쓰기 권한과 ACL을 벗기고 소유자를 옛 번들과 맞춘 뒤 옮긴다. ditto는 root로 돌 때 원본 소유자를 유지해, 그대로 두면
///   /Applications의 앱이 그 사용자 소유가 되어 나중에 그 권한으로 고칠 수 있다. 서명은 파일 권한을 다루지 않으므로 권한을 먼저 벗기고 root로 넘긴다.
///   ACL도 ditto가 그대로 복사하고 서명 검사에 걸리지 않아, 남기면 root 소유로 바뀐 뒤에도 그 사용자가 실행 파일을 덮어쓸 수 있다(독립 리뷰 B-P3-1, 2026-11-07).
struct UpdateReplacementScript {
    struct Commands {
        var copy = "/usr/bin/ditto"
        var move = "/bin/mv"
        var remove = "/bin/rm"
        var codesign = "/usr/bin/codesign"
    }

    /// 사용자 권한에서 검증을 통과한 번들의 정체. 관리자 인증 뒤 복사본이 이 값과 같아야 한다.
    struct VerifiedIdentity: Equatable, Sendable {
        let bundleID: String
        let version: String
        let build: String
    }

    let source: URL
    let destination: URL
    /// 소유자 전용 임시 폴더. 앱은 그 안의 `stagedApp`에 복사된다.
    let staging: URL
    let backup: URL
    let identity: VerifiedIdentity

    var stagedApp: URL { staging.appendingPathComponent(destination.lastPathComponent) }

    /// 코드 서명 검사의 요구사항. `UpdateDecision.codesignRequirement`에 번들 ID를 더했다.
    var codesignRequirement: String {
        "anchor apple generic and identifier \"\(identity.bundleID)\" and certificate leaf[subject.OU] = \"\(UpdateDecision.signingTeamIdentifier)\""
    }

    func shellCommand(commands: Commands = Commands()) -> String {
        let copy = Self.shellQuote(commands.copy)
        let move = Self.shellQuote(commands.move)
        let remove = Self.shellQuote(commands.remove)
        let codesign = Self.shellQuote(commands.codesign)
        var ancestors: [String] = []
        var url = destination
        while url.path != "/" { ancestors.append(url.path); url.deleteLastPathComponent() }
        let linkChecks = ancestors.map { "[ ! -L \(Self.shellQuote($0)) ] || reject" }.joined(separator: "\n")
        return """
        source=\(Self.shellQuote(source.path))
        destination=\(Self.shellQuote(destination.path))
        staging=\(Self.shellQuote(staging.path))
        staged=\(Self.shellQuote(stagedApp.path))
        backup=\(Self.shellQuote(backup.path))
        info="$staged/Contents/Info.plist"
        reject() {
            \(remove) -rf "$staging"
            printf '%s\\n' '내려받은 앱을 설치 직전에 다시 확인했더니 달라져 있어 설치하지 않았어요.' >&2
            exit 77
        }
        \(linkChecks)
        if ! /bin/mkdir -m 700 "$staging"; then
            exit 1
        fi
        if ! \(copy) "$source" "$staged"; then
            \(remove) -rf "$staging"
            exit 1
        fi
        [ -d "$staged" ] && [ ! -L "$staged" ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" = \(Self.shellQuote(identity.bundleID)) ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" = \(Self.shellQuote(identity.version)) ] || reject
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" = \(Self.shellQuote(identity.build)) ] || reject
        \(codesign) --verify --deep --strict --all-architectures \(Self.shellQuote("-R=" + codesignRequirement)) "$staged" || reject
        owner="$(/usr/bin/stat -f '%u:%g' "$destination")" || reject
        /bin/chmod -R u-s,g-s,go-w "$staged" || reject
        /bin/chmod -RN "$staged" || reject
        /usr/sbin/chown -hR "$owner" "$staged" || reject
        if ! \(move) "$destination" "$backup"; then
            \(remove) -rf "$staging"
            exit 1
        fi
        if \(move) "$staged" "$destination"; then
            \(remove) -rf "$staging"
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

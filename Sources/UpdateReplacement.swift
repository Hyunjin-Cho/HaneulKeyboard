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
///
/// 2026-11-13 (#226, 리뷰 security-overlap-C-1 · 오너 결정 6가 "확인 없이 강화"): 검증을 마친 뒤 경로 이름으로 다시 접근하는 틈을 줄인다.
/// 예전 staging(`/Applications/.HaneulKeyboard.app.update-…`)은 root 소유 0700이라 안은 못 바꿔도, 관리자 그룹이 쓸 수 있는 /Applications에서
/// 그 폴더 자체의 이름은 바뀔 수 있었다 — 검증한 폴더를 치우고 같은 이름으로 다른 폴더를 놓으면 마지막 `mv`가 그것을 설치했다.
/// - staging은 root만 이름을 바꿀 수 있는 자리에 만든다: 부모(/private/tmp)가 root 소유이고 끈적이 비트가 있어 남이 만든 항목이 아니면 이름을 못 바꾼다.
///   스크립트가 부모의 소유자·권한(끈적이 비트 또는 그룹·다른 사용자 쓰기 불가)과 링크 여부를 확인한 뒤에만 만든다.
/// - staging과 설치 위치가 같은 볼륨이어야 한다. 그래야 마지막 배치가 이름 바꾸기 한 번(원자적)이다 — 다른 볼륨이면 `mv`가 복사로 바뀌므로 거부한다.
/// - 배치 직전 설치 위치가 비어 있는지 보고, 배치 뒤 그 자리의 파일 번호가 검증한 사본과 같은지 확인한다(그 사이에 다른 폴더가 생겨 그 안으로 들어간 경우를 잡는다).
/// - 성공 뒤 백업은 응용 프로그램 폴더에서 바로 지우지 않고 root 전용 staging 안으로 옮겨 파일 번호를 확인한 뒤 지운다(이름이 바뀐 다른 항목을 root로 지우지 않게).
///   백업 자체는 복구할 수 있게 응용 프로그램 폴더에 둔다(/private/tmp는 재시동 때 비워진다).
/// 링크·파일 번호·번들 ID·버전·빌드·서명·권한 정리 검사는 그대로다. 실제 관리자 계정에서의 동작은 실기 확인 항목이다.
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
    /// 소유자 전용 임시 폴더. 앱은 그 안의 `stagedApp`에 복사된다. 제품은 `privateStaging(token:)`을 쓴다.
    let staging: URL
    let backup: URL
    let identity: VerifiedIdentity

    var stagedApp: URL { staging.appendingPathComponent(destination.lastPathComponent) }
    /// 성공 뒤 백업을 지우기 전에 옮겨 두는 자리(staging 안).
    var retiredBackup: URL { staging.appendingPathComponent("previous.app") }

    /// root만 이름을 바꿀 수 있는 staging 자리의 부모. 2026-11-13 (#226): 끈적이 비트가 있는 root 소유 폴더.
    static let privateParent = URL(fileURLWithPath: "/private/tmp")

    static func privateStaging(token: String, parent: URL = privateParent) -> URL {
        parent.appendingPathComponent("HaneulKeyboardUpdate-\(token)")
    }

    /// 코드 서명 검사의 요구사항. `UpdateDecision.codesignRequirement`에 번들 ID를 더했다. 사용자 경로 재확인(`Updater.isIntactCopy`)도 같은 값을 쓴다.
    static func codesignRequirement(bundleID: String) -> String {
        "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(UpdateDecision.signingTeamIdentifier)\""
    }

    var codesignRequirement: String { Self.codesignRequirement(bundleID: identity.bundleID) }

    func shellCommand(commands: Commands = Commands()) -> String {
        let copy = Self.shellQuote(commands.copy)
        let move = Self.shellQuote(commands.move)
        let remove = Self.shellQuote(commands.remove)
        let codesign = Self.shellQuote(commands.codesign)
        func ancestors(of start: URL) -> [String] {
            var list: [String] = []
            var url = start
            while url.path != "/" { list.append(url.path); url.deleteLastPathComponent() }
            return list
        }
        let linkChecks = ancestors(of: destination).map { "[ ! -L \(Self.shellQuote($0)) ] || reject" }.joined(separator: "\n")
        let stagingLinkChecks = ancestors(of: staging.deletingLastPathComponent())
            .map { "[ ! -L \(Self.shellQuote($0)) ] || refuse" }.joined(separator: "\n")
        return """
        source=\(Self.shellQuote(source.path))
        destination=\(Self.shellQuote(destination.path))
        parent=\(Self.shellQuote(destination.deletingLastPathComponent().path))
        staging=\(Self.shellQuote(staging.path))
        sparent=\(Self.shellQuote(staging.deletingLastPathComponent().path))
        staged=\(Self.shellQuote(stagedApp.path))
        retired=\(Self.shellQuote(retiredBackup.path))
        backup=\(Self.shellQuote(backup.path))
        info="$staged/Contents/Info.plist"
        created=0
        cleanup() {
            if [ "$created" = 1 ]; then \(remove) -rf "$staging"; fi
        }
        reject() {
            cleanup
            printf '%s\\n' '내려받은 앱을 설치 직전에 다시 확인했더니 달라져 있어 설치하지 않았어요.' >&2
            exit 77
        }
        refuse() {
            cleanup
            printf '%s\\n' '설치에 쓸 임시 폴더를 안전하게 준비하지 못해 설치하지 않았어요.' >&2
            exit 78
        }
        \(linkChecks)
        \(stagingLinkChecks)
        # staging의 부모는 root(또는 이 실행 계정) 소유이고, 끈적이 비트가 있거나 그룹·다른 사용자가 쓸 수 없어야 한다.
        # 그래야 만든 뒤에 다른 사용자가 staging의 이름을 바꾸지 못한다.
        [ -d "$sparent" ] || refuse
        sowner="$(/usr/bin/stat -f %u "$sparent")" || refuse
        [ "$sowner" = 0 ] || [ "$sowner" = "$(/usr/bin/id -u)" ] || refuse
        smode="$(/usr/bin/stat -f %Lp "$sparent")" || refuse
        [ -k "$sparent" ] || [ "$(( 0$smode & 022 ))" -eq 0 ] || refuse
        if ! /bin/mkdir -m 700 "$staging"; then
            exit 1
        fi
        created=1
        [ -d "$staging" ] && [ ! -L "$staging" ] || refuse
        [ "$(/usr/bin/stat -f '%u:%Lp' "$staging")" = "$(/usr/bin/id -u):700" ] || refuse
        # 마지막 배치는 이름 바꾸기 한 번이어야 원자적이다. 다른 볼륨이면 mv가 복사로 바뀌므로 거부한다.
        [ "$(/usr/bin/stat -f %d "$staging")" = "$(/usr/bin/stat -f %d "$parent")" ] || refuse
        if ! \(copy) "$source" "$staged"; then
            cleanup
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
        previous_id="$(/usr/bin/stat -f '%i:%d' "$destination")" || reject
        staged_id="$(/usr/bin/stat -f '%i:%d' "$staged")" || reject
        if ! \(move) "$destination" "$backup"; then
            cleanup
            exit 1
        fi
        # 실행 경로가 비어 있을 때만 놓고, 놓은 뒤 그 자리가 검증한 사본인지 파일 번호로 확인한다.
        if [ ! -e "$destination" ] && [ ! -L "$destination" ] && \(move) "$staged" "$destination" \\
            && [ ! -L "$destination" ] && [ "$(/usr/bin/stat -f '%i:%d' "$destination")" = "$staged_id" ]; then
            # 새 앱 배치가 끝났으므로 백업 정리 실패는 교체 실패로 취급하지 않는다.
            # 백업은 root 전용 staging 안으로 옮겨 옛 앱인지 확인한 뒤에만 지운다.
            if \(move) "$backup" "$retired" && [ ! -L "$retired" ] \\
                && [ "$(/usr/bin/stat -f '%i:%d' "$retired")" = "$previous_id" ]; then
                if ! \(remove) -rf "$staging"; then
                    printf '%s\\n' "새 앱은 설치됐지만 기존 앱 백업을 정리하지 못했어요: $staging"
                fi
            else
                # 백업 자리에 다른 항목이 있었다. 지우지 않고 제자리로 돌려놓는다.
                if { [ -e "$retired" ] || [ -L "$retired" ]; } && [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
                    \(move) "$retired" "$backup"
                fi
                if [ ! -e "$retired" ] && [ ! -L "$retired" ]; then
                    \(remove) -rf "$staging"
                fi
                printf '%s\\n' "새 앱은 설치됐지만 기존 앱 백업을 정리하지 못했어요: $backup"
            fi
        else
            # 다른 항목이 실행 경로에 생겼다면 덮어쓰거나 그 안에 백업을 넣지 않는다.
            if [ ! -e "$destination" ] && [ ! -L "$destination" ] && \(move) "$backup" "$destination"; then
                cleanup
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

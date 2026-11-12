import Foundation

/// 인증창이 닫힌 뒤, 권한 상승한 실행기 안에서 경로·inode/device·ID·서명을 재확인한다.
/// 2026-11-07 (#176, 독립 리뷰 2.3절): `codesign --strict`를 뺐다. Finder로 복사한 앱은 최상위 폴더의 FinderInfo 때문에 --strict에 걸려
/// 관리자 제거가 exit 77로 막혔다. 여기는 삭제 직전 신원 확인이라 서명 유효성과 Team 요구사항이면 충분하고, `BundleTrust`도 strict 없이 본다.
/// 업데이트 쪽 `UpdateReplacementScript`는 ZIP을 푼 사본이라 FinderInfo가 없어 --strict를 유지한다.
///
/// 2026-11-13 (#226, 리뷰 security-overlap-C-1 · 오너 결정 6가 "확인 없이 강화"): 예전엔 마지막 파일 번호 대조 뒤 `rm -rf "$target"`이 경로를 다시 풀었다.
/// 응용 프로그램 폴더처럼 관리자 그룹이 이름을 바꿀 수 있는 자리에서는 그 사이에 다른 폴더가 같은 이름으로 들어오면 root가 그것을 지웠다.
/// 이제 확인을 마친 대상을 먼저 root 전용 격리 자리(끈적이 비트가 있는 root 소유 /private/tmp 아래에 `mktemp -d`로 만든 0700 폴더)로
/// 이름만 바꿔 옮기고, 옮긴 것이 확인한 그 대상(링크 아님·폴더·파일 번호·장치·번들 ID)인지 다시 본 뒤에만 지운다.
/// 다르면 지우지 않고 제자리로 돌려놓은 뒤 75로 끝낸다. 격리 자리가 대상과 다른 볼륨이면(이름 바꾸기가 복사로 바뀐다) 옮기지 않는다.
/// 링크·파일 번호·번들 ID·서명 재확인은 그대로다. 실제 관리자 계정에서의 동작은 실기 확인 항목이다.
struct RemovalAdminScript {
    let target: RemovalTarget
    let team: String
    /// 격리 폴더를 만들 부모. 제품은 /private/tmp(root 소유·끈적이 비트). 시험에서만 바꾼다.
    var quarantineParent = URL(fileURLWithPath: "/private/tmp")

    /// `codesign`·`move`는 시험에서만 바꾼다(Apple 서명 fixture가 없어 요구사항만 뺀 실제 codesign을 쓰고, 옮기는 순간의 바꿔치기를 흉내 낸다).
    func shellCommand(codesign: String = "/usr/bin/codesign", move: String = "/bin/mv") -> String {
        let quote = Self.quote
        var ancestors: [String] = []
        var url = target.url
        while url.path != "/" { ancestors.append(url.path); url.deleteLastPathComponent() }
        let checks = ancestors.map { "[ ! -L \(quote($0)) ] || exit 73" }.joined(separator: "\n")
        var parents: [String] = []
        url = quarantineParent
        while url.path != "/" { parents.append(url.path); url.deleteLastPathComponent() }
        let parentChecks = parents.map { "[ ! -L \(quote($0)) ] || exit 78" }.joined(separator: "\n")
        let requirement = "-R=anchor apple generic and identifier \"\(target.identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        let identity = quote("\(target.fileNumber):\(target.device)")
        return """
        set -eu
        \(checks)
        target=\(quote(target.url.path))
        [ -d "$target" ] || exit 74
        [ "$(/usr/bin/stat -f '%i:%d' "$target")" = \(identity) ] || exit 75
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")" = \(quote(target.identifier)) ] || exit 76
        \(quote(codesign)) --verify --all-architectures \(quote(requirement)) "$target" || exit 77
        # 서명 검사 중 경로가 바뀌는 경우도 최종 식별자로 차단한다.
        \(checks)
        [ "$(/usr/bin/stat -f '%i:%d' "$target")" = \(identity) ] || exit 75
        # 격리 자리: root(또는 이 실행 계정) 소유이고, 끈적이 비트가 있거나 그룹·다른 사용자가 쓸 수 없는 부모 아래에 새로 만든 0700 폴더.
        qparent=\(quote(quarantineParent.path))
        \(parentChecks)
        [ -d "$qparent" ] || exit 78
        qowner="$(/usr/bin/stat -f %u "$qparent")" || exit 78
        [ "$qowner" = 0 ] || [ "$qowner" = "$(/usr/bin/id -u)" ] || exit 78
        qmode="$(/usr/bin/stat -f %Lp "$qparent")" || exit 78
        [ -k "$qparent" ] || [ "$(( 0$qmode & 022 ))" -eq 0 ] || exit 78
        quarantine="$(/usr/bin/mktemp -d "$qparent/HaneulKeyboardRemoval.XXXXXXXX")" || exit 78
        if [ -L "$quarantine" ] || [ "$(/usr/bin/stat -f '%u:%Lp' "$quarantine")" != "$(/usr/bin/id -u):700" ] \\
            || [ "$(/usr/bin/stat -f %d "$quarantine")" != \(quote("\(target.device)")) ]; then
            /bin/rmdir "$quarantine" || true
            exit 78
        fi
        held="$quarantine/item"
        if ! \(quote(move)) "$target" "$held"; then
            /bin/rmdir "$quarantine" || true
            exit 79
        fi
        # 옮긴 것이 확인한 그 대상인지 다시 본다. 아니면 지우지 않고 제자리로 돌려놓는다.
        if [ -L "$held" ] || [ ! -d "$held" ] || [ "$(/usr/bin/stat -f '%i:%d' "$held")" != \(identity) ] \\
            || [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$held/Contents/Info.plist" 2>/dev/null)" != \(quote(target.identifier)) ]; then
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then /bin/mv "$held" "$target" || true; fi
            /bin/rmdir "$quarantine" 2>/dev/null || true
            exit 75
        fi
        /bin/rm -rf -- "$held"
        /bin/rmdir "$quarantine" || true
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

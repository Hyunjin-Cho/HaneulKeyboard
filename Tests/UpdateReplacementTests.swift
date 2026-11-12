import AppKit
import Foundation

/// 앱이 관리자 실행에 쓰는 실제 명령을 임시 번들에서 실행한다.
/// 실패 주입은 외부 명령 경계에만 넣으며 설치본·설정·관리자 인증은 건드리지 않는다.
/// 2026-11-07 (#176, 리뷰 security-overlap-F-3): 내려받은 앱을 검증한 뒤 바꿔치기한 경우를 시험에 넣었다. 서명 검사는 Apple 서명 fixture가 없어
/// 대부분 스텁으로 대체하되, `real-codesign`은 실제 codesign이 서명 없는 사본을 거부하는지 본다.
@MainActor enum UpdateReplacementTests {
    private typealias Identity = UpdateReplacementScript.VerifiedIdentity

    static func run(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        // 스크립트가 목적지 조상의 심볼릭 링크를 거부하므로 /var → /private/var를 푼 실제 경로에서 돌린다.
        guard let resolved = realpath(fm.temporaryDirectory.path, nil) else {
            check(false, "교체 검사 준비: 임시 폴더 경로를 풀지 못함")
            return
        }
        defer { free(resolved) }
        let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("haneul-replacement-tests-\(UUID().uuidString)")
        let identity = Identity(bundleID: AppMoveDecision.mainAppBundleID, version: "2099.01.01", build: "200")
        func writeBundle(_ url: URL, version: String, identity: Identity) throws {
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try version.write(to: url.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            let info = ["CFBundleIdentifier": identity.bundleID, "CFBundleShortVersionString": identity.version, "CFBundleVersion": identity.build]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
            let code = url.appendingPathComponent("Contents/MacOS/app")
            try Data("code".utf8).write(to: code)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: code.path)
        }
        func mode(_ url: URL) -> mode_t? {
            var info = stat()
            return lstat(url.path, &info) == 0 ? info.st_mode & 0o7777 : nil
        }
        func exists(_ url: URL) -> Bool { mode(url) != nil }
        let rejections: Set<String> = ["swapped-id", "swapped-version", "swapped-build", "swapped-signature",
                                       "tampered-after-copy", "linked-copy", "real-codesign", "linked-destination", "unsafe-parent"]
        // 2026-11-13 (#226, 리뷰 security-overlap-C-1): staging 자리·배치 경쟁·백업 바꿔치기.
        let successes: Set<String> = ["real", "modes", "acl", "cleanup", "sticky-parent", "private-tmp", "backup-swapped"]
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            for step in ["real", "modes", "acl", "copy", "backup", "place", "restore", "occupied", "cleanup",
                         "sticky-parent", "private-tmp", "prestaged", "raced-place", "backup-swapped"] + rejections.sorted() {
                let directory = root.appendingPathComponent(step)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "하늘 ' \" $HOME $(touch injected) `touch injected2`\n.app"
                // staging 부모: 기본은 이 시험 폴더(소유자 전용 쓰기). 끈적이 비트 없이 누구나 쓰는 폴더는 거부, 끈적이 비트가 있으면 허용,
                // `private-tmp`는 제품과 같은 실제 /private/tmp(root 소유·끈적이)다.
                var stagingParent = directory
                if step == "unsafe-parent" || step == "sticky-parent" {
                    stagingParent = directory.appendingPathComponent(step == "unsafe-parent" ? "open" : "sticky")
                    try fm.createDirectory(at: stagingParent, withIntermediateDirectories: true)
                    try fm.setAttributes([.posixPermissions: step == "unsafe-parent" ? 0o777 : 0o1777], ofItemAtPath: stagingParent.path)
                }
                let staging = step == "private-tmp" ? UpdateReplacementScript.privateStaging(token: UUID().uuidString)
                    : stagingParent.appendingPathComponent(".stage \(name)")
                defer { if step == "private-tmp" { try? fm.removeItem(at: staging) } }
                let replacement = UpdateReplacementScript(
                    source: directory.appendingPathComponent("new \(name)"),
                    destination: directory.appendingPathComponent(name),
                    staging: staging,
                    backup: directory.appendingPathComponent(".backup \(name)"),
                    identity: identity
                )
                if step == "prestaged" {
                    // 다른 사용자가 같은 이름을 미리 만들어 둔 경우: 만들기가 실패하고, 남이 만든 폴더는 지우지 않는다.
                    try fm.createDirectory(at: replacement.staging, withIntermediateDirectories: true)
                    try Data("planted".utf8).write(to: replacement.staging.appendingPathComponent("planted"))
                }
                // 사용자 권한 검증을 통과한 뒤 임시 폴더의 사본이 이렇게 바뀐 경우를 흉내 낸다.
                var incoming = identity
                switch step {
                case "swapped-id": incoming = Identity(bundleID: "com.example.other", version: identity.version, build: identity.build)
                case "swapped-version": incoming = Identity(bundleID: identity.bundleID, version: "2020.01.01", build: identity.build)
                case "swapped-build": incoming = Identity(bundleID: identity.bundleID, version: identity.version, build: "100")
                default: break
                }
                try writeBundle(replacement.source, version: "new", identity: incoming)
                // 리뷰 B-P3-1: 인증창이 떠 있는 동안 사본에 ACL을 붙이면 권한 비트를 정리해도 그 사용자가 계속 쓸 수 있다.
                // 소유자 맞춤(chown)은 이 시험이 root가 아니라 실제로 못 본다. 스크립트 순서만 아래에서 본다.
                let aclCode = replacement.source.appendingPathComponent("Contents/MacOS/app")
                if step == "acl" {
                    let user = NSUserName()
                    for (path, rights) in [(aclCode.path, "write,delete,append,writeattr,writeextattr"),
                                           (aclCode.deletingLastPathComponent().path, "add_file,add_subdirectory,delete_child"),
                                           (replacement.source.path, "add_file,add_subdirectory,delete_child")] {
                        let acl = Process()
                        acl.executableURL = URL(fileURLWithPath: "/bin/chmod")
                        acl.arguments = ["+a", "user:\(user) allow \(rights)", path]
                        try acl.run(); acl.waitUntilExit()
                        check(acl.terminationStatus == 0, "교체 acl: fixture에 ACL 붙임")
                    }
                }
                func aclListing(_ url: URL) -> String {
                    let list = Process(); let listOut = Pipe()
                    list.executableURL = URL(fileURLWithPath: "/bin/ls")
                    list.arguments = ["-ledR", url.path, url.appendingPathComponent("Contents").path,
                                      url.appendingPathComponent("Contents/MacOS").path, url.appendingPathComponent("Contents/MacOS/app").path]
                    list.standardOutput = listOut; list.standardError = FileHandle.nullDevice
                    guard (try? list.run()) != nil else { return "" }
                    let data = listOut.fileHandleForReading.readDataToEndOfFile()
                    list.waitUntilExit()
                    return String(decoding: data, as: UTF8.self)
                }
                if step == "linked-destination" {
                    let target = directory.appendingPathComponent("linked-target.app")
                    try writeBundle(target, version: "old", identity: identity)
                    try fm.createSymbolicLink(at: replacement.destination, withDestinationURL: target)
                } else {
                    try writeBundle(replacement.destination, version: "old", identity: identity)
                }
                let copy = directory.appendingPathComponent("copy.sh")
                let move = directory.appendingPathComponent("move.sh")
                let remove = directory.appendingPathComponent("remove.sh")
                let codesign = directory.appendingPathComponent("codesign.sh")
                let modeLog = directory.appendingPathComponent("staging-mode.log")
                let codesignLog = directory.appendingPathComponent("codesign.log")
                let scripts = [
                    (copy, """
                    #!/bin/sh
                    /usr/bin/stat -f %Lp "$(/usr/bin/dirname "$2")" > "$HANEUL_TEST_MODE_LOG"
                    case "$HANEUL_TEST_STEP" in
                    copy)
                        /bin/mkdir -p "$2"
                        printf partial > "$2/version"
                        exit 71 ;;
                    tampered-after-copy)
                        /usr/bin/ditto "$1" "$2" || exit 1
                        printf evil > "$2/Contents/Info.plist"
                        exit 0 ;;
                    linked-copy)
                        /bin/ln -s "$1" "$2"
                        exit 0 ;;
                    modes)
                        /usr/bin/ditto "$1" "$2" || exit 1
                        /bin/chmod 6775 "$2/Contents/MacOS/app"
                        exit 0 ;;
                    esac
                    exec /usr/bin/ditto "$@"
                    """),
                    (move, """
                    #!/bin/sh
                    if [ "$HANEUL_TEST_STEP" = backup ] && [ "$2" = "$HANEUL_TEST_BACKUP" ]; then exit 72; fi
                    if { [ "$HANEUL_TEST_STEP" = place ] || [ "$HANEUL_TEST_STEP" = restore ] || [ "$HANEUL_TEST_STEP" = occupied ]; } && [ "$1" = "$HANEUL_TEST_STAGE" ]; then
                        if [ "$HANEUL_TEST_STEP" = occupied ]; then
                            /bin/mkdir -p "$2"
                            printf other > "$2/version"
                        fi
                        exit 73
                    fi
                    if [ "$HANEUL_TEST_STEP" = restore ] && [ "$1" = "$HANEUL_TEST_BACKUP" ]; then exit 74; fi
                    if [ "$HANEUL_TEST_STEP" = raced-place ] && [ "$1" = "$HANEUL_TEST_STAGE" ]; then
                        # 확인과 이름 바꾸기 사이에 설치 위치에 다른 폴더가 생기면 mv가 그 안으로 옮긴다.
                        /bin/mkdir -p "$2"
                        printf other > "$2/version"
                    fi
                    if [ "$HANEUL_TEST_STEP" = backup-swapped ] && [ "$1" = "$HANEUL_TEST_BACKUP" ] && [ "$2" = "$HANEUL_TEST_RETIRED" ]; then
                        # 백업을 지우러 옮기는 순간 그 이름에 다른 폴더를 놓는다.
                        /bin/mv "$1" "$1.real"
                        /bin/mkdir -p "$1"
                        printf foreign > "$1/version"
                    fi
                    exec /bin/mv "$@"
                    """),
                    (remove, """
                    #!/bin/sh
                    if [ "$HANEUL_TEST_STEP" = cleanup ] && [ "$2" = "$HANEUL_TEST_STAGING" ]; then exit 75; fi
                    exec /bin/rm "$@"
                    """),
                    (codesign, """
                    #!/bin/sh
                    printf '%s\\n' "$@" >> "$HANEUL_TEST_CODESIGN_LOG"
                    if [ "$HANEUL_TEST_STEP" = swapped-signature ]; then exit 3; fi
                    exit 0
                    """)
                ]
                for (url, script) in scripts {
                    try script.write(to: url, atomically: true, encoding: .utf8)
                    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                }
                let commands: UpdateReplacementScript.Commands
                switch step {
                case "real", "acl", "sticky-parent", "private-tmp": commands = .init(codesign: codesign.path)
                case "real-codesign": commands = .init()
                default: commands = .init(copy: copy.path, move: move.path, remove: remove.path, codesign: codesign.path)
                }
                let command = replacement.shellCommand(commands: commands)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", command]
                task.currentDirectoryURL = directory
                task.environment = ProcessInfo.processInfo.environment.merging([
                    "HANEUL_TEST_STEP": step,
                    "HANEUL_TEST_STAGE": replacement.stagedApp.path,
                    "HANEUL_TEST_BACKUP": replacement.backup.path,
                    "HANEUL_TEST_STAGING": replacement.staging.path,
                    "HANEUL_TEST_RETIRED": replacement.retiredBackup.path,
                    "HANEUL_TEST_MODE_LOG": modeLog.path,
                    "HANEUL_TEST_CODESIGN_LOG": codesignLog.path
                ]) { _, value in value }
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                try task.run()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                task.waitUntilExit()
                func version(_ url: URL) -> String? {
                    try? String(contentsOf: url.appendingPathComponent("version"), encoding: .utf8)
                }
                check(version(replacement.source) == "new", "교체 \(step): 검증된 원본 보존")
                check(!fm.fileExists(atPath: directory.appendingPathComponent("injected").path)
                    && !fm.fileExists(atPath: directory.appendingPathComponent("injected2").path),
                      "교체 \(step): 경로의 셸 특수문자를 실행하지 않음")
                if rejections.contains(step) {
                    check(task.terminationStatus != 0, "교체 \(step): 바꿔치기된 사본을 거부")
                    check(version(replacement.destination) == "old", "교체 \(step): 기존 앱이 원래 경로에 있음")
                    check(!exists(replacement.backup) && !exists(replacement.staging), "교체 \(step): 임시 복사본·백업이 남지 않음")
                    check(output.contains("설치하지 않았어요"), "교체 \(step): 거부 이유를 알림")
                    if step == "unsafe-parent" {
                        check(task.terminationStatus == 78, "교체: 남이 이름을 바꿀 수 있는 부모에는 staging을 만들지 않음")
                    }
                    if step == "linked-destination" {
                        check((try? fm.destinationOfSymbolicLink(atPath: replacement.destination.path)) != nil, "교체: 링크인 목적지를 따라가지 않음")
                    }
                } else if step == "prestaged" {
                    check(task.terminationStatus != 0 && version(replacement.destination) == "old", "교체: 미리 만들어진 staging이면 설치하지 않음")
                    check((try? Data(contentsOf: replacement.staging.appendingPathComponent("planted"))) == Data("planted".utf8)
                          && !exists(replacement.stagedApp) && !exists(replacement.backup), "교체: 남이 만든 staging은 건드리지 않음")
                } else if successes.contains(step) {
                    check(task.terminationStatus == 0 && version(replacement.destination) == "new",
                          "교체 \(step): 새 앱 정상 배치")
                    if step != "cleanup" { check(!exists(replacement.staging), "교체 \(step): staging 없음") }
                    if step == "cleanup" {
                        check(version(replacement.retiredBackup) == "old" && output.contains("정리하지 못했어요"),
                              "교체: 백업 정리 실패는 새 앱 설치 성공과 구분")
                        check(!exists(replacement.backup), "교체: 백업은 root 전용 staging 안으로 옮긴 뒤 지움")
                    } else if step == "backup-swapped" {
                        check(version(replacement.backup) == "foreign" && output.contains("정리하지 못했어요"),
                              "교체: 백업 자리에 바꿔 놓인 다른 폴더는 지우지 않고 제자리로")
                        check(version(URL(fileURLWithPath: replacement.backup.path + ".real")) == "old", "교체: 바꿔치기 시험의 옛 앱 보존")
                    } else if step == "acl" {
                        check(aclListing(replacement.source).contains(" allow "), "교체 acl: 원본에 ACL이 있음(시험 전제)")
                        check(!aclListing(replacement.destination).contains(" allow "), "교체: 배치된 앱에 ACL이 남지 않음")
                    } else if step == "modes" {
                        check(!exists(replacement.backup), "교체: 성공 뒤 옛 백업 제거")
                        check((try? String(contentsOf: modeLog, encoding: .utf8))?.hasPrefix("700") == true,
                              "교체: 복사 시작 전에 staging 폴더가 소유자 전용(0700)")
                        check(mode(replacement.destination.appendingPathComponent("Contents/MacOS/app")) == 0o755,
                              "교체: setuid·setgid·그룹 쓰기 권한을 벗기고 배치")
                    } else {
                        check(!exists(replacement.backup), "교체: 성공 뒤 옛 백업 제거")
                        let log = (try? String(contentsOf: codesignLog, encoding: .utf8)) ?? ""
                        let lines = log.components(separatedBy: "\n")
                        check(log.contains(replacement.stagedApp.path), "교체: 권한 상승 뒤 복사본을 다시 검증")
                        check(!log.contains(replacement.source.path), "교체: 사용자 임시 폴더의 원본이 아니라 복사본을 검증")
                        check(lines.contains("-R=anchor apple generic and identifier \"\(identity.bundleID)\" and certificate leaf[subject.OU] = \"\(UpdateDecision.signingTeamIdentifier)\""),
                              "교체: Apple 인증서 사슬·번들 ID·Team을 요구사항으로 검사")
                        check(["--verify", "--deep", "--strict", "--all-architectures"].allSatisfy(lines.contains), "교체: 깊은 엄격 검사")
                        var error: NSDictionary?
                        let literal = UpdateReplacementScript.appleScriptLiteral(command)
                        let roundTrip = NSAppleScript(source: "return \(literal)")?.executeAndReturnError(&error)
                        check(error == nil && roundTrip?.stringValue == command,
                              "교체: AppleScript 문자열 인용의 명령·경로 왕복")
                        let script = NSAppleScript(source: replacement.appleScriptSource)
                        check(script?.compileAndReturnError(&error) == true && error == nil,
                              "교체: 실제 관리자 AppleScript 구문 컴파일")
                        let realCommand = replacement.shellCommand()
                        let order = ["/usr/bin/codesign", "/bin/chmod -R u-s,g-s,go-w", "/bin/chmod -RN", "/usr/sbin/chown -hR", "\"$destination\" \"$backup\""]
                            .map { realCommand.range(of: $0)?.lowerBound }
                        check(!order.contains(nil) && zip(order, order.dropFirst()).allSatisfy { $0! < $1! },
                              "교체: 검증 → 권한 정리 → 소유자 맞춤 → 교체 순서")
                        // 2026-11-13 (#226): 부모 확인 → staging 만들기 → 소유·권한·볼륨 확인 → 복사, 배치 뒤 파일 번호 확인 → 백업은 staging 안에서 확인 후 삭제.
                        let setup = ["[ -k \"$sparent\" ]", "/bin/mkdir -m 700 \"$staging\"", "\"$(/usr/bin/id -u):700\"",
                                     "/usr/bin/stat -f %d \"$staging\"", "\"$source\" \"$staged\"", "staged_id=",
                                     "\"$staged\" \"$destination\"", "= \"$staged_id\"", "\"$backup\" \"$retired\"", "= \"$previous_id\""]
                            .map { realCommand.range(of: $0)?.lowerBound }
                        check(!setup.contains(nil) && zip(setup, setup.dropFirst()).allSatisfy { $0! < $1! },
                              "교체: root 전용 staging 준비 → 복사·검증 → 배치 확인 → 백업 확인 후 삭제 순서")
                        check(!realCommand.contains("-rf \"$backup\""), "교체: 응용 프로그램 폴더의 백업 경로를 root로 바로 지우지 않음")
                    }
                } else {
                    check(task.terminationStatus != 0, "교체 \(step): 실패 상태 반환")
                    if step == "raced-place" {
                        check(version(replacement.backup) == "old" && output.contains("실패"), "교체: 배치 뒤 파일 번호가 다르면 실패로 보고하고 백업 보존")
                        check(version(replacement.destination) == "other", "교체: 경쟁으로 생긴 폴더를 덮어쓰지 않음")
                    } else if step == "restore" || step == "occupied" {
                        check(version(replacement.backup) == "old" && version(replacement.stagedApp) == "new",
                              "교체 \(step): 복구 실패 뒤 백업과 staging 보존")
                        check(mode(replacement.staging) == 0o700, "교체 \(step): 남은 staging은 소유자 전용")
                        check(version(replacement.destination) == (step == "occupied" ? "other" : nil),
                              "교체 \(step): 다른 항목을 덮어쓰거나 백업을 그 안에 옮기지 않음")
                    } else {
                        check(version(replacement.destination) == "old", "교체 \(step): 기존 앱이 원래 경로에 있음")
                        check(!exists(replacement.backup) && !exists(replacement.staging),
                              "교체 \(step): 임시 복사본·백업 정리")
                        if step == "place" {
                            check(output.contains("원래 위치로 복구"), "교체: 새 앱 배치 실패 뒤 복구 안내")
                        }
                    }
                }
            }
            // 제품이 쓰는 staging 자리: /private/tmp 아래(이 Mac에서 root 소유·끈적이 비트 — 읽기 전용 확인).
            let productStaging = UpdateReplacementScript.privateStaging(token: "fixture")
            var tmpInfo = stat()
            check(productStaging.deletingLastPathComponent().path == "/private/tmp" && lstat("/private/tmp", &tmpInfo) == 0
                  && tmpInfo.st_uid == 0 && tmpInfo.st_mode & S_ISVTX != 0 && tmpInfo.st_mode & S_IFMT == S_IFDIR,
                  "교체: 관리자 staging은 root 소유·끈적이 비트 폴더 아래")
            let recovery = UpdateError.replaceRecoveryFailed(reason: "fixture", backupPath: "/tmp/backup.app",
                                                             destinationPath: "/tmp/original.app").errorDescription ?? ""
            check(recovery.contains("/tmp/backup.app") && recovery.contains("/tmp/original.app")
                && recovery.contains("Finder"), "교체: 복구 실패 안내에 실제 백업·복원 경로와 방법 포함")
            check(!(UpdateError.replaceFailed("fixture").errorDescription ?? "").contains("그대로예요"),
                  "교체: 실패 시 기존 앱 보존을 무조건 단정하지 않음")
        } catch {
            check(false, "교체 검사 준비·실행 실패: \(error)")
        }
    }
}

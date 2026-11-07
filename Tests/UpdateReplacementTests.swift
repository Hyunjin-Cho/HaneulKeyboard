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
                                       "tampered-after-copy", "linked-copy", "real-codesign", "linked-destination"]
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            for step in ["real", "modes", "copy", "backup", "place", "restore", "occupied", "cleanup"] + rejections.sorted() {
                let directory = root.appendingPathComponent(step)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "하늘 ' \" $HOME $(touch injected) `touch injected2`\n.app"
                let replacement = UpdateReplacementScript(
                    source: directory.appendingPathComponent("new \(name)"),
                    destination: directory.appendingPathComponent(name),
                    staging: directory.appendingPathComponent(".stage \(name)"),
                    backup: directory.appendingPathComponent(".backup \(name)"),
                    identity: identity
                )
                // 사용자 권한 검증을 통과한 뒤 임시 폴더의 사본이 이렇게 바뀐 경우를 흉내 낸다.
                var incoming = identity
                switch step {
                case "swapped-id": incoming = Identity(bundleID: "com.example.other", version: identity.version, build: identity.build)
                case "swapped-version": incoming = Identity(bundleID: identity.bundleID, version: "2020.01.01", build: identity.build)
                case "swapped-build": incoming = Identity(bundleID: identity.bundleID, version: identity.version, build: "100")
                default: break
                }
                try writeBundle(replacement.source, version: "new", identity: incoming)
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
                    exec /bin/mv "$@"
                    """),
                    (remove, """
                    #!/bin/sh
                    if [ "$HANEUL_TEST_STEP" = cleanup ] && [ "$2" = "$HANEUL_TEST_BACKUP" ]; then exit 75; fi
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
                case "real": commands = .init(codesign: codesign.path)
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
                    if step == "linked-destination" {
                        check((try? fm.destinationOfSymbolicLink(atPath: replacement.destination.path)) != nil, "교체: 링크인 목적지를 따라가지 않음")
                    }
                } else if step == "real" || step == "cleanup" || step == "modes" {
                    check(task.terminationStatus == 0 && version(replacement.destination) == "new",
                          "교체 \(step): 새 앱 정상 배치")
                    check(!exists(replacement.staging), "교체 \(step): staging 없음")
                    if step == "cleanup" {
                        check(version(replacement.backup) == "old" && output.contains("정리하지 못했어요"),
                              "교체: 백업 정리 실패는 새 앱 설치 성공과 구분")
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
                        let order = ["/usr/bin/codesign", "/bin/chmod -R u-s,g-s,go-w", "/usr/sbin/chown -hR", "\"$destination\" \"$backup\""]
                            .map { realCommand.range(of: $0)?.lowerBound }
                        check(!order.contains(nil) && zip(order, order.dropFirst()).allSatisfy { $0! < $1! },
                              "교체: 검증 → 권한 정리 → 소유자 맞춤 → 교체 순서")
                    }
                } else {
                    check(task.terminationStatus != 0, "교체 \(step): 실패 상태 반환")
                    if step == "restore" || step == "occupied" {
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

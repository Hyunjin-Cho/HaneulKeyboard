import AppKit
import Foundation

/// 앱이 관리자 실행에 쓰는 실제 명령을 임시 번들에서 실행한다.
/// 실패 주입은 외부 명령 경계에만 넣으며 설치본·설정·관리자 인증은 건드리지 않는다.
@MainActor enum UpdateReplacementTests {
    static func run(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("haneul-replacement-tests-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            for step in ["real", "copy", "backup", "place", "restore", "occupied", "cleanup"] {
                let directory = root.appendingPathComponent(step)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "하늘 ' \" $HOME $(touch injected) `touch injected2`\n.app"
                let replacement = UpdateReplacementScript(
                    source: directory.appendingPathComponent("new \(name)"),
                    destination: directory.appendingPathComponent(name),
                    staging: directory.appendingPathComponent(".stage \(name)"),
                    backup: directory.appendingPathComponent(".backup \(name)")
                )
                for (url, version) in [(replacement.source, "new"), (replacement.destination, "old")] {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    try version.write(to: url.appendingPathComponent("version"), atomically: true, encoding: .utf8)
                }
                let copy = directory.appendingPathComponent("copy.sh")
                let move = directory.appendingPathComponent("move.sh")
                let remove = directory.appendingPathComponent("remove.sh")
                let scripts = [
                    (copy, """
                    #!/bin/sh
                    if [ "$HANEUL_TEST_STEP" = copy ]; then
                        /bin/mkdir -p "$2"
                        printf partial > "$2/version"
                        exit 71
                    fi
                    exec /usr/bin/ditto "$@"
                    """),
                    (move, """
                    #!/bin/sh
                    if [ "$HANEUL_TEST_STEP" = backup ] && [ "$2" = "$HANEUL_TEST_BACKUP" ]; then exit 72; fi
                    if [ "$HANEUL_TEST_STEP" != cleanup ] && [ "$1" = "$HANEUL_TEST_STAGE" ]; then
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
                    """)
                ]
                for (url, script) in scripts {
                    try script.write(to: url, atomically: true, encoding: .utf8)
                    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                }
                let commands = step == "real" ? UpdateReplacementScript.Commands()
                    : .init(copy: copy.path, move: move.path, remove: remove.path)
                let command = replacement.shellCommand(commands: commands)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", command]
                task.currentDirectoryURL = directory
                task.environment = ProcessInfo.processInfo.environment.merging([
                    "HANEUL_TEST_STEP": step,
                    "HANEUL_TEST_STAGE": replacement.staging.path,
                    "HANEUL_TEST_BACKUP": replacement.backup.path
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
                if step == "real" || step == "cleanup" {
                    check(task.terminationStatus == 0 && version(replacement.destination) == "new",
                          "교체 \(step): 새 앱 정상 배치")
                    check(!fm.fileExists(atPath: replacement.staging.path), "교체 \(step): staging 없음")
                    if step == "cleanup" {
                        check(version(replacement.backup) == "old" && output.contains("정리하지 못했어요"),
                              "교체: 백업 정리 실패는 새 앱 설치 성공과 구분")
                    } else {
                        check(!fm.fileExists(atPath: replacement.backup.path), "교체: 성공 뒤 옛 백업 제거")
                        var error: NSDictionary?
                        let literal = UpdateReplacementScript.appleScriptLiteral(command)
                        let roundTrip = NSAppleScript(source: "return \(literal)")?.executeAndReturnError(&error)
                        check(error == nil && roundTrip?.stringValue == command,
                              "교체: AppleScript 문자열 인용의 명령·경로 왕복")
                        let script = NSAppleScript(source: replacement.appleScriptSource)
                        check(script?.compileAndReturnError(&error) == true && error == nil,
                              "교체: 실제 관리자 AppleScript 구문 컴파일")
                    }
                } else {
                    check(task.terminationStatus != 0, "교체 \(step): 실패 상태 반환")
                    if step == "restore" || step == "occupied" {
                        check(version(replacement.backup) == "old" && version(replacement.staging) == "new",
                              "교체 \(step): 복구 실패 뒤 백업과 staging 보존")
                        check(version(replacement.destination) == (step == "occupied" ? "other" : nil),
                              "교체 \(step): 다른 항목을 덮어쓰거나 백업을 그 안에 옮기지 않음")
                    } else {
                        check(version(replacement.destination) == "old", "교체 \(step): 기존 앱이 원래 경로에 있음")
                        check(!fm.fileExists(atPath: replacement.backup.path)
                            && !fm.fileExists(atPath: replacement.staging.path),
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

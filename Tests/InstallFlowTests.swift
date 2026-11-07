import Foundation

/// 2026-11-07 (#176): 설치·업데이트·제거 흐름의 회귀 검사. 임시 폴더 fixture와 주입된 동작만 쓴다.
/// 실제 설치 경로·설정 도메인·입력기 프로세스는 건드리지 않는다.
@MainActor enum InstallFlowTests {
    static func run(_ check: (Bool, String) -> Void) async {
        imeTargetBoundary(check)
    }

    /// security-overlap-F-4 (2): 입력기 바이너리에는 프로세스 종료·ps·defaults 실행 코드가 없어야 한다.
    /// 입력기가 자기 정리에 쓰는 lsregister 호출은 남아 있어야 한다.
    private static func imeTargetBoundary(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
        func text(_ path: String) -> String {
            (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
        }
        let imeFiles = ["IMESources", "Shared"].flatMap { directory in
            ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)) ?? [])
                .filter { $0.hasSuffix(".swift") }
                .map { "\(directory)/\($0)" }
        } + ["Sources/BundleTrust.swift"]
        check(imeFiles.count > 3, "입력기 경계: 입력기 소스를 찾음")
        for forbidden in ["kill(", "/bin/ps", "/usr/bin/defaults", "NSRunningApplication", "CFPreferencesSetValue"] {
            let offenders = imeFiles.filter { text($0).contains(forbidden) }
            check(offenders.isEmpty, "입력기 경계: \(forbidden) 없음 \(offenders)")
        }
        let shared = text("Shared/RemovalObservation.swift")
        check(shared.contains("lsregister") && shared.contains("\"-u\""), "입력기 경계: 자기 정리의 lsregister 호출은 유지")
        check(imeFiles.map { text($0).components(separatedBy: "Process()").count - 1 }.reduce(0, +) == 1,
              "입력기 경계: 프로세스 실행은 lsregister 한 곳뿐")

        let project = text("project.yml")
        guard let start = project.range(of: "\n  HaneulKeyboardIM:\n"),
              let end = project.range(of: "\n    info:", range: start.upperBound..<project.endIndex) else {
            check(false, "입력기 경계: project.yml에서 입력기 타깃을 찾지 못함")
            return
        }
        let imeTarget = project[start.upperBound..<end.lowerBound]
        check(!imeTarget.contains("- path: Sources\n") && !imeTarget.contains("RemovalMainAppOperations"),
              "입력기 경계: 메인 앱 전용 파일이 입력기 타깃에 없음")
        check(project.contains("      - path: Sources\n"), "입력기 경계: 메인 앱 타깃은 Sources 폴더를 통째로 포함")
        let mainOnly = text("Sources/RemovalMainAppOperations.swift")
        check(mainOnly.contains("stopIMEProcesses") && mainOnly.contains("clearProductSettings"),
              "입력기 경계: 프로세스 종료·설정 정리는 메인 앱 전용 파일에 있음")
        let listed = text("scripts/uninstall.sh") + text("scripts/run_updater_tests.sh")
        check(listed.components(separatedBy: "RemovalMainAppOperations.swift").count - 1 == 2,
              "입력기 경계: 복구 CLI·테스트 컴파일 목록에 메인 앱 전용 파일 포함")
    }
}

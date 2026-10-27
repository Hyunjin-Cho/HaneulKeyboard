import Foundation

@main @MainActor enum RemovalCommandMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("하늘키보드 복구 제거: 정식 사용자/시스템 입력기와 제품 설정을 정리해요. 메인 앱은 Finder에서 직접 제거해 주세요. --inspect는 조회만 해요.")
            return
        }
        guard args.isEmpty || args == ["--inspect"] else { print("사용법: bash scripts/uninstall.sh [--inspect | --help]"); exit(64) }
        if args == ["--inspect"] {
            for url in [RemovalObservation.userIME, RemovalObservation.systemIME] {
                print("\(url.path): \(RemovalObservation.absence(at: url).text)")
            }
            print("입력 소스: \(RemovalObservation.observeInputSources().text)")
            switch RemovalObservation.registrations(for: RemovalObservation.imeID) {
            case .paths(let urls): print("시스템 등록 경로 수: \(urls.count)")
            case .unknown(let why): print("시스템 등록: 확인 불가 — \(why)")
            }
            switch RemovalObservation.imeProcesses() {
            case .success(let processes): print("입력기 실행 수: \(processes.count)")
            case .failure: print("입력기 실행: 확인 불가")
            }
            return
        }
        print("하늘키보드 복구 제거 — 메인 앱을 먼저 종료해 주세요. 관리자 요청을 취소하거나 필수 정리가 실패하면 설정을 보존해요.")
        let report = RemovalCommand.run()
        print(report.statusText)
        if report.complete { print("입력기·설정 정리를 확인했어요. 메인 앱 제거는 위 안내대로 직접 진행해 주세요.") }
        else { print("제거가 끝나지 않았어요. 위 항목을 해결한 뒤 다시 시도해 주세요.") }
        exit(RemovalCommand.exitCode(report))
    }
}

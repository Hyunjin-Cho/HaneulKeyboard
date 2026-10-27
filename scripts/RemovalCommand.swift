import Foundation

/// 개발용 복구 CLI도 앱과 같은 제품 실행 순서·C1·OS 관측 함수를 사용한다.
@MainActor
enum RemovalCommand {
    static let officialTeam = "6RH6FXY82P"
    static func run() -> RemovalReport {
        let urls = [RemovalObservation.userIME, RemovalObservation.systemIME]
        var targets: [RemovalTarget] = []
        var absent: [RemovalStep] = []
        let trust: (URL) -> Bool = { BundleTrust.isAppleSignedBundle(at: $0, matchingTeam: officialTeam) }
        return RemovalSequence.run(mode: .commandLine, operations: .init(
            prepare: {
                let other = RemovalObservation.otherMainInstance()
                guard other.reachedGoal else { return other }
                for url in urls {
                    let (target, state) = RemovalObservation.capture(url, identifier: RemovalObservation.imeID, trust: trust)
                    guard state.reachedGoal else { return state }
                    if let target { targets.append(target) }
                    else { absent.append(RemovalStep(id: "ime", title: "정식 입력기", state: state, target: url.path)) }
                }
                return .verified
            },
            secureInput: { RemovalObservation.secureInput() },
            stopProcesses: { RemovalObservation.stopIMEProcesses() },
            removeInputMethods: {
                var results = absent
                for target in targets {
                    let result = RemovalObservation.remove(target, admin: { target in
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                        task.arguments = ["/bin/bash", "-c", RemovalAdminScript(target: target, team: officialTeam).shellCommand()]
                        try task.run(); task.waitUntilExit()
                        if task.terminationStatus == 130 { throw RemovalCancelled() }
                        guard task.terminationStatus == 0 else { throw NSError(domain: "RemovalCommand.Admin", code: Int(task.terminationStatus)) }
                    }, trust: trust)
                    results.append(RemovalStep(id: "ime", title: "정식 입력기 제거", state: result, target: target.url.path))
                    if !result.reachedGoal { break }
                }
                return results
            },
            verifyInputMethods: { RemovalObservation.verifyInputMethods(urls) },
            unregister: { RemovalObservation.unregister(urls, identifier: RemovalObservation.imeID) },
            observeInputSources: { RemovalObservation.observeInputSources() },
            clearSettings: {
                let other = RemovalObservation.otherMainInstance()
                guard other.reachedGoal else { return other }
                guard RemovalObservation.verifyInputMethods(urls).allSatisfy({ $0.state.reachedGoal }) else { return .preserved("입력기 파일이 다시 생겼어요") }
                return RemovalObservation.clearProductSettings()
            },
            removeMainApps: { .preserved("메인 앱은 Finder에서 직접 제거해 주세요") }
        ))
    }
    static func exitCode(_ report: RemovalReport) -> Int32 { report.complete ? 0 : 1 }
}

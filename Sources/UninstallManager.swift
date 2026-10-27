import AppKit
import Foundation

/// 2026-10-11 B안: 실제 설치 대상만 식별하고 공통 실행 순서·검증·C1 관문을 사용한다.
/// 설치/업데이트와의 배타 실행 및 updater 일시 정지는 AppCore가 책임진다.
@MainActor
enum Uninstaller {
    typealias Outcome = UninstallOutcome

    static func run() -> Outcome { Outcome(report: run(mode: .wholeProduct)) }
    static func removeInputMethod() -> RemovalReport { run(mode: .inputMethod) }

    private static func run(mode: RemovalReport.Mode) -> RemovalReport {
        var imeTargets: [RemovalTarget] = []
        var mainTargets: [RemovalTarget] = []
        var absentIMEs: [RemovalStep] = []
        let imeURLs = [RemovalObservation.userIME, RemovalObservation.systemIME]
        return RemovalSequence.run(mode: mode, operations: .init(
            prepare: {
                let other = RemovalObservation.otherMainInstance()
                guard other.reachedGoal else { return other }
                for (index, url) in imeURLs.enumerated() {
                    let (target, state) = RemovalObservation.capture(url, identifier: RemovalObservation.imeID)
                    guard state.reachedGoal else { return state }
                    if let target { imeTargets.append(target) }
                    else { absentIMEs.append(RemovalStep(id: "ime", title: index == 0 ? "사용자 입력기" : "시스템 입력기", state: state, target: url.path)) }
                }
                if mode == .wholeProduct {
                    let current = Bundle.main.bundleURL.standardizedFileURL
                    let directories = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
                    // 개발 산출물, Downloads, DMG, 휴지통은 제품 제거 대상이 아니다.
                    guard directories.contains(where: { current.path.hasPrefix($0.path + "/") }),
                          Bundle.main.bundleIdentifier == RemovalObservation.mainID else {
                        return .preserved("설치한 /Applications 또는 ~/Applications의 하늘키보드 앱에서 전체 제거를 실행해 주세요")
                    }
                    var urls: Set<URL> = [current]
                    for directory in directories {
                        do {
                            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "app" {
                                let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
                                if info?["CFBundleIdentifier"] as? String == RemovalObservation.mainID { urls.insert(url.standardizedFileURL) }
                            }
                        } catch { if !RemovalObservation.isMissing(error) { return .unknown("설치 폴더를 읽지 못했어요: \(directory.path)") } }
                    }
                    // 현재 실행본은 마지막에 지워, 앞선 대상 검증이 호스트 서명을 계속 확인할 수 있게 한다.
                    for url in urls.sorted(by: { $0 == current ? false : $1 == current ? true : $0.path < $1.path }) {
                        let (target, state) = RemovalObservation.capture(url, identifier: RemovalObservation.mainID)
                        guard state.reachedGoal, let target else { return state }
                        mainTargets.append(target)
                    }
                }
                return .verified
            },
            secureInput: { RemovalObservation.secureInput() },
            stopProcesses: { RemovalObservation.stopIMEProcesses() },
            removeInputMethods: {
                var results = absentIMEs
                for target in imeTargets {
                    let state = RemovalObservation.remove(target, admin: IMEInstaller.removeWithAdminPrivileges)
                    results.append(RemovalStep(id: "ime", title: target.url == RemovalObservation.userIME ? "사용자 입력기" : "시스템 입력기", state: state, target: target.url.path))
                    if !state.reachedGoal { break }
                }
                return results
            },
            verifyInputMethods: { RemovalObservation.verifyInputMethods(imeURLs) },
            unregister: {
                let ime = RemovalObservation.unregister(imeURLs, identifier: RemovalObservation.imeID)
                guard ime.reachedGoal else { return ime }
                if mode == .wholeProduct {
                    return RemovalObservation.unregister(mainTargets.map(\.url), identifier: RemovalObservation.mainID)
                }
                return ime
            },
            observeInputSources: { RemovalObservation.observeInputSources() },
            clearSettings: {
                let other = RemovalObservation.otherMainInstance()
                guard other.reachedGoal else { return other }
                guard RemovalObservation.verifyInputMethods(imeURLs).allSatisfy({ $0.state.reachedGoal }) else { return .preserved("입력기 파일이 다시 생겼어요") }
                return RemovalObservation.clearProductSettings()
            },
            removeMainApps: {
                let other = RemovalObservation.otherMainInstance()
                guard other.reachedGoal else { return other }
                // 등록 해제 실패 시 메인 앱을 지우지 않아 같은 화면에서 재시도할 수 있다.
                let registration = RemovalObservation.unregister(mainTargets.map(\.url), identifier: RemovalObservation.mainID)
                guard registration.reachedGoal else { return registration }
                for target in mainTargets {
                    let result = RemovalObservation.remove(target, admin: IMEInstaller.removeWithAdminPrivileges)
                    guard result.reachedGoal else { return result }
                }
                return mainTargets.isEmpty ? .alreadyAbsent : .removed
            }
        ))
    }
}

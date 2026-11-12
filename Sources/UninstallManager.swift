import AppKit
import Foundation

/// 2026-10-11 B안: 실제 설치 대상만 식별하고 공통 실행 순서·검증·C1 관문을 사용한다.
/// 설치/업데이트와의 배타 실행 및 updater 일시 정지는 AppCore가 책임진다.
///
/// 2026-11-07 (#177, 리뷰 app-ui-F-4): 제거 순서(`RemovalSequence`)는 예전에 메인 스레드에서 통째로 돌았다. ps·lsregister·defaults의
/// `waitUntilExit`, 입력기가 늦게 끝날 때의 `Thread.sleep`, 서명 검증이 끝날 때까지 UI가 멈췄고, 진행 표시가 그려지기도 전에 멈출 수 있었다.
/// 이제 순서 전체를 GCD 스레드에서 돌린다 — 순서·실패 보존 규칙(입력기 → LaunchServices → 설정 → 메인 앱, 입력기 삭제가 실패하면 메인 앱 유지)은
/// 같은 `RemovalSequence` 코드가 정하므로 그대로다. 메인으로 돌아와야 하는 것만 `onMain`으로 메인에서 실행하고 기다린다:
/// - NSAppleScript 관리자 인증(IMEInstaller 주석: 인증창은 메인에서 띄운다) — 암호창이 떠 있는 동안은 UI가 멈추는 것이 설계상 불가피하다.
/// - TIS 호출(`secureInput`·`observeInputSources`) · `NSRunningApplication` 조회 · 로그인 항목 해제.
@MainActor
enum Uninstaller {
    typealias Outcome = UninstallOutcome

    static func run() async -> Outcome { Outcome(report: await run(mode: .wholeProduct)) }
    // 2026-11-08 (#201): 입력기만 지우는 `removeInputMethod()`는 호출처(설정의 '입력기 제거')와 함께 없앴다. `.inputMethod` 모드는 CLI·테스트가 쓴다.

    /// 협력 스레드 풀을 막지 않으려고 GCD 스레드에서 돌린다(관리자 암호창을 기다리는 동안 스레드 하나가 묶인다).
    private static func run(mode: RemovalReport.Mode) async -> RemovalReport {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: sequence(mode: mode))
            }
        }
    }

    /// 제거 순서를 일으키는 스레드(GCD)에서 메인으로 한 번 다녀온다. 메인 스레드에서 부르면 바로 실행한다(교착 방지).
    nonisolated private static func onMain<T: Sendable>(_ work: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try MainActor.assumeIsolated(work) }
        return try DispatchQueue.main.sync { try MainActor.assumeIsolated(work) }
    }

    nonisolated private static func sequence(mode: RemovalReport.Mode) -> RemovalReport {
        var imeTargets: [RemovalTarget] = []
        var mainTargets: [RemovalTarget] = []
        var absentIMEs: [RemovalStep] = []
        let imeURLs = [RemovalObservation.userIME, RemovalObservation.systemIME]
        let adminRemoval: (RemovalTarget) throws -> Void = { target in
            try onMain { try IMEInstaller.removeWithAdminPrivileges(target: target) }
        }
        return RemovalSequence.run(mode: mode, operations: .init(
            prepare: {
                let other = onMain { RemovalObservation.otherMainInstance() }
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
            secureInput: { onMain { RemovalObservation.secureInput() } },
            stopProcesses: { RemovalObservation.stopIMEProcesses() },
            removeInputMethods: {
                var results = absentIMEs
                for target in imeTargets {
                    let state = RemovalObservation.remove(target, admin: adminRemoval)
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
                    // 2026-11-13 (#226, 리뷰 install-update-F-4): 로그인 항목 해제는 여기(2026-11-06 #160)에서 메인 앱 삭제 직전(`releaseLoginItem`)으로 옮겼다.
                    return RemovalObservation.unregister(mainTargets.map(\.url), identifier: RemovalObservation.mainID)
                }
                return ime
            },
            observeInputSources: { onMain { RemovalObservation.observeInputSources() } },
            clearSettings: {
                let other = onMain { RemovalObservation.otherMainInstance() }
                guard other.reachedGoal else { return other }
                guard RemovalObservation.verifyInputMethods(imeURLs).allSatisfy({ $0.state.reachedGoal }) else { return .preserved("입력기 파일이 다시 생겼어요") }
                return RemovalObservation.clearProductSettings()
            },
            removeMainApps: {
                let other = onMain { RemovalObservation.otherMainInstance() }
                guard other.reachedGoal else { return other }
                // 등록 해제 실패 시 메인 앱을 지우지 않아 같은 화면에서 재시도할 수 있다.
                let registration = RemovalObservation.unregister(mainTargets.map(\.url), identifier: RemovalObservation.mainID)
                guard registration.reachedGoal else { return registration }
                for target in mainTargets {
                    let result = RemovalObservation.remove(target, admin: adminRemoval)
                    guard result.reachedGoal else { return result }
                }
                return mainTargets.isEmpty ? .alreadyAbsent : .removed
            },
            otherAccountNotice: {
                RemovalObservation.otherAccountNotice(removingSystemIME: imeTargets.contains { $0.url == RemovalObservation.systemIME })
            },
            // 로그인 항목이 지운 앱을 가리키지 않게 메인 앱을 지우기 바로 앞에서 푼다. 실패해도 제거는 계속한다.
            releaseLoginItem: { onMain { try? LoginItem.set(enabled: false) } }
        ))
    }
}

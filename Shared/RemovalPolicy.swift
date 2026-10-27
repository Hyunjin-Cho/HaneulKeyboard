import Foundation

/// 2026-10-11 B안: 실행 결과와 확인된 목표 상태를 구분한다. OS 실행은 별도 어댑터다.
enum RemovalState: Equatable, Sendable {
    case verified, removed, alreadyAbsent
    case preserved(String), cancelled(String), failed(String), unknown(String), needsUserAction(String)

    var reachedGoal: Bool {
        switch self { case .verified, .removed, .alreadyAbsent: return true; default: return false }
    }
    var text: String {
        switch self {
        case .verified: return "확인됨"
        case .removed: return "제거됨"
        case .alreadyAbsent: return "이미 없음"
        case .preserved(let reason): return "보존 — \(reason)"
        case .cancelled(let reason): return "취소 — \(reason)"
        case .failed(let reason): return "실패 — \(reason)"
        case .unknown(let reason): return "확인 불가 — \(reason)"
        case .needsUserAction(let reason): return "사용자 조치 필요 — \(reason)"
        }
    }
}

struct RemovalStep: Equatable, Sendable {
    let id: String
    let title: String
    let state: RemovalState
    var target: String? = nil
    var required = true
}

struct RemovalReport: Equatable, Sendable {
    enum Mode: String, Sendable { case inputMethod, wholeProduct, orphan, commandLine }
    let mode: Mode
    var steps: [RemovalStep]
    var complete: Bool { steps.contains(where: \.required) && steps.allSatisfy { !$0.required || $0.state.reachedGoal } }
    func succeeded(_ id: String) -> Bool {
        let matches = steps.filter { $0.id == id }
        return !matches.isEmpty && matches.allSatisfy { $0.state.reachedGoal }
    }
    var statusText: String {
        steps.map { "\($0.title): \($0.state.text)" + ($0.target.map { "\n  \($0)" } ?? "") }.joined(separator: "\n")
    }
    static func blocked(mode: Mode, reason: String) -> Self {
        Self(mode: mode, steps: [RemovalStep(id: "prepare", title: "제거 준비", state: .preserved(reason))])
    }
}

/// 네 진입점이 같은 C1 관문을 사용한다. Finder 자동 정리는 설정을 지우지 않는다.
enum RemovalPolicy {
    static func canClearSettings(mode: RemovalReport.Mode, inputMethods: [RemovalState], processes: RemovalState) -> Bool {
        (mode == .wholeProduct || mode == .commandLine) && !inputMethods.isEmpty && inputMethods.allSatisfy(\.reachedGoal) && processes.reachedGoal
    }
    static func canRemoveMainApp(critical: [RemovalState]) -> Bool {
        !critical.isEmpty && critical.allSatisfy(\.reachedGoal)
    }
}

/// 실제 제품 흐름. 실패 주입도 이 함수를 실행하며 개인 데이터/OS 작업만 대체한다.
enum RemovalSequence {
    struct Operations {
        let prepare: () -> RemovalState
        let secureInput: () -> RemovalState
        let stopProcesses: () -> RemovalState
        let removeInputMethods: () -> [RemovalStep]
        let verifyInputMethods: () -> [RemovalStep]
        let unregister: () -> RemovalState
        let observeInputSources: () -> RemovalState
        let clearSettings: () -> RemovalState
        let removeMainApps: () -> RemovalState
    }
    static func run(mode: RemovalReport.Mode, operations op: Operations) -> RemovalReport {
        var report = RemovalReport(mode: mode, steps: [])
        func add(_ id: String, _ title: String, _ state: RemovalState, required: Bool = true) {
            report.steps.append(RemovalStep(id: id, title: title, state: state, required: required))
        }
        func keepDataAndApp(_ reason: String) {
            add("settings", "개인 사전·설정", .preserved(reason), required: false)
            add("main", "메인 앱", .preserved("이 앱에서 다시 시도할 수 있어요"), required: false)
        }
        let preparation = op.prepare(); add("prepare", "제거 대상 확인", preparation)
        guard preparation.reachedGoal else { keepDataAndApp("안전한 제거를 확인하지 못했어요"); return report }
        let input = op.secureInput(); add("input", "안전한 입력 소스", input)
        guard input.reachedGoal else { keepDataAndApp("입력 소스를 안전하게 전환하지 못했어요"); return report }
        let stopped = op.stopProcesses(); add("process", "입력기 실행 종료", stopped)
        guard stopped.reachedGoal else { keepDataAndApp("실행 종료를 확인하지 못했어요"); return report }
        let files = op.removeInputMethods(); report.steps += files
        guard !files.isEmpty && files.allSatisfy({ $0.state.reachedGoal }) else {
            keepDataAndApp("입력기 제거를 끝내지 못했어요"); return report
        }
        // 다른 실행본/재기동이 설정을 다시 쓰는 경우를 삭제 관문 직전에 확인한다.
        let quiet = op.stopProcesses(); add("process", "입력기 실행 재확인", quiet)
        guard quiet.reachedGoal else { keepDataAndApp("입력기 실행이 남아 있어요"); return report }
        let verifiedFiles = op.verifyInputMethods(); report.steps += verifiedFiles
        guard !verifiedFiles.isEmpty && verifiedFiles.allSatisfy({ $0.state.reachedGoal }) else {
            keepDataAndApp("입력기 파일의 부재를 확인하지 못했어요"); return report
        }
        let registration = op.unregister(); add("registration", "시스템 등록 해제", registration)
        let sources = op.observeInputSources(); add("sources", "입력 소스 정리", sources)
        guard mode == .wholeProduct || mode == .commandLine else {
            add("settings", "개인 사전·설정", .preserved("입력기만 제거할 때는 보존해요"), required: false)
            add("main", "메인 앱", .preserved("입력기만 제거할 때는 보존해요"), required: false)
            return report
        }
        guard registration.reachedGoal && sources.reachedGoal,
              RemovalPolicy.canClearSettings(mode: mode, inputMethods: files.map(\.state), processes: quiet) else {
            keepDataAndApp("필수 정리 단계가 남아 있어요"); return report
        }
        let finalFiles = op.verifyInputMethods(); report.steps += finalFiles
        guard !finalFiles.isEmpty && finalFiles.allSatisfy({ $0.state.reachedGoal }) else {
            keepDataAndApp("입력기가 다시 생겼거나 조회가 불명확해요"); return report
        }
        let finalQuiet = op.stopProcesses(); add("process", "설정 정리 전 실행 확인", finalQuiet)
        guard finalQuiet.reachedGoal else { keepDataAndApp("입력기 실행 종료를 확인하지 못했어요"); return report }
        let settings = op.clearSettings(); add("settings", "개인 사전·설정 정리", settings)
        guard RemovalPolicy.canRemoveMainApp(critical: [registration, sources, settings]) else {
            add("main", "메인 앱", .preserved("정리하지 못한 항목을 이 앱에서 다시 시도해 주세요"), required: false)
            return report
        }
        if mode == .commandLine {
            add("main", "메인 앱", .needsUserAction("Finder에서 설치한 메인 앱을 휴지통으로 옮겨 주세요"), required: false)
        } else {
            add("main", "메인 앱 제거", op.removeMainApps())
        }
        return report
    }
}


/// 자동 정리는 개인 데이터에 접근할 작업 자체를 받지 않는다. 실패하면 실행을 유지해 재시도한다.
enum OrphanRemovalSequence {
    struct Operations {
        let recheck: () -> RemovalState
        let remove: () -> RemovalState
        let unregister: () -> RemovalState
    }
    static func run(operations: Operations) -> RemovalReport {
        var steps = [RemovalStep(id: "prepare", title: "메인 앱 부재 재확인", state: operations.recheck())]
        guard steps[0].state.reachedGoal else { return RemovalReport(mode: .orphan, steps: steps) }
        let removed = operations.remove()
        steps.append(RemovalStep(id: "ime", title: "자동 입력기 제거", state: removed))
        if removed.reachedGoal {
            steps.append(RemovalStep(id: "registration", title: "시스템 등록 해제", state: operations.unregister()))
        }
        steps.append(RemovalStep(id: "settings", title: "개인 사전·설정", state: .preserved("자동 정리에서는 항상 보존해요"), required: false))
        return RemovalReport(mode: .orphan, steps: steps)
    }
}

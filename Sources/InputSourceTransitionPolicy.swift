import Foundation

/// #81 · 2026-10-12: 입력 내용이나 키를 보지 않고, 확인된 입력 소스 전환만 알린다.
struct InputSourceTransitionPolicy {
    static let defaultsKey = "haneul.inputSourceIndicatorEnabled"
    static let defaultEnabled = true

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    enum Action: Equatable {
        case unchanged
        case showHaneul(token: UInt64)
        case hide
    }

    private let haneulSourceID: String
    private var previousSourceID: String?
    private var generation: UInt64 = 0
    private(set) var activeToken: UInt64?

    init(haneulSourceID: String, currentSourceID: String?) {
        self.haneulSourceID = haneulSourceID
        previousSourceID = currentSourceID
    }

    mutating func observe(sourceID: String?, enabled: Bool, secureInput: Bool,
                          isPreparingIME: Bool) -> Action {
        let previous = previousSourceID
        // OFF/보안 입력/설치·제거 중에도 기준값은 갱신한다. 나중에 가짜 전환을 만들지 않는다.
        previousSourceID = sourceID
        guard enabled, !secureInput, !isPreparingIME,
              let sourceID, let previous else {
            cancelPendingDisplay()
            return .hide
        }
        guard sourceID == haneulSourceID else {
            cancelPendingDisplay()
            return .hide
        }
        // 시작/알림 중복은 표시하지 않고, 이미 보이는 안내의 시간도 늘리지 않는다.
        guard sourceID != previous else { return .unchanged }
        generation &+= 1
        activeToken = generation
        return .showHaneul(token: generation)
    }

    mutating func cancelPendingDisplay() {
        generation &+= 1
        activeToken = nil
    }

    /// 이전 전환의 늦은 타이머가 새 안내를 닫지 못하게 한다.
    mutating func expire(token: UInt64) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        return true
    }
}

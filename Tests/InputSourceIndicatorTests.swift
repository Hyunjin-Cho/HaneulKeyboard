import Foundation

@main
enum InputSourceIndicatorTests {
    static let own = "com.hyunjincho.inputmethod.haneul.korean"
    static let abc = "com.apple.keylayout.ABC"
    static var passed = 0
    static var failed = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if value() { passed += 1 }
        else { failed += 1; print("FAIL: \(message)") }
    }

    static func observe(_ policy: inout InputSourceTransitionPolicy, _ source: String?,
                        enabled: Bool = true, secure: Bool = false, busy: Bool = false)
        -> InputSourceTransitionPolicy.Action {
        policy.observe(sourceID: source, enabled: enabled, secureInput: secure, isPreparingIME: busy)
    }

    static func token(_ action: InputSourceTransitionPolicy.Action) -> UInt64? {
        if case .showHaneul(let token) = action { return token }
        return nil
    }

    static func main() {
        var policy = InputSourceTransitionPolicy(haneulSourceID: own, currentSourceID: own)
        expect(observe(&policy, own) == .unchanged, "이미 하늘을 쓰며 앱 시작: 안내 없음")
        expect(policy.activeToken == nil, "앱 시작: 만료할 표시 없음")
        expect(observe(&policy, abc) == .hide, "영문 전환: 안내 숨김")
        let first = token(observe(&policy, own))
        expect(first != nil, "ABC → 하늘: 안내 표시")
        expect(observe(&policy, own) == .unchanged, "중복 TIS 알림: 안내 다시 띄우지 않음")
        expect(policy.activeToken == first, "중복 TIS 알림: 기존 만료 시간 유지")
        expect(policy.expire(token: first!) == true, "900ms 타이머: 현재 안내 닫음")
        expect(policy.expire(token: first!) == false, "이미 만료한 타이머는 효과 없음")

        // 한국어라는 이유만으로 Apple·타사 입력기를 하늘로 표시하면 안 된다.
        for other in [abc, "com.apple.inputmethod.Korean.2SetKorean",
                      "org.example.haneul.korean", "com.hyunjincho.inputmethod.haneul",
                      "com.hyunjincho.inputmethod.haneul.korean-extra", ""] {
            policy = InputSourceTransitionPolicy(haneulSourceID: own, currentSourceID: abc)
            expect(observe(&policy, other) == .hide, "다른 입력기/부모 ID: 표시 없음 \(other)")
            expect(token(observe(&policy, own)) != nil, "다른 입력기 → 정확한 하늘 모드: 표시")
        }

        policy = InputSourceTransitionPolicy(haneulSourceID: own, currentSourceID: nil)
        expect(observe(&policy, own) == .hide, "시작 ID 확인 불가: 첫 유효 상태는 기준으로만")
        expect(observe(&policy, own) == .unchanged, "기준 상태 중복: 표시 없음")
        _ = observe(&policy, abc)
        let beforeUnknown = token(observe(&policy, own))!
        expect(observe(&policy, nil) == .hide, "관찰 오류: 기존 안내 숨김")
        expect(!policy.expire(token: beforeUnknown), "관찰 오류 후 늦은 타이머 무효")
        expect(observe(&policy, own) == .hide, "ABC → nil → 하늘: 전환을 추측하지 않음")

        for mode in ["disabled", "secure", "busy"] {
            policy = InputSourceTransitionPolicy(haneulSourceID: own, currentSourceID: abc)
            let hidden = observe(&policy, own, enabled: mode != "disabled", secure: mode == "secure", busy: mode == "busy")
            expect(hidden == .hide, "\(mode) 중: 안내 없음")
            expect(observe(&policy, own) == .unchanged, "\(mode) 종료: 뒤늦게 가짜 안내 없음")
            _ = observe(&policy, abc)
            let current = token(observe(&policy, own))!
            expect(observe(&policy, own, enabled: mode != "disabled", secure: mode == "secure", busy: mode == "busy") == .hide,
                   "\(mode) 중복 알림: 기존 안내도 숨김")
            expect(policy.activeToken == nil, "\(mode) 중: 활성 타이머 없음")
            expect(!policy.expire(token: current), "\(mode) 전 타이머 무효")
        }

        // 빠른 반복 전환/설정 OFF/종료 뒤에도 오래된 hide가 새 표시를 닫으면 안 된다.
        policy = InputSourceTransitionPolicy(haneulSourceID: own, currentSourceID: abc)
        var oldTokens: [UInt64] = []
        for _ in 0..<16 {
            let current = token(observe(&policy, own))!
            for old in oldTokens { expect(!policy.expire(token: old), "이전 타이머가 새 안내를 닫지 않음") }
            expect(policy.activeToken == current, "빠른 반복 전환: 최신 안내 유지")
            oldTokens.append(current)
            _ = observe(&policy, abc)
        }
        let latest = token(observe(&policy, own))!
        policy.cancelPendingDisplay()
        expect(!policy.expire(token: latest), "설정 OFF/앱 종료: 예약 타이머 취소")
        expect(observe(&policy, own) == .unchanged, "설정 ON: 실제 다음 전환 전까지 표시 없음")

        let suite = "haneul.tests.input-indicator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(InputSourceTransitionPolicy.isEnabled(in: defaults), "설정 없는 기존 사용자도 기본 ON")
        defaults.set(false, forKey: InputSourceTransitionPolicy.defaultsKey)
        expect(!InputSourceTransitionPolicy.isEnabled(in: defaults), "설정 OFF 보존")
        defaults.set(true, forKey: InputSourceTransitionPolicy.defaultsKey)
        expect(InputSourceTransitionPolicy.isEnabled(in: defaults), "설정 ON 복원")
        defaults.set("invalid", forKey: InputSourceTransitionPolicy.defaultsKey)
        expect(InputSourceTransitionPolicy.isEnabled(in: defaults), "잘못된 저장 타입은 기본값")
        print("Input source indicator: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}

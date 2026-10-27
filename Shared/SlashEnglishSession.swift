import Foundation

/// #87 · 2026-10-12: 한 입력 세션에서 `/`부터 일반 Space까지 영문 키를 그대로 전달한다.
/// 입력 내용은 저장하지 않으며 자동 변환·앱별 예외 설정과 독립적이다.
struct SlashEnglishSession {
    static let defaultsKey = "haneul.slashEnglishEnabled"
    static let defaultEnabled = true

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    enum Action: Equatable {
        case composeKorean
        /// 앞 조합을 기존 활성 구두점 경계 정책으로 확정한 뒤 `/` 자체는 앱에 전달한다.
        case begin
        case passThrough
        /// 이번 일반 Space도 앱이 한 번만 입력한다. 다음 키부터 한글 조합을 재개한다.
        case end
    }

    private(set) var isActive = false

    mutating func reset() { isActive = false }

    mutating func process(characters: String?, keyCode: UInt16,
                          modifierFlagsRaw: UInt, enabled: Bool) -> Action {
        guard enabled else {
            reset()
            return .composeKorean
        }
        // NSEvent의 device-independent modifier 비트. CapsLock/Fn은 문자 수정을
        // 뜻하지 않으므로 무시한다. Shift+Space와 Ctrl/Cmd/Option 단축키는 그대로 둔다.
        let modifiers = modifierFlagsRaw & ((1 << 17) | (1 << 18) | (1 << 19) | (1 << 20))
        if isActive {
            if keyCode == 49, characters == nil || characters == " ", modifiers == 0 {
                reset()
                return .end
            }
            return .passThrough
        }
        let applicationModifiers: UInt = (1 << 18) | (1 << 19) | (1 << 20)
        // KeyboardLayout2Set과 같은 ABC override 전제. macOS가 문자를 주지 않은
        // 경우만 물리 Slash/키패드 Divide를 사용하고, 실제 '?' 등은 덮어쓰지 않는다.
        let isSlash = characters == "/" || (characters == nil
            && (keyCode == 44 || keyCode == 75) && modifiers & (1 << 17) == 0)
        guard isSlash, modifiers & applicationModifiers == 0 else {
            return .composeKorean
        }
        isActive = true
        return .begin
    }
}

import Foundation

/// #87 · 2026-10-25: `/` 뒤 영문을 전달하고 Space·시작 기호 삭제·종료 기호에서 복귀한다.
/// 시작 위치만 세션 동안 보유하며 입력 내용은 저장하지 않는다. 자동 변환 설정과 독립적이다.
struct SlashEnglishSession {
    static let defaultsKey = "haneul.slashEnglishEnabled"
    static let defaultEnabled = true
    static let endingDelimiters: Set<String> = [")", "]", "}"]

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    enum Action: Equatable {
        case composeKorean
        /// 앞 조합을 기존 활성 구두점 경계 정책으로 확정한 뒤 `/` 자체는 앱에 전달한다.
        case begin
        case passThrough
        /// 종료 Space·삭제·기호도 앱이 한 번만 처리한다. 다음 키부터 한글 조합을 재개한다.
        case end
    }

    /// 컨트롤러가 handle 안에서만 읽는 일회성 자료. 세션에는 이 값을 저장하지 않는다.
    /// triggerText == nil은 조회 불가, 빈 문자열은 해당 위치에 문자가 없다는 확인이다.
    struct Context {
        let selection: NSRange
        let markedRange: NSRange
        let triggerText: String?
    }

    private(set) var isActive = false
    private(set) var triggerRange: NSRange?
    /// Only the very next key can use the no-readback immediate-delete fallback.
    /// No text or sequence of typed characters is retained.
    private var awaitingFirstKeyAfterTrigger = false

    mutating func reset() {
        isActive = false
        triggerRange = nil
        awaitingFirstKeyAfterTrigger = false
    }

    /// 앞 조합을 확정한 뒤, `/` 키를 앱에 전달하기 직전의 삽입 위치를 사용한다.
    /// RPC 중 reset된 세션을 되살리지 않는다. 위치 조회 불가이면 범위를 추적하지 않는다.
    @discardableResult
    mutating func captureTrigger(in selection: NSRange, markedRange: NSRange) -> Bool {
        guard isActive else { return false }
        guard Self.validSelection(selection), Self.noMarkedText(markedRange) else {
            triggerRange = nil
            return false
        }
        triggerRange = NSRange(location: selection.location, length: 1)
        return true
    }

    private static func validSelection(_ range: NSRange) -> Bool {
        range.location >= 0 && range.location != NSNotFound && range.length >= 0
            && range.length <= Int.max - range.location
    }

    private static func noMarkedText(_ range: NSRange) -> Bool {
        range.location >= 0 && range.length == 0
    }

    private func deletesTrigger(keyCode: UInt16, modifiers: UInt,
                                modifierFlagsRaw: UInt, selection: NSRange, trigger: NSRange) -> Bool {
        guard keyCode == 51 || keyCode == 117 else { return false }
        // Cmd+A → Backspace 등 선택 삭제는 단어/줄 삭제 수정자와 무관하게 범위를 알 수 있다.
        if selection.length > 0 {
            return selection.location <= trigger.location
                && selection.length > trigger.location - selection.location
        }
        // 수정자 단어/줄 삭제 범위는 추측하지 않는다. 앱에 전달한 뒤 실제 기호를 재확인한다.
        let applicationModifiers: UInt = (1 << 18) | (1 << 19) | (1 << 20)
        guard modifiers & applicationModifiers == 0 else { return false }
        if keyCode == 117 { return selection.location == trigger.location }
        // Fn+Delete를 keyCode 51로 보내는 호스트는 삭제 방향을 추측하지 않는다.
        guard modifierFlagsRaw & (1 << 23) == 0 else { return false }
        return selection.location == trigger.location + 1
    }

    private func deletesImmediateTrigger(keyCode: UInt16, modifiers: UInt,
                                         modifierFlagsRaw: UInt, context: Context?) -> Bool {
        let applicationModifiers: UInt = (1 << 18) | (1 << 19) | (1 << 20)
        guard keyCode == 51, modifiers & applicationModifiers == 0,
              modifierFlagsRaw & (1 << 23) == 0 else { return false }
        // A host without range support still receives '/' followed immediately
        // by plain Backspace. End the temporary mode, leaving deletion to it.
        guard let context else { return true }
        // Available geometry must agree. An unknown substring alone must not
        // prevent this one adjacent deletion; contradictory/marked ranges do.
        guard context.triggerText == nil, Self.validSelection(context.selection),
              Self.noMarkedText(context.markedRange), context.selection.length == 0,
              let trigger = triggerRange else { return false }
        return context.selection.location == trigger.location + 1
    }

    mutating func process(characters: String?, keyCode: UInt16,
                          modifierFlagsRaw: UInt, enabled: Bool, context: Context? = nil) -> Action {
        guard enabled else {
            reset()
            return .composeKorean
        }
        // NSEvent의 device-independent modifier 비트. CapsLock/Fn은 문자 수정을
        // 뜻하지 않으므로 무시한다. Shift+Space와 Ctrl/Cmd/Option 단축키는 그대로 둔다.
        let modifiers = modifierFlagsRaw & ((1 << 17) | (1 << 18) | (1 << 19) | (1 << 20))
        let isFirstKeyAfterTrigger = awaitingFirstKeyAfterTrigger
        if isActive { awaitingFirstKeyAfterTrigger = false }
        if isActive, let trigger = triggerRange, let context,
           Self.validSelection(context.selection), Self.noMarkedText(context.markedRange) {
            if let text = context.triggerText, text != "/" {
                // 조회에 성공해 시작 기호가 사라졌다면 현재 키부터 한글 경로로 돌린다.
                reset()
            } else if context.triggerText == "/",
                      deletesTrigger(keyCode: keyCode, modifiers: modifiers,
                                     modifierFlagsRaw: modifierFlagsRaw,
                                     selection: context.selection, trigger: trigger) {
                // `/`만 지워 빈 필드가 되면 다음 substring은 nil일 수 있다.
                // 삭제 전에 확인한 기호·선택 범위로 종료하고 실제 삭제는 앱에 맡긴다.
                reset()
                return .end
            }
        }
        if isActive {
            if isFirstKeyAfterTrigger,
               deletesImmediateTrigger(keyCode: keyCode, modifiers: modifiers,
                                       modifierFlagsRaw: modifierFlagsRaw, context: context) {
                reset()
                return .end
            }
            let applicationModifiers: UInt = (1 << 18) | (1 << 19) | (1 << 20)
            let delimiter: String?
            if let characters {
                delimiter = characters
            } else if keyCode == 29, modifiers & (1 << 17) != 0 {
                delimiter = ")"
            } else if keyCode == 30 {
                delimiter = modifiers & (1 << 17) == 0 ? "]" : "}"
            } else {
                delimiter = nil
            }
            if let delimiter, Self.endingDelimiters.contains(delimiter),
               modifiers & applicationModifiers == 0 {
                reset()
                return .end
            }
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
        awaitingFirstKeyAfterTrigger = true
        return .begin
    }
}

import Foundation

/// #87 · 2026-10-25: `/` 뒤 영문을 전달하고 Space·시작 기호 삭제·종료 기호에서 복귀한다(2026-11-04 Return 추가).
/// 시작 위치만 세션 동안 보유하며 입력 내용은 저장하지 않는다. 자동 변환 설정과 독립적이다.
/// 2026-11-04: 글자 조회가 안 되는 앱을 위해 `/` 뒤 글자 "수"만 함께 센다(내용·키 순서는 남기지 않는다).
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
    /// 2026-11-07 (#173, 리뷰 F-1): NSTextView는 문서 끝 읽기에 빈 문자열 대신 nil을 준다(실측) — nil을 전부 조회 불가로
    /// 읽으면 수정키 삭제로 기호가 사라져도 영어가 남았다. 아래 triggerWasRead로 호스트가 읽기를 지원하는지 가른다.
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
    /// 2026-11-04 (#87 오너 신고): 글자 조회가 안 되는 앱(터미널 등)에서 `/`와 뒷글자를 전부 지워도 영어가 남았다.
    /// `/` 뒤에 앱이 넣은 글자 수만 센다 — 내용은 저장하지 않는다. 셀 수 없는 편집(이동·붙여넣기·수정키 삭제·
    /// 엔터·dead key 등)이 끼면 nil로 두고 개수로는 종료하지 않는다(기존 보수 정책).
    private var typedAfterTrigger: Int?
    /// 커서 위치를 돌려주지만 입력해도 움직이지 않는 앱(Ghostty처럼 늘 시작 자리)을 확인했는지.
    private var caretFrozen = false
    /// 커서 위치가 개수와 한 번이라도 어긋났는지(마우스 이동 등 — 그 뒤로는 개수를 믿지 않는다).
    private var caretDiverged = false
    /// 커서 위치가 개수와 한 번이라도 맞았는지 — 맞았던 호스트는 커서를 제대로 알려 주는 앱이다(Fable 리뷰 F3).
    private var caretMatched = false
    /// 이 세션에서 시작 자리의 `/`를 읽은 적이 있는지 — 글자는 저장하지 않고 호스트가 읽기를 지원한다는 사실만 남긴다.
    private var triggerWasRead = false

    mutating func reset() {
        isActive = false
        triggerRange = nil
        awaitingFirstKeyAfterTrigger = false
        typedAfterTrigger = nil
        caretFrozen = false
        caretDiverged = false
        caretMatched = false
        triggerWasRead = false
    }

    /// 2026-11-12 (#224, 리뷰 input-core-F-5): 시작 직후 첫 키를 기다리는 중인지 — 컨트롤러가 시작 자리를 한 번 다시 잡을 때만 쓴다.
    var isAwaitingFirstKey: Bool { isActive && awaitingFirstKeyAfterTrigger }

    /// 2026-11-12 (#224, 리뷰 input-core-F-5): 확정 직후 옛 커서를 주는 호스트에서 시작 자리를 잘못 잡았을 때, 첫 키에서
    /// 커서 바로 앞의 `/` 자리로 한 번 옮긴다. 시작 직후 첫 키가 아니면 바꾸지 않는다. 글자는 저장하지 않는다(위치만).
    @discardableResult
    mutating func relocateTrigger(to location: Int) -> Bool {
        guard isActive, awaitingFirstKeyAfterTrigger, location >= 0, location != NSNotFound else { return false }
        triggerRange = NSRange(location: location, length: 1)
        return true
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
        // #87: range support can disappear between '/' and Backspace. NSNotFound
        // is unavailable geometry, not proof that the caret moved elsewhere.
        // Only the first plain Backspace gets this fallback; marked text and
        // an actual nonadjacent caret still block it.
        guard Self.noMarkedText(context.markedRange) else { return false }
        if context.selection.location == NSNotFound, context.selection.length == 0 {
            return true
        }
        // Available geometry must agree. An unknown substring alone must not
        // prevent this one adjacent deletion; contradictory/marked ranges do.
        guard context.triggerText == nil, Self.validSelection(context.selection),
              Self.noMarkedText(context.markedRange), context.selection.length == 0,
              let trigger = triggerRange else { return false }
        return context.selection.location == trigger.location + 1
    }

    /// 앱에 글자 하나를 넣는 일반 키인지(Shift·Option 문자 포함, Cmd/Ctrl 단축키·제어 문자·기능 키 제외).
    private static func insertsOneCharacter(_ characters: String?, modifiers: UInt) -> Bool {
        guard modifiers & ((1 << 18) | (1 << 20)) == 0, let characters, characters.count == 1,
              let scalar = characters.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7f && !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// 커서 위치를 개수와 맞춰 본다. 조회 가능한 위치가 개수 기대값(시작 기호 뒤 + typed)과 다르면:
    /// 시작 자리에 그대로면 '움직이지 않는 커서' 호스트, 그 밖이면 실제 커서 이동으로 본다.
    private mutating func observeCaret(_ context: Context?, typed: Int) {
        guard let context, let trigger = triggerRange, Self.validSelection(context.selection),
              context.selection.location != NSNotFound, Self.noMarkedText(context.markedRange),
              context.selection.length == 0 else { return }
        let location = context.selection.location
        // Fable 리뷰 F2: 커서를 Int.max 근처로 주는 호스트에서 덧셈이 넘쳐 입력기가 죽었다 — 넘침 검사 덧셈으로.
        let (expected, overflow) = trigger.location.addingReportingOverflow(1 + typed)
        guard !overflow else { return }
        if location == expected {
            // 한 박자 늦은 스냅샷 때문에 잠깐 '움직이지 않는 커서'로 봤어도, 맞는 순간 정상 호스트로 돌아온다.
            caretMatched = true
            caretFrozen = false
            return
        }
        // Fable 리뷰 F3: 한 번이라도 맞았던 호스트에서 커서가 시작 자리에 있으면 '움직이지 않는 커서'가 아니라
        // 실제 이동(마우스)이다. 시작 자리 고정은 맞은 적이 없는 호스트(Ghostty형 — 늘 0)만 해당한다.
        if location == trigger.location, !caretMatched {
            caretFrozen = true
        } else if !caretFrozen {
            caretDiverged = true
        }
    }

    /// 2026-11-12 (#224, 리뷰 input-core-F-4): 읽은 커서가 슬래시 낱말을 떠났는가 — 글자를 넣는 키에서만 쓴다(추가 읽기 없음).
    /// 시작 기호보다 앞이면 떠난 것이다. 기호 바로 앞(같은 자리)은 커서 값이 개수와 맞은 적이 있는 호스트에서만 떠난 것으로 본다
    /// (늘 시작 자리를 주는 Ghostty형·한 박자 늦은 첫 키와 구분). 뒤쪽은 개수를 세는 동안 '기호 뒤 + 센 글자 수'를 넘으면 떠난 것이다.
    /// 화살표·단축키로 개수를 놓친 뒤의 뒤쪽 이동은 판단하지 않는다(낱말 끝을 모른다 — 지금처럼 영어 유지).
    /// 슬래시 낱말 안에서 좌우로 고치는 것은 계속 영어다(2026-10 결정, 이동 키 자체는 종료하지 않는다).
    private func caretLeftSlashWord(_ selection: NSRange, trigger: NSRange) -> Bool {
        guard selection.length == 0 else { return false }
        let location = selection.location
        if location < trigger.location { return true }
        if location == trigger.location { return caretMatched }
        guard let typed = typedAfterTrigger, caretMatched, !caretFrozen else { return false }
        let (end, overflow) = trigger.location.addingReportingOverflow(1 + typed)
        return !overflow && location > end
    }

    /// 개수가 0일 때의 일반 Backspace를 시작 기호 삭제로 봐도 되는지 — 글자 조회가 안 되는 경우에만 쓴다.
    private func countedDeletionAllowed(_ context: Context?, firstKey: Bool) -> Bool {
        guard typedAfterTrigger == 0, !caretDiverged else { return false }
        guard let context else { return true }
        guard context.triggerText == nil, Self.noMarkedText(context.markedRange) else { return false }
        let selection = context.selection
        if selection.location == NSNotFound { return selection.length == 0 }
        guard Self.validSelection(selection), selection.length == 0, let trigger = triggerRange else { return false }
        if selection.location == trigger.location &+ 1 { return true }     // trigger는 validSelection을 거쳐 넘치지 않는다
        return selection.location == trigger.location && (caretFrozen || firstKey)
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
            } else if context.triggerText == "/" {
                triggerWasRead = true
                if deletesTrigger(keyCode: keyCode, modifiers: modifiers,
                                  modifierFlagsRaw: modifierFlagsRaw,
                                  selection: context.selection, trigger: trigger) {
                    // `/`만 지워 빈 필드가 되면 다음 substring은 nil일 수 있다.
                    // 삭제 전에 확인한 기호·선택 범위로 종료하고 실제 삭제는 앱에 맡긴다.
                    reset()
                    return .end
                }
                if Self.insertsOneCharacter(characters, modifiers: modifiers),
                   caretLeftSlashWord(context.selection, trigger: trigger) {
                    // 2026-11-12 (#224, 리뷰 input-core-F-4): 클릭·위아래 이동으로 슬래시 낱말을 떠났다 — 이 키부터 한글로 돌린다.
                    reset()
                }
            } else if context.triggerText == nil, triggerWasRead, context.selection.length == 0,
                      context.selection.location <= trigger.location {
                // 2026-11-07 (#173, 리뷰 F-1): 읽기가 되던 호스트에서 시작 자리 읽기가 nil이고 커서가 그 자리 이하면 기호가 문서
                // 끝에서 사라진 것이다(수정키 삭제·잘라내기·실행 취소). 처음부터 못 읽는 호스트(Ghostty형)는 플래그가 없어 추측하지 않는다.
                reset()
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
            // 2026-11-04 오너 결정: Return도 한글로 돌아온다(10월 'Space만 종료'에서 확장). 글자를 돌려주지 않는 터미널에서
            // /clear를 실행한 뒤 다음 입력이 영어로 남았다. Return·키패드 Enter, Cmd/Ctrl/Option 없이(Shift 줄바꿈 포함).
            if keyCode == 36 || keyCode == 76, modifiers & applicationModifiers == 0 {
                reset()
                return .end
            }
            // 2026-11-04 (#87): 글자 조회가 안 되는 앱에서도 개수로 시작 기호 삭제를 알아챈다.
            if let typed = typedAfterTrigger { observeCaret(context, typed: typed) }
            let plainBackspace = keyCode == 51 && modifiers & applicationModifiers == 0
                && modifierFlagsRaw & (1 << 23) == 0
            if plainBackspace {
                if countedDeletionAllowed(context, firstKey: isFirstKeyAfterTrigger) {
                    reset()
                    return .end
                }
                if let typed = typedAfterTrigger { typedAfterTrigger = typed > 0 ? typed - 1 : nil }
            } else if Self.insertsOneCharacter(characters, modifiers: modifiers) {
                if let typed = typedAfterTrigger { typedAfterTrigger = typed + 1 }
            } else {
                typedAfterTrigger = nil
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
        typedAfterTrigger = 0
        caretFrozen = false
        caretDiverged = false
        triggerWasRead = false
        return .begin
    }
}

import Cocoa
import Carbon
import InputMethodKit
import os.log

/// Bridges the Foundation-only KoreanComposer to the IMK client.
private struct IMKComposerClient: ComposerClient, ExternalEnglishContextClient {
    let client: IMKTextInput
    let trace: RoundTripTrace
    let composer: KoreanComposer
    var isCurrentSession: () -> Bool = { true }

    func insertText(_ text: String) {
        guard isCurrentSession() else { return }
        trace.call(.composerInsert, composer: composer) {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    func setMarkedText(_ text: String) {
        guard isCurrentSession() else { return }
        trace.call(.composerMark, composer: composer) {
            client.setMarkedText(
                text as NSString,
                selectionRange: NSRange(location: (text as NSString).length, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
    }

    func contextSelection() -> NSRange { trace.call(.selection, composer: composer) { client.selectedRange() } }
    func contextMarkedRange() -> NSRange { trace.call(.markedRange, composer: composer) { client.markedRange() } }
    func contextSubstring(in range: NSRange) -> String? {
        trace.call(.substring, composer: composer) { client.attributedSubstring(from: range)?.string }
    }
}

@objc(HaneulInputController)
final class HaneulInputController: IMKInputController {
    private let log = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "ime")
    private let composer = KoreanComposer()
    private let roundTripTrace = RoundTripTrace()
    private var didOverrideKeyboard = false
    private var slashEnglish = SlashEnglishSession()
    private weak var slashClient: AnyObject?
    private var externalContextPending = true
    // 2026-10-20: client RPCs can service a session callback while awaiting a reply.
    // Never continue a captured conversion into a different input session.
    private var sessionGeneration: UInt = 0
    private var inputSequence: UInt = 0

    // Chromium hosts can acknowledge replacement before their text snapshot updates.
    // Keep only a candidate until a later shortcut verifies the expected surface.
    // It never enables English context or survives an input-session boundary.
    private struct DeferredManualToggle {
        let identifier = UUID()
        let generation: UInt
        let start: Int
        let trailing: String
        let hangul: String
        let english: String
        let toEnglish: Bool
        let origin: KoreanComposer.ConversionOrigin
    }
    private var deferredManualToggle: DeferredManualToggle?

    // Listen ONLY for .keyDown. macOS routes CapsLock-based Korean<->ABC
    // switching automatically via TICapsLockLanguageSwitchCapable in plist,
    // and we must NOT subscribe to .flagsChanged — every Shift press fires
    // a flagsChanged event, and if we react to it (even just to read state)
    // it's easy to accidentally flush the in-flight Hangul syllable, which
    // is what breaks 쌍자음 input (ㅆ ㄲ ㄸ ㅉ ㅃ).
    override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        sessionGeneration &+= 1
        deferredManualToggle = nil
        roundTripTrace.record(.activateBegin, composer: composer)
        defer { roundTripTrace.record(.activateEnd, composer: composer) }
        log.log("activateServer")
        slashEnglish.reset()
        externalContextPending = true
        slashClient = sender as AnyObject?
        // NOTE: never query the client (markedRange/attributes/...) in here —
        // it deadlocks Chromium-based apps. Defaults reads only.
        // 2026-09-19 (#32): 메인 앱이 지워졌는지 확인 — 즉시 반환하고 백그라운드에서
        // 60초에 한 번만 조회한다(전환 경로에 동기 작업을 얹지 않는다).
        OrphanWatcher.shared.checkIfDue()
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        // 2026-09-21 (#53): 개인 사전도 같은 시점에 읽는다(defaults 읽기뿐 — 클라이언트 질의 아님).
        composer.personalDictionary = PersonalDictionary.load(from: .standard)
        composer.resetEnglishContext() // 새 필드/앱 — 영어 문맥은 이어지지 않음
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }
    }

    override func deactivateServer(_ sender: Any!) {
        sessionGeneration &+= 1
        deferredManualToggle = nil
        roundTripTrace.record(.deactivateBegin, composer: composer)
        defer { roundTripTrace.record(.deactivateEnd, composer: composer) }
        log.log("deactivateServer")
        slashEnglish.reset()
        externalContextPending = false
        slashClient = nil
        if let client = sender as? IMKTextInput {
            composer.commit(to: IMKComposerClient(client: client, trace: roundTripTrace, composer: composer))
        }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        sessionGeneration &+= 1
        deferredManualToggle = nil
        roundTripTrace.record(.commitBegin, composer: composer)
        defer { roundTripTrace.record(.commitEnd, composer: composer) }
        // #87: 이 콜백에는 확정 원인/키 이벤트 ID가 없다. 같은 프록시도 다른 입력칸을
        // 나타낼 수 있으므로 세션 종료 요청은 항상 초기화한다. 직전 Enter/Tab/Esc만
        // 보고 다음 commit을 무시하면 다음 마우스·포커스 이동을 삼킬 수 있다.
        // 키 자체로는 종료하지 않지만, 호스트가 명시적으로 세션 종료를 요청하면 종료한다.
        // Apple IMKServerInput.commitComposition: 종료 시 per-session variables를 정리.
        slashEnglish.reset()
        externalContextPending = true
        slashClient = sender as AnyObject?
        guard let client = sender as? IMKTextInput else { return }
        composer.commit(to: IMKComposerClient(client: client, trace: roundTripTrace, composer: composer))
        composer.resetEnglishContext() // 클릭/포커스 이동 = 문맥 단절
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        inputSequence &+= 1
        let eventSequence = inputSequence

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Key codes/characters are keystroke content — never log them as
        // .public (an IME writing keystrokes to the unified log is a
        // keylogger). Even with .private redaction, emitting one log record
        // per keystroke is poor hygiene for an IME — so the whole typing-path
        // log is Debug-only; release builds write nothing per keystroke.
        #if DEBUG
        log.log("keyDown code=\(event.keyCode, privacy: .private) shift=\(mods.contains(.shift), privacy: .public) caps=\(mods.contains(.capsLock), privacy: .public)")
        #endif

        if !didOverrideKeyboard {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }

        let composerClient = IMKComposerClient(client: client, trace: roundTripTrace, composer: composer)

        // 클라이언트 교체 시 이전 대상의 임시 영어 상태를 넘기지 않는다.
        // 객체 식별만 비교하며 입력 내용·커서·앱 정보를 추가 조회하지 않는다.
        if slashClient !== (sender as AnyObject?) {
            sessionGeneration &+= 1
            deferredManualToggle = nil
            roundTripTrace.record(.clientChangedBegin, composer: composer)
            defer { roundTripTrace.record(.clientChangedEnd, composer: composer) }
            slashEnglish.reset()
            slashClient = sender as AnyObject?
            composer.resetEnglishContext()
            externalContextPending = true
        }
        let eventSession = sessionGeneration

        let isToggle = RevertKey.couldMatch(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue)
            && RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
                .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue)
        if !isToggle { deferredManualToggle = nil }

        // (secure-input) 정상적인 secure 필드는 macOS가 서드파티 IME를 아예
        // 우회하지만(PRIVACY.md #4), 그 우회가 안 걸리는 예외 상황에 대비한
        // 방어선이다 — 조합 중이던 자모를 흘리지 않고 커밋한 뒤, 이번 키는
        // 조합하지 않고 그대로 통과시킨다(review0706 P3-4).
        if IsSecureEventInputEnabled() {
            deferredManualToggle = nil
            slashEnglish.reset()
            externalContextPending = false
            composer.commit(to: composerClient)
            composer.resetEnglishContext()
            return false
        }

        // R12: bounded opt-in state diagnostics; no keystroke/text logging.
        let traceState = roundTripTrace.beginHandle(isToggle: isToggle, composer: composer)
        defer { roundTripTrace.endHandle(traceState, composer: composer) }

        // #87: Backspace·Shift+Space·단축키보다 먼저 분기한다. 영어 상태에서는
        // 키를 소비하거나 재삽입하지 않아 앱의 삭제·단축키·Option 입력이 그대로 동작한다.
        // OFF도 다음 키부터 반영한다. 입력 내용은 이 상태에 저장되지 않는다.
        // 세션이 바뀌어도 아직 처리하지 않은 원래 키는 앱에 전달한다.
        // 아래 명시적 변환 경로의 stale 작업 취소와 달리 키 자체를 소비하면 안 된다.
        let slashEnabled = SlashEnglishSession.isEnabled(in: .standard)
        var slashContext: SlashEnglishSession.Context?
        if slashEnabled, slashEnglish.isActive, let trigger = slashEnglish.triggerRange {
            let selection = tracedSelection(client)
            guard eventSession == sessionGeneration else { return false }
            let marked = tracedMarkedRange(client)
            guard eventSession == sessionGeneration else { return false }
            let triggerText = tracedSubstring(client, from: trigger)?.string
            guard eventSession == sessionGeneration else { return false }
            slashContext = .init(selection: selection, markedRange: marked, triggerText: triggerText)
        }
        let slashAction = slashEnglish.process(
            characters: event.characters, keyCode: event.keyCode,
            modifierFlagsRaw: mods.rawValue,
            enabled: slashEnabled, context: slashContext)
        if slashAction == .begin {
            externalContextPending = false
            // Fn 등 passive modifier 분기로 빠지지 않게 slash 시작 경계를 먼저 처리.
            // 문자열 누락의 물리 키 fallback도 확정 경계는 실제 '/'와 동일하다.
            commitActiveBoundary("/", client: client)
            guard eventSession == sessionGeneration else { return false }
            if slashEnglish.isActive {
                // 변환으로 앞 단어 길이가 달라질 수 있으므로 확정 이후의 위치를 쓴다.
                let selection = tracedSelection(client)
                guard eventSession == sessionGeneration else { return false }
                let marked = tracedMarkedRange(client)
                guard eventSession == sessionGeneration else { return false }
                slashEnglish.captureTrigger(in: selection, markedRange: marked)
            }
            return false
        }
        if slashAction == .passThrough || slashAction == .end {
            externalContextPending = false
            composer.resetEnglishContext()
            return false
        }

        if event.keyCode == 51 {
            externalContextPending = false
            // (H-08) Cmd/Opt/Ctrl+Backspace(단어·줄 삭제)는 composer가 먹지
            // 않고 클라이언트가 처리하게 한다 — 조합 중에도 일상 단축키가 한
            // 자모 삭제로 둔갑하지 않도록. 무수정 Backspace만 자모를 떼어낸다.
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                composer.commit(to: composerClient)
                composer.resetEnglishContext()
                return false
            }
            refreshAutomaticSettings(client: client)
            if IsSecureEventInputEnabled() {
                composer.commit(to: composerClient)
                composer.resetEnglishContext()
                externalContextPending = false
                return false
            }
            let handled = composer.deleteBackward(client: composerClient)
            // Backspace into already-committed text (composer absorbed
            // nothing) breaks any English run — otherwise a wrongly-converted
            // word (새→to) can't be fixed by delete+retype (it re-converts).
            if !handled {
                composer.resetEnglishContext()
            }
            return handled
        }

        if isToggle, deferredManualToggle != nil {
            guard confirmDeferredManualToggle(client: client, generation: eventSession) else {
                // Unknown/stale reads must not fall through to keyboard inversion.
                return true
            }
        }

        // 미확정 혼합 표시는 문서 재삽입 없이 조합 범위 안에서 원문과 왕복한다.
        if RevertKey.couldMatch(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue),
           RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
               .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue),
           let displayed = composer.pendingParticlePreviewText {
            let marked = tracedMarkedRange(client)
            guard eventSession == sessionGeneration else { return true }
            let selection = tracedSelection(client)
            guard eventSession == sessionGeneration else { return true }
            let matchesGeometry = marked.location != NSNotFound
                && marked.length == (displayed as NSString).length
                && selection.length == 0 && selection.location == NSMaxRange(marked)
            let markedText = matchesGeometry ? tracedSubstring(client, from: marked)?.string : nil
            guard eventSession == sessionGeneration else { return true }
            if markedText == displayed {
                refreshAutomaticSettings(client: client)
                guard eventSession == sessionGeneration else { return true }
                if IsSecureEventInputEnabled() {
                    composer.commit(to: composerClient)
                    composer.resetEnglishContext()
                    externalContextPending = false
                    return false
                }
                if composer.togglePendingParticlePreview(
                    client: guardedComposerClient(client, generation: eventSession)) {
                    guard eventSession == sessionGeneration else { return true }
                    externalContextPending = false
                    return true
                }
            }
        }

        // 되돌리기 키(기본 Shift+Space): 마지막 변환을 영어↔한글 토글로 교체(㉠ 직후만).
        // 커서 직전 텍스트를 읽어 boundary(스페이스·구두점)를 건너뛰고 영어/
        // 한글을 정확히 찾아 replace — 변환 시 입력된 공백("i ") 때문에 커서가
        // 영어 바로 뒤가 아니어도 옳게 동작한다. lastConversion을 유지해 연속
        // 되돌리기로 영↔한을 반복 토글(다음 글자 입력/백스페이스 시 리셋).
        // 한글 모드는 CapsLock 전환 방식이라 keyDown의 modifierFlags에
        // .capsLock이 상시 포함될 수 있다 — 엄격 비교하면 한글 모드에서 토글이
        // 발동하지 않는다(영어 모드에선 OK라 더 헷갈린다). capsLock/function을
        // 빼고 비교하는 규칙은 RevertKey.matches 안에 그대로 있다.
        // 2026-09-21 (#54): 키 조합은 설정값(haneul.revertKey, 고정 후보 4종)이다 —
        // 하드코딩 Shift+Space를 순수 타입 RevertKey로 옮겼다. defaults는 키
        // 이벤트마다 읽지 않고 **Space 키코드 + 되돌릴 변환이 있을 때만** 읽는다
        // (autoEnglishEnabled를 경계마다 다시 읽는 것과 같은 비용 수준).
        if event.keyCode == RevertKey.spaceKeyCode, let conv = composer.lastConversion,
           RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
               .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue) {
            let origin = composer.lastConversionOrigin
            let sel = tracedSelection(client)
            guard eventSession == sessionGeneration else { return true }
            #if DEBUG
            log.log("ss진단A: selLoc=\(sel.location, privacy: .public) selLen=\(sel.length, privacy: .public)")
            #endif
            // (L3) 드래그 선택 중(length>0)이거나 커서 위치를 모르면 손대지 않음.
            if sel.location != NSNotFound, sel.length == 0 {
                let span = max((conv.english as NSString).length, (conv.hangul as NSString).length) + 4
                let readStart = max(0, sel.location - span)
                let reqLen = sel.location - readStart
                let attr = tracedSubstring(client,
                    from: NSRange(location: readStart, length: reqLen))
                guard eventSession == sessionGeneration else { return true }
                let before = (attr?.string ?? "") as NSString
                #if DEBUG
                log.log("ss진단B: reqLen=\(reqLen, privacy: .public) beforeLen=\(before.length, privacy: .public)")
                #endif
                // (T1) 커서 앞을 읽어줄 수 없는 클라이언트(Ghostty 등 일부 터미널)
                // 에서는 되돌리기가 원리적으로 불가능하다 — 아래로 흘려보내면
                // 되돌리기를 요청한 자리에 엉뚱한 스페이스만 끼어드니, 아무것도
                // 하지 않고 키만 소비한다. 판정은 순수함수로 분리해 테스트한다(#30).
                if KoreanComposer.toggleUnsupported(cursorLocation: sel.location,
                                                    didReadText: attr != nil) {
                    return true
                }
                // (H1) Chromium/Electron 등이 substring을 잘라 반환하면 좌표가
                // 어긋나 인접 글자를 덮어쓴다 — 요청 길이와 다르면 안전하게 포기.
                // boundary skip·좌측경계·매칭은 순수함수 resolveToggle이 담당
                // (M1: IMK 비의존이라 단위테스트로 검증).
                if before.length == reqLen,
                   let r = KoreanComposer.resolveToggle(before: before as String,
                       english: conv.english, hangul: conv.hangul, atDocStart: readStart == 0) {
                    let start = sel.location - r.offsetFromEnd
                    tracedInsert(client, text: r.text as NSString,
                        replacementRange: NSRange(location: start, length: r.replaceLen))
                    guard eventSession == sessionGeneration else { return true }
                    // (T2) Terminal.app 등은 이 교체를 조용히 무시한다 — 교체 자리를
                    // 다시 읽어 옛 글자가 그대로면 거부로 판정하고, 화면·내부 상태를
                    // 손대지 않은 채 키만 소비한다(스페이스가 끼어들지 않게). 연속
                    // 시도해도 같은 결과가 되도록 lastConversion은 유지한다(#30).
                    let previous = r.text == conv.english ? conv.hangul : conv.english
                    let rejected = KoreanComposer.toggleWasRejected(
                        textAtReplacement: tracedSubstring(client, stage: .readback,
                            from: NSRange(location: start, length: r.replaceLen))?.string,
                        previousText: previous)
                    guard eventSession == sessionGeneration else { return true }
                    #if DEBUG
                    log.log("ss진단C: rejected=\(rejected, privacy: .public)")
                    #endif
                    if rejected { return true }
                    // (M-01) 화면만 바꾸지 말고 내부 영어 문맥도 방향에 맞춰 전이 —
                    // r.text가 영어면 영어 문맥 복원, 한글이면 끊김. (안 하면 다음
                    // 단어가 옛 문맥으로 잘못 변환됨.)
                    composer.applyToggle(toEnglish: r.text == conv.english,
                                         hangul: conv.hangul, english: conv.english, origin: origin)
                    externalContextPending = false
                    // 2026-09-21 (#53): 영어→한글로 되돌린 순간만 기록한다(한글→영어 재토글은
                    // 기록 대상이 아님 — "오변환이었다"는 신호는 되돌림 쪽뿐).
                    if r.text != conv.english, composer.shouldRecordAutomaticRevert {
                        recordRevert(hangul: conv.hangul, english: conv.english)
                    }
                    return true
                }
            }
            // (M2) 매칭 실패/불안전 → 토글하지 않고 아래 일반 경계 처리로 흘려보낸다
            // (키를 먹지 않게 — 최소한 스페이스는 입력됨).
        }

        // #84 · 2026-10-09: 저장된 변환 쌍 → 등록 발음 → 기존 자판 토글 순서.
        // 일반 Space는 couldMatch에서 탈락하며 발음 사전을 조회하지 않는다.
        if composer.lastConversion == nil,
           RevertKey.couldMatch(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue),
           RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
               .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue) {
            let phoneticEnabled = UserDefaults.standard.object(forKey: RevertKey.phoneticKey) as? Bool
                ?? RevertKey.phoneticDefault
            let keyboardEnabled = UserDefaults.standard.object(forKey: RevertKey.manualToggleAllWordsKey) as? Bool
                ?? RevertKey.manualToggleAllWordsDefault
            if composer.hasPendingComposition {
                if phoneticEnabled, handlePendingPhonetic(client: client, generation: eventSession) {
                    guard eventSession == sessionGeneration else { return true }
                    externalContextPending = false
                    return true
                }
            } else if (phoneticEnabled || keyboardEnabled),
                      handleManualToggle(client: client, phoneticEnabled: phoneticEnabled,
                                         keyboardEnabled: keyboardEnabled, generation: eventSession, inputSequence: eventSequence) {
                guard eventSession == sessionGeneration else { return true }
                externalContextPending = false
                return true
            }
        }

        // (M-02) `.numericPad`는 passive 목록에서 뺀다 — 화살표/탐색키는
        // `.function`도 함께 달려 위에서 passive로 잡히지만, 키패드 숫자·Enter는
        // `.numericPad`만 달려 예전엔 변환 없이 그대로 확정됐다. 이제 키패드
        // 문자·Enter는 아래 active boundary로 흘러 영타 변환 대상이 된다.
        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.function) {
            composer.commit(to: composerClient) // passive: 변환 안 함
            composer.resetEnglishContext()      // 커서 이동/단축키 = 문맥 단절
            externalContextPending = true       // 다음 조합에서 현재 커서 앞을 다시 검증
            return false
        }

        let shifted = mods.contains(.shift)

        if let inputChar = KeyboardLayout2Set.inputCharacter(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            characters: event.characters,
            keyCode: Int(event.keyCode),
            shifted: shifted
        ) {
            refreshAutomaticSettings(client: client)
            prepareExternalEnglishContext(client: client)
            // 문맥 읽기 왕복 중 secure 상태가 바뀌면 이번 키도 IME에서 처리하지 않는다.
            if IsSecureEventInputEnabled() {
                composer.commit(to: composerClient)
                composer.resetEnglishContext()
                externalContextPending = false
                return false
            }
            return composer.handleInput(String(inputChar), client: composerClient)
        }

        // 2026-09-19 (#34): 조합 중의 `'`는 경계가 아니라 단어 내부 문자다 —
        // i'm·don't 같은 축약형을 통째로 변환하려면 `'`가 단어에 붙어 있어야
        // 한다. 단어가 비어 있거나(여는 따옴표 `'안녕`) 이미 `'`가 있으면
        // composer가 false를 돌려주고, 그대로 아래 기존 경계 처리로 흘러간다.
        // (L-02와 같은 이유로 실제 출력 문자 기준 — Shift+'는 `"`라 안 걸린다.)
        if let typed = event.characters?.first, Contractions.isApostrophe(typed),
           composer.handleApostrophe(typed, client: composerClient) {
            externalContextPending = false
            return true
        }

        // 2026-10-06 (#5): 등록된 영숫자 이름의 숫자를 단어 안에 유지한다.
        // 개인 사전에 방금 추가한 이름도 첫 숫자부터 인식하도록 새 값을 읽는다.
        if let typed = event.characters?.first, AlphanumericWords.isDigit(typed) {
            composer.personalDictionary = PersonalDictionary.load(from: .standard)
            if composer.handleDigit(typed, client: composerClient) {
                externalContextPending = false
                return true
            }
        }

        if event.characters == ".", composer.handleQuantityPoint(client: composerClient) { return true }

        // Active boundary: the user typed a non-jamo key (space, punctuation,
        // digit, Enter...) — the only path where English auto-conversion may
        // fire. Re-read the toggle so Settings changes apply immediately.
        commitActiveBoundary(event.characters?.first, client: client)
        return false
    }

    private func tracedSelection(_ client: IMKTextInput) -> NSRange {
        roundTripTrace.call(.selection, composer: composer) { client.selectedRange() }
    }

    private func tracedMarkedRange(_ client: IMKTextInput) -> NSRange {
        roundTripTrace.call(.markedRange, composer: composer) { client.markedRange() }
    }

    private func tracedSubstring(_ client: IMKTextInput, stage: RoundTripTrace.Stage = .substring,
                                 from range: NSRange) -> NSAttributedString? {
        roundTripTrace.call(stage, composer: composer) { client.attributedSubstring(from: range) }
    }

    private func tracedInsert(_ client: IMKTextInput, text: Any, replacementRange: NSRange) {
        roundTripTrace.call(.replacement, composer: composer) {
            client.insertText(text, replacementRange: replacementRange)
        }
    }

    private func guardedComposerClient(_ client: IMKTextInput, generation: UInt) -> IMKComposerClient {
        IMKComposerClient(client: client, trace: roundTripTrace, composer: composer,
                          isCurrentSession: { self.sessionGeneration == generation })
    }

    /// #87 · 2026-10-12: 일반 활성 경계와 slash 시작이 같은 설정·사전 정책을 사용한다.
    private func commitActiveBoundary(_ character: Character?, client: IMKTextInput) {
        if composer.hasPendingComposition { externalContextPending = false }
        refreshAutomaticSettings(client: client)
        composer.commit(to: IMKComposerClient(client: client, trace: roundTripTrace, composer: composer), convertEnglish: true)
        // 영어 문맥은 Space/쉼표만 이어간다. 실제 출력 문자 기준이다.
        composer.completeBoundary(character)
    }

    /// #14: 활성화 콜백/일반 타이핑마다 읽지 않고 새 조합의 첫 문자 직전에 한 번만 읽는다.
    private func prepareExternalEnglishContext(client: IMKTextInput) {
        guard externalContextPending, !composer.hasPendingComposition else { return }
        externalContextPending = false
        refreshAutomaticSettings(client: client)
        guard composer.autoEnglishEnabled, composer.lastEnglishWord == nil,
              composer.lastConversion == nil else { return }
        let previous = ExternalEnglishContext.capture(
            from: IMKComposerClient(client: client, trace: roundTripTrace, composer: composer),
            enabled: InputInferencePolicy.externalEnglishContextEnabled(in: .standard),
            secureInput: { IsSecureEventInputEnabled() },
            isKnownEnglishWord: EnglishDetector.isExplicitEnglishContextWord)
        composer.beginExternalEnglishContext(previous)
    }

    private func refreshAutomaticSettings(client: IMKTextInput) {
        // secure input은 호출하는 handle 진입부에서 이미 걸러지므로 여기서는 항상 false.
        // 2026-09-21 (#54): 앱별 끄기 — 목록(haneul.disabledAppBundleIDs)에 이 클라이언트의
        // bundle ID가 있으면 이번 경계에선 변환하지 않는다. 판정은 순수함수
        // AutoConvertPolicy.allowed(테스트 있음). 클라이언트 왕복(bundleIdentifier)은
        // 목록이 비어 있지 않을 때만 — 비어 있으면 결과가 어차피 "허용"이다.
        // bundle ID를 못 얻으면(nil) 허용(기본 동작으로 복귀).
        let defaults = UserDefaults.standard
        let disabledAppIDs = defaults.stringArray(forKey: AutoConvertPolicy.disabledAppsKey) ?? []
        composer.autoEnglishEnabled = AutoConvertPolicy.allowed(
            globalEnabled: defaults.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true,
            disabledIDs: disabledAppIDs,
            clientBundleID: disabledAppIDs.isEmpty ? nil : client.bundleIdentifier())
        // 개인 사전은 미리보기가 바뀔 수 있는 문자/삭제와 확정 경계에서 읽는다.
        // 주변 문맥을 읽거나 키 내용을 기록하지 않으며, OFF/금지를 다음 입력부터 반영한다.
        composer.personalDictionary = PersonalDictionary.load(from: .standard)
        composer.dictionaryCompoundEnabled = InputInferencePolicy.dictionaryCompoundEnabled(in: defaults)
        if !InputInferencePolicy.externalEnglishContextEnabled(in: defaults) {
            composer.clearExternalEnglishContext()
        }
    }

    /// Verify a previous replacement on the next explicit shortcut, never on a timer.
    /// Both cursor positions (at replacement end / after the old trailing boundary)
    /// are accepted only when the same anchored result and word boundaries match.
    private func confirmDeferredManualToggle(client: IMKTextInput, generation: UInt) -> Bool {
        guard let candidate = deferredManualToggle else { return true }
        func isCurrent() -> Bool {
            generation == sessionGeneration && deferredManualToggle?.identifier == candidate.identifier
        }
        func discard() -> Bool {
            if isCurrent() { deferredManualToggle = nil }
            return false
        }
        guard candidate.generation == generation, !composer.hasPendingComposition,
              composer.lastConversion == nil else { return discard() }
        let selection = tracedSelection(client)
        guard isCurrent() else { return false }
        guard selection.location != NSNotFound else { return false }
        guard selection.length == 0 else { return discard() }
        let expected = candidate.toEnglish ? candidate.english : candidate.hangul
        let opposite = candidate.toEnglish ? candidate.hangul : candidate.english
        let expectedEnd = candidate.start + (expected as NSString).length
        let previousEnd = candidate.start + (opposite as NSString).length
        let trailingLength = (candidate.trailing as NSString).length
        guard selection.location == expectedEnd || selection.location == expectedEnd + trailingLength else {
            // The caret can be stale along with the text snapshot. Never retry a
            // replacement against it. A clearly different position ends the candidate.
            if selection.location == previousEnd || selection.location == previousEnd + trailingLength { return false }
            return discard()
        }
        let marked = tracedMarkedRange(client)
        guard isCurrent() else { return false }
        guard marked.location == NSNotFound || marked.length == 0 else { return discard() }
        let span = max((candidate.english as NSString).length, (candidate.hangul as NSString).length) + 4
        let readStart = max(0, selection.location - span)
        let length = selection.location - readStart
        let before = tracedSubstring(client, from: NSRange(location: readStart, length: length))?.string
        guard isCurrent() else { return false }
        guard let before, (before as NSString).length == length else { return false }
        guard let result = KoreanComposer.resolveToggle(before: before,
                  english: candidate.english, hangul: candidate.hangul, atDocStart: readStart == 0),
              selection.location - result.offsetFromEnd == candidate.start else { return discard() }
        // A genuine rejection or a still-stale original is not a confirmed result.
        guard result.text == opposite, result.replaceLen == (expected as NSString).length else { return false }
        if trailingLength > 0 {
            let trailing = tracedSubstring(client, from: NSRange(location: expectedEnd, length: trailingLength))?.string
            guard isCurrent() else { return false }
            guard let trailing, (trailing as NSString).length == trailingLength else { return false }
            guard trailing == candidate.trailing else { return discard() }
        } else {
            let right = tracedSubstring(client, from: NSRange(location: expectedEnd, length: 1))?.string
            guard isCurrent() else { return false }
            guard PhoneticDictionary.isBoundary(right) else { return discard() }
        }
        guard !IsSecureEventInputEnabled() else { return discard() }
        deferredManualToggle = nil
        composer.applyToggle(toEnglish: candidate.toEnglish, hangul: candidate.hangul,
                             english: candidate.english, origin: candidate.origin)
        roundTripTrace.record(.deferredConfirmed, composer: composer)
        return true
    }

    /// 조합 중 등록 단어는 확정된 문서를 재작성하지 않고 marked text로 한 번에 바꾼다.
    /// 조합 범위와 화면 원문이 같을 때만 실행하여 다른 단어의 일부를 바꾸지 않는다.
    private func handlePendingPhonetic(client: IMKTextInput, generation: UInt) -> Bool {
        guard let conversion = composer.pendingPhoneticConversion() else { return false }
        let marked = tracedMarkedRange(client)
        guard generation == sessionGeneration else { return true }
        let selection = tracedSelection(client)
        guard generation == sessionGeneration else { return true }
        guard marked.location != NSNotFound else {
            roundTripTrace.record(.pendingMarkedUnavailable, composer: composer); return false
        }
        guard marked.length == (conversion.hangul as NSString).length else {
            roundTripTrace.record(.pendingMarkedLengthMismatch, composer: composer); return false
        }
        guard selection.length == 0 else {
            roundTripTrace.record(.pendingSelectionNonCaret, composer: composer); return false
        }
        guard selection.location == NSMaxRange(marked) else {
            roundTripTrace.record(.pendingSelectionNotAtEnd, composer: composer); return false
        }
        let markedText = tracedSubstring(client, from: marked)?.string
        guard generation == sessionGeneration else { return true }
        guard markedText == conversion.hangul else { return false }
        if marked.location > 0 {
            let left = tracedSubstring(client, from: NSRange(location: marked.location - 1, length: 1))?.string
            guard generation == sessionGeneration else { return true }
            guard let left, PhoneticDictionary.isBoundary(left) else { return false }
        }
        let right = tracedSubstring(client, from: NSRange(location: NSMaxRange(marked), length: 1))?.string
        guard generation == sessionGeneration else { return true }
        guard PhoneticDictionary.isBoundary(right) else { return false }
        return composer.commitPhonetic(to: guardedComposerClient(client, generation: generation),
                                       isCurrentSession: { self.sessionGeneration == generation })
    }

    /// 커서 앞 확정 단어: 등록 발음 우선, 미등록이면 기존 자판 배열 토글.
    /// 읽기 길이·선택·교체 거부 방어선은 기존 수동 토글과 동일하다.
    private func handleManualToggle(client: IMKTextInput, phoneticEnabled: Bool, keyboardEnabled: Bool,
                                    generation: UInt, inputSequence eventSequence: UInt) -> Bool {
        let sel = tracedSelection(client)
        guard generation == sessionGeneration else { return true }
        // (L3) 드래그 선택 중(length>0)이거나 커서 위치를 모르면 손대지 않음 — 자동 경로와 동일.
        guard sel.location != NSNotFound, sel.length == 0 else { return false }
        let readStart = max(0, sel.location - ManualToggle.readSpan)
        let reqLen = sel.location - readStart
        let attr = tracedSubstring(client, from: NSRange(location: readStart, length: reqLen))
        guard generation == sessionGeneration else { return true }
        #if DEBUG
        log.log("mt진단A: selLoc=\(sel.location, privacy: .public) reqLen=\(reqLen, privacy: .public) read=\(attr != nil, privacy: .public)")
        #endif
        // (T1) 커서 앞을 읽어줄 수 없는 클라이언트(Ghostty 등 터미널)에서는 원리적으로 불가능 —
        // 아무것도 하지 않고 키만 소비한다(#30). 아래로 흘려보내면 되돌리기를 요청한 자리에
        // 엉뚱한 스페이스만 끼어든다.
        guard let attr else { return true }
        // 커서가 문서 맨 앞 = 앞에 단어가 없는 **정상 상태**다. 자동 경로의 `toggleUnsupported`는
        // 이걸 "거짓 보고"로 보고 키를 먹는데(변환 직후라면 앞에 글자가 반드시 있으므로),
        // 수동 경로에선 뜻이 다르다 — 빈 필드에서 스페이스가 사라지지 않게 흘려보낸다.
        guard sel.location > 0 else { return false }
        let before = attr.string as NSString
        // (H1) 요청 길이와 다르게 잘라 주는 클라이언트(Chromium/Electron 등)는 좌표가 어긋나
        // 인접 글자를 덮어쓴다 — 안전하게 포기한다.
        guard before.length == reqLen,
              let target = KoreanComposer.wordBeforeCursor(
                  before: before as String, atDocStart: readStart == 0) else { return false }
        let right = target.trailing == 0
            ? tracedSubstring(client, from: NSRange(location: sel.location, length: 1))?.string : nil
        guard generation == sessionGeneration else { return true }
        guard let result = ManualToggle.resolve(word: target.word,
            phoneticEnabled: phoneticEnabled && PhoneticDictionary.isBoundary(right),
            keyboardEnabled: keyboardEnabled) else { return false }
        let toggled = result.text
        let wordLength = (target.word as NSString).length
        let start = sel.location - wordLength - target.trailing
        guard start >= 0 else { return false }
        tracedInsert(client, text: toggled as NSString,
                          replacementRange: NSRange(location: start, length: wordLength))
        guard generation == sessionGeneration else { return true }
        // (T2) Terminal.app 등은 범위 교체를 조용히 무시한다 — 그 자리에 옛 글자가 그대로면
        // 거부로 판정하고, 화면·내부 상태를 손대지 않은 채 키만 소비한다(#30).
        let rejected = KoreanComposer.toggleWasRejected(
            textAtReplacement: tracedSubstring(client, stage: .readback,
                from: NSRange(location: start, length: wordLength))?.string,
            previousText: target.word)
        guard generation == sessionGeneration else { return true }
        #if DEBUG
        log.log("mt진단B: rejected=\(rejected, privacy: .public)")
        #endif
        // A nested key can invalidate this operation without changing sessions.
        // Do not overwrite that key's newer candidate or confirmed conversion.
        guard eventSequence == inputSequence else { return true }
        if rejected {
            deferredManualToggle = DeferredManualToggle(generation: generation, start: start,
                trailing: before.substring(from: before.length - target.trailing),
                hangul: result.toEnglish ? target.word : toggled,
                english: result.toEnglish ? toggled : target.word,
                toEnglish: result.toEnglish, origin: result.origin)
            roundTripTrace.record(.deferredStored, composer: composer)
            return true
        }
        // 한 번 더 누르면 되돌아오게 `lastConversion`을 세운다 — 그러면 **기존** 되돌리기 경로가
        // 그대로 매칭해 역토글한다(수동 경로를 두 번 타지 않고, 좌표 로직도 하나만 쓴다).
        //
        // `applyToggle`은 영어 문맥(`lastEnglishWord`)까지 함께 옮기는데, 그 부작용이 여기서도
        // 맞다(코드 확인 후 결정): 화면 끝이 실제로 영어 단어가 됐으면 다음 단어는 영어 문맥으로
        // 판정돼야 하고(M-01과 같은 이유 — 화면과 내부 상태가 어긋나면 다음 단어가 잘못 변환된다),
        // 한글로 바꿨으면 문맥은 끊겨야 한다. 숫자 이름은 영어로 돌려도 문맥을 시작하지 않는다(#5).
        let toEnglish = result.toEnglish
        composer.applyToggle(toEnglish: toEnglish,
                             hangul: toEnglish ? target.word : toggled,
                             english: toEnglish ? toggled : target.word, origin: result.origin)
        // 수동 경로는 #53 `recordRevert`를 **부르지 않는다**. "최근 되돌린 변환"은 자동변환이
        // 틀렸다는 신호를 모으는 목록인데, 여기서 바꾼 단어는 애초에 자동변환된 적이 없다 —
        // 넣으면 일어나지도 않은 오변환에 "금지" 버튼을 달게 된다.
        return true
    }

    /// 2026-09-21 (#53): 되돌린 변환을 "최근 되돌린 변환" 목록에 남긴다 — (한글 표기, 영어)
    /// 쌍만. 키스트로크·앞뒤 문맥·앱 이름·시각은 담지 않고, 로그에도 남기지 않는다(키로거
    /// 금지). secure input은 `handle` 진입부에서 이미 걸러져 여기까지 오지 않는다.
    /// 이 키는 IME만 쓴다(설정 앱은 읽기+삭제) — 형식·상한은 `RecentReverts`가 정본.
    private func recordRevert(hangul: String, english: String) {
        let defaults = UserDefaults.standard
        RecentReverts.load(from: defaults)
            .recording(hangul: hangul, english: english)
            .save(to: defaults)
    }
}

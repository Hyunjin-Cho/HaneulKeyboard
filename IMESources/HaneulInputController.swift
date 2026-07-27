import Cocoa
import Carbon
import InputMethodKit
import os.log

/// Bridges the Foundation-only KoreanComposer to the IMK client.
private struct IMKComposerClient: ComposerClient {
    let client: IMKTextInput

    func insertText(_ text: String) {
        client.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    func setMarkedText(_ text: String) {
        client.setMarkedText(
            text as NSString,
            selectionRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}

@objc(HaneulInputController)
final class HaneulInputController: IMKInputController {
    private let log = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "ime")
    private let composer = KoreanComposer()
    private var didOverrideKeyboard = false

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
        log.log("activateServer")
        // NOTE: never query the client (markedRange/attributes/...) in here —
        // it deadlocks Chromium-based apps. Defaults reads only.
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        composer.resetEnglishContext() // 새 필드/앱 — 영어 문맥은 이어지지 않음
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }
    }

    override func deactivateServer(_ sender: Any!) {
        log.log("deactivateServer")
        if let client = sender as? IMKTextInput {
            composer.commit(to: IMKComposerClient(client: client))
        }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        composer.commit(to: IMKComposerClient(client: client))
        composer.resetEnglishContext() // 클릭/포커스 이동 = 문맥 단절
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

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

        let composerClient = IMKComposerClient(client: client)

        // (secure-input) 정상적인 secure 필드는 macOS가 서드파티 IME를 아예
        // 우회하지만(PRIVACY.md #4), 그 우회가 안 걸리는 예외 상황에 대비한
        // 방어선이다 — 조합 중이던 자모를 흘리지 않고 커밋한 뒤, 이번 키는
        // 조합하지 않고 그대로 통과시킨다(review0706 P3-4).
        if IsSecureEventInputEnabled() {
            composer.commit(to: composerClient)
            composer.resetEnglishContext()
            return false
        }

        if event.keyCode == 51 {
            // (H-08) Cmd/Opt/Ctrl+Backspace(단어·줄 삭제)는 composer가 먹지
            // 않고 클라이언트가 처리하게 한다 — 조합 중에도 일상 단축키가 한
            // 자모 삭제로 둔갑하지 않도록. 무수정 Backspace만 자모를 떼어낸다.
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                composer.commit(to: composerClient)
                composer.resetEnglishContext()
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

        // shift+space: 마지막 변환을 영어↔한글 토글로 교체(㉠ 직후만).
        // 커서 직전 텍스트를 읽어 boundary(스페이스·구두점)를 건너뛰고 영어/
        // 한글을 정확히 찾아 replace — 변환 시 입력된 공백("i ") 때문에 커서가
        // 영어 바로 뒤가 아니어도 옳게 동작한다. lastConversion을 유지해 연속
        // shift+space로 영↔한을 반복 토글(다음 글자 입력/백스페이스 시 리셋).
        // 한글 모드는 CapsLock 전환 방식이라 keyDown의 modifierFlags에
        // .capsLock이 상시 포함될 수 있다 — mods == .shift로 엄격 비교하면
        // 한글 모드에서 shift+space 토글이 발동하지 않는다(영어 모드에선 OK라
        // 더 헷갈린다). capsLock/function을 빼고 비교해 한글 모드에서도 먹게.
        if event.keyCode == 49, mods.subtracting([.capsLock, .function]) == .shift,
           let conv = composer.lastConversion {
            let sel = client.selectedRange()
            #if DEBUG
            log.log("ss진단A: selLoc=\(sel.location, privacy: .public) selLen=\(sel.length, privacy: .public)")
            #endif
            // (L3) 드래그 선택 중(length>0)이거나 커서 위치를 모르면 손대지 않음.
            if sel.location != NSNotFound, sel.length == 0 {
                let span = max((conv.english as NSString).length, (conv.hangul as NSString).length) + 4
                let readStart = max(0, sel.location - span)
                let reqLen = sel.location - readStart
                let attr = client.attributedSubstring(
                    from: NSRange(location: readStart, length: reqLen))
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
                    client.insertText(r.text as NSString,
                        replacementRange: NSRange(location: start, length: r.replaceLen))
                    // (T2) Terminal.app 등은 이 교체를 조용히 무시한다 — 교체 자리를
                    // 다시 읽어 옛 글자가 그대로면 거부로 판정하고, 화면·내부 상태를
                    // 손대지 않은 채 키만 소비한다(스페이스가 끼어들지 않게). 연속
                    // 시도해도 같은 결과가 되도록 lastConversion은 유지한다(#30).
                    let previous = r.text == conv.english ? conv.hangul : conv.english
                    let rejected = KoreanComposer.toggleWasRejected(
                        textAtReplacement: client.attributedSubstring(
                            from: NSRange(location: start, length: r.replaceLen))?.string,
                        previousText: previous)
                    #if DEBUG
                    log.log("ss진단C: rejected=\(rejected, privacy: .public)")
                    #endif
                    if rejected { return true }
                    // (M-01) 화면만 바꾸지 말고 내부 영어 문맥도 방향에 맞춰 전이 —
                    // r.text가 영어면 영어 문맥 복원, 한글이면 끊김. (안 하면 다음
                    // 단어가 옛 문맥으로 잘못 변환됨.)
                    composer.applyToggle(toEnglish: r.text == conv.english,
                                         hangul: conv.hangul, english: conv.english)
                    return true
                }
            }
            // (M2) 매칭 실패/불안전 → 토글하지 않고 아래 일반 경계 처리로 흘려보낸다
            // (키를 먹지 않게 — 최소한 스페이스는 입력됨).
        }

        // (M-02) `.numericPad`는 passive 목록에서 뺀다 — 화살표/탐색키는
        // `.function`도 함께 달려 위에서 passive로 잡히지만, 키패드 숫자·Enter는
        // `.numericPad`만 달려 예전엔 변환 없이 그대로 확정됐다. 이제 키패드
        // 문자·Enter는 아래 active boundary로 흘러 영타 변환 대상이 된다.
        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.function) {
            composer.commit(to: composerClient) // passive: 변환 안 함
            composer.resetEnglishContext()      // 커서 이동/단축키 = 문맥 단절
            return false
        }

        let shifted = mods.contains(.shift)

        if let inputChar = KeyboardLayout2Set.inputCharacter(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            characters: event.characters,
            keyCode: Int(event.keyCode),
            shifted: shifted
        ) {
            return composer.handleInput(String(inputChar), client: composerClient)
        }

        // Active boundary: the user typed a non-jamo key (space, punctuation,
        // digit, Enter...) — the only path where English auto-conversion may
        // fire. Re-read the toggle so Settings changes apply immediately.
        // secure input은 이 함수 진입부에서 이미 걸러지므로 여기서는 항상 false.
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        composer.commit(to: composerClient, convertEnglish: true)
        // 영어 문맥("I want to...")은 스페이스/쉼표로만 이어진다 — 마침표·
        // 엔터·기타 문자는 문장 단절로 보고 리셋 ("Nice. 새로운" 보호).
        // (L-02) 실제 출력 문자 기준 — Shift+,는 '<'(문장 단절 경계)이지 ','가
        // 아니다. charactersIgnoringModifiers는 '<'를 ','로 잘못 보고했다.
        let boundary = event.characters?.first
        if boundary != " " && boundary != "," {
            composer.resetEnglishContext()
        }
        return false
    }
}

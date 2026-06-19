import Cocoa
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
        // keylogger). .private redacts unless private-data logging is
        // deliberately enabled for a debug session.
        log.log("keyDown code=\(event.keyCode, privacy: .private) shift=\(mods.contains(.shift), privacy: .public)")

        if !didOverrideKeyboard {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }

        let composerClient = IMKComposerClient(client: client)

        if event.keyCode == 51 {
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
        if event.keyCode == 49, mods == .shift, let conv = composer.lastConversion {
            let sel = client.selectedRange()
            if sel.location != NSNotFound {
                let eng = conv.english as NSString
                let han = conv.hangul as NSString
                let span = max(eng.length, han.length) + 3
                let readStart = max(0, sel.location - span)
                let before = (client.attributedSubstring(
                    from: NSRange(location: readStart, length: sel.location - readStart)
                )?.string ?? "") as NSString
                // 끝의 boundary(공백 0x20·쉼표 0x2C·마침표 0x2E·개행 0x0A) 건너뛰기
                var end = before.length
                while end > 0, [0x20, 0x2C, 0x2E, 0x0A].contains(Int(before.character(at: end - 1))) {
                    end -= 1
                }
                if end >= eng.length,
                   before.substring(with: NSRange(location: end - eng.length, length: eng.length)) == conv.english {
                    client.insertText(conv.hangul as NSString,
                        replacementRange: NSRange(location: readStart + end - eng.length, length: eng.length))
                } else if end >= han.length,
                          before.substring(with: NSRange(location: end - han.length, length: han.length)) == conv.hangul {
                    client.insertText(conv.english as NSString,
                        replacementRange: NSRange(location: readStart + end - han.length, length: han.length))
                }
            }
            return true // lastConversion 유지 → 연속 토글
        }

        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.numericPad)
           || mods.contains(.function) {
            composer.commit(to: composerClient) // passive: 변환 안 함
            composer.resetEnglishContext()      // 커서 이동/단축키 = 문맥 단절
            return false
        }

        let shifted = mods.contains(.shift)

        if let chars = event.charactersIgnoringModifiers,
           let lower = chars.lowercased().first {
            let inputChar: Character = shifted
                ? Character(String(lower).uppercased())
                : lower
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                return composer.handleInput(String(inputChar), client: composerClient)
            }
        } else if let raw = event.characters?.lowercased().first,
                  raw.isASCII, raw.isLetter {
            let inputChar: Character = shifted
                ? Character(String(raw).uppercased())
                : raw
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                return composer.handleInput(String(inputChar), client: composerClient)
            }
        }

        // Active boundary: the user typed a non-jamo key (space, punctuation,
        // digit, Enter...) — the only path where English auto-conversion may
        // fire. Re-read the toggle so Settings changes apply immediately.
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        composer.commit(to: composerClient, convertEnglish: true)
        // 영어 문맥("I want to...")은 스페이스/쉼표로만 이어진다 — 마침표·
        // 엔터·기타 문자는 문장 단절로 보고 리셋 ("Nice. 새로운" 보호).
        let boundary = event.charactersIgnoringModifiers?.first
        if boundary != " " && boundary != "," {
            composer.resetEnglishContext()
        }
        return false
    }
}

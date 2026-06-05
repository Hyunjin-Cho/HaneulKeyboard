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
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
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
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        log.log("keyDown code=\(event.keyCode, privacy: .public) ignMod=\(event.charactersIgnoringModifiers ?? "?", privacy: .public) shift=\(mods.contains(.shift), privacy: .public)")

        if !didOverrideKeyboard {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }

        let composerClient = IMKComposerClient(client: client)

        if event.keyCode == 51 {
            return composer.deleteBackward(client: composerClient)
        }

        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.numericPad)
           || mods.contains(.function) {
            composer.commit(to: composerClient)
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
        return false
    }
}

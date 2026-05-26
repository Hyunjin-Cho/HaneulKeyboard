import Cocoa
import InputMethodKit
import os.log

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
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }
    }

    override func deactivateServer(_ sender: Any!) {
        log.log("deactivateServer")
        if let client = sender as? IMKTextInput {
            composer.commit(to: client)
        }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        composer.commit(to: client)
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

        if event.keyCode == 51 {
            return composer.deleteBackward(client: client)
        }

        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.numericPad)
           || mods.contains(.function) {
            composer.commit(to: client)
            return false
        }

        let shifted = mods.contains(.shift)

        if let chars = event.charactersIgnoringModifiers,
           let lower = chars.lowercased().first {
            let inputChar: Character = shifted
                ? Character(String(lower).uppercased())
                : lower
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                return composer.handleInput(String(inputChar), client: client)
            }
        } else if let raw = event.characters?.lowercased().first,
                  raw.isASCII, raw.isLetter {
            let inputChar: Character = shifted
                ? Character(String(raw).uppercased())
                : raw
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                return composer.handleInput(String(inputChar), client: client)
            }
        }

        composer.commit(to: client)
        return false
    }
}

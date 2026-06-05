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

    // Prediction (Korean-only autocomplete): shared across all clients.
    private static let wordStore: WordFrequencyStore = {
        let store = WordFrequencyStore()
        // Settings(메인 앱)의 "학습 데이터 삭제"는 파일 삭제 + 이 플래그.
        // 모든 쓰기 직전에 확인해서, 진행 중이던 저장이 삭제를 되살리는
        // 일이 없게 한다 (리뷰 발견 반영).
        store.onExternalClearRequest = {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "haneul.clearLearnedData") else { return false }
            defaults.set(false, forKey: "haneul.clearLearnedData")
            return true
        }
        return store
    }()
    private static let suggestionPanel = SuggestionPanel()
    /// Always-fresh read so Settings changes apply immediately (UserDefaults
    /// reads are served from cfprefsd's in-process cache — negligible cost).
    private var predictionEnabled: Bool {
        UserDefaults.standard.object(forKey: "haneul.predictionEnabled") as? Bool ?? true
    }

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
        // 메모리에 남은 학습 데이터 사본까지 비운다 (쓰기 경로들도 같은
        // 훅을 확인하므로 여기서는 즉시성 확보용).
        Self.wordStore.consumeClearRequestIfAny()
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }
    }

    // 학습은 ACTIVE 경계(사용자가 직접 친 스페이스/문장부호)에서만 — 수동
    // 경계(화살표/클릭/앱 전환)는 단어 조각을 만들기 때문에 commit만 하고
    // 학습하지 않는다 (리뷰 발견: '안녕하' 조각이 제안으로 떠오르는 문제).
    override func deactivateServer(_ sender: Any!) {
        log.log("deactivateServer")
        Self.suggestionPanel.hide()
        if let client = sender as? IMKTextInput {
            composer.commit(to: IMKComposerClient(client: client))
        }
        Self.wordStore.saveNow() // dirty-guarded: 변경 없으면 no-op
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        Self.suggestionPanel.hide()
        composer.commit(to: IMKComposerClient(client: client))
        composer.resetEnglishContext() // 클릭/포커스 이동 = 문맥 단절
    }

    private func learnIfEnabled(_ word: String) {
        guard predictionEnabled, !word.isEmpty else { return }
        Self.wordStore.learn(word)
    }

    /// Shows/hides the ghost suggestion for the current composition state.
    private func refreshSuggestion(client: IMKTextInput) {
        guard predictionEnabled else {
            Self.suggestionPanel.hide()
            return
        }
        let prefix = composer.currentPreview()
        guard !prefix.isEmpty,
              let word = Self.wordStore.suggest(prefix: prefix) else {
            Self.suggestionPanel.hide()
            return
        }
        let remainder = String(word.dropFirst(prefix.count))
        Self.suggestionPanel.show(
            fullWord: word,
            remainder: remainder,
            caretIndex: (prefix as NSString).length, // 캐럿 = marked text 끝
            client: client
        )
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
            refreshSuggestion(client: client)
            return handled
        }

        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.numericPad)
           || mods.contains(.function) {
            Self.suggestionPanel.hide()
            composer.commit(to: composerClient) // passive: 학습 안 함
            composer.resetEnglishContext()      // 커서 이동/단축키 = 문맥 단절
            return false
        }

        // Tab accepts the visible suggestion — and ONLY then. With no
        // suggestion showing, Tab falls through to the boundary commit
        // below and reaches the app as a normal Tab. Shift-Tab is excluded
        // so back-tab focus moves keep working.
        if event.keyCode == 48, !mods.contains(.shift),
           let word = Self.suggestionPanel.suggestedWord {
            composer.acceptSuggestion(word, client: composerClient)
            Self.suggestionPanel.hide()
            return true
        }

        let shifted = mods.contains(.shift)

        if let chars = event.charactersIgnoringModifiers,
           let lower = chars.lowercased().first {
            let inputChar: Character = shifted
                ? Character(String(lower).uppercased())
                : lower
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                let handled = composer.handleInput(String(inputChar), client: composerClient)
                refreshSuggestion(client: client)
                return handled
            }
        } else if let raw = event.characters?.lowercased().first,
                  raw.isASCII, raw.isLetter {
            let inputChar: Character = shifted
                ? Character(String(raw).uppercased())
                : raw
            if KeyboardLayout2Set.jamo(for: inputChar) != nil {
                let handled = composer.handleInput(String(inputChar), client: composerClient)
                refreshSuggestion(client: client)
                return handled
            }
        }

        // Active boundary: the user typed a non-jamo key (space, punctuation,
        // digit, Enter...) — the only path where English auto-conversion may
        // fire. Re-read the toggle so Settings changes apply immediately.
        Self.suggestionPanel.hide()
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        learnIfEnabled(composer.commit(to: composerClient, convertEnglish: true))
        // 영어 문맥("I want to...")은 스페이스/쉼표로만 이어진다 — 마침표·
        // 엔터·기타 문자는 문장 단절로 보고 리셋 ("Nice. 새로운" 보호).
        let boundary = event.charactersIgnoringModifiers?.first
        if boundary != " " && boundary != "," {
            composer.resetEnglishContext()
        }
        return false
    }
}

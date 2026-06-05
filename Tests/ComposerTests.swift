import Foundation

// Standalone test harness for the IME composition core. Runs without Xcode:
//   scripts/run_ime_tests.sh
// Compiles HangulJamo + KeyboardLayout2Set + KoreanComposer + EnglishDetector
// (all Foundation-only) together with this file and executes main().

// MARK: - Fake client

final class FakeClient: ComposerClient {
    var inserted: [String] = []
    var marked: String = ""

    func insertText(_ text: String) {
        inserted.append(text)
    }

    func setMarkedText(_ text: String) {
        marked = text
    }

    var committedText: String { inserted.joined() }
}

// MARK: - Tiny assertion runner

var failures = 0
var passes = 0

func expect(_ actual: String, _ expected: String, _ label: String) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(label): expected \"\(expected)\", got \"\(actual)\"")
    }
}

func expect(_ actual: Bool, _ expected: Bool, _ label: String) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(label): expected \(expected), got \(actual)")
    }
}

// MARK: - Helpers

/// Feeds each character through the composer as typed keys, then commits at
/// an ACTIVE boundary (as if the user pressed Space).
func type(_ keys: String, autoEnglish: Bool = true) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    composer.autoEnglishEnabled = autoEnglish
    for ch in keys {
        _ = composer.handleInput(String(ch), client: client)
    }
    composer.commit(to: client, convertEnglish: true)
    return client
}

/// Same, but commits at a PASSIVE boundary (focus change, mouse click,
/// CapsLock switch) — must always commit the marked text as displayed.
func typePassive(_ keys: String) -> FakeClient {
    let client = FakeClient()
    let composer = KoreanComposer()
    for ch in keys {
        _ = composer.handleInput(String(ch), client: client)
    }
    composer.commit(to: client)
    return client
}

// MARK: - Tests

@main
struct ComposerTests {
    static func main() {
        // Wordlist: system dict + a temp supplement (no app bundle here).
        // Must be set before the first shouldConvert call (lazy load).
        let supplementPath = NSTemporaryDirectory() + "haneul_test_supplement.txt"
        try? "google\ngithub\n".write(toFile: supplementPath, atomically: true, encoding: .utf8)
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words", supplementPath]

        // Hangul composition (regression — must match pre-word-buffer behavior)
        expect(type("dkssud").committedText, "안녕", "basic 안녕")
        expect(type("dkssudgktpdy").committedText, "안녕하세요", "안녕하세요")
        expect(type("gksk").committedText, "하나", "도깨비불 carry 하나")
        expect(type("Rk").committedText, "까", "쌍자음 까")
        expect(type("ghk").committedText, "화", "compound vowel 화")
        expect(type("dhks").committedText, "완", "compound vowel with final 완")
        expect(type("dlfrrh").committedText, "읽고", "compound final 읽고")

        // Backspace: peel in-flight jamo
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dks" { _ = composer.handleInput(String(ch), client: client) } // 안
            _ = composer.deleteBackward(client: client) // peel ㄴ → 아
            expect(client.marked, "아", "backspace peels final")
            _ = composer.handleInput("s", client: client) // 안
            composer.commit(to: client)
            expect(client.committedText, "안", "retype after peel")
        }

        // Backspace: through the word buffer down to empty
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) } // 안녕
            expect(client.marked, "안녕", "word-level marked text")
            _ = composer.deleteBackward(client: client) // 녕 → 녀
            expect(client.marked, "안녀", "peel into in-flight syllable")
            _ = composer.deleteBackward(client: client) // 녀 → ㄴ
            _ = composer.deleteBackward(client: client) // ㄴ → (empty in-flight)
            expect(client.marked, "안", "in-flight fully peeled")
            _ = composer.deleteBackward(client: client) // word unit 안 removed
            expect(client.marked, "", "word unit removed")
            expect(composer.deleteBackward(client: client), false, "empty → system handles")
            composer.commit(to: client)
            expect(client.committedText, "", "nothing left to commit")
        }

        // Wrong-layout English auto-correction
        expect(type("apple").committedText, "apple", "apple converts (메ㅔㅣㄷ → apple)")
        expect(type("hello").committedText, "hello", "hello converts (ㅗ디ㅣㅐ → hello)")
        expect(type("google").committedText, "google", "supplement wordlist hit")
        expect(type("apple", autoEnglish: false).committedText, "메ㅔㅣㄷ", "toggle off keeps hangul")
        expect(type("zzz").committedText, "ㅋㅋㅋ", "emotive ㅋㅋㅋ untouched")
        expect(type("bb").committedText, "ㅠㅠ", "emotive ㅠㅠ untouched")
        expect(type("dkssud").committedText, "안녕", "valid hangul never converted")
        expect(type("Apple").committedText, "Apple", "case preserved on conversion")

        // Bare-vowel + consonant fix (was silent data loss: ㄷ vanished)
        expect(type("le", autoEnglish: false).committedText, "ㅣㄷ", "consonant after bare vowel survives")

        // Backspace inside a wrong-layout word still converts correctly
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "applw" { _ = composer.handleInput(String(ch), client: client) } // typo: w
            _ = composer.deleteBackward(client: client) // remove ㅈ (w)
            _ = composer.handleInput("e", client: client) // correct: e
            composer.commit(to: client, convertEnglish: true)
            expect(client.committedText, "apple", "backspace correction mid-word")
        }

        // Jamo slang / kaomoji must NEVER convert (review findings)
        expect(type("gee").committedText, "ㅎㄷㄷ", "consonant-only slang ㅎㄷㄷ untouched")
        expect(type("aw").committedText, "ㅁㅈ", "2-key slang ㅁㅈ untouched")
        expect(type("hi").committedText, "ㅗㅑ", "2-key vowel slang ㅗㅑ untouched")
        expect(type("ml").committedText, "ㅢ", "standalone ㅢ untouched")
        // (the composer assembles these as ㅡ므/ㅜ무/ㅠ뮤 — same as Apple's
        // IME; the point is the V-C-V palindrome guard blocks conversion)
        expect(type("mam").committedText, "ㅡ므", "kaomoji keys mam not converted")
        expect(type("nan").committedText, "ㅜ무", "kaomoji keys nan not converted")
        expect(type("bab").committedText, "ㅠ뮤", "kaomoji keys bab not converted")
        expect(type("sdr").committedText, "ㄴㅇㄱ", "ㄴㅇㄱ untouched")

        // 3-key English with vowels still converts
        expect(type("you").committedText, "you", "3-key you converts")
        expect(type("man").committedText, "man", "non-palindrome man converts")

        // Inflected English converts via suffix fallback ("apples"/"typing"
        // are not in the 1934 dict; their stems are)
        expect(type("apples").committedText, "apples", "plural apples converts")
        expect(type("typing").committedText, "typing", "typing converts (-ing → +e stem)")

        // PASSIVE boundaries (click, CapsLock, app switch) never convert —
        // they must commit exactly the marked text the user saw.
        expect(typePassive("apple").committedText, "메ㅔㅣㄷ", "passive boundary commits as displayed")
        expect(typePassive("dkssud").committedText, "안녕", "passive boundary commits hangul")

        // Detector unit tests
        expect(EnglishDetector.shouldConvert(units: ["메", "ㅔ", "ㅣ", "ㄷ"], keys: Array("apple")), true, "detector: apple")
        expect(EnglishDetector.shouldConvert(units: ["안", "녕"], keys: Array("dkssud")), false, "detector: no broken jamo")
        expect(EnglishDetector.shouldConvert(units: ["ㅠ", "ㅠ"], keys: Array("bb")), false, "detector: same-key run")
        expect(EnglishDetector.shouldConvert(units: ["ㄴ", "ㅇ", "ㄱ"], keys: Array("sdr")), false, "detector: not a word")
        expect(EnglishDetector.shouldConvert(units: ["ㄷ"], keys: Array("e")), false, "detector: single key")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

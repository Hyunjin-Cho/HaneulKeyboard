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

func expect(_ actual: Int, _ expected: Int, _ label: String) {
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

        // ── WordFrequencyStore (prediction) ──
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory() + "haneul_test_store/word_frequency.json")
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        let store = WordFrequencyStore(fileURL: storeURL)

        // Below threshold (3): no suggestion yet
        store.learn("안녕하세요")
        store.learn("안녕하세요")
        expect(store.suggest(prefix: "안녕") == nil, true, "store: below threshold")
        store.learn("안녕하세요")
        expect(store.suggest(prefix: "안녕") ?? "", "안녕하세요", "store: suggests after 3 commits")
        expect(store.suggest(prefix: "안녕하세") ?? "", "안녕하세요", "store: longer prefix")
        expect(store.suggest(prefix: "안녕하세요") == nil, true, "store: never suggests the prefix itself")

        // Frequency wins
        for _ in 0..<5 { store.learn("안녕히가세요") }
        expect(store.suggest(prefix: "안녕") ?? "", "안녕히가세요", "store: higher frequency wins")

        // Korean-only learning
        store.learn("apple")
        store.learn("안녕ㅋ")
        store.learn("한")          // 1 syllable — below learnable length
        store.learn("오늘저녁에치킨먹을래") // 10 syllables — spaceless sentence, over cap
        expect(store.count(of: "apple"), 0, "store: never learns English")
        expect(store.count(of: "안녕ㅋ"), 0, "store: never learns jamo-mixed")
        expect(store.count(of: "한"), 0, "store: never learns 1-syllable words")
        expect(store.count(of: "오늘저녁에치킨먹을래"), 0, "store: never learns spaceless sentences (>7 syllables)")

        // Non-hangul prefixes never suggest
        expect(store.suggest(prefix: "안녕ㅎ") == nil, true, "store: jamo prefix → no suggestion")
        expect(store.suggest(prefix: "ap") == nil, true, "store: ascii prefix → no suggestion")

        // Persistence roundtrip — and privacy: count==1 units never reach disk
        store.learn("일회성단어")
        store.saveNow()
        let reloaded = WordFrequencyStore(fileURL: storeURL)
        expect(reloaded.count(of: "안녕하세요"), 3, "store: persistence roundtrip")
        expect(reloaded.count(of: "일회성단어"), 0, "store: one-off units never persisted")
        expect(reloaded.suggest(prefix: "안녕") ?? "", "안녕히가세요", "store: suggest after reload")

        // Disk contains only words + counts — no timestamps (PRIVACY.md)
        if let raw = try? String(contentsOf: storeURL, encoding: .utf8) {
            expect(raw.contains("lastUsed"), false, "store: lastUsed never persisted")
        } else {
            expect(false, true, "store: file readable after saveNow")
        }

        // Clean store never creates a file footprint
        let emptyURL = URL(fileURLWithPath: NSTemporaryDirectory() + "haneul_test_store/empty.json")
        let emptyStore = WordFrequencyStore(fileURL: emptyURL)
        emptyStore.saveNow()
        expect(FileManager.default.fileExists(atPath: emptyURL.path), false, "store: no file when nothing learned")

        // deleteAll erases memory + file
        reloaded.deleteAll()
        expect(reloaded.suggest(prefix: "안녕") == nil, true, "store: deleteAll clears suggestions")
        expect(FileManager.default.fileExists(atPath: storeURL.path), false, "store: deleteAll removes file")

        // ── Composer suggestion acceptance (Tab) ──
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) } // 안녕
            expect(composer.currentPreview(), "안녕", "composer: currentPreview")
            composer.acceptSuggestion("안녕하세요", client: client)
            expect(client.marked, "안녕하세요", "composer: accepted suggestion is marked")
            let committed = composer.commit(to: client, convertEnglish: true)
            expect(committed, "안녕하세요", "composer: commit returns accepted word")
            expect(client.committedText, "안녕하세요", "composer: accepted word inserted")
        }

        // Regression (review finding): accepted word + wrong-layout continuation
        // must commit EXACTLY the marked text — never English-convert away
        // the accepted Hangul.
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) }
            composer.acceptSuggestion("안녕하세요", client: client)
            for ch in "mail" { _ = composer.handleInput(String(ch), client: client) }
            let marked = client.marked
            let committed = composer.commit(to: client, convertEnglish: true)
            expect(committed, marked, "regression: commit equals marked text after accept")
            expect(committed.contains("안녕하세요"), true, "regression: accepted word survives conversion")
        }

        // Regression (review finding): backspace after accept peels ONE
        // syllable, not the whole word.
        do {
            let client = FakeClient()
            let composer = KoreanComposer()
            for ch in "dkssud" { _ = composer.handleInput(String(ch), client: client) }
            composer.acceptSuggestion("안녕하세요", client: client)
            _ = composer.deleteBackward(client: client)
            expect(client.marked, "안녕하세", "regression: backspace peels one syllable after accept")
        }

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

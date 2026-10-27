import Foundation

private final class ContextProbe: ExternalEnglishContextClient {
    var text: String
    var selection: NSRange
    var marked = NSRange(location: NSNotFound, length: 0)
    var reply: String?
    var useReply = false
    var selectionReads = 0
    var selectionAfterFirstRead: NSRange?
    var markedReads = 0
    var requests: [NSRange] = []
    init(_ text: String) {
        self.text = text
        selection = NSRange(location: (text as NSString).length, length: 0)
    }
    func contextSelection() -> NSRange {
        selectionReads += 1
        return selectionReads > 1 ? (selectionAfterFirstRead ?? selection) : selection
    }
    func contextMarkedRange() -> NSRange { markedReads += 1; return marked }
    func contextSubstring(in range: NSRange) -> String? {
        requests.append(range)
        if useReply { return reply }
        let source = text as NSString
        guard range.location <= source.length, range.length <= source.length - range.location else { return nil }
        return source.substring(with: range)
    }
    var reads: Int { selectionReads + markedReads + requests.count }
}

private final class InferenceSink: ComposerClient {
    var output = ""
    var marked = ""
    func insertText(_ text: String) { output += text }
    func setMarkedText(_ text: String) { marked = text }
}

@main
enum InputInferenceTests {
    static var passes = 0
    static var failures = 0
    static func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        if actual == expected { passes += 1 }
        else { failures += 1; print("FAIL \(label): expected \(expected), got \(actual)") }
    }
    private static func capture(_ probe: ContextProbe, enabled: Bool = true,
                        secureInput: () -> Bool = { false }) -> String? {
        ExternalEnglishContext.capture(from: probe, enabled: enabled,
            secureInput: secureInput, isKnownEnglishWord: EnglishDetector.isExplicitEnglishContextWord)
    }
    static func commit(_ keys: String, external: String? = nil, compounds: Bool = true,
                       automatic: Bool = true, active: Bool = true,
                       dictionary: PersonalDictionary = .empty) -> String {
        let composer = KoreanComposer()
        let sink = InferenceSink()
        composer.autoEnglishEnabled = automatic
        composer.dictionaryCompoundEnabled = compounds
        composer.personalDictionary = dictionary
        composer.beginExternalEnglishContext(external)
        for key in keys {
            if AlphanumericWords.isDigit(key), composer.handleDigit(key, client: sink) { continue }
            _ = composer.handleInput(String(key), client: sink)
        }
        composer.commit(to: sink, convertEnglish: active)
        return sink.output
    }
    static func hangul(_ keys: String) -> String { ManualToggle.keysToHangul(keys)! }

    static func main() {
        let root = FileManager.default.currentDirectoryPath
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + EnglishDetector.bundledWordlistNames.map {
            "\(root)/Resources/IM/\($0).txt"
        }
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map {
            "\(root)/Resources/IM/\($0).txt"
        })
        KoreanDictionary.wordlistPath = "\(root)/Resources/IM/korean_words.txt"
        check(KoreanDictionary.isLoaded, true, "real Korean veto loaded")

        for (before, expected) in [
            ("I ", "i"), ("I, ", "i"), ("hello ", "hello"), ("HELLO ", "hello"),
            ("hello,,  ", "hello"), ("한글 hello ", "hello"), ("😀 hello ", "hello"),
            ("hello\nworld ", "world"), ("I’m ", "i'm"), ("don’t ", "don't"),
            ("(hello ", "hello"), ("\"hello ", "hello"),
        ] {
            let probe = ContextProbe(before)
            check(capture(probe), Optional(expected), "context \(before.debugDescription)")
            check(probe.requests.count, 1, "one bounded substring read")
            check(probe.requests.first!.length <= ExternalEnglishContext.readSpan, true, "bounded request")
            check(probe.text, before, "surrounding document never rewritten")
        }
        for before in ["", "hello", "hello. ", "hello! ", "hello? ", "hello\n",
                       "hello\n ", "hello\t ", "hello/ ", "'hello' ", "hello’ ",
                       "hello_world ", "hello-world ", "123world ", "한글world ",
                       "hello你好 ", "hello🐱 ", "éhello ", "aplle ", "applle ",
                       "helloworl ", "123 ", "a1 ", "e''mail ", "100 ml ",
                       "100 mL ", "1.5 ml ", "100 bar ", "100 in "] {
            check(capture(ContextProbe(before)), nil, "reject ambiguous/unregistered context \(before.debugDescription)")
        }
        let disabled = ContextProbe("hello ")
        check(capture(disabled, enabled: false), nil, "context OFF")
        check(disabled.reads, 0, "OFF never queries client")
        let secure = ContextProbe("hello ")
        check(capture(secure, secureInput: { true }), nil, "secure blocked")
        check(secure.reads, 0, "secure never queries client")
        for flipAt in 2...6 {
            var calls = 0
            let probe = ContextProbe("hello ")
            check(capture(probe, secureInput: { calls += 1; return calls >= flipAt }), nil,
                  "secure becomes active at check \(flipAt)")
            if flipAt < 4 { check(probe.requests.count, 0, "secure rechecked before substring") }
        }
        let selected = ContextProbe("hello ")
        selected.selection.length = 2
        check(capture(selected), nil, "selection refuses context")
        check(selected.markedReads, 0, "selection stops before marked read")
        let moved = ContextProbe("hello ")
        moved.selectionAfterFirstRead = NSRange(location: 2, length: 0)
        check(capture(moved), nil, "cursor moved during request refuses stale context")
        let beganSelection = ContextProbe("hello ")
        beganSelection.selectionAfterFirstRead = NSRange(location: 6, length: 1)
        check(capture(beganSelection), nil, "selection began during request refuses stale context")
        for range in [NSRange(location: NSNotFound, length: NSNotFound),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: 0)] {
            let probe = ContextProbe("hello "); probe.selection = range
            check(capture(probe), nil, "unsupported/empty cursor refuses context")
            check(probe.requests.isEmpty, true, "invalid selection has no substring read")
        }
        for range in [NSRange(location: 0, length: 1), NSRange(location: NSNotFound, length: NSNotFound)] {
            let probe = ContextProbe("hello "); probe.marked = range
            check(capture(probe), nil, "existing/unsupported marked range refuses context")
            check(probe.requests.isEmpty, true, "marked failure has no substring read")
        }
        for reply: String? in [nil, "hello", "hello  ", "o "] {
            let probe = ContextProbe("hello "); probe.useReply = true; probe.reply = reply
            check(capture(probe), nil, "nil/truncated/oversized reply refused")
        }
        let distant = ContextProbe(String(repeating: "가", count: 300) + " hello ")
        check(capture(distant), "hello", "long document bounded suffix")
        check(distant.requests.first?.length, ExternalEnglishContext.readSpan, "long request remains 128 UTF-16")
        let cut = ContextProbe(String(repeating: "h", count: 128) + "ello ")
        check(capture(cut), nil, "token crossing read window not inferred")
        check(ExternalEnglishContext.previousWord(before: "hello ", atDocumentStart: false), nil,
              "unknown left window edge refused")
        check(ExternalEnglishContext.previousWord(before: " hello ", atDocumentStart: false), "hello",
              "known left token boundary accepted")
        check(ExternalEnglishContext.previousWord(before: String(repeating: "a", count: 65) + " ",
              atDocumentStart: true), nil, "word length bounded")

        check(commit("to", external: capture(ContextProbe("I "))), "to", "ABC I then Hangul 새 -> to")
        check(commit("go", external: capture(ContextProbe("I "))), "go", "external exact trigger for go")
        check(commit("go", external: "I"), "go", "external context normalizes case before trigger lookup")
        check(commit("go", external: capture(ContextProbe("render "))), "해", "go trigger stays conservative")
        check(commit("to"), "새", "no outside context preserves Korean 새")
        check(commit("to", external: "i", automatic: false), "새", "master OFF defeats external context")
        check(commit("to", external: "i", active: false), "새", "passive commit never converts")
        check(commit("to", external: capture(ContextProbe("100 ml "))), "새", "quantity unit cannot seed English context")
        check(capture(ContextProbe("hello in ")), "in", "English preposition unaffected without quantity")
        check(commit("to", external: "i", dictionary: PersonalDictionary(forceList: [], blockList: ["to"])),
              "새", "personal block defeats external context")
        for keys in ["cor", "ahems", "rksk", "rkwl", "dlTwl", "goT", "sO", "whwhr", "dd", "zz", "bb"] {
            check(commit(keys, external: "hello"), hangul(keys), "Korean/Shift/slang preserved after ABC: \(keys)")
        }
        for typo in ["aplle", "applle", "helloworl", "hellovide", "helllovideo"] {
            for external in [nil, "hello"] as [String?] {
                check(commit(typo, external: external), hangul(typo), "unregistered typo unchanged \(typo)")
            }
        }
        // 'appel'은 macOS broad 사전에 실제 등재된 단어다. 철자 근사 교정과 구분한다.
        check(commit("appel"), "appel", "existing exact registered word is not treated as an inferred typo")
        check(commit("to", external: "aplle"), "새", "unregistered external seed cannot create English intent")
        let sequence = KoreanComposer(); let sequenceSink = InferenceSink()
        sequence.beginExternalEnglishContext("hello")
        for key in "an" { _ = sequence.handleInput(String(key), client: sequenceSink) }
        sequence.commit(to: sequenceSink, convertEnglish: true); sequence.completeBoundary(" ")
        check(sequenceSink.output, "an", "external context consumed for initial homograph")
        check(sequence.lastEnglishWord, nil, "homograph doesn't start a new English chain")
        for key in "so" { _ = sequence.handleInput(String(key), client: sequenceSink) }
        sequence.commit(to: sequenceSink, convertEnglish: true)
        check(sequenceSink.output, "an내", "external seed not reused for following Korean word")
        let cleared = KoreanComposer(); let clearedSink = InferenceSink()
        cleared.beginExternalEnglishContext("i"); cleared.resetEnglishContext()
        for key in "to" { _ = cleared.handleInput(String(key), client: clearedSink) }
        cleared.commit(to: clearedSink, convertEnglish: true)
        check(clearedSink.output, "새", "cursor reset clears external seed")

        for word in ["helloworld", "hellovideo", "appleworld", "videoworld"] {
            check(EnglishDetector.dictionaryCompoundParts(word) != nil, true, "exact 2-word split \(word)")
            check(commit(word), word, "runtime compound enabled \(word)")
            check(commit(word, compounds: false), hangul(word), "compound OFF \(word)")
            check(commit(word, automatic: false), hangul(word), "master OFF compound \(word)")
            check(commit(word, active: false), hangul(word), "passive compound \(word)")
            check(commit(word, dictionary: PersonalDictionary(forceList: [], blockList: [word])),
                  hangul(word), "whole-word block compound \(word)")
        }
        for part in ["hello", "world", hangul("hello"), hangul("world")] {
            check(commit("helloworld", dictionary: PersonalDictionary(forceList: [], blockList: [part])),
                  hangul("helloworld"), "constituent block protects \(part)")
        }
        for raw in ["helloworl", "hellovide", "heloworld", "theworld", "videotv",
                    "hello123world", "helloworldvideo", "hello-world", "HelloWorld", "HELLOWORLD"] {
            // Case normalization belongs to caller; the pure resolver accepts lowercase ASCII only.
            check(EnglishDetector.dictionaryCompoundParts(raw) == nil, true, "invalid/inexact split \(raw)")
        }
        for raw in ["accordanger", "accordinner", "accordriver", "acrosscare", "acrosscore"] {
            check(EnglishDetector.dictionaryCompoundParts(raw) == nil, true, "ambiguous exact splits refused \(raw)")
            check(commit(raw), hangul(raw), "ambiguous compound leaves typed composition \(raw)")
        }
        check(EnglishDetector.dictionaryCompoundParts("workform") != nil, true, "two exact components can form clean Hangul")
        check(commit("workform"), hangul("workform"), "actual clean Hangul cannot use compound inference")
        for raw in ["HelloWorld", "HELLOWORLD", "helloWorld"] {
            check(commit(raw), hangul(raw), "meaningful Shift cannot open compound \(raw)")
        }
        for raw in ["helloworld", "hellovideo"] {
            check(EnglishDetector.shouldConvert(units: ["책"], keys: Array(raw),
                  dictionaryCompoundsEnabled: true), false, "Korean veto before compound \(raw)")
            check(EnglishDetector.shouldConvert(units: ["며", "새"], keys: Array(raw),
                  dictionaryCompoundsEnabled: true), false, "clean Hangul no inferred compound \(raw)")
        }
        check(commit("apple", compounds: false), "apple", "exact existing dictionary unaffected by compound OFF")
        check(commit("helloworld", compounds: false,
              dictionary: PersonalDictionary(forceList: ["helloworld"], blockList: [])), "helloworld",
              "explicit personal force remains independently available")

        // #94: numeric fallback must use the same policy as the original composer.
        for prefix in ["1", "123"] {
            for word in ["helloworld", "hellovideo"] {
                let raw = prefix + word
                let original = prefix + hangul(word)
                check(commit(raw), raw, "numeric compound ON \(raw)")
                check(commit(raw, compounds: false), original, "numeric compound OFF \(raw)")
                check(commit(raw, automatic: false), original, "numeric master OFF \(raw)")
                check(commit(raw, active: false), original, "numeric passive commit \(raw)")
                check(commit(raw, dictionary: PersonalDictionary(forceList: [], blockList: [word])),
                      original, "numeric constituent block \(raw)")
                check(commit(raw, dictionary: PersonalDictionary(forceList: [], blockList: [raw])),
                      original, "numeric whole-word block \(raw)")
                check(commit(raw, compounds: false,
                      dictionary: PersonalDictionary(forceList: [raw], blockList: [])),
                      raw, "numeric explicit force remains independent \(raw)")
            }
        }

        let suite = "haneul.input-inference.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(InputInferencePolicy.externalEnglishContextEnabled(in: defaults), true, "external context default ON")
        check(InputInferencePolicy.dictionaryCompoundEnabled(in: defaults), true, "compound default ON")
        defaults.set(false, forKey: InputInferencePolicy.externalEnglishContextKey)
        defaults.set(false, forKey: InputInferencePolicy.dictionaryCompoundKey)
        check(InputInferencePolicy.externalEnglishContextEnabled(in: defaults), false, "external context stored OFF")
        check(InputInferencePolicy.dictionaryCompoundEnabled(in: defaults), false, "compound stored OFF")
        defaults.set("invalid", forKey: InputInferencePolicy.externalEnglishContextKey)
        defaults.set("invalid", forKey: InputInferencePolicy.dictionaryCompoundKey)
        check(InputInferencePolicy.externalEnglishContextEnabled(in: defaults), true, "bad context type uses default")
        check(InputInferencePolicy.dictionaryCompoundEnabled(in: defaults), true, "bad compound type uses default")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

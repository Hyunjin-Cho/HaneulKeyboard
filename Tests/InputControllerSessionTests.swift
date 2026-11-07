import AppKit
import Carbon
import InputMethodKit

// 2026-10-20: regression coverage for real controller method bodies with a fake IMK host.
// This process neither opens windows nor sends system keyboard events.
// All text below is synthetic test data. No text contents are written to logs.
final class OrphanWatcher { static let shared = OrphanWatcher(); func checkIfDue() {} }
final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    init() { super.init(suiteName: "local.synthetic.haneul-r12.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
let probeDefaults = MemoryDefaults()

final class ProbeClient: NSObject, IMKTextInput {
    /// 2026-11-07 (#173, 리뷰 F-14): 실제 NSTextView를 재서 나온 값으로도 전 시나리오를 돌린다(off-screen 실측) —
    /// 길이 0·문서 끝 읽기는 nil, 넘친 읽기는 잘라서 반환, 조합이 없을 때 markedRange {caret,0}, 범위 교체 뒤 캐럿 유지.
    /// 합성 호스트의 빈 문자열 응답이 F-5를 숨겼다. IMK 프록시를 거친 실기기 값은 별도 확인 대상이다.
    static var nsTextViewByDefault = false
    var nsTextView = ProbeClient.nsTextViewByDefault
    var readLengths: [Int] = []
    struct Field { var text = ""; var selection = NSRange(location: 0, length: 0); var marked = NSRange(location: NSNotFound, length: 0) }
    var fields = [Field(), Field()]
    var active = 0
    var text: String { get { fields[active].text } set { fields[active].text = newValue } }
    var selection: NSRange { get { fields[active].selection } set { fields[active].selection = newValue } }
    var marked: NSRange { get { fields[active].marked } set { fields[active].marked = newValue } }
    var afterInsert: (() -> Void)?
    var afterMark: (() -> Void)?
    var beforeSelection: (() -> Void)?
    var beforeSubstring: (() -> Void)?
    var rejectReplacement = false
    var unreadable = false
    var shortenRead = false
    var delayReplacementReadback = false
    var preserveTrailingCaret = false
    var reportMissingMarkedRange = false
    var reportMissingSelectionRange = false
    /// 2026-11-04 (#87): 커서 위치를 늘 0으로 돌려주는 호스트(Ghostty형 터미널).
    var frozenSelection = false
    var replacementReadSnapshot: String?
    func beginKeyEvent() { replacementReadSnapshot = nil }
    func insertText(_ value: Any!, replacementRange: NSRange) {
        if rejectReplacement && replacementRange.location != NSNotFound { return }
        if delayReplacementReadback && replacementRange.location != NSNotFound { replacementReadSnapshot = text }
        let string = (value as? NSAttributedString)?.string ?? (value as? String ?? "")
        let range = replacementRange.location != NSNotFound ? replacementRange : (marked.location != NSNotFound ? marked : selection)
        precondition(range.location != NSNotFound && NSMaxRange(range) <= (text as NSString).length)
        let trailing = (preserveTrailingCaret || nsTextView) && replacementRange.location != NSNotFound
            ? max(0, selection.location - NSMaxRange(range)) : 0
        text = (text as NSString).replacingCharacters(in: range, with: string)
        selection = NSRange(location: range.location + (string as NSString).length + trailing, length: 0)
        marked = NSRange(location: NSNotFound, length: 0)
        afterInsert?()
    }
    func setMarkedText(_ value: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let string = (value as? NSAttributedString)?.string ?? (value as? String ?? "")
        let range = replacementRange.location != NSNotFound ? replacementRange : (marked.location != NSNotFound ? marked : selection)
        text = (text as NSString).replacingCharacters(in: range, with: string)
        selection = NSRange(location: range.location + selectionRange.location, length: selectionRange.length)
        marked = string.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: range.location, length: (string as NSString).length)
        afterMark?()
    }
    func selectedRange() -> NSRange {
        beforeSelection?()
        if frozenSelection { return NSRange(location: 0, length: 0) }
        return reportMissingSelectionRange ? NSRange(location: NSNotFound, length: 0) : selection
    }
    func markedRange() -> NSRange {
        if reportMissingMarkedRange { return NSRange(location: NSNotFound, length: 0) }
        if nsTextView, marked.location == NSNotFound { return NSRange(location: selection.location, length: 0) }
        return marked
    }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        beforeSubstring?()
        readLengths.append(range.length)
        let readable = replacementReadSnapshot ?? text
        if nsTextView {
            let available = (readable as NSString).length - range.location
            guard !unreadable, range.location != NSNotFound, range.length > 0, available > 0 else { return nil }
            let clipped = min(range.length, available)
            let actual = NSRange(location: range.location, length: shortenRead ? clipped - 1 : clipped)
            return NSAttributedString(string: (readable as NSString).substring(with: actual))
        }
        guard !unreadable, range.location != NSNotFound, NSMaxRange(range) <= (readable as NSString).length else { return nil }
        let actual = shortenRead && range.length > 0 ? NSRange(location: range.location, length: range.length - 1) : range
        return NSAttributedString(string: (readable as NSString).substring(with: actual))
    }
    func length() -> Int { (text as NSString).length }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! { [:] }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed name: String!) {}
    func selectMode(_ name: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "local.haneul.controller-session-tests" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { UUID().uuidString }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { actualRange?.pointee = range; return attributedSubstring(from: range)?.string }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
    func setField(_ index: Int, text value: String) {
        fields[index] = Field(text: value, selection: NSRange(location: (value as NSString).length, length: 0))
    }
}

@main enum InputControllerSessionTests {
    static var checks = 0
    static var failures: [String] = []
    static var scenarios: [[String: Any]] = []
    static var hostLabel = ""
    static func check(_ value: Bool, _ id: String) { checks += 1; if !value { failures.append(hostLabel + id) } }
    static func fresh(key: RevertKey = .shiftSpace, keyboard: Bool = true) -> (HaneulInputController, ProbeClient) {
        probeDefaults.values = [RevertKey.defaultsKey: key.rawValue, RevertKey.phoneticKey: true,
            RevertKey.manualToggleAllWordsKey: keyboard, SlashEnglishSession.defaultsKey: true,
            "haneul.autoEnglishEnabled": true]
        let controller = HaneulInputController(), client = ProbeClient()
        controller.activateServer(client)
        return (controller, client)
    }
    @discardableResult static func press(_ controller: HaneulInputController, _ client: ProbeClient,
                                        _ text: String?, code: UInt16, flags: NSEvent.ModifierFlags = [],
                                        deliver: Bool = true) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: text ?? "", charactersIgnoringModifiers: text ?? "",
            isARepeat: false, keyCode: code)!
        client.beginKeyEvent()
        let handled = controller.handle(event, client: client)
        if !handled && deliver, let text { client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        return handled
    }
    static func shortcut(_ c: HaneulInputController, _ h: ProbeClient, _ key: RevertKey = .shiftSpace,
                         extras: NSEvent.ModifierFlags = []) {
        let flags = NSEvent.ModifierFlags(rawValue: key.requiredModifiers.rawValue).union(extras)
        press(c, h, " ", code: 49, flags: flags)
    }
    // #101: real key codes and Shift information exercise the controller's digit,
    // two-set jamo, boundary and modifier dispatch rather than a direct composer call.
    static func typeKeys(_ keys: String, _ c: HaneulInputController, _ h: ProbeClient,
                         extras: NSEvent.ModifierFlags = []) {
        let codes: [Character: UInt16] = [
            "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
            "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,
            "6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,
            "l":37,"j":38,"k":40,"n":45,"m":46,
        ]
        for key in keys {
            let lower = Character(String(key).lowercased())
            guard let code = codes[lower] else { preconditionFailure("unsupported synthetic test key") }
            let flags = key.isUppercase ? extras.union(.shift) : extras
            press(c,h,String(key),code:code,flags:flags)
        }
    }
    static func typeOriginal(_ c: HaneulInputController, _ h: ProbeClient) {
        for (text, code): (String, UInt16) in [("t",17),("k",40),("r",15),("h",4),("k",40)] { press(c,h,text,code:code) }
    }
    static func convert(_ c: HaneulInputController, _ h: ProbeClient, committed: Bool = false,
                        key: RevertKey = .shiftSpace, extras: NSEvent.ModifierFlags = []) {
        typeOriginal(c,h)
        if committed { press(c,h," ",code:49) }
        shortcut(c,h,key,extras:extras)
        check(c.probeComposer.lastConversion?.hangul == "사과", "conversion_original_pair")
        check(c.probeComposer.lastConversionOrigin == .phonetic, "conversion_phonetic_origin")
        check(h.text == (committed ? "apple " : "apple"), "conversion_english_surface")
    }
    static func result(_ id: String, _ c: HaneulInputController, _ h: ProbeClient) {
        let classification: String
        if h.text.trimmingCharacters(in: .whitespacesAndNewlines) == "사과" { classification = "original" }
        else if h.text.trimmingCharacters(in: .whitespacesAndNewlines) == "apple" { classification = "english" }
        else if h.text.trimmingCharacters(in: .whitespacesAndNewlines) == "메ㅔㅣㄷ" { classification = "keyboardInverse" }
        else { classification = "other" }
        scenarios.append(["id": hostLabel + id, "surfaceClass": classification,
            "pairPresent": c.probeComposer.lastConversion != nil,
            "origin": String(describing: c.probeComposer.lastConversionOrigin),
            "englishContextPresent": c.probeComposer.lastEnglishWord != nil,
            "slashActive": c.probeSlashActive])
    }
    static func main() {
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + EnglishDetector.bundledWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" })
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        // 2026-11-07 (#173, 리뷰 F-14): 같은 시나리오를 합성 호스트와 NSTextView 실측 호스트로 두 번 돈다.
        for nsTextView in [false, true] {
            ProbeClient.nsTextViewByDefault = nsTextView
            hostLabel = nsTextView ? "nstextview:" : ""
            runScenarios()
            runInputCoreReviewScenarios()
        }
        let output: [String:Any] = ["checks":checks,"failures":failures,"scenarioCount":scenarios.count,
            "scenarios":scenarios,"limits":"Controller method bodies with a synthetic IMK host. Physical input and OS timing still require separate validation."]
        let data = try! JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if !failures.isEmpty { exit(1) }
    }

    static func runScenarios() {
        check(PhoneticDictionary.bundled.english(for: "사과") == "apple", "bundled_dictionary_available")
        // #104: actual controller dispatch must use the registered spark word,
        // preserve surrounding text and keep the existing saved-pair undo.
        for extras: NSEvent.ModifierFlags in [[], .capsLock] {
            for keys in ["spark", "Spark"] {
                for prefix in ["", "앞말 😀 "] {
                    let (c,h) = fresh()
                    h.setField(0, text: prefix)
                    typeKeys(keys,c,h,extras:extras)
                    check(h.text == prefix + "넴가", "spark_composition_before_boundary")
                    press(c,h," ",code:49,flags:extras)
                    check(h.text == prefix + keys + " ", "spark_space_converts")
                    check(c.probeComposer.lastConversion?.hangul == "넴가", "spark_original_pair")
                    check(c.probeComposer.lastConversion?.english == keys, "spark_english_pair")
                    shortcut(c,h,extras:extras)
                    check(h.text == prefix + "넴가 ", "spark_undo_preserves_surroundings")
                    shortcut(c,h,extras:extras)
                    check(h.text == prefix + keys + " ", "spark_redo_preserves_surroundings")
                    result("spark_saved_pair_\(keys)_\(extras.rawValue)_\(prefix.count)",c,h)
                }
            }
        }
        for policy in ["global_off", "app_off", "block_english", "block_hangul"] {
            let (c,h) = fresh()
            switch policy {
            case "global_off": probeDefaults.values["haneul.autoEnglishEnabled"] = false
            case "app_off": probeDefaults.values[AutoConvertPolicy.disabledAppsKey] = ["local.haneul.controller-session-tests"]
            case "block_english": probeDefaults.values[PersonalDictionary.Keys.block] = ["spark"]
            default: probeDefaults.values[PersonalDictionary.Keys.block] = ["넴가"]
            }
            typeKeys("spark",c,h)
            press(c,h," ",code:49)
            check(h.text == "넴가 ", "spark_policy_keeps_original_\(policy)")
            check(c.probeComposer.lastConversion == nil, "spark_policy_has_no_conversion_\(policy)")
            result("spark_\(policy)",c,h)
        }
        // #93: real controller modifier paths must leave settled selections untouched.
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .function] {
            let (c,h) = fresh()
            h.setField(0, text: "keep selected text")
            let selection = NSRange(location: 5, length: 8)
            h.selection = selection
            check(!press(c,h,"c",code:8,flags:flags,deliver:false), "empty_modifier_passes_through")
            check(h.text == "keep selected text", "empty_modifier_preserves_text")
            check(h.selection == selection, "empty_modifier_preserves_selection")
            result("empty_modifier_\(flags.rawValue)",c,h)
        }
        for committed in [false, true] {
            for key in RevertKey.allCases {
                for extras: NSEvent.ModifierFlags in [[], .capsLock, .function, [.capsLock, .function]] {
                    let (c,h) = fresh(key:key)
                    convert(c,h,committed:committed,key:key,extras:extras)
                    for target in ["사과", "apple", "사과"] {
                        shortcut(c,h,key,extras:extras)
                        check(h.text == target + (committed ? " " : ""), "normal_roundtrip")
                        check(c.probeComposer.lastConversionOrigin == .phonetic, "normal_origin")
                    }
                    result("normal_\(committed)_\(key.rawValue)_\(extras.rawValue)",c,h)
                }
            }
        }
        // Notion reproduction: display changes immediately, but this key's
        // readback still returns the previous snapshot. The next key sees new text.
        for preserveCaret in [false, true] {
            for prefix in ["", "앞말 ", "😀 "] {
                for suffix in ["", " ", ", ", "'", "’"] {
                    let (c,h) = fresh()
                    h.text = prefix + "사과" + suffix
                    h.selection = NSRange(location: (h.text as NSString).length, length: 0)
                    h.delayReplacementReadback = true; h.preserveTrailingCaret = preserveCaret
                    shortcut(c,h)
                    check(h.text == prefix + "apple" + suffix,"delayed_first_surface")
                    check(c.probeComposer.lastConversion == nil,"delayed_not_prematurely_confirmed")
                    check(c.probeComposer.lastEnglishWord == nil,"delayed_no_premature_context")
                    for target in ["사과", "apple", "사과"] {
                        shortcut(c,h)
                        check(h.text == prefix + target + suffix,"delayed_original_roundtrip")
                        check(c.probeComposer.lastConversionOrigin == .phonetic,"delayed_phonetic_origin")
                    }
                    result("delayed_readback_\(preserveCaret)_\(prefix.count)_\(suffix.count)",c,h)
                }
            }
        }
        for original in ["키보드", "zlqhem", "밀가루", "키보드".decomposedStringWithCanonicalMapping] {
            let (c,h) = fresh(); h.setField(0,text:"😀 " + original + " ")
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            let expected = ManualToggle.resolve(word:original,phoneticEnabled:true,keyboardEnabled:true)!
            shortcut(c,h)
            check(h.text == "😀 " + expected.text + " ","delayed_alias_surface")
            shortcut(c,h)
            check(h.text == "😀 " + original + " ","delayed_exact_original_and_phrase")
            check(c.probeComposer.lastConversionOrigin == expected.origin,"delayed_original_origin")
            result("delayed_alias_\(original)",c,h)
        }
        // Match the trace's first failed marked geometry, then committed-space path.
        do {
            let (c,h) = fresh(); h.reportMissingMarkedRange = true
            typeOriginal(c,h); shortcut(c,h)
            check(h.text == "사과 ","missing_mark_geometry_commits_only")
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            shortcut(c,h); check(h.text == "apple ","notion_sequence_converts")
            shortcut(c,h); check(h.text == "사과 ","notion_sequence_restores")
            result("notion_sequence_missing_mark_then_delayed_readback",c,h)
        }
        for failure in ["unreadable", "short", "still_old", "selected", "marked", "moved", "rejected"] {
            let (c,h) = fresh(); h.setField(0,text:"사과 ")
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            if failure == "rejected" { h.rejectReplacement = true }
            shortcut(c,h)
            let expectedSurface = h.text
            let savedSelection = h.selection
            h.unreadable = failure == "unreadable"; h.shortenRead = failure == "short"
            if failure == "still_old" { h.beforeSubstring = { h.replacementReadSnapshot = "사과 " } }
            if failure == "selected" { h.selection.length = 1 }
            if failure == "marked" { h.marked = NSRange(location:0,length:5) }
            if failure == "moved" { h.selection.location = 0 }
            shortcut(c,h)
            check(h.text == expectedSurface,"deferred_uncertain_does_not_replace_\(failure)")
            check(c.probeComposer.lastConversion == nil,"deferred_uncertain_not_confirmed_\(failure)")
            check(c.probeComposer.lastEnglishWord == nil,"deferred_uncertain_no_context_\(failure)")
            h.unreadable = false; h.shortenRead = false; h.beforeSubstring = nil
            h.selection = savedSelection; h.marked = NSRange(location:NSNotFound,length:0)
            if ["selected", "marked", "moved"].contains(failure) {
                shortcut(c,h); check(!h.text.contains("사과"),"deferred_mismatch_discards_\(failure)")
            } else if failure != "rejected" {
                shortcut(c,h); check(h.text == "사과 ","deferred_later_verified_restore_\(failure)")
            } else {
                shortcut(c,h); check(h.text == "사과 ","deferred_true_rejection_stays_unchanged")
            }
            result("deferred_uncertain_\(failure)",c,h)
        }
        for boundary in ["commit", "activate", "deactivate", "new_proxy", "letter", "backspace", "arrow", "space", "other_shortcut"] {
            let (c,h) = fresh(); h.setField(0,text:"사과 ");h.delayReplacementReadback = true
            shortcut(c,h)
            switch boundary {
            case "commit": c.commitComposition(h)
            case "activate": c.activateServer(h)
            case "deactivate": c.deactivateServer(h); c.activateServer(h)
            case "letter": press(c,h,"s",code:1)
            case "backspace": _ = press(c,h,"\u{7f}",code:51,deliver:false)
            case "arrow": _ = press(c,h,"",code:123,flags:.function,deliver:false)
            case "space": press(c,h," ",code:49)
            case "other_shortcut": _ = press(c,h,"a",code:0,flags:.command,deliver:false)
            default: break
            }
            let destination = boundary == "new_proxy" ? ProbeClient() : h
            destination.setField(1,text:"apple "); destination.active = 1
            // No lifecycle callback here: ordinary key alone must also discard candidate.
            shortcut(c,destination)
            check(!destination.text.contains("사과"),"deferred_not_reused_after_\(boundary)")
            result("deferred_boundary_\(boundary)",c,destination)
        }
        for mutation in ["right_letter", "changed_suffix", "extra_suffix", "different_word", "same_session_key"] {
            let (c,h) = fresh();h.setField(0,text:mutation == "right_letter" ? "사과" : "사과 ")
            h.delayReplacementReadback = true;shortcut(c,h)
            switch mutation {
            case "right_letter": h.text = "apples";h.selection = NSRange(location:5,length:0)
            case "changed_suffix": h.text = "apple,";h.selection = NSRange(location:5,length:0)
            case "extra_suffix": h.text = "apple  ";h.selection = NSRange(location:7,length:0)
            case "different_word": h.text = "other ";h.selection = NSRange(location:5,length:0)
            default:
                h.beforeSubstring = {
                    h.beforeSubstring = nil
                    _ = press(c,h,"",code:123,flags:.function,deliver:false)
                }
            }
            let before = h.text;shortcut(c,h)
            check(h.text == before,"deferred_invalid_surface_untouched_\(mutation)")
            check(c.probeComposer.lastConversion == nil,"deferred_invalid_surface_not_armed_\(mutation)")
            result("deferred_invalid_\(mutation)",c,h)
        }
        for nested in ["ordinary_key", "newer_candidate"] {
            let (c,h) = fresh();h.setField(0,text:"사과 ");h.delayReplacementReadback = true
            h.afterInsert = {
                h.afterInsert = nil
                if nested == "ordinary_key" {
                    _ = press(c,h,"",code:123,flags:.function,deliver:false)
                } else {
                    h.setField(0,text:"키보드 ");shortcut(c,h)
                }
            }
            shortcut(c,h)
            shortcut(c,h)
            if nested == "ordinary_key" {
                check(h.text == "메ㅔㅣㄷ ","creation_nested_key_does_not_rearm_old_candidate")
            } else {
                check(h.text == "키보드 ","creation_nested_new_candidate_kept")
                check(c.probeComposer.lastConversion?.hangul == "키보드","creation_nested_new_origin_kept")
            }
            result("deferred_creation_nested_\(nested)",c,h)
        }
        for rpc in ["selection", "substring"] {
            let (c,h) = fresh(); h.setField(0,text:"사과 ");h.delayReplacementReadback = true
            shortcut(c,h)
            func nestedConversion() {
                h.beforeSelection = nil; h.beforeSubstring = nil
                c.deactivateServer(h);h.setField(1,text:"");h.active = 1;c.activateServer(h)
                for (text,code): (String,UInt16) in [("z",6),("l",37),("q",12),("h",4),("e",14),("m",46)] { press(c,h,text,code:code) }
                shortcut(c,h)
            }
            if rpc == "selection" { h.beforeSelection = nestedConversion } else { h.beforeSubstring = nestedConversion }
            shortcut(c,h)
            check(h.text == "keyboard","deferred_nested_new_surface_kept")
            check(c.probeComposer.lastConversion?.hangul == "키보드","deferred_nested_new_pair_kept")
            shortcut(c,h);check(h.text == "키보드","deferred_nested_new_roundtrip")
            result("deferred_nested_\(rpc)",c,h)
        }
        for reentrancy in ["insert_first", "insert_reverse", "selection_reverse", "substring_reverse"] {
            let (c,h) = fresh()
            if reentrancy != "insert_first" { convert(c,h) }
            func resetOnce() {
                h.afterInsert = nil; h.beforeSelection = nil; h.beforeSubstring = nil
                c.commitComposition(h)
            }
            if reentrancy.hasPrefix("insert") { h.afterInsert = resetOnce }
            else if reentrancy.hasPrefix("selection") { h.beforeSelection = resetOnce }
            else { h.beforeSubstring = resetOnce }
            if reentrancy == "insert_first" { typeOriginal(c,h) }
            shortcut(c,h)
            check(c.probeComposer.lastConversion == nil,"reentrant_callback_pair_not_rearmed_\(reentrancy)")
            check(c.probeComposer.lastEnglishWord == nil,"reentrant_context_not_rearmed_\(reentrancy)")
            result("artificial_reentrancy_\(reentrancy)",c,h)
        }
        for stage in ["selection", "substring"] {
            for value in ["apple", "hello"] {
                for mode in ["pending", "committed", "stored"] {
                    let (c,h) = fresh()
                    if mode == "stored" { convert(c,h) }
                    else { typeOriginal(c,h); if mode == "committed" { press(c,h," ",code:49) } }
                    let source = h.text
                    func changeField() {
                        h.beforeSelection = nil; h.beforeSubstring = nil
                        c.deactivateServer(h)
                        h.setField(1,text:value); h.active = 1
                        c.activateServer(h)
                    }
                    if stage == "selection" { h.beforeSelection = changeField }
                    else { h.beforeSubstring = changeField }
                    shortcut(c,h)
                    check(h.text == value, "changed_field_untouched_\(mode)_\(stage)")
                    check(h.fields[0].text == source, "source_field_kept_\(mode)_\(stage)")
                    check(c.probeComposer.lastConversion == nil, "changed_field_no_stale_pair_\(mode)_\(stage)")
                    result("changed_field_\(mode)_\(stage)_\(value)",c,h)
                }
            }
        }
        for action in ["unreadable", "truncated", "replacement_rejected"] {
            let (c,h) = fresh(); convert(c,h)
            h.unreadable = action == "unreadable"; h.shortenRead = action == "truncated"; h.rejectReplacement = action == "replacement_rejected"
            shortcut(c,h)
            check(h.text.hasPrefix("apple"),"unsupported_host_does_not_inverse")
            check(c.probeComposer.lastConversion != nil,"unsupported_host_keeps_pair")
            result(action,c,h)
        }
        // The old RPC must leave a conversion completed by a nested new session intact.
        for stage in ["preview_mark", "phonetic_insert"] {
            let (c,h) = fresh()
            if stage == "preview_mark" {
                for (text,code): (String,UInt16) in [("g",5),("i",34),("t",17),("h",4),("u",32),("b",11),("f",3),("h",4)] {
                    press(c,h,text,code:code)
                }
            } else { typeOriginal(c,h) }
            func convertInNewField() {
                h.afterInsert = nil; h.afterMark = nil
                c.deactivateServer(h)
                h.setField(1,text:""); h.active = 1
                c.activateServer(h)
                for (text,code): (String,UInt16) in [("z",6),("l",37),("q",12),("h",4),("e",14),("m",46)] {
                    press(c,h,text,code:code)
                }
                shortcut(c,h)
            }
            if stage == "preview_mark" { h.afterMark = convertInNewField }
            else { h.afterInsert = convertInNewField }
            shortcut(c,h)
            check(h.text == "keyboard","nested_new_field_text_kept_\(stage)")
            check(c.probeComposer.lastConversion?.hangul == "키보드","nested_new_pair_kept_\(stage)")
            check(c.probeComposer.lastConversionOrigin == .phonetic,"nested_new_origin_kept_\(stage)")
            shortcut(c,h)
            check(h.text == "키보드","nested_new_field_roundtrip_\(stage)")
            result("nested_new_session_\(stage)",c,h)
        }
        // The host owns deletion; the IME must forward it once, then compose Korean.
        func hostDelete(_ c: HaneulInputController, _ h: ProbeClient, forward: Bool = false) {
            let handled = press(c,h,forward ? "\u{f728}" : "\u{7f}",code:forward ? 117 : 51,deliver:false)
            check(!handled,"slash_delete_is_forwarded")
            guard !handled else { return }
            let selected = h.selection
            let range = selected.length > 0 ? selected
                : NSRange(location: forward ? selected.location : selected.location - 1,length:1)
            h.insertText("",replacementRange:range)
        }
        // A session callback while inspecting slash mode must not swallow the host key.
        for scenario in ["begin_selection", "letter_selection", "backspace_selection", "space_selection",
                         "letter_substring", "backspace_substring", "space_substring"] {
            let (c,h) = fresh()
            if !scenario.hasPrefix("begin") { press(c,h,"/",code:44) }
            var callbackCount = 0
            func endSession() {
                h.beforeSelection = nil; h.beforeSubstring = nil
                callbackCount += 1
                c.commitComposition(h)
            }
            if scenario.hasSuffix("selection") { h.beforeSelection = endSession }
            else { h.beforeSubstring = endSession }
            if scenario.hasPrefix("backspace") { hostDelete(c,h) }
            else {
                let text = scenario.hasPrefix("begin") ? "/" : scenario.hasPrefix("letter") ? "h" : " "
                let code: UInt16 = scenario.hasPrefix("begin") ? 44 : scenario.hasPrefix("letter") ? 4 : 49
                check(!press(c,h,text,code:code),"slash_session_change_forwards_\(scenario)")
            }
            let expected = scenario.hasPrefix("begin") ? "/" : scenario.hasPrefix("letter") ? "/h"
                : scenario.hasPrefix("backspace") ? "" : "/ "
            check(callbackCount == 1,"slash_session_callback_once_\(scenario)")
            check(h.text == expected,"slash_session_change_keeps_key_\(scenario)")
            check(!c.probeSlashActive,"slash_session_change_stays_ended_\(scenario)")
            result("slash_session_callback_\(scenario)",c,h)
        }
        // #87 · 2026-10-25: an immediate slash deletion must also work when the
        // host cannot expose a substring or even the pre-insertion caret range.
        for prefix in ["", "🙂"] {
            for unavailable in ["readable", "substring", "selection"] {
                let (c,h) = fresh(); h.setField(0,text:prefix)
                h.unreadable = unavailable == "substring"
                h.reportMissingSelectionRange = unavailable == "selection"
                press(c,h,"/",code:44)
                check(h.text == prefix + "/" && c.probeSlashActive,"immediate_slash_started_\(unavailable)")
                hostDelete(c,h)
                check(h.text == prefix && !c.probeSlashActive,"immediate_slash_delete_ends_\(unavailable)")
                press(c,h,"h",code:4)
                check(h.text == prefix + "ㅗ","immediate_slash_delete_korean_\(unavailable)")
                result("immediate_slash_delete_\(unavailable)_\(prefix.isEmpty)",c,h)
            }
        }
        // 2026-11-04 오너 신고: CLI에서 숫자 선택(1. Yes)이 안 먹었다 — 첫머리 숫자가 조합 중 글자로 붙잡혔다.
        // 조합이 없을 때 숫자는 앱에 바로 전달되고(조합 중 표시 없음), 수량 변환은 그대로 남는다.
        for host in ["readable", "unreadable"] {
            let (c,h) = fresh(); h.unreadable = host == "unreadable"
            check(!press(c,h,"1",code:18),"cli_digit_forwarded_\(host)")
            check(h.text == "1" && h.marked.location == NSNotFound,"cli_digit_no_marked_\(host)")
            press(c,h,"0",code:29)
            for (key, code) in [("k", UInt16(40)), ("g", 5)] { press(c,h,key,code:code) }
            press(c,h," ",code:49)
            check(h.text == "10kg ","cli_digit_quantity_still_converts_\(host)")
            result("cli_digit_\(host)",c,h)
        }
        // 2026-11-04 오너 신고(#87): `/` 뒤 영어를 치고 `/`까지 전부 지운 뒤 다시 치면 영어가 나왔다.
        // 글자를 돌려주지 않는 호스트(터미널 등)에서도 전부 지운 다음 키는 한글이어야 한다.
        for prefix in ["", "앞 "] {
            for host in ["readable", "substring", "selection", "frozen"] {
                let (c,h) = fresh(); h.setField(0,text:prefix)
                h.unreadable = host != "readable"
                h.reportMissingSelectionRange = host == "selection"
                h.frozenSelection = host == "frozen"
                press(c,h,"/",code:44)
                for (letter, code) in [("a", UInt16(0)), ("b", 11), ("c", 8)] {
                    check(!press(c,h,letter,code:code),"slash_delete_all_letter_forwarded_\(host)")
                }
                check(h.text == prefix + "/abc" && c.probeSlashActive,"slash_delete_all_typed_\(host)")
                for _ in 0..<3 { hostDelete(c,h) }
                check(h.text == prefix + "/" && c.probeSlashActive,"slash_delete_all_letters_keep_english_\(host)")
                hostDelete(c,h)
                check(h.text == prefix && !c.probeSlashActive,"slash_delete_all_slash_ends_\(host)")
                press(c,h,"h",code:4)
                check(h.text == prefix + "ㅗ","slash_delete_all_then_korean_\(host)")
                result("slash_delete_all_\(host)_\(prefix.isEmpty)",c,h)
            }
        }
        // #87: capability can disappear after '/' was already anchored. This
        // differs from a host whose selection is unavailable for the entire run.
        for prefix in ["", "앞🙂 "] {
            for readable in [false,true] {
                let (c,h) = fresh(); h.setField(0,text:prefix)
                press(c,h,"/",code:44)
                h.reportMissingSelectionRange = true
                h.unreadable = !readable
                hostDelete(c,h)
                check(h.text == prefix && !c.probeSlashActive,"slash_selection_disappears_delete_ends_\(readable)")
                h.reportMissingSelectionRange = false
                h.unreadable = false
                press(c,h,"h",code:4)
                check(h.text == prefix + "ㅗ","slash_selection_disappears_korean_\(readable)")
                result("slash_selection_disappears_\(readable)_\(prefix.isEmpty)",c,h)
            }
        }
        for (delimiter,key,flags): (String,UInt16,NSEvent.ModifierFlags) in [
            (")",29,.shift),("]",30,[]),("}",30,.shift)
        ] {
            for unavailable in [false,true] {
                let (c,h) = fresh(); h.unreadable = unavailable
                press(c,h,"/",code:44)
                check(!press(c,h,delimiter,code:key,flags:flags),"slash_closing_delimiter_forwarded_once")
                check(h.text == "/" + delimiter && !c.probeSlashActive,"slash_closing_delimiter_ends_mode")
                press(c,h,"h",code:4)
                check(h.text == "/" + delimiter + "ㅗ","slash_closing_delimiter_returns_to_korean")
                result("slash_closing_delimiter_\(delimiter)_\(unavailable)",c,h)
            }
        }
        for prefix in ["", "🙂"] {
            let (c,h) = fresh(); h.setField(0,text:prefix)
            press(c,h,"/",code:44); press(c,h,"h",code:4)
            hostDelete(c,h)
            check(c.probeSlashActive && h.text == prefix + "/","slash_tail_delete_keeps_mode")
            hostDelete(c,h)
            check(!c.probeSlashActive && h.text == prefix,"slash_trigger_delete_ends_mode")
            press(c,h,"h",code:4)
            check(h.text == prefix + "ㅗ","slash_delete_returns_to_korean")
            result("slash_delete_utf16_\(prefix.isEmpty)",c,h)
        }
        for forward in [false,true] {
            let (c,h) = fresh(); press(c,h,"/",code:44); press(c,h,"h",code:4)
            h.selection = NSRange(location:0,length:forward ? 0 : 2)
            hostDelete(c,h,forward:forward)
            check(!c.probeSlashActive,"slash_selected_or_forward_delete_ends_mode")
            press(c,h,"h",code:4)
            check(h.text.hasPrefix("ㅗ"),"slash_selected_or_forward_delete_korean")
            result("slash_delete_selection_forward_\(forward)",c,h)
        }
        // #101: composing and finalized surfaces must share the same original
        // pair, including UTF-16 offsets after an emoji and persistent CapsLock.
        let attached: [(String,String)] = [
            ("github","밖에"),("github","뿐"),("github","라도"),("github","까지라도"),
            ("T800","에"),("800T","는"),("a24","에서"),("a16z","만"),("a7R","로"),
        ]
        for (name,particle) in attached {
            let keys = name + ManualToggle.hangulToKeys(particle)!
            let original = ManualToggle.keysToHangul(keys)!
            for prefix in ["", "앞🙂 "] {
                for committed in [false,true] {
                    let (c,h) = fresh(); h.setField(0,text:prefix)
                    typeKeys(keys,c,h,extras:.capsLock)
                    check(h.text == prefix + name + particle,"attached_particle_preview_\(name)_\(particle)")
                    check(h.marked.location != NSNotFound,"attached_particle_still_composing")
                    if committed { press(c,h," ",code:49,flags:.capsLock) }
                    let trailing = committed ? " " : ""
                    check(h.text == prefix + name + particle + trailing,"attached_particle_boundary_surface")
                    for expected in [original,name + particle,original,name + particle] {
                        shortcut(c,h,extras:.capsLock)
                        check(h.text == prefix + expected + trailing,"attached_particle_original_roundtrip_\(name)_\(particle)")
                    }
                    check(c.probeComposer.lastEnglishWord == nil,"attached_particle_does_not_start_english_context")
                    press(c,h," ",code:49,flags:.capsLock)
                    typeKeys("so",c,h,extras:.capsLock)
                    press(c,h," ",code:49,flags:.capsLock)
                    check(h.text.trimmingCharacters(in:.whitespacesAndNewlines).hasSuffix(" 내"),"attached_particle_next_korean_protected_\(name)_\(particle)_\(prefix.isEmpty)_\(committed)")
                    check(c.probeComposer.lastEnglishWord == nil,"attached_particle_korean_context_after_next_word")
                    result("attached_particle_\(name)_\(particle)_\(prefix.isEmpty)_\(committed)",c,h)
                }
            }
            for protection in ["global_off","host_off","prefix_block","whole_block"] {
                let (c,h) = fresh()
                if protection == "global_off" { probeDefaults.set(false,forKey:"haneul.autoEnglishEnabled") }
                if protection == "host_off" {
                    probeDefaults.set(["local.haneul.controller-session-tests"],forKey:AutoConvertPolicy.disabledAppsKey)
                }
                if protection == "prefix_block" || protection == "whole_block" {
                    let blocked = protection == "prefix_block" ? name.lowercased() : keys.lowercased()
                    probeDefaults.set([blocked],forKey:PersonalDictionary.Keys.block)
                }
                typeKeys(keys,c,h)
                press(c,h," ",code:49)
                check(h.text == original + " ","attached_particle_protection_\(protection)_\(name)_\(particle)")
                result("attached_particle_protection_\(protection)_\(name)_\(particle)",c,h)
            }
        }
        for quote in ["'", "’"] {
            let (c,h) = fresh(); press(c,h,quote,code:39)
            for (text,code): (String,UInt16) in [("g",5),("i",34),("t",17),("h",4),("u",32),("b",11),("f",3),("h",4)] {
                press(c,h,text,code:code)
            }
            check(h.text == quote + "github로","quoted_particle_preview")
            press(c,h,quote,code:39)
            check(h.text == quote + "github로" + quote,"closing_quote_keeps_particle_conversion")
            result("quoted_particle_\(quote == "'")",c,h)
        }
        for action in ["same_field_commit", "new_field_same_proxy_commit", "new_proxy", "activate_same_proxy"] {
            let (c,h) = fresh()
            press(c,h,"/",code:44); press(c,h,"h",code:4)
            check(c.probeSlashActive, "slash_active_before_boundary")
            var target = h
            switch action {
            case "same_field_commit": c.commitComposition(h)
            case "new_field_same_proxy_commit": h.active = 1; c.commitComposition(h)
            case "new_proxy": target = ProbeClient()
            default: c.activateServer(h)
            }
            let handled = press(c,target,"h",code:4)
            check(handled && !c.probeSlashActive && target.text.hasSuffix("ㅗ"), "slash_resets_\(action)")
            result("slash_\(action)",c,target)
        }
        for (text, code, label): (String, UInt16, String) in [("\r",36,"enter"),("\t",48,"tab"),("\u{1b}",53,"escape")] {
            let (c,h) = fresh()
            press(c,h,"/",code:44); press(c,h,text,code:code)
            // 2026-11-04 오너 결정: Return은 이제 slash 영어를 끝낸다(Tab·Esc는 그대로 유지).
            check(c.probeSlashActive == (label != "enter"),"slash_special_key_alone_keeps_session")
            h.active = 1
            c.commitComposition(h)
            check(!c.probeSlashActive,"slash_later_commit_always_ends_session")
            check(press(c,h,"h",code:4),"slash_after_special_key_other_field_is_korean")
            result("slash_\(label)_then_other_field_commit",c,h)
        }
    }

    /// 2026-11-07 (#173): 입력 코어 리뷰(input-core-F-1~6·12·13·15·16) 회귀. 고친 동작마다 정상 동작 대조군을 함께 둔다.
    static func runInputCoreReviewScenarios() {
        func moveCaretToEnd(_ h: ProbeClient) { h.selection = NSRange(location: (h.text as NSString).length, length: 0) }
        func recentReverts() -> Int { RecentReverts.load(from: probeDefaults).entries.count }
        func shift(_ c: HaneulInputController, _ h: ProbeClient) -> Bool { press(c,h," ",code:49,flags:.shift) }

        // F-1: 수정키 삭제로 시작 기호가 문서 끝에서 사라지면 읽기가 nil이다 — 기호를 읽어 본 호스트면 소실로 본다.
        for flags: NSEvent.ModifierFlags in [.command, .option] {
            for prefix in ["", "앞 "] {
                let (c,h) = fresh(); h.setField(0,text:prefix)
                press(c,h,"/",code:44); press(c,h,"h",code:4); press(c,h,"i",code:34)
                check(h.text == prefix + "/hi" && c.probeSlashActive,"slash_modified_delete_started")
                check(!press(c,h,"\u{7f}",code:51,flags:flags,deliver:false),"slash_modified_delete_forwarded")
                h.text = prefix; moveCaretToEnd(h)
                check(press(c,h,"h",code:4),"slash_modified_delete_next_key_composes")
                check(h.text == prefix + "ㅗ" && !c.probeSlashActive,"slash_modified_delete_korean_\(flags.rawValue)_\(prefix.isEmpty)")
                result("slash_modified_delete_\(flags.rawValue)_\(prefix.isEmpty)",c,h)
            }
        }
        do { // 대조: 뒤에 글자가 남아 있으면 다른 글자가 읽혀 원래도 복귀한다.
            let (c,h) = fresh(); h.setField(0,text:"뒤"); h.selection = NSRange(location:0,length:0)
            press(c,h,"/",code:44); press(c,h,"h",code:4)
            _ = press(c,h,"\u{7f}",code:51,flags:.option,deliver:false)
            h.text = "뒤"; h.selection = NSRange(location:0,length:0)
            check(press(c,h,"h",code:4) && !c.probeSlashActive,"slash_modified_delete_following_text_control")
            result("slash_modified_delete_following_text_control",c,h)
        }
        for host in ["unreadable", "frozen"] { // 대조: 처음부터 못 읽는 호스트는 기호 소실을 알 수 없다 — 추측하지 않는다.
            let (c,h) = fresh(); h.unreadable = true; h.frozenSelection = host == "frozen"
            press(c,h,"/",code:44); press(c,h,"h",code:4)
            _ = press(c,h,"\u{7f}",code:51,flags:.command,deliver:false)
            h.text = ""; h.selection = NSRange(location:0,length:0)
            check(!press(c,h,"h",code:4) && c.probeSlashActive && h.text == "h","slash_never_readable_stays_english_\(host)")
            result("slash_never_readable_\(host)",c,h)
        }

        // F-2: 교체 직후 읽기가 옛 글자여도(노션형) 되돌림은 화면에 반영된다 — 영어 문맥을 끊고, 다음 키에서 확인해 기록한다.
        for host in ["immediate", "delayed", "rejected"] {
            let (c,h) = fresh()
            typeKeys("want",c,h); press(c,h," ",code:49)
            check(h.text == "want " && c.probeComposer.lastEnglishWord == "want","auto_revert_precondition_\(host)")
            h.delayReplacementReadback = host == "delayed"; h.rejectReplacement = host == "rejected"
            h.preserveTrailingCaret = true
            check(shift(c,h),"auto_revert_consumed_\(host)")
            let surface = host == "rejected" ? "want " : "ㅈ뭇 "
            check(h.text == surface,"auto_revert_surface_\(host)")
            check(c.probeComposer.lastEnglishWord == nil,"auto_revert_cuts_english_context_\(host)")
            check(c.probeComposer.lastConversion?.english == "want","auto_revert_keeps_pair_\(host)")
            typeKeys("to",c,h); press(c,h," ",code:49)
            // 2026-11-07 (#173, 독립 리뷰 A-P2-1): 진짜 거부(Terminal.app형)는 화면이 영어 그대로라 문맥도 돌아와야 한다.
            // 처음엔 `want 새 `를 정답으로 적었는데 예전 동작을 깨는 회귀였다. 기록도 하지 않는다.
            check(h.text == (host == "rejected" ? "want to " : surface + "새 "),"auto_revert_next_word_\(host)")
            check(recentReverts() == (host == "rejected" ? 0 : 1),"auto_revert_recorded_\(host)")
            result("auto_revert_\(host)",c,h)
        }
        for (first, second) in [("git","is"),("cd","ls")] { // 대조: 문맥과 무관하게 변환되는 단어는 거부 호스트에서도 같다.
            let (c,h) = fresh(); h.rejectReplacement = true; h.preserveTrailingCaret = true
            typeKeys(first,c,h); press(c,h," ",code:49)
            _ = shift(c,h)
            typeKeys(second,c,h); press(c,h," ",code:49)
            check(h.text == first + " " + second + " ","auto_revert_rejected_context_free_\(first)")
            result("auto_revert_rejected_context_free_\(first)",c,h)
        }
        do { // 거부 호스트에서 여러 번 눌러도 문맥은 처음 그대로다.
            let (c,h) = fresh(); h.rejectReplacement = true; h.preserveTrailingCaret = true
            typeKeys("want",c,h); press(c,h," ",code:49)
            for _ in 0..<3 { _ = shift(c,h) }
            typeKeys("to",c,h); press(c,h," ",code:49)
            check(h.text == "want to " && recentReverts() == 0,"auto_revert_rejected_repeat")
            result("auto_revert_rejected_repeat",c,h)
        }
        do { // 되돌리는 값은 쌍의 영어가 아니라 끊기 전 문맥이다 — `apple'`은 원래 문맥을 넘기지 않는다.
            let (c,h) = fresh(); h.rejectReplacement = true; h.preserveTrailingCaret = true
            typeKeys("apple",c,h)
            check(press(c,h,"'",code:39),"auto_revert_rejected_apostrophe_absorbed")
            press(c,h," ",code:49)
            check(c.probeComposer.lastConversion?.english == "apple'" && c.probeComposer.lastEnglishWord == nil,"auto_revert_rejected_apostrophe_precondition")
            _ = shift(c,h)
            typeKeys("t",c,h)
            check(c.probeComposer.lastEnglishWord == nil,"auto_revert_rejected_restores_previous_context_only")
            result("auto_revert_rejected_apostrophe",c,h)
        }
        do { // 대조: 다음 키에서 읽기가 안 되면 무엇이 맞는지 모른다 — 끊어 둔 채로 둔다(안전한 실패).
            let (c,h) = fresh(); h.rejectReplacement = true; h.preserveTrailingCaret = true
            typeKeys("want",c,h); press(c,h," ",code:49)
            _ = shift(c,h)
            h.unreadable = true
            typeKeys("to",c,h); press(c,h," ",code:49)
            check(h.text == "want 새 ","auto_revert_rejected_unknown_stays_cut")
            result("auto_revert_rejected_unknown",c,h)
        }
        do { // 지연 호스트의 재토글: 다음 키에서 영어로 확인되면 문맥이 돌아오고, 기록은 한글로 되돌린 한 번뿐이다.
            let (c,h) = fresh(); typeKeys("want",c,h); press(c,h," ",code:49)
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            _ = shift(c,h); _ = shift(c,h)
            check(h.text == "want " && recentReverts() == 1,"auto_revert_delayed_redo_surface")
            typeKeys("to",c,h); press(c,h," ",code:49)
            check(h.text == "want to ","auto_revert_delayed_redo_restores_context")
            check(recentReverts() == 1,"auto_revert_delayed_redo_one_record")
            result("auto_revert_delayed_redo",c,h)
        }
        for boundary in ["commit", "deactivate", "new_proxy"] { // 세션이 바뀌면 후보를 버리고 기록하지 않는다.
            let (c,h) = fresh(); typeKeys("want",c,h); press(c,h," ",code:49)
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            _ = shift(c,h)
            var next = h
            switch boundary {
            case "commit": c.commitComposition(h)
            case "deactivate": c.deactivateServer(h); c.activateServer(h)
            default: next = ProbeClient()
            }
            typeKeys("t",c,next)
            check(recentReverts() == 0,"auto_revert_candidate_dropped_\(boundary)")
            result("auto_revert_candidate_\(boundary)",c,next)
        }
        do { // 후보 확인 읽기 중 세션이 끝나면 원래 키는 앱에 넘기고 낡은 기록을 남기지 않는다.
            let (c,h) = fresh(); typeKeys("want",c,h); press(c,h," ",code:49)
            h.delayReplacementReadback = true; h.preserveTrailingCaret = true
            _ = shift(c,h)
            h.beforeSubstring = { h.beforeSubstring = nil; c.commitComposition(h) }
            check(!press(c,h,"h",code:4),"auto_revert_candidate_session_change_forwards_key")
            check(recentReverts() == 0,"auto_revert_candidate_session_change_no_record")
            result("auto_revert_candidate_session_change",c,h)
        }

        // F-3 (오너 결정 2026-11-07): 같은 줄의 공백·닫는 기호·따옴표만 건너뛴다. 그 밖의 글자를 만나면 바꾸지 않고 스페이스를 넘긴다.
        let blocked = ["hello\n\n", "안녕\n", "안녕\r\n", "func foo() {\n    ", "안녕 🎬", "안녕 漢字", "résumé", "안녕(", "안녕[", "안녕{", "안녕:", "안녕\u{3000}"]
        for (index, before) in blocked.enumerated() {
            let (c,h) = fresh(); h.setField(0,text:before)
            check(!shift(c,h),"manual_skip_blocked_passes_key_\(index)")
            check(h.text == before + " ","manual_skip_blocked_only_space_added_\(index)")
            check(c.probeComposer.lastConversion == nil,"manual_skip_blocked_no_pair_\(index)")
            result("manual_skip_blocked_\(index)",c,h)
        }

        // F-15: 건너뛸 수 있는 뒤 경계가 길어도 두 번째 입력으로 돌아온다(스페이스가 쌓이지 않는다).
        for prefix in ["", "앞말 ", "😀 "] {
            for trailing in [" ", "   ", "    ", "... ", "!!! ", ", ", "\t\t\t\t", "\"')] ", "’”", String(repeating: " ", count: 40), "\u{a0}", "\u{a0}\u{a0}\u{a0}\u{a0}", ",\u{a0}"] {
                for caret in [false, true] {
                    let (c,h) = fresh(); h.setField(0,text:prefix + "안녕" + trailing); h.preserveTrailingCaret = caret
                    for (step, expected) in ["dkssud","안녕","dkssud","안녕"].enumerated() {
                        check(shift(c,h),"manual_roundtrip_consumed_\(step)_\(trailing.count)_\(prefix.count)")
                        check(h.text == prefix + expected + trailing,"manual_roundtrip_surface_\(step)_\(trailing.count)_\(prefix.count)")
                    }
                    check(c.probeComposer.lastConversionOrigin == .keyboard,"manual_roundtrip_origin")
                    result("manual_roundtrip_\(prefix.count)_\(trailing.count)_\(caret)",c,h)
                }
            }
        }
        // 2026-11-07 (#173, 루트 판단): 크롬 계열 contenteditable은 줄 끝 공백을 NBSP로 줄 수 있다(실기기 미확인) — 변환 직후 되돌리기가 깨지면 안 된다.
        do {
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.text = "apple\u{a0}"; moveCaretToEnd(h)
            for expected in ["메ㅔㅣㄷ\u{a0}","apple\u{a0}","메ㅔㅣㄷ\u{a0}"] { check(shift(c,h) && h.text == expected,"nbsp_pair_roundtrip") }
            check(c.probeComposer.lastConversionOrigin == .automatic,"nbsp_pair_keeps_saved_pair")
            result("nbsp_pair_roundtrip",c,h)
        }
        // 첫 교체를 호스트가 늦게 보여 줘도(노션형) 긴 뒤 경계에서 저장 쌍으로 돌아온다 — 자판 역변환(메ㅔㅣㄷ)으로 새지 않는다.
        for prefix in ["", "앞말 "] {
            for trailing in ["    ", "... ", "!!! "] {
                let (c,h) = fresh(); h.setField(0,text:prefix + "사과" + trailing)
                h.delayReplacementReadback = true; h.preserveTrailingCaret = true
                _ = shift(c,h)
                check(h.text == prefix + "apple" + trailing,"deferred_long_trailing_first")
                _ = shift(c,h)
                check(h.text == prefix + "사과" + trailing,"deferred_long_trailing_restores_\(prefix.count)_\(trailing.count)")
                result("deferred_long_trailing_\(prefix.count)_\(trailing.count)",c,h)
            }
        }
        do { // 자동 경로도 공백을 여러 번 친 뒤 저장 쌍으로 돌아온다(발음 쌍이 자판 역변환으로 바뀌지 않는다).
            let (c,h) = fresh(); h.setField(0,text:"앞말 ")
            typeOriginal(c,h); shortcut(c,h)
            check(h.text == "앞말 apple","pair_spaces_precondition")
            for _ in 0..<4 { press(c,h," ",code:49) }
            check(shift(c,h),"pair_spaces_consumed")
            check(h.text == "앞말 사과    ","pair_spaces_restores_saved_original")
            result("pair_spaces_restore",c,h)
        }
        do { // 대조: 일반 되돌리기는 읽는 범위가 넓어지지 않는다(긴 읽기를 잘라 주는 호스트 회귀·문맥 최소 읽기).
            let (c,h) = fresh(); h.setField(0,text:String(repeating: "앞", count: 80) + " ")
            typeKeys("apple",c,h); press(c,h," ",code:49)
            h.readLengths = []
            check(shift(c,h),"pair_read_narrow_consumed")
            check(h.text.hasSuffix(" 메ㅔㅣㄷ "),"pair_read_narrow_surface")
            check((h.readLengths.max() ?? 0) <= 9,"pair_read_narrow_length")
            result("pair_read_narrow",c,h)
        }

        // F-16: 저장 쌍이 화면과 다르면 쌍을 버리고 수동 경로로 넘어간다.
        do {
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.text = "Apple "; moveCaretToEnd(h)
            check(shift(c,h),"pair_mismatch_consumed")
            check(h.text == "메ㅔㅣㄷ ","pair_mismatch_manual_surface")
            check(c.probeComposer.lastConversion?.english == "Apple","pair_mismatch_new_pair")
            check(c.probeComposer.lastConversionOrigin == .keyboard,"pair_mismatch_new_origin")
            _ = shift(c,h)
            check(h.text == "Apple ","pair_mismatch_roundtrip")
            result("pair_mismatch_case",c,h)
        }
        do { // 커서가 다른 단어로 옮겨진 경우: 그 단어만 바뀌고 옛 단어는 건드리지 않는다.
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.text = "apple 안녕 "; moveCaretToEnd(h)
            check(shift(c,h),"pair_moved_consumed")
            check(h.text == "apple dkssud ","pair_moved_only_new_word")
            result("pair_moved_word",c,h)
        }
        do { // 바꿀 단어가 없으면 쌍을 버리고 스페이스 — 다음 입력이 옛 쌍을 다시 쓰지 않는다.
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.text = "apple 😀 "; moveCaretToEnd(h)
            check(!shift(c,h),"pair_blocked_passes_key")
            check(h.text == "apple 😀  ","pair_blocked_only_space_added")
            check(c.probeComposer.lastConversion == nil && c.probeComposer.lastEnglishWord == nil,"pair_blocked_clears_stale_state")
            result("pair_blocked",c,h)
        }
        do { // 설정으로 수동 변환이 꺼져 있으면 스페이스.
            let (c,h) = fresh(keyboard:false); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.text = "Apple "; moveCaretToEnd(h)
            check(!shift(c,h) && h.text == "Apple  ","pair_mismatch_keyboard_off_space")
            result("pair_mismatch_keyboard_off",c,h)
        }
        do { // 대조: 쌍이 맞으면 수동 경로를 타지 않고 저장 쌍으로 왕복한다.
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            for expected in ["메ㅔㅣㄷ ","apple ","메ㅔㅣㄷ "] { check(shift(c,h) && h.text == expected,"pair_match_control") }
            check(c.probeComposer.lastConversionOrigin == .automatic,"pair_match_control_origin")
            result("pair_match_control",c,h)
        }

        // F-4: 글자를 넣는 왕복 중 세션 콜백이 재진입해도 같은 단어를 두 번 넣지 않는다.
        for (scenario, keys, expected) in [("active","rk","가 "),("passive","rk","가"),("deactivate","rk","가 "),
                                           ("converted","apple","apple "),("particle","githubdp","github에 "),
                                           ("alphanumeric","a24","a24 "),("sent_digits","10kg","10kg ")] {
            let (c,h) = fresh()
            typeKeys(keys,c,h)
            h.afterInsert = {
                h.afterInsert = nil
                if scenario == "deactivate" { c.deactivateServer(h) } else { c.commitComposition(h) }
            }
            if scenario == "passive" { _ = press(c,h,"a",code:0,flags:.command,deliver:false) }
            else { press(c,h," ",code:49) }
            check(h.text == expected,"commit_reentrancy_once_\(scenario)")
            check(!c.probeComposer.hasPendingComposition,"commit_reentrancy_no_pending_\(scenario)")
            result("commit_reentrancy_\(scenario)",c,h)
        }
        do { // 넘침으로 앞부분을 내보내는 왕복 중 재진입해도 글자가 늘지 않는다.
            let (c,h) = fresh()
            for _ in 0..<45 {
                h.afterInsert = { h.afterInsert = nil; c.commitComposition(h) }
                typeKeys("rk",c,h)
            }
            h.afterInsert = nil
            check(h.text == String(repeating: "가", count: 45),"spill_reentrancy_once")
            result("spill_reentrancy",c,h)
        }
        do { // 대조: 재진입이 없으면 그대로.
            let (c,h) = fresh(); typeKeys("rk",c,h); press(c,h," ",code:49)
            check(h.text == "가 ","commit_no_reentrancy_control")
            result("commit_no_reentrancy_control",c,h)
        }

        // F-5: NSTextView는 길이 0 읽기에 nil을 준다. 글자가 있는 문서 맨 앞은 오른쪽 글자가 읽히니 스페이스를 넘긴다.
        do {
            let (c,h) = fresh(); h.setField(0,text:"abc"); h.selection = NSRange(location:0,length:0)
            check(!shift(c,h),"manual_doc_start_passes_key")
            check(h.text == " abc","manual_doc_start_space")
            result("manual_doc_start",c,h)
        }
        do { // 빈 칸: 길이 0 읽기에 빈 문자열을 주는 호스트는 넘긴다. nil을 주는 호스트는 아래 Ghostty형과 구분되지 않는다(오너 판단 대기).
            let (c,h) = fresh()
            check(shift(c,h) == h.nsTextView,"manual_empty_field_key")
            check(h.text == (h.nsTextView ? "" : " "),"manual_empty_field_surface")
            result("manual_empty_field",c,h)
        }
        do { // 대조(#30): 커서가 늘 0이고 못 읽는 터미널은 스페이스가 끼어들지 않는다.
            let (c,h) = fresh(); h.setField(0,text:"재가 "); h.unreadable = true; h.frozenSelection = true
            check(shift(c,h) && h.text == "재가 ","manual_ghostty_like_consumes_key")
            result("manual_ghostty_like",c,h)
        }

        // F-6: 쌍이 있는데 커서 위치를 모르면 키만 소비한다. 수동 경로(쌍 없음)는 일반 스페이스와 구분이 안 돼 그대로 넘긴다.
        do {
            let (c,h) = fresh(); typeKeys("apple",c,h); press(c,h," ",code:49)
            h.reportMissingSelectionRange = true
            check(shift(c,h),"pair_missing_selection_consumed")
            check(h.text == "apple ","pair_missing_selection_no_space")
            check(c.probeComposer.lastConversion != nil,"pair_missing_selection_keeps_pair")
            h.reportMissingSelectionRange = false
            check(shift(c,h) && h.text == "메ㅔㅣㄷ ","pair_missing_selection_later_recovers")
            result("pair_missing_selection",c,h)
        }
        do {
            let (c,h) = fresh(); h.setField(0,text:"재가 "); h.reportMissingSelectionRange = true
            check(!shift(c,h) && h.text == "재가  ","manual_missing_selection_control")
            result("manual_missing_selection_control",c,h)
        }

        // F-14 ④: 조합 중 Return·Tab·Esc는 조합을 활성 경계로 확정하고 키를 앱에 한 번 넘긴다. 문맥은 끊긴다.
        for (text, code, flags, label): (String, UInt16, NSEvent.ModifierFlags, String) in [
            ("\r",36,[],"return"), ("\r",36,.shift,"shift_return"), ("\u{3}",76,.numericPad,"keypad_enter"),
            ("\t",48,[],"tab"), ("\u{1b}",53,[],"escape"),
        ] {
            for (keys, committed) in [("rk","가"),("dkssud","안녕"),("apple","apple"),("githubdp","github에")] {
                let (c,h) = fresh(); typeKeys(keys,c,h)
                check(h.marked.location != NSNotFound,"composing_key_precondition_\(label)")
                check(!press(c,h,text,code:code,flags:flags,deliver:false),"composing_key_forwarded_\(label)_\(keys)")
                check(h.text == committed,"composing_key_commits_active_\(label)_\(keys)")
                check(h.marked.location == NSNotFound && !c.probeComposer.hasPendingComposition,"composing_key_ends_composition_\(label)_\(keys)")
                check(c.probeComposer.lastConversion == nil && c.probeComposer.lastEnglishWord == nil,"composing_key_breaks_context_\(label)_\(keys)")
                typeKeys("to",c,h); press(c,h," ",code:49)
                check(h.text == committed + "새 ","composing_key_next_word_korean_\(label)_\(keys)")
                result("composing_key_\(label)_\(keys)",c,h)
            }
        }
        for (text, code, flags, label): (String, UInt16, NSEvent.ModifierFlags, String) in [
            ("\r",36,.command,"cmd_return"), ("\r",36,.option,"option_return"), ("\t",48,.control,"ctrl_tab"), ("\u{1b}",53,.command,"cmd_escape"),
        ] { // 대조: 수정키가 붙으면 앱 단축키다 — 화면에 보이던 글자 그대로 확정한다(영타 변환 없음).
            let (c,h) = fresh(); typeKeys("apple",c,h)
            check(!press(c,h,text,code:code,flags:flags,deliver:false),"composing_shortcut_forwarded_\(label)")
            check(h.text == "메ㅔㅣㄷ" && !c.probeComposer.hasPendingComposition,"composing_shortcut_passive_\(label)")
            result("composing_shortcut_\(label)",c,h)
        }

        // 2026-11-07 (#173, 독립 리뷰 A-P3-2): 대문자가 두 글자가 되는 문자는 자모가 아니다 — 활성 경계로 넘기고 Debug에서도 죽지 않는다.
        do {
            let (c,h) = fresh(); typeKeys("rk",c,h)
            check(!press(c,h,"ß",code:27,flags:.shift),"sharp_s_shift_forwarded")
            check(h.text == "가ß" && !c.probeComposer.hasPendingComposition,"sharp_s_shift_boundary")
            result("sharp_s_shift",c,h)
        }

        // F-14 ④: 조합이 없으면 세션 콜백·단축키가 호스트의 선택 범위를 건드리지 않는다(#93 — 빈 marked text가 선택을 지운다).
        for action in ["commit", "deactivate", "deactivate_activate", "cmd_backspace", "arrow"] {
            let (c,h) = fresh(); h.setField(0,text:"keep selected text")
            let selection = NSRange(location:5,length:8)
            h.selection = selection
            var hostWrites = 0
            h.afterInsert = { hostWrites += 1 }; h.afterMark = { hostWrites += 1 }
            switch action {
            case "commit": c.commitComposition(h)
            case "deactivate": c.deactivateServer(h)
            case "deactivate_activate": c.deactivateServer(h); c.activateServer(h)
            case "cmd_backspace": check(!press(c,h,"\u{7f}",code:51,flags:.command,deliver:false),"selection_keep_forwarded_\(action)")
            default: check(!press(c,h,"\u{f702}",code:123,flags:.function,deliver:false),"selection_keep_forwarded_\(action)")
            }
            check(h.text == "keep selected text" && h.selection == selection,"selection_keep_surface_\(action)")
            check(hostWrites == 0,"selection_keep_no_host_write_\(action)")
            result("selection_keep_\(action)",c,h)
        }
        for action in ["commit", "deactivate"] { // 대조: 조합 중이면 보이던 글자를 확정하고 캐럿은 그 뒤다.
            let (c,h) = fresh(); h.setField(0,text:"앞 ")
            typeKeys("apple",c,h)
            if action == "commit" { c.commitComposition(h) } else { c.deactivateServer(h) }
            check(h.text == "앞 메ㅔㅣㄷ" && h.marked.location == NSNotFound,"selection_commit_visible_\(action)")
            check(h.selection == NSRange(location:6,length:0),"selection_commit_caret_\(action)")
            check(!c.probeComposer.hasPendingComposition,"selection_commit_no_pending_\(action)")
            result("selection_commit_\(action)",c,h)
        }

        // F-12·F-13: 실제 키 분배로 확인한다(조합 규칙 자체는 ComposerTests).
        for (keys, next, expected) in [("rks","k","가나"),("rk","s","간")] {
            let (c,h) = fresh(); typeKeys(keys,c,h)
            check(press(c,h,"'",code:39),"apostrophe_absorbed")
            check(press(c,h,"\u{7f}",code:51,deliver:false),"apostrophe_delete_absorbed")
            typeKeys(next,c,h)
            check(h.text == expected,"apostrophe_delete_reopens_syllable_\(keys)")
            result("apostrophe_delete_\(keys)",c,h)
        }
        do {
            let (c,h) = fresh()
            for _ in 0..<45 { typeKeys("rk",c,h) }
            while c.probeComposer.hasPendingComposition { _ = press(c,h,"\u{7f}",code:51,deliver:false) }
            typeKeys("apple",c,h); press(c,h," ",code:49)
            check(h.text.hasSuffix("apple "),"spill_deleted_next_word_converts")
            result("spill_deleted_next_word",c,h)
        }
    }
}

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
    var replacementReadSnapshot: String?
    func beginKeyEvent() { replacementReadSnapshot = nil }
    func insertText(_ value: Any!, replacementRange: NSRange) {
        if rejectReplacement && replacementRange.location != NSNotFound { return }
        if delayReplacementReadback && replacementRange.location != NSNotFound { replacementReadSnapshot = text }
        let string = (value as? NSAttributedString)?.string ?? (value as? String ?? "")
        let range = replacementRange.location != NSNotFound ? replacementRange : (marked.location != NSNotFound ? marked : selection)
        precondition(range.location != NSNotFound && NSMaxRange(range) <= (text as NSString).length)
        let trailing = preserveTrailingCaret && replacementRange.location != NSNotFound
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
        return reportMissingSelectionRange ? NSRange(location: NSNotFound, length: 0) : selection
    }
    func markedRange() -> NSRange { reportMissingMarkedRange ? NSRange(location: NSNotFound, length: 0) : marked }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        beforeSubstring?()
        let readable = replacementReadSnapshot ?? text
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
    static func check(_ value: Bool, _ id: String) { checks += 1; if !value { failures.append(id) } }
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
        scenarios.append(["id": id, "surfaceClass": classification,
            "pairPresent": c.probeComposer.lastConversion != nil,
            "origin": String(describing: c.probeComposer.lastConversionOrigin),
            "englishContextPresent": c.probeComposer.lastEnglishWord != nil,
            "slashActive": c.probeSlashActive])
    }
    static func main() {
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + EnglishDetector.bundledWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" })
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        check(PhoneticDictionary.bundled.english(for: "사과") == "apple", "bundled_dictionary_available")
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
            check(c.probeSlashActive,"slash_special_key_alone_keeps_session")
            h.active = 1
            c.commitComposition(h)
            check(!c.probeSlashActive,"slash_later_commit_always_ends_session")
            check(press(c,h,"h",code:4),"slash_after_special_key_other_field_is_korean")
            result("slash_\(label)_then_other_field_commit",c,h)
        }
        let output: [String:Any] = ["checks":checks,"failures":failures,"scenarioCount":scenarios.count,
            "scenarios":scenarios,"limits":"Controller method bodies with a synthetic IMK host. Physical input and OS timing still require separate validation."]
        let data = try! JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}

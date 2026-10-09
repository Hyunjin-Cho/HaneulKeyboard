import AppKit

// 2026-10-07 (#80): 실제 NSTextView에 조합 코어 출력을 보내는 회귀 검사.
// OS 키 이벤트/IMK 연결 실기 검사를 대신하지 않는다.
@MainActor private struct TextClient: @preconcurrency ComposerClient {
    let editor: OnboardingPracticeTextView
    func insertText(_ text: String) {
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func setMarkedText(_ text: String) {
        editor.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

@main @MainActor enum OnboardingPracticeTests {
    static func main() {
        _ = NSApplication.shared
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + EnglishDetector.bundledWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" })
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            checks += 1
        }
        let editor = OnboardingPracticeTextView(frame: NSRect(x: 0, y: 0, width: 636, height: 105))
        var observedStages: [OnboardingPracticeStage] = []
        editor.onProgressChange = { observedStages.append($0) }
        let client = TextClient(editor: editor)
        let composer = KoreanComposer()
        check(editor.showsPlaceholder, "빈 칸 안내")
        for (key, expected) in zip("apple", ["ㅁ", "메", "메ㅔ", "메ㅔㅣ", "메ㅔㅣㄷ"]) {
            _ = composer.handleInput(String(key), client: client)
            check(editor.string == expected, "조합 글자 누락: \(key): \(editor.string)")
            check(editor.hasMarkedText() && !editor.showsPlaceholder, "조합 중 안내 문구 겹침")
        }
        _ = composer.deleteBackward(client: client)
        check(editor.string == "메ㅔㅣ", "조합 중 Backspace")
        _ = composer.handleInput("e", client: client)
        composer.commit(to: client, convertEnglish: true)
        client.insertText(" ")
        check(editor.string == "apple ", "자동 변환 확정: \(editor.string.debugDescription)")
        check(!editor.hasMarkedText() && !editor.showsPlaceholder, "확정 후 표시")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        check(observedStages.last == .converted, "실제 조합→영문 치환 성공 안내: \(observedStages)")
        check(editor.string == "apple ", "안내 갱신이 실제 텍스트를 건드리지 않음")
        for target in ["메ㅔㅣㄷ", "apple", "메ㅔㅣㄷ", "apple"] {
            let currentLength = (editor.string as NSString).length - 1
            editor.insertText(target, replacementRange: NSRange(location: 0, length: currentLength))
            check(editor.string == target + " ", "수동 치환 시 글자 누락")
            check(editor.frame.width == 636 && editor.font?.pointSize == 23, "치환 시 입력칸 크기/폰트 변경")
        }
        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        check(editor.showsPlaceholder, "비우기 후 안내")
        let korean = KoreanComposer()
        for key in "gksrmf" { _ = korean.handleInput(String(key), client: client) }
        korean.commit(to: client)
        check(editor.string == "한글", "한국어 조합 확정")
        editor.insertText("\n붙여넣기", replacementRange: NSRange(location: NSNotFound, length: 0))
        check(editor.string == "한글\n붙여넣기", "줄바꿈/붙여넣기")
        let forced = KoreanComposer()
        forced.personalDictionary = PersonalDictionary(force: ["hola"], block: [])
        editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
        for key in "hola" { _ = forced.handleInput(String(key), client: client) }
        forced.commit(to: client, convertEnglish: true)
        check(editor.string == "hola", "개인 사전 예시 변환")

        // #82: 숫자와 소수점도 실제 NSTextView marked text에서 유실 없이 조합된다.
        for value in ["100ml", "1.5ml", "35mm", "100 ml", "10GB"] {
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
            let quantityComposer = KoreanComposer()
            for key in value {
                if AlphanumericWords.isDigit(key), quantityComposer.handleDigit(key, client: client) { continue }
                if key == ".", quantityComposer.handleQuantityPoint(client: client) { continue }
                if KeyboardLayout2Set.jamo(for: key) != nil {
                    _ = quantityComposer.handleInput(String(key), client: client)
                } else {
                    quantityComposer.commit(to: client, convertEnglish: true)
                    client.insertText(String(key))
                    quantityComposer.completeBoundary(key)
                }
            }
            quantityComposer.commit(to: client, convertEnglish: true)
            check(editor.string == value, "수량/단위 확정 유실: \(value): \(editor.string)")
            check(!editor.hasMarkedText(), "수량/단위 확정 뒤 조합 종료")
        }

        var progress = OnboardingPracticeProgress()
        check(progress.observe(text: "apple", hasMarkedText: false) == .english, "붙여넣기를 자동 변환 성공으로 오인하지 않음")
        check(progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: false) == .reverted, "실제 영어→한글 치환 안내")
        progress.reset()
        check(progress.stage == .empty, "명시적 초기화")
        check(progress.observe(text: "메", hasMarkedText: true) == .composing, "입력 중 안내")
        check(progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: true) == .readyToCommit, "Space 준비 안내")
        _ = progress.observe(text: "", hasMarkedText: false)
        check(progress.observe(text: "apple ", hasMarkedText: false) == .converted, "IME의 중간 비우기 후 영어 삽입")
        _ = progress.observe(text: "", hasMarkedText: false)
        progress.finishEditingBatch()
        check(progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: false) == .readyToCommit, "삭제 후 한글 붙여넣기를 되돌리기로 오인하지 않음")
        _ = progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: true)
        _ = progress.observe(text: "", hasMarkedText: false)
        progress.finishEditingBatch()
        check(progress.observe(text: "apple", hasMarkedText: false) == .english, "조합 삭제 후 영어 붙여넣기")
        _ = progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: true)
        _ = progress.observe(text: "메ㅔㅣ", hasMarkedText: true)
        check(progress.observe(text: "apple", hasMarkedText: false) == .english, "완성 전 Backspace 후 오인 방지")
        _ = progress.observe(text: "메ㅔㅣㄷ", hasMarkedText: true)
        check(progress.observe(text: "한글", hasMarkedText: false) == .other, "다른 단어의 성공 오인 방지")
        check(progress.observe(text: "apple", hasMarkedText: false) == .english, "다른 단어 뒤 이전 성공 증거 제거")
        // #84: 실제 NSTextView marked text를 발음 변환으로 확정하고 전체 범위로 왕복한다.
        let phonetic = try! PhoneticDictionary.load(data: Data(contentsOf:
            URL(fileURLWithPath: "Resources/IM/phonetic_dictionary.json")))
        for (hangul, english) in ["레스토랑": "restaurant", "맥스튜디오": "Mac Studio", "엔비디아": "NVIDIA",
                                   "축구": "football", "미식축구": "american football", "라이더": "rider",
                                   "시각효과": "VFX", "컬러그레이딩": "color grading", "파인튜닝": "fine-tuning",
                                   "선물": "gift", "선물거래": "futures trading"] {
            editor.string = "앞 "; editor.setSelectedRange(NSRange(location: 2, length: 0))
            let phoneticComposer = KoreanComposer()
            for key in ManualToggle.hangulToKeys(hangul)! {
                _ = phoneticComposer.handleInput(String(key), client: client)
            }
            check(editor.markedRange() == NSRange(location: 2, length: (hangul as NSString).length), "발음 marked 범위")
            check(editor.selectedRange().location == NSMaxRange(editor.markedRange()), "조합 끝 커서")
            check(phoneticComposer.commitPhonetic(to: client, dictionary: phonetic), "한 번의 발음 확정")
            check(editor.string == "앞 " + english && !editor.hasMarkedText(), "중복 없는 영문 교체")
            client.insertText(" ")
            for expected in [hangul, english, hangul] {
                let pair = phoneticComposer.lastConversion!
                let before = editor.string as NSString
                let result = KoreanComposer.resolveToggle(before: editor.string, english: pair.english,
                                                           hangul: pair.hangul, atDocStart: true)!
                editor.insertText(result.text, replacementRange: NSRange(
                    location: before.length - result.offsetFromEnd, length: result.replaceLen))
                phoneticComposer.applyToggle(toEnglish: expected == english, hangul: pair.hangul, english: pair.english)
                check(editor.string == "앞 " + expected + " ", "발음 왕복과 인접 공백 보존")
                check(!phoneticComposer.shouldRecordAutomaticRevert, "발음 왕복은 오변환 목록 제외")
            }
        }
        print("OnboardingPractice: \(checks) passed, 0 failed")
    }
}

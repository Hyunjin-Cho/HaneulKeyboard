import AppKit
import CryptoKit

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
        // #93: an empty commit owns no marked text and must preserve the host selection.
        for active in [false, true] {
            for selectedLength in [0, 8] {
                let untouched = OnboardingPracticeTextView(frame: .zero)
                let untouchedClient = TextClient(editor: untouched)
                untouched.string = "앞 😀 selected text"
                let selection = NSRange(location: ("앞 😀 " as NSString).length, length: selectedLength)
                untouched.setSelectedRange(selection)
                let empty = KoreanComposer()
                for _ in 0..<2 {
                    check(empty.commit(to: untouchedClient, convertEnglish: active).isEmpty, "빈 확정 반환값")
                    check(untouched.string == "앞 😀 selected text", "빈 확정은 선택한 글자를 보존")
                    check(untouched.selectedRange() == selection, "빈 확정은 UTF16 선택 범위를 보존")
                    check(!untouched.hasMarkedText(), "빈 확정은 새 조합을 만들지 않음")
                }
            }
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
        for value in ["bike", "camera", "water"] {
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0)); editor.resetProgress()
            let c = KoreanComposer()
            for key in value { _ = c.handleInput(String(key), client: client) }
            c.commit(to: client, convertEnglish: true)
            client.insertText(" ")
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            check(editor.string == value + " ", "추가 예시 실제 자동 변환: \(value)")
            check(observedStages.last == .converted, "apple 이외 단어도 성공 안내: \(value)")
        }
        editor.string = "apple "; editor.setSelectedRange(NSRange(location: 6, length: 0))
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

        // 혼합 문자열도 실제 NSTextView에서 조합 종료·UTF-16 범위 왕복을 보존한다.
        for (typed, expected) in [("githubdp", "github에"), ("APIsms", "API는"),
                                  ("APISMS", "API는"), ("APIDMF", "API을"),
                                  ("githubdptjqnxj", "github에서부터"),
                                  ("githubqkRdp", "github밖에"), ("githubQns", "github뿐"),
                                  ("githubfkeh", "github라도"), ("githubRkwlfkeh", "github까지라도"),
                                  ("T800dp", "T800에"), ("800Tsms", "800T는"),
                                  ("a24dptj", "a24에서"), ("a16zaks", "a16z만"), ("a7Rfh", "a7R로")] {
            let prefix = "앞말 😀 "
            let original = ManualToggle.keysToHangul(typed)!
            editor.string = prefix
            editor.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))
            let mixed = KoreanComposer()
            for key in typed {
                if AlphanumericWords.isDigit(key), mixed.handleDigit(key, client: client) { continue }
                _ = mixed.handleInput(String(key), client: client)
            }
            check(editor.string == prefix + expected, "혼합 입력 Space 전 미리보기")
            check(editor.hasMarkedText(), "혼합 입력 조합 상태")
            check(editor.markedRange() == NSRange(location: (prefix as NSString).length,
                  length: (expected as NSString).length), "혼합 미리보기 UTF16 범위")
            check(editor.selectedRange().location == NSMaxRange(editor.markedRange()), "미리보기 끝 커서")
            check(mixed.togglePendingParticlePreview(client: client), "미확정 원문 표시 토글")
            check(editor.string == prefix + original && editor.hasMarkedText(), "미확정 원문 전체 복원")
            check(mixed.togglePendingParticlePreview(client: client), "미확정 혼합 재표시 토글")
            check(editor.string == prefix + expected && editor.hasMarkedText(), "미확정 혼합 왕복과 이웃 보존")
            mixed.commit(to: client, convertEnglish: true)
            client.insertText(" ")
            check(editor.string == prefix + expected + " ", "혼합 확정과 이웃 보존")
            check(!editor.hasMarkedText(), "혼합 확정 뒤 marked text 종료")
            for replacement in [original, expected] {
                let before = editor.string as NSString
                let toggle = KoreanComposer.resolveToggle(before: editor.string, english: expected,
                                                          hangul: original, atDocStart: true)!
                editor.insertText(toggle.text, replacementRange: NSRange(
                    location: before.length - toggle.offsetFromEnd, length: toggle.replaceLen))
                mixed.applyToggle(toEnglish: replacement == expected, hangul: original, english: expected)
                check(editor.string == prefix + replacement + " ", "혼합 왕복과 이모지·공백 보존")
                check(mixed.lastEnglishWord == nil, "혼합 재토글 뒤 영어 문맥 없음")
            }
        }

        for active in [false, true] {
            editor.string = "앞 😀 "; editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            let live = KoreanComposer()
            for key in "githubdp" { _ = live.handleInput(String(key), client: client) }
            check(editor.string == "앞 😀 github에", "실제 클라이언트 확정 전 혼합 표시")
            if active { _ = live.togglePendingParticlePreview(client: client) }
            let shown = editor.string
            live.commit(to: client, convertEnglish: active)
            check(editor.string == shown && !editor.hasMarkedText(), "클릭 확정/원문 선택 Space는 표시 그대로")
        }
        editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
        let erasedPreview = KoreanComposer()
        for key in "githubdp" { _ = erasedPreview.handleInput(String(key), client: client) }
        _ = erasedPreview.togglePendingParticlePreview(client: client)
        var eraseCount = 0
        while erasedPreview.hasPendingComposition && eraseCount < 30 {
            _ = erasedPreview.deleteBackward(client: client); eraseCount += 1
        }
        check(editor.string.isEmpty && !editor.hasMarkedText(), "전체 삭제 뒤 실제 조합 범위 비움")
        for key in "githubdp" { _ = erasedPreview.handleInput(String(key), client: client) }
        check(editor.string == "github에" && editor.hasMarkedText(), "전체 삭제 뒤 새 혼합 미리보기")
        erasedPreview.commit(to: client, convertEnglish: true)
        check(editor.string == "github에" && !editor.hasMarkedText(), "새 혼합 확정도 정상")
        var progress = OnboardingPracticeProgress()
        check(progress.observe(text: "apple", hasMarkedText: false) == .english, "붙여넣기를 자동 변환 성공으로 오인하지 않음")
        check(progress.observe(text: "apple ", hasMarkedText: false) == .english, "직접 영어 뒤 Space도 자동 변환 성공으로 오인하지 않음")
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
        var phoneticProgress = OnboardingPracticeProgress(dictionary: phonetic)
        _ = phoneticProgress.observe(text: "바나나", hasMarkedText: true)
        check(phoneticProgress.observe(text: "banana", hasMarkedText: false) == .converted, "등록 한글→영어 연습 안내")
        check(phoneticProgress.observe(text: "바나나", hasMarkedText: false) == .reverted, "등록 한글 원문으로 되돌린 안내")
        var sentenceProgress = OnboardingPracticeProgress(dictionary: phonetic)
        _ = sentenceProgress.observe(text: "한글 ㅠㅑㅏㄷ", hasMarkedText: true, markedRange: NSRange(location: 3, length: 4))
        check(sentenceProgress.observe(text: "한글 bike ", hasMarkedText: false) == .converted, "앞의 한글 문장과 새 단어의 조합 범위 구분")
        for (hangul, english) in ["레스토랑": "restaurant", "맥스튜디오": "Mac Studio", "엔비디아": "NVIDIA",
                                   "축구": "football", "미식축구": "american football", "라이더": "rider",
                                   "시각효과": "VFX", "컬러그레이딩": "color grading", "파인튜닝": "fine-tuning",
                                   "선물": "gift", "선물거래": "futures trading",
                                   "단어": "word", "물": "water", "의자": "chair",
                                   "빗방울": "raindrop", "세탁기": "washing machine", "고양이": "cat",
                                   "학교": "school", "식당": "restaurant", "주방": "kitchen", "견적서": "quotation"] {
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
        // 새 명사와 공백 포함 출력을 실제 NSTextView의 NFD 원문 범위로 왕복한다.
        for original in ["단어", "물", "세탁기", "옷걸이", "학교", "식당", "주방", "견적서"] {
            let rawOriginal = original.decomposedStringWithCanonicalMapping
            let initial = "앞 " + rawOriginal + " "
            editor.string = initial
            editor.setSelectedRange(NSRange(location: (initial as NSString).length, length: 0))
            let target = KoreanComposer.wordBeforeCursor(before: initial, atDocStart: true)!
            check(target.word.utf16.elementsEqual(rawOriginal.utf16), "NFD 단어의 실제 원문 유지")
            let result = ManualToggle.resolve(word: target.word, phoneticEnabled: true,
                                             keyboardEnabled: false, dictionary: phonetic)!
            let before = initial as NSString
            editor.insertText(result.text, replacementRange: NSRange(
                location: before.length - target.trailing - (target.word as NSString).length,
                length: (target.word as NSString).length))
            check(editor.string == "앞 " + result.text + " ", "NFD 명사 영문 교체와 이웃 보존")
            let conversion = KoreanComposer()
            conversion.applyToggle(toEnglish: true, hangul: target.word, english: result.text, origin: .phonetic)
            let undo = KoreanComposer.resolveToggle(before: editor.string, english: result.text,
                                                     hangul: target.word, atDocStart: true)!
            editor.insertText(undo.text, replacementRange: NSRange(
                location: (editor.string as NSString).length - undo.offsetFromEnd, length: undo.replaceLen))
            check(editor.string.utf16.elementsEqual(initial.utf16), "NFD 명사 Undo는 UTF16 원문 그대로 복원")
            check(!conversion.shouldRecordAutomaticRevert && conversion.lastEnglishWord == nil,
                  "NFD 명사 수동 변환은 자동 기록·영어 문맥 없음")
        }
        checkNavigation(check)
        checkArtwork(check)
        print("OnboardingPractice: \(checks) passed, 0 failed")
    }

    private static func checkArtwork(_ check: (Bool, String) -> Void) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Onboarding")
        let manifest = try! JSONSerialization.jsonObject(with:
            Data(contentsOf: root.appendingPathComponent("HaneulApprovedPoses.json"))) as! [String: Any]
        let pages = manifest["pages"] as! [[String: Any]]
        check(pages.count == 7 && OnboardingPeopleArtwork.pageCount == 7, "승인 자세는 안내7페이지와 일치")
        var renderedSignatures = [Set<String>](repeating: [], count: 3)
        func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        for page in 0..<7 {
            let figures = pages[page]["figures"] as! [[String: String]]
            let expectedNames = figures.map { $0["resourceName"]! }
            var requested: [String] = []
            let people = OnboardingPeopleArtwork.people(page: page) { name in
                requested.append(name)
                return root.appendingPathComponent(name + ".png")
            }
            check(requested == expectedNames, "페이지\(page + 1)는 사용자 지정 순서의 세 인물을 요청")
            check(people.count == 3, "페이지\(page + 1)의 그림3장 모두 실제 PNG로 읽기")
            for person in 0..<3 {
                let source = try! Data(contentsOf: root.appendingPathComponent(expectedNames[person] + ".png"))
                check(hash(source) == figures[person]["sha256"], "승인 PNG 바이트 보존: \(expectedNames[person])")
                let cg = people[person].cgImage(forProposedRect: nil, context: nil, hints: nil)!
                check(cg.width == 512 && cg.height == 512, "공통 정사각형 렌더 캔버스")
                let data = cg.dataProvider!.data! as Data
                let pixels = [UInt8](data)
                check(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }, "인물이 비어 있지 않음")
                let edges = (0..<512).allSatisfy { i in
                    pixels[i * 4 + 3] == 0 && pixels[511 * cg.bytesPerRow + i * 4 + 3] == 0 &&
                    pixels[i * cg.bytesPerRow + 3] == 0 && pixels[i * cg.bytesPerRow + 511 * 4 + 3] == 0
                }
                check(edges, "팔·치마·신발을 자르지 않는 공통 투명 여백")
                renderedSignatures[person].insert(hash(data))
            }
        }
        for signatures in renderedSignatures {
            check(signatures.count == 7, "각 인물은 모든 페이지에서 다른 승인 그림을 렌더")
        }
        let first = (pages[0]["figures"] as! [[String: String]]).map { $0["resourceName"]! }
        let last = (pages[6]["figures"] as! [[String: String]]).map { $0["resourceName"]! }
        check(OnboardingPeopleArtwork.resourceNames(for: Int.min) == first, "첫 페이지 이전은 첫 그림")
        check(OnboardingPeopleArtwork.resourceNames(for: Int.max) == last, "마지막 페이지 이후는 마지막 그림")
        let missing = OnboardingPeopleArtwork.people(page: 3) { name in
            name == "HaneulPoseBraid04" ? nil : root.appendingPathComponent(name + ".png")
        }
        check(missing.isEmpty, "세 그림 중 하나가 누락되면 잘못된 부분 집합을 표시하지 않음")
        let invalid = OnboardingPeopleArtwork.people(page: 0) { _ in
            root.appendingPathComponent("missing-image.png")
        }
        check(invalid.isEmpty, "이미지를 읽지 못해도 충돌 없이 처리")
    }

    private static func checkNavigation(_ check: (Bool, String) -> Void) {
        // 2026-10-20: invoke the production event handler with offscreen windows.
        // This tests focus/routing without posting keys or selecting an input source.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled],
                                   backing: .buffered, defer: false)
        let navigation = OnboardingPageNavigation.NavigationView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(navigation)
        defer { navigation.stop() }
        var moves: [Int] = []
        navigation.move = { moves.append($0) }
        func event(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = [],
                   repeatKey: Bool = false, target: NSWindow? = nil,
                   type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: (target ?? window).windowNumber, context: nil,
                             characters: "", charactersIgnoringModifiers: "",
                             isARepeat: repeatKey, keyCode: keyCode)!
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            navigation.handle(event, applicationIsActive: true, keyWindow: window)
        }
        let left = event(123), right = event(124)
        check(!window.isVisible && !otherWindow.isVisible, "방향키 검사는 창을 표시하지 않음")
        check(handle(left) == nil && moves == [-1], "활성 안내창 왼쪽 키는 한 단계 이전")
        check(handle(right) == nil && moves == [-1, 1], "활성 안내창 오른쪽 키는 한 단계 다음")
        let beforeRepeat = moves
        check(handle(event(124, repeatKey: true)) == nil && moves == beforeRepeat,
              "방향키를 계속 누른 반복 이벤트는 여러 페이지를 넘기지 않음")
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            let modified = event(124, flags: flags)
            check(handle(modified) === modified && moves == beforeRepeat, "조합 방향키는 앱의 기본 동작에 전달")
        }
        for keyCode: UInt16 in [0, 36, 125, 126] {
            let otherKey = event(keyCode)
            check(handle(otherKey) === otherKey && moves == beforeRepeat, "좌우 이외 키는 가로채지 않음")
        }
        let keyUp = event(124, type: .keyUp)
        check(handle(keyUp) === keyUp && moves == beforeRepeat, "키를 뗀 이벤트는 넘기지 않음")
        check(navigation.handle(right, applicationIsActive: false, keyWindow: window) === right,
              "비활성 앱은 안내 방향키를 가로채지 않음")
        check(navigation.handle(right, applicationIsActive: true, keyWindow: otherWindow) === right,
              "다른 창이 활성일 때 안내창은 방향키를 가로채지 않음")
        check(navigation.handle(right, applicationIsActive: true, keyWindow: nil) === right,
              "활성 창이 없으면 방향키를 가로채지 않음")
        let otherEvent = event(124, target: otherWindow)
        check(handle(otherEvent) === otherEvent && moves == beforeRepeat, "다른 창의 이벤트를 가로채지 않음")
        check(handle(event(124, flags: [.function, .numericPad, .capsLock])) == nil,
              "일반 화살표의 function/numericPad 및 Caps Lock 상태 허용")

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        navigation.addSubview(text)
        text.string = "연습"
        text.setSelectedRange(NSRange(location: 1, length: 0))
        check(window.makeFirstResponder(text) && window.firstResponder === text, "편집 칸에 포커스")
        let beforeEditing = moves
        check(handle(left) === left && handle(right) === right && moves == beforeEditing,
              "편집 가능한 입력칸에서는 좌우 커서 이동 보호")
        check(text.string == "연습" && text.selectedRange() == NSRange(location: 1, length: 0),
              "방향키 모니터가 입력 내용과 선택 위치를 바꾸지 않음")
        text.setMarkedText("가", selectedRange: NSRange(location: 1, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        check(handle(right) === right && text.hasMarkedText() && moves == beforeEditing,
              "한글 조합 중 방향키도 입력칸에 전달")
        text.unmarkText()
        text.isEditable = false
        check(window.firstResponder === text, "읽기 전용이어도 NSText 포커스는 남을 수 있음")
        check(handle(left) == nil && moves.last == -1 && moves.count == beforeEditing.count + 1,
              "읽기 전용 텍스트를 선택한 뒤에도 이전 페이지 이동")
        check(handle(right) == nil && moves.last == 1 && moves.count == beforeEditing.count + 2,
              "읽기 전용 텍스트를 선택한 뒤에도 다음 페이지 이동")
        text.isEditable = true
        _ = window.makeFirstResponder(text)
        text.isHidden = true
        check(handle(right) == nil, "숨겨진 입력칸은 페이지 이동을 막지 않음")
        text.isHidden = false
        _ = window.makeFirstResponder(text)
        text.removeFromSuperview()
        check(handle(left) == nil, "제거된 입력칸은 페이지 이동을 막지 않음")
        let beforeDetach = moves
        navigation.removeFromSuperview()
        check(handle(right) === right && moves == beforeDetach, "안내창에서 분리된 모니터는 이벤트를 가로채지 않음")
    }
}

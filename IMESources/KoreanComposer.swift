import Foundation

/// Abstraction over the IMK client so the composer stays testable without
/// InputMethodKit (HaneulInputController wraps IMKTextInput in an adapter).
protocol ComposerClient {
    /// Insert finalized text at the cursor (replaces any marked text).
    func insertText(_ text: String)
    /// Show composition-in-progress text, cursor pinned at the end.
    /// An empty string clears the marked text.
    func setMarkedText(_ text: String)
}

/// Stateful Hangul word composer driven by 2-set jamo input.
///
/// Completed syllables accumulate into a word-level buffer (shown as marked
/// text) instead of committing eagerly. The whole word commits at a boundary:
/// space/punctuation/digit, modifier shortcut, focus change, or deactivate.
/// At that point, if the composed word is broken as Korean and the raw
/// keystrokes form a known English word (e.g. 메ㅔㅣㄷ ← "apple"), the
/// original keystrokes are committed instead — see EnglishDetector.
final class KoreanComposer {
    /// Gates the English auto-correction at word commit. The word-level
    /// buffering itself is always on.
    var autoEnglishEnabled = true

    /// 2026-09-21 (#53): 개인 사전(변환 추가·변환 금지). 컨트롤러가 활성 경계마다
    /// defaults에서 읽어 넘긴다(`autoEnglishEnabled`와 같은 시점). 판정 합성은
    /// `shouldConvertWord` 한 곳에서만 한다.
    var personalDictionary = PersonalDictionary.empty

    /// The most recent commit, when it was English (lowercased; nil = the
    /// last commit was Korean or context was reset). Feeds EnglishDetector's
    /// context rules — the WORD itself matters now (whitelistTriggers:
    /// "want"+새→to fires, "github"+새 stays Korean). The controller resets
    /// it on boundaries that end the English run.
    private(set) var lastEnglishWord: String?

    /// 직전에 영어로 변환된 단어 — (변환 전 한글, 변환 후 영어). shift+space로
    /// 영어↔한글을 토글할 때 쓴다(㉠ 직후만). 다음 입력(자모/백스페이스)이
    /// 들어오면 nil로 리셋 = "변환 직후, 다음 글자 치기 전"에만 유효.
    private(set) var lastConversion: (hangul: String, english: String)?

    var lastCommitWasEnglish: Bool { lastEnglishWord != nil }

    func resetEnglishContext() {
        lastEnglishWord = nil
        // (H1) 커서 이동이 동반되는 경계(클릭·포커스이동·단축키·화살표·마침표·
        // 엔터)에서 이 메서드가 호출된다 — 그때 lastConversion도 함께 비워
        // stale 상태로 엉뚱한 위치를 교체하는 사고를 막는다. 스페이스·쉼표
        // 경계는 resetEnglishContext를 부르지 않으므로 되돌리기는 유지된다.
        lastConversion = nil
    }

    /// (M-01) shift+space 토글이 화면 텍스트를 영어↔한글로 바꾼 뒤, 내부 영어
    /// 문맥도 화면과 일치시킨다. resolveToggle은 화면만 교체하므로 이걸 호출하지
    /// 않으면 화면은 한글인데 lastEnglishWord는 영어로 남아 다음 단어가 잘못
    /// 변환된다(예: "want "→"ㅈ무ㅅ " 되돌린 뒤 "to "의 새가 다시 to로 변환).
    /// lastConversion은 (hangul, english)를 그대로 유지해 연속 토글을 가능케 한다.
    /// - toEnglish: 토글 결과가 영어면 true(영어 문맥 복원), 한글이면 false(끊김).
    func applyToggle(toEnglish: Bool, hangul: String, english: String) {
        lastEnglishWord = toEnglish ? english.lowercased() : nil
        lastConversion = (hangul: hangul, english: english)
    }

    /// (M1) shift+space 되돌리기의 순수 매칭 로직 — IMKTextInput 비의존이라
    /// 단위테스트 가능. 커서 직전 텍스트(before)에서 trailing boundary를
    /// 건너뛰고 english/hangul을 "좌측이 단어경계"인 위치에서만 매칭해, 교체할
    /// (text, 교체길이, 커서에서 거슬러 갈 거리)를 돌려준다. 매칭 실패·불안전
    /// (brand의 끝 and 등)이면 nil. atDocStart=before의 시작(읽기 시작점)이
    /// 문서 맨 앞인지 — 아니면 읽기 경계에 붙은 단어는 좌측을 알 수 없어 nil.
    static func resolveToggle(before: String, english: String, hangul: String,
                              atDocStart: Bool) -> (text: String, replaceLen: Int, offsetFromEnd: Int)? {
        let s = before as NSString
        func isWordChar(_ c: unichar) -> Bool {
            (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A)
                || (c >= 0xAC00 && c <= 0xD7A3)   // 완성형 음절 가–힣
                || (c >= 0x3130 && c <= 0x318F)   // 호환 낱자모 ㄱ–ㅣ — hangul이
                                                  // "메ㅔㅣㄷ"(apple)처럼 낱자모로
                                                  // 끝나도 trailing이 먹지 않게.
        }
        var end = s.length
        while end > 0, !isWordChar(s.character(at: end - 1)) { end -= 1 }
        let trailing = s.length - end
        func leftIsBoundary(_ matchLen: Int) -> Bool {
            let i = end - matchLen
            if i <= 0 { return atDocStart }
            return !isWordChar(s.character(at: i - 1))
        }
        let eng = english as NSString
        let han = hangul as NSString
        if end >= eng.length, leftIsBoundary(eng.length),
           s.substring(with: NSRange(location: end - eng.length, length: eng.length)) == english {
            return (hangul, eng.length, eng.length + trailing)
        }
        if end >= han.length, leftIsBoundary(han.length),
           s.substring(with: NSRange(location: end - han.length, length: han.length)) == hangul {
            return (english, han.length, han.length + trailing)
        }
        return nil
    }

    /// (T1) 되돌리기를 아예 지원할 수 없는 클라이언트인지 — IMK 비의존 순수함수.
    ///
    /// 직전에 영타 변환이 일어났다면 커서 앞에는 그 글자가 반드시 있다. 그런데도
    /// 커서를 "문서 맨 앞"(0)이라 답하거나 커서 앞 텍스트를 아예 못 읽어주는
    /// 클라이언트가 있다(Ghostty 등 일부 터미널: `selectedRange`가 항상 0,
    /// `attributedSubstring`이 nil). 터미널에 입력된 글자는 즉시 셸 프로세스
    /// 소유가 되어 앱조차 회수할 수단이 없기 때문으로, 이런 앱에서 되돌리기는
    /// 원리적으로 불가능하다 — 시도조차 하지 않는다(#30).
    /// - cursorLocation: `selectedRange().location`
    /// - didReadText: `attributedSubstring`이 nil 아닌 값을 돌려줬는지
    static func toggleUnsupported(cursorLocation: Int, didReadText: Bool) -> Bool {
        cursorLocation == 0 || !didReadText
    }

    /// (T2) 교체 요청이 클라이언트에 실제로 반영됐는지 — IMK 비의존 순수함수.
    ///
    /// Terminal.app은 읽기 API에는 정상 응답하면서 `insertText(_:replacementRange:)`의
    /// 범위 교체는 조용히 무시한다(실측: 9번 눌러도 커서가 80에서 불변). 그런데도
    /// 성공으로 믿고 키를 소비하면 되돌리기도 안 되고 스페이스까지 사라진다.
    /// 교체 자리에 옛 글자가 **그대로** 남아 있는 것이 확인될 때만 거부로 판정하고,
    /// 읽기가 안 되면(nil) 판정 불가로 보아 false를 돌려준다 — 정상 앱 회귀 방지(#30).
    /// - textAtReplacement: 교체 직후 그 자리에서 다시 읽은 텍스트(못 읽으면 nil)
    /// - previousText: 교체 전 그 자리에 있던 글자
    static func toggleWasRejected(textAtReplacement: String?, previousText: String) -> Bool {
        textAtReplacement == previousText
    }

    private var buffer = SyllableBuffer()
    /// Completed units (syllables or standalone jamo) of the current word,
    /// each paired with the keystrokes that produced it.
    private var word: [(text: String, keys: [Character])] = []
    /// Keystrokes that produced the current in-flight syllable buffer.
    private var pendingKeys: [Character] = []

    /// Safety cap — a run this long without a boundary is not a word. Spill
    /// it as Hangul rather than growing the marked text without bound.
    private let maxWordUnits = 40

    func handleInput(_ input: String, client: ComposerClient) -> Bool {
        guard let scalar = input.unicodeScalars.first else { return false }
        let character = Character(scalar)
        lastConversion = nil // 새 글자 입력 = 되돌리기 기회 끝

        guard let jamo = KeyboardLayout2Set.jamo(for: character) else {
            commit(to: client, convertEnglish: true)
            return false
        }

        switch jamo {
        case .consonant(let c):
            appendConsonant(c)
        case .vowel(let v):
            appendVowel(v)
        }
        pendingKeys.append(character)

        if word.count >= maxWordUnits {
            let hangul = wordText()
            if !hangul.isEmpty { client.insertText(hangul) }
            word = []
            lastEnglishWord = nil // spill emits Hangul — breaks English context
        }

        refreshMarkedText(client: client)
        return true
    }

    /// 2026-09-19 (#34): 단어에 끼워 넣은 아포스트로피 유닛의 위치 (없으면 nil).
    /// 상태 플래그가 아니라 `word`에서 매번 유도하므로, Backspace로 `'` 유닛을
    /// 지우면 "아직 `'`가 없는 단어"로 자동 복귀한다.
    private var apostropheIndex: Int? {
        word.firstIndex { $0.keys.count == 1 && Contractions.isApostrophe($0.keys[0]) }
    }

    /// 2026-09-19 (#34): 조합 중에 들어온 `'`를 **경계가 아니라 단어 내부 문자**로
    /// 흡수한다. 자모가 아니므로 text·keys 모두 친 글자 그대로인 유닛을 붙여
    /// marked text에 보이게 하고, 커밋 때 `i'm`·`don't`를 통째로 변환할 수
    /// 있게 한다. (예전엔 `'`가 active boundary라 `ㅑ`만 `i`로 변환되고 `m`은
    /// `ㅡ` 한 글자로 남아 화면에 `i'ㅡ`가 됐다.)
    ///
    /// 흡수하지 않는 경우(false를 돌려 컨트롤러의 기존 경계 처리로 넘긴다):
    ///   - 단어가 비어 있을 때 → 여는 따옴표다 (`'안녕`)
    ///   - 이미 `'`가 하나 있을 때 → 두 번째 `'`는 경계로 본다 (단순화)
    /// - Returns: 키를 소비했으면 true.
    func handleApostrophe(_ character: Character, client: ComposerClient) -> Bool {
        guard Contractions.isApostrophe(character) else { return false }
        guard !word.isEmpty || !buffer.isEmpty else { return false }
        guard apostropheIndex == nil else { return false }
        lastConversion = nil // 새 글자 입력 = 되돌리기 기회 끝 (handleInput과 동일)
        stashBuffer()
        word.append((text: String(character), keys: [character]))
        refreshMarkedText(client: client)
        return true
    }

    /// Word boundary: commit the buffered word once. Returns the text that
    /// was actually inserted (tests assert on this to verify exactly what
    /// got committed).
    ///
    /// `convertEnglish` is true only for ACTIVE boundaries — a space,
    /// punctuation, digit, or Enter the user actually typed. Passive
    /// boundaries (focus change, mouse click, input-source switch, modifier
    /// shortcuts) must commit exactly the marked text the user saw on
    /// screen, never something different.
    @discardableResult
    func commit(to client: ComposerClient, convertEnglish: Bool = false) -> String {
        stashBuffer()
        defer { word = [] }

        let hangul = wordText()
        guard !hangul.isEmpty else {
            client.setMarkedText("")
            return ""
        }

        let committed: String
        let keys = word.flatMap(\.keys)
        let units = word.map(\.text)
        // Conversion may only fire when EVERY unit carries the keys that
        // produced it — an accepted suggestion's units have empty keys, and
        // converting then would commit text that differs from (and drops
        // part of) the marked text the user saw.
        let convertible = convertEnglish && autoEnglishEnabled
            && word.allSatisfy { !$0.keys.isEmpty }
        if let apostrophe = apostropheIndex {
            // 2026-09-19 (#34): `'`를 품은 단어는 축약형 경로로 판정한다.
            committed = commitTextWithApostrophe(
                at: apostrophe, convertible: convertible, hangul: hangul)
        } else if convertible, shouldConvertWord(units: units, keys: keys) {
            committed = String(keys)
        } else {
            committed = hangul
        }
        // English context chains through every CONVERTED word ("that was
        // great" — was must arm great), EXCEPT clean-Hangul whitelist hits
        // (새→to): those exist only because of context and must not start
        // chains of their own (a run of 새/무 homographs would otherwise
        // cascade). Korean commits always break the run.
        // 2026-09-19 (#34): 축약형(i'm)은 `'`를 품고도 "영어로 커밋됐다".
        // 아포스트로피를 허용하지 않으면 lastEnglishWord/lastConversion이
        // nil이 되어 뒤 단어의 문맥 변환도, shift+space 되돌리기도 끊긴다.
        // 글자가 하나도 없는 `'` 단독은 영어로 치지 않는다.
        let isAscii = committed.contains { $0.isASCII && $0.isLetter }
            && committed.allSatisfy {
                ($0.isASCII && $0.isLetter) || Contractions.isApostrophe($0)
            }
        if isAscii {
            // 2026-09-20 (#44, 리뷰 F-6): 문맥 단어는 사전 조회와 같은 정규화를 거친다 —
            // 곱은 아포스트로피(U+2019)를 `'`로 통일해야 `don’t` 뒤의 해(go)가
            // goDoTriggers(직선 따옴표만)와 맞는다. 화면에 넣는 committed·lastConversion은
            // 친 글자 그대로 유지한다. 아포스트로피가 없는 단어는 종전 소문자화와 동일.
            let wordLower = Contractions.normalizedKey(keys)
            let cleanHangul = !units.contains { unit in
                unit.unicodeScalars.contains { (0x3131...0x3163).contains($0.value) }
            }
            // whitelistOnly = clean homograph(새→to 등)는 다음 단어에 영어 문맥을
            // 넘기지 않는다(체이닝 방지). 단 (H2) goDoTriggers 멤버(to 등)는 예외 —
            // "to go"의 go가 문맥을 받아 변환되게 한다(사용자 결정). 다음 단어가
            // 한국어면 어차피 변환 안 되므로 안전.
            let whitelistOnly = EnglishDetector.shortWords.contains(wordLower) && cleanHangul
                && !EnglishDetector.goDoTriggers.contains(wordLower)
            // 2026-09-19 (#34): `'`로 **끝나는** 커밋(`apple'`)은 닫는 따옴표일 가능성이
            // 복수 소유격(students')보다 훨씬 높다 — `'apple' 내 생각`에서 `내`가 so로
            // 오변환되지 않게 문맥을 끊는다(`'`가 경계였던 예전과 같은 동작).
            let endsWithApostrophe = committed.last.map(Contractions.isApostrophe) ?? false
            lastEnglishWord = (whitelistOnly || endsWithApostrophe) ? nil : wordLower
            // 방금 영어로 변환됨 — shift+space 즉시 되돌리기용(㉠ 직후만).
            lastConversion = (hangul: hangul, english: committed)
        } else {
            lastEnglishWord = nil
            lastConversion = nil
        }
        client.insertText(committed)
        client.setMarkedText("")
        return committed
    }

    /// 2026-09-19 (#34): `'`를 품은 단어의 커밋 텍스트를 만든다.
    ///
    /// (a) 축약형 소사전 정확 일치(i'm·don't·o'clock) → 통째로 영어.
    /// (b) base가 **기존 규칙 그대로** 변환되고 `'` 뒤가 허용 접미(s·d·m·t·
    ///     re·ve·ll·빈 문자열)면 → 통째로 영어 (apple's, `ㅑ'` → `i'`).
    /// (c) 그 외 → `'` 앞에서 끊어 base만 base 규칙대로(변환 or 한글 유지),
    ///     `'`와 뒤 조각은 친 그대로. 뒤가 자모면 `'`가 경계였던 예전과 같은
    ///     결과라 회귀가 없다 (`안녕'하세요` → `안녕'하세요`).
    private func commitTextWithApostrophe(
        at index: Int, convertible: Bool, hangul: String
    ) -> String {
        // (H-10과 같은 fail-closed) 한국어 veto 사전이 정상이 아니면 자동변환을
        // 전부 끈다 — 축약형만 예외로 살려 두면 "사전이 깨지면 변환하지 않는다"는
        // 단일 불변식이 조용히 무너진다.
        guard convertible, KoreanDictionary.isLoaded else { return hangul }

        let keys = word.flatMap(\.keys)
        // 2026-09-21 (#53): 통째 판정을 소사전보다 먼저 — `don't`(또는 그 한글형 애ㅜ'ㅅ)를
        // 금지했으면 축약형 소사전에 있어도 한글로 남기고, `y'know`처럼 추가했으면 소사전에
        // 없어도 통째로 변환한다. block이 force보다 먼저인 이유는 shouldConvertWord와 같다.
        switch personalDictionary.decision(word: Contractions.normalizedKey(keys), hangul: hangul) {
        case .block: return hangul
        case .forceConvert: return String(keys)
        case nil: break
        }
        if Contractions.matchesDictionary(keys) { return String(keys) }

        // base만 떼어 기존 판정에 그대로 묻는다 — 축약형 전용 규칙을 새로 만들지
        // 않고 이미 검증된 EnglishDetector를 재사용한다(오변환 채널 최소화).
        // 2026-09-21 (#53): base 판정도 일반 경로와 같은 합성(shouldConvertWord)을 거친다 —
        // apple을 금지했으면 apple's도 한글, vismo를 추가했으면 vismo's도 영어. base의
        // 한글 표기(`'` 앞부분)로도 금지가 걸리므로 메ㅔㅣㄷ 금지가 메ㅔㅣㄷ'ㄴ까지 막는다.
        let base = Array(word[..<index])
        let baseConverts = shouldConvertWord(units: base.map(\.text), keys: base.flatMap(\.keys))
        if baseConverts, Contractions.hasAllowedSuffix(keys) { return String(keys) }

        let baseText = baseConverts
            ? String(base.flatMap(\.keys))
            : base.map(\.text).joined()
        let tail = word[(index + 1)...].map(\.text).joined()
        return baseText + word[index].text + tail
    }

    /// 2026-09-21 (#53): `EnglishDetector.shouldConvert`에 개인 사전 판정을 합성한다.
    /// `shouldConvert`를 부르던 두 곳(일반 경로·축약형의 base 경로)이 모두 여기를 거친다 —
    /// 합성 규칙이 한 곳에만 있어야 두 경로가 갈라지지 않는다.
    ///
    /// 순서 = block → force → EnglishDetector.
    ///   - **block이 맨 앞**: "절대 변환하지 않는다"는 약속은 같은 단어를 양쪽에 넣는 실수에도
    ///     지켜져야 한다(안 바뀌는 쪽이 항상 안전한 실패). 영어 키열과 한글 표기 둘 다 대조.
    ///   - **force가 EnglishDetector보다 앞**: 사전 등급·구조 룰(ㅋㅋㅋ 가드 포함)·우리말샘
    ///     veto 전부를 건너뛰는 것이 명세다(사용자 명시 > 사전). "친 키가 그 단어를 이루어야
    ///     한다"는 조건은 별도 검사가 필요 없다 — `word`가 실제 키열에서 만들어지므로 다른 키로
    ///     친 우연한 한글이 강제 변환될 수는 없다.
    ///   - **남기는 관문은 둘뿐**: ① 호출자의 `convertible`(활성 경계 + 자동 변환 켜짐 —
    ///     passive 경계는 화면 그대로 커밋해야 하고 마스터 스위치는 개인 사전보다 위다),
    ///     ② `KoreanDictionary.isLoaded` fail-closed(H-10). "veto 사전이 깨지면 자동변환을
    ///     전부 끈다"는 단일 불변식이라(commitTextWithApostrophe 참조) force도 예외로 두지
    ///     않는다 — 사용자 입장에서도 "기능이 통째로 꺼진 상태"와 일치한다.
    private func shouldConvertWord(units: [String], keys: [Character]) -> Bool {
        switch personalDictionary.decision(
            word: Contractions.normalizedKey(keys), hangul: units.joined()
        ) {
        case .block:
            return false
        case .forceConvert:
            return KoreanDictionary.isLoaded
        case nil:
            return EnglishDetector.shouldConvert(
                units: units, keys: keys, previousEnglishWord: lastEnglishWord)
        }
    }

    /// Peels one jamo from the in-flight syllable, or one whole unit from the
    /// word buffer. Returns true if the composer absorbed the backspace;
    /// false means everything was empty and the system should perform a
    /// normal delete on the text behind the cursor.
    func deleteBackward(client: ComposerClient) -> Bool {
        lastConversion = nil // 백스페이스 = 되돌리기 기회 끝
        if !buffer.isEmpty {
            peelJamo()
            if !pendingKeys.isEmpty { pendingKeys.removeLast() }
            refreshMarkedText(client: client)
            return true
        }

        if !word.isEmpty {
            word.removeLast()
            refreshMarkedText(client: client)
            return true
        }

        return false
    }

    // MARK: - State transitions

    private func appendConsonant(_ c: Consonant) {
        if buffer.medial == nil {
            if buffer.initial != nil {
                stashBuffer()
            }
            buffer.initial = c
            return
        }

        // Bare vowel (no initial) followed by a consonant — e.g. English
        // typed in the wrong layout. Start a new unit; attaching the
        // consonant as a final would silently drop it, since a syllable
        // block can't assemble without an initial.
        if buffer.initial == nil {
            stashBuffer()
            buffer.initial = c
            return
        }

        if buffer.final == nil {
            if c.finalIndex != nil {
                buffer.final = .single(c)
            } else {
                stashBuffer()
                buffer.initial = c
            }
            return
        }

        if case let .single(prev) = buffer.final,
           CompoundFinal.index(first: prev, second: c) != nil {
            buffer.final = .compound(first: prev, second: c)
            return
        }

        stashBuffer()
        buffer.initial = c
    }

    private func appendVowel(_ v: Vowel) {
        if let final = buffer.final {
            // 도깨비불: the final consonant carries into the next syllable.
            // Its key is always the most recent one in pendingKeys.
            let (committedFinal, carry) = splitFinal(final)
            let committed = SyllableBuffer(
                initial: buffer.initial,
                medial: buffer.medial,
                final: committedFinal
            )
            let carryKey = pendingKeys.last
            stash(committed, keys: Array(pendingKeys.dropLast()))
            buffer = SyllableBuffer(initial: carry, medial: v, final: nil)
            pendingKeys = carryKey.map { [$0] } ?? []
            return
        }

        if let existing = buffer.medial {
            if let combined = Vowel.combine(existing, v) {
                buffer.medial = combined
            } else {
                stashBuffer()
                buffer.medial = v
            }
            return
        }

        buffer.medial = v
    }

    private func splitFinal(_ final: SyllableBuffer.Final) -> (commit: SyllableBuffer.Final?, carry: Consonant) {
        switch final {
        case .single(let c):
            return (nil, c)
        case .compound(let first, let second):
            return (.single(first), second)
        }
    }

    /// Inverse of Vowel.combine for compound vowels — returns the base vowel
    /// that the user "started with" before adding the modifier.
    private func decomposeVowel(_ v: Vowel) -> Vowel? {
        switch v {
        case .wa, .wae, .oe: return .o
        case .wo, .we, .wi:  return .u
        case .ui:            return .eu
        default:             return nil
        }
    }

    /// One backspace = one jamo off the in-flight syllable.
    private func peelJamo() {
        if let final = buffer.final {
            switch final {
            case .compound(let first, _):
                buffer.final = .single(first)
            case .single:
                buffer.final = nil
            }
            return
        }

        if let medial = buffer.medial {
            buffer.medial = decomposeVowel(medial)
            return
        }

        if buffer.initial != nil {
            buffer.initial = nil
        }
    }

    // MARK: - Word buffer

    private func stashBuffer() {
        if !buffer.isEmpty {
            stash(buffer, keys: pendingKeys)
        }
        buffer.reset()
        pendingKeys = []
    }

    private func stash(_ syllable: SyllableBuffer, keys: [Character]) {
        let text = syllable.assembled()
        if !text.isEmpty {
            word.append((text, keys))
        }
    }

    private func wordText() -> String {
        return word.map(\.text).joined()
    }

    // MARK: - Output

    private func refreshMarkedText(client: ComposerClient) {
        client.setMarkedText(wordText() + buffer.previewString())
    }
}

// MARK: - Buffer

struct SyllableBuffer {
    enum Final {
        case single(Consonant)
        case compound(first: Consonant, second: Consonant)
    }

    var initial: Consonant?
    var medial: Vowel?
    var final: Final?

    var isEmpty: Bool {
        return initial == nil && medial == nil && final == nil
    }

    mutating func reset() {
        initial = nil
        medial = nil
        final = nil
    }

    func previewString() -> String {
        return assembled()
    }

    func assembled() -> String {
        if let initial, let medial {
            let finalIdx: Int
            switch final {
            case .none:
                finalIdx = 0
            case .single(let c):
                finalIdx = c.finalIndex ?? 0
            case .compound(let a, let b):
                finalIdx = CompoundFinal.index(first: a, second: b) ?? 0
            }
            let code = 0xAC00 + (initial.initialIndex * 21 + medial.medialIndex) * 28 + finalIdx
            if let scalar = UnicodeScalar(code) {
                return String(scalar)
            }
            return ""
        }

        if let initial {
            return String(initial.compatibility)
        }
        if let medial {
            return String(medial.compatibility)
        }
        return ""
    }
}

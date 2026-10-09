import Foundation

/// #84 · 2026-10-09: 실제 배포 사전과 조합/명시 변환/되돌림 경로를 함께 검사한다.
func runPhoneticTests() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: "Resources/IM/phonetic_dictionary.json")),
          let dictionary = try? PhoneticDictionary.load(data: data) else {
        expect(false, true, "발음 사전 로드")
        return
    }
    expect(dictionary.entries.count, 1903, "발음 사전 입력 표기 수")
    expect(Set(dictionary.entries.map(\.english)).count, 1880, "발음 사전 영문 출력 수")
    expect(dictionary.entries.filter { $0.category == "phone-confirmed" }.count, 29, "확인한 번호 별칭")
    expect(dictionary.entries.filter { $0.category == "phone-reserved" }.count, 6, "다음 3개 번호 별칭")
    for (hangul, english) in ["레스토랑": "restaurant", "라이트": "light", "워크": "work",
                               "애플": "Apple", "엔비디아": "NVIDIA", "삼성": "Samsung",
                               "맥스튜디오": "Mac Studio", "갤럭시24": "Galaxy24", "아이폰17": "iPhone17",
                               "축구": "football", "미식축구": "american football", "야구": "baseball",
                               "라이더": "rider", "스포츠": "sports", "아메리칸": "american",
                               "시각효과": "VFX", "브이에프엑스": "VFX", "초현실주의": "surrealism",
                               "케닝": "kerning", "리깅": "rigging", "프록시": "proxy",
                               "색보정": "color grading", "색교정": "color correction",
                               "폴리": "foley", "아메리카노": "americano", "베이글": "bagel",
                               "기내수하물": "carry-on baggage", "와이파이": "Wi-Fi",
                               "파인튜닝": "fine-tuning", "인공지능": "AI", "검색증강생성": "RAG",
                               "로그라이크": "roguelike", "로그라이트": "roguelite", "셰이더": "shader",
                               "애니메이션": "animation", "스톱모션": "stop-motion", "영화": "movie",
                               "디스코드": "Discord",
                               "선물": "gift", "선물거래": "futures trading", "선물계약": "futures contract",
                               "지수": "index", "메시": "mesh", "줌": "zoom"] {
        expect(dictionary.english(for: hangul) ?? "", english, "오너 예시: \(hangul)")
    }
    for word in ["겔럭시", "에플", "레스토런트", "레스토랑에서", "애플은", "맥 스튜디오", "갤럭시024",
                 "갤럭시1", "갤럭시11", "갤럭시19", "갤럭시30", "갤럭시99", "아이폰9", "아이폰10",
                 "아이폰22", "갤럭시24울트라", "아이폰17프로맥스", "갤럭시２４", "애플 ", " 애플", "삼성전자",
                 "축구를", "미식 축구", "라이더가", "스포트", "펑크",
                 "시각 효과", "시각효과를", "브이에프엑쓰", "케닝을", "파인 튜닝", "베이글은", "타임",
                 "선물을", "선물옵션", "디스코오드",
                 "테일러스위프트", "아이유", "봉준호", "뷔", "제이홉", "리오넬메시",
                 "블랙핑크지수", "방탄소년단", "블랙핑크", "비틀스", "콜드플레이"] {
        expect(dictionary.english(for: word) == nil, true, "정확한 등록 표기만 허용: \(word)")
        let fallback = ManualToggle.resolve(word: word, phoneticEnabled: true, keyboardEnabled: true, dictionary: dictionary)
        expect(fallback?.origin != .phonetic, true, "미등록 표기의 발음 추측 없음: \(word)")
        expect(fallback?.text ?? "", ManualToggle.manualToggle(word: word) ?? "", "미등록은 기존 자판 토글: \(word)")
    }
    for word in ["갤럭시27", "갤럭시28", "갤럭시29", "아이폰19", "아이폰20", "아이폰21"] {
        expect(dictionary.english(for: word) != nil, true, "명시 예약 번호: \(word)")
    }

    // 사전 전체를 실제 두벌식 입력으로 재현한다. 숫자는 기존 컨트롤러처럼 문서에 확정된 뒤 조회한다.
    for entry in dictionary.entries {
        guard let keys = ManualToggle.hangulToKeys(entry.hangul) else {
            expect(false, true, "두벌식 도달 불가: \(entry.hangul)")
            continue
        }
        let client = FakeClient(), composer = KoreanComposer()
        for key in keys { typeKeyViaController(key, composer: composer, client: client) }
        if entry.hangul.contains(where: { $0.isNumber }) {
            composer.commit(to: client) // 숫자 이름은 확정 문서 전체에서 찾는다.
            expect(client.committedText, entry.hangul, "숫자 제품명 원문 보존: \(entry.hangul)")
            let result = ManualToggle.resolve(word: client.committedText, phoneticEnabled: true,
                                              keyboardEnabled: true, dictionary: dictionary)
            expect(result?.text ?? "", entry.english, "숫자 제품명 변환: \(entry.hangul)")
            composer.applyToggle(toEnglish: true, hangul: entry.hangul, english: entry.english, origin: .phonetic)
        } else {
            expect(client.marked, entry.hangul, "발음 단어 조합: \(entry.hangul)")
            expect(composer.commitPhonetic(to: client, dictionary: dictionary), true, "조합 중 한 번 변환: \(entry.hangul)")
            expect(client.committedText, entry.english, "영문 대소문자·공백 보존: \(entry.hangul)")
            expect(composer.hasPendingComposition, false, "확정 후 조합 정리: \(entry.hangul)")
        }
        expect(composer.lastEnglishWord == nil, true, "발음 변환이 자동 영타 문맥을 만들지 않음: \(entry.hangul)")
        let before = "문장 " + entry.english + " "
        let toggle = KoreanComposer.resolveToggle(before: before, english: entry.english, hangul: entry.hangul, atDocStart: true)
        expect(toggle?.text ?? "", entry.hangul, "원래 한글로 되돌림: \(entry.hangul)")
        if let toggle {
            let replaced = (before as NSString).replacingCharacters(
                in: NSRange(location: (before as NSString).length - toggle.offsetFromEnd, length: toggle.replaceLen),
                with: toggle.text)
            expect(replaced, "문장 " + entry.hangul + " ", "인접 문장·공백 유지: \(entry.hangul)")
        }
        for toEnglish in [false, true, false] {
            composer.applyToggle(toEnglish: toEnglish, hangul: entry.hangul, english: entry.english)
            expect(composer.shouldRecordAutomaticRevert, false, "수동 왕복은 오변환 기록에서 제외: \(entry.hangul)")
        }
        let nfd = entry.hangul.decomposedStringWithCanonicalMapping
        expect(dictionary.english(for: nfd) ?? "", entry.english, "붙여넣은 NFD 표기: \(entry.hangul)")
    }

    // 자동 변환/수동 키 배열 변환과 다른 원문을 기억해야 한다.
    expect(ManualToggle.resolve(word: "재가", phoneticEnabled: true, keyboardEnabled: true, dictionary: dictionary)?.text ?? "", "work", "기존 재가→work")
    expect(ManualToggle.resolve(word: "work", phoneticEnabled: true, keyboardEnabled: true, dictionary: dictionary)?.text ?? "", "재가", "새 영어 입력은 기존 자판 역변환")
    expect(ManualToggle.resolve(word: "워크", phoneticEnabled: false, keyboardEnabled: true, dictionary: dictionary)?.text ?? "", "dnjzm", "발음 설정 OFF")
    expect(ManualToggle.resolve(word: "워크", phoneticEnabled: true, keyboardEnabled: false, dictionary: dictionary)?.text ?? "", "work", "발음과 모든 단어 토글 설정 독립")
    expect(ManualToggle.resolve(word: "워크", phoneticEnabled: false, keyboardEnabled: false, dictionary: dictionary) == nil, true, "두 설정 OFF")
    expect(ManualToggle.resolve(word: "워크", phoneticEnabled: true, keyboardEnabled: true, dictionary: .empty)?.text ?? "", "dnjzm", "사전 누락은 기존 기능 유지")

    for hangul in ["레스토랑", "워크", "라이트", "애플", "아이폰", "맥스튜디오", "엔비디아", "삼성", "갤럭시24",
                   "축구", "미식축구", "야구", "라이더", "스포츠",
                   "시각효과", "브이에프엑스", "컬러그레이딩", "파인튜닝", "기내수하물", "로그라이크",
                   "선물", "선물거래", "디스코드"] {
        let keys = ManualToggle.hangulToKeys(hangul)!
        expect(typeViaController(keys + " ").committedText, hangul + " ", "일반 Space는 발음 변환 없음: \(hangul)")
        let client = FakeClient(), composer = KoreanComposer()
        composer.autoEnglishEnabled = false
        composer.personalDictionary = PersonalDictionary(block: [keys])
        for key in keys { typeKeyViaController(key, composer: composer, client: client) }
        if !hangul.contains(where: { $0.isNumber }) {
            expect(composer.commitPhonetic(to: client, dictionary: dictionary), true, "자동 변환 OFF/금지와 명시 변환 독립: \(hangul)")
        }
    }
    // 같은 의미의 여러 표기는 원래 입력한 한글 각각으로 돌아와야 한다.
    for original in ["축구", "풋볼"] {
        expect(KoreanComposer.resolveToggle(before: "football ", english: "football", hangul: original,
                                             atDocStart: true)?.text ?? "", original, "별칭 원문 보존: \(original)")
    }
    for original in ["시각효과", "브이에프엑스"] {
        expect(KoreanComposer.resolveToggle(before: "VFX ", english: "VFX", hangul: original,
                                             atDocStart: true)?.text ?? "", original, "VFX 별칭 원문 보존: \(original)")
    }
    expect(dictionary.english(for: "코트") ?? "", "coat", "스포츠 확장으로 기존 의류 뜻을 덮어쓰지 않음")
    expect(dictionary.english(for: "타이어펑크") ?? "", "puncture", "펑크 장르와 타이어 문제 구분")
    expect(dictionary.english(for: "쿨다운") ?? "", "cool-down", "게임 확장도 기존 출력 표기 유지")
    // 금융 문맥 뒤에서도 단독 선물의 지정 의미를 바꾸지 않는다.
    do {
        let composer = KoreanComposer(), client = FakeClient()
        for key in "stock " { typeKeyViaController(key, composer: composer, client: client) }
        for key in ManualToggle.hangulToKeys("선물")! { typeKeyViaController(key, composer: composer, client: client) }
        expect(composer.commitPhonetic(to: client, dictionary: dictionary), true, "금융 문맥 뒤 선물 명시 변환")
        expect(client.committedText, "stock gift", "선물은 문맥과 무관하게 gift")
        expect(composer.lastConversion?.hangul ?? "", "선물", "금융 문맥 뒤에도 원래 단어 보존")
    }
    for word in ["american", "American", "AMERICAN", "rider", "sports", "football", "baseball"] {
        expect(typeViaController(word).committedText, word, "기존 영타 자동 변환: \(word)")
    }
    expect(typeViaController("american football ").committedText, "american football ", "미식축구 영문 직접 입력")
    do {
        let composer = KoreanComposer(), client = FakeClient()
        for key in "apple" { _ = composer.handleInput(String(key), client: client) }
        composer.commit(to: client, convertEnglish: true)
        expect(composer.shouldRecordAutomaticRevert, true, "기존 자동 변환 기록 유지")
        let pair = composer.lastConversion!
        composer.applyToggle(toEnglish: false, hangul: pair.hangul, english: pair.english)
        expect(composer.shouldRecordAutomaticRevert, true, "자동 변환 되돌림 기록 유지")
        composer.resetEnglishContext()
        expect(composer.shouldRecordAutomaticRevert, false, "포커스 변경 시 변환 출처 초기화")
    }
    do {
        let composer = KoreanComposer(), client = FakeClient()
        for key in ManualToggle.hangulToKeys("애플")! { _ = composer.handleInput(String(key), client: client) }
        _ = composer.deleteBackward(client: client)
        expect(composer.commitPhonetic(to: client, dictionary: dictionary), false, "조합 수정 후 오래된 후보 사용 금지")
    }
    for neighbor in ["가", "ㄱ", "ᄀ", "A", "9", "'", "’"] {
        expect(PhoneticDictionary.isBoundary(neighbor), false, "단어 중간 보호: \(neighbor)")
    }
    for neighbor in [nil, "", " ", ".", ",", "\n", "🙂"] as [String?] {
        expect(PhoneticDictionary.isBoundary(neighbor), true, "단어 경계 허용")
    }
    // malformed dictionary must fail as a whole, not let duplicate/invalid data silently win.
    for json in [
        #"{"schemaVersion":2,"entries":[]}"#,
        #"{"schemaVersion":1,"entries":[{"hangul":"애플","english":"Apple","category":"brand"},{"hangul":"애플","english":"apple","category":"brand"}]}"#,
        #"{"schemaVersion":1,"entries":[{"hangul":"에 플","english":"Apple","category":"brand"}]}"#,
        #"{"schemaVersion":1,"entries":[{"hangul":"애플","english":"Apple\n","category":"brand"}]}"#,
        #"{"schemaVersion":1,"entries":[{"hangul":"애플","english":"Apple","category":"guessed"}]}"#
    ] {
        expect((try? PhoneticDictionary.load(data: Data(json.utf8))) == nil, true, "잘못된 사전 안전 차단")
    }
}

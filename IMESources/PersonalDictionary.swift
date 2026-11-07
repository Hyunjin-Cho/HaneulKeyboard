import Foundation

/// 2026-09-21 (#53): 개인 사전 — 사용자가 설정 창에서 직접 관리하는 두 목록(변환 추가·
/// 변환 금지)과 그 판정. IMK·UI 비의존 순수 값 타입이라 테스트 하네스
/// (`scripts/run_ime_tests.sh`)가 판정을 직접 검증한다.
///
/// 원칙 세 가지:
///   1. **기기 안에만.** IME 설정 도메인(`com.hyunjincho.inputmethod.haneul`)의 defaults 키에
///      저장되고 네트워크·자동 수집은 없다(PRIVACY.md). 앱의 전체 제거는 IME 제거 성공
///      뒤 공통 `RemovalSequence` 관문에서 실행 종료·등록·입력 소스까지 확인한 뒤 정리한다.
///      Finder 자동 정리(`OrphanWatcher.selfRemove`)는 개인 사전·설정을 항상 보존한다(2026-10-11 B안).
///   2. **판정은 순수 함수.** 로딩(`load(from:)`)과 판정(`decision`)을 분리한다.
///   3. **저장 형식은 plist 원시 타입(`[String]`)만.** `defaults read`로 사용자가 직접 확인할
///      수 있어야 "무엇을 저장하는가"라는 주장이 검증 가능하다.
///
/// 저장 규약(설정 앱 ↔ IME, 두 프로세스):
///   - 설정 앱이 `UserDefaults(suiteName:)`으로 쓰고, IME가 `UserDefaults.standard`로 읽는다.
///     입력기를 켤 때, 조합 글자·Backspace·활성 경계 키마다, 숫자 키에서 읽는다(HaneulInputController의
///     `refreshAutomaticSettings`) — 기존 `haneul.autoEnglishEnabled` 패턴과 같다.
///   - 두 목록은 설정 앱만 쓴다. IME는 읽기만.
struct PersonalDictionary: Equatable {
    enum Decision: Equatable {
        /// 사전 등급·구조 룰·우리말샘 veto와 무관하게 변환한다(사용자가 명시).
        case forceConvert
        /// 절대 변환하지 않는다.
        case block
    }

    /// defaults 키 — 설정 앱과 IME가 공유하는 단일 정의.
    enum Keys {
        static let force = "haneul.personalDict.force"
        static let block = "haneul.personalDict.block"
    }

    /// 변환 추가 — 소문자 a–z·숫자와 `'` 한 개, 또는 `1.5ml` 형태의 소수 수량.
    var force: Set<String>
    /// 2026-11-07 (#174, 리뷰 E174-P2-1) 오너 결정: 변환 추가에 대문자를 섞어 등록한 표기 원문(QuickTime).
    /// 이 키열과 정확히 같으면 `hasEnglishCasing`을 건너뛴다. 소문자로 등록한 항목은 여기 들어오지 않아 goT·wOrk가 계속 막힌다.
    var registeredSpellings: Set<String>
    /// 변환 금지 — 영어(소문자) 또는 그 한글 자판 표기(`normalizedBlockEntry`로 정규화된 값).
    /// 커밋 때 영어 키열과 한글 표기를 **둘 다** 이 집합에 대조한다.
    var block: Set<String>

    static let empty = PersonalDictionary(force: [], block: [])

    init(force: Set<String> = [], block: Set<String> = [], registeredSpellings: Set<String> = []) {
        self.force = force
        self.block = block
        self.registeredSpellings = registeredSpellings
    }

    /// 저장된 목록에서 만든다. 저장 시 이미 정규화됐더라도 다시 정규화한다 —
    /// `defaults write`로 손으로 넣은 값도 같은 규칙을 타게 하고, 규칙에 안 맞는 항목은
    /// 조용히 버린다(빈 문자열·공백·한글이 force에 섞여도 판정이 오염되지 않게).
    init(forceList: [String], blockList: [String]) {
        let entries = Self.forceEntries(forceList)
        self.init(
            force: Set(entries.compactMap(Self.normalizedForceEntry)),
            block: Set(blockList.compactMap(Self.normalizedBlockEntry)),
            registeredSpellings: Set(entries.filter { $0.contains(where: \.isUppercase) })
        )
    }

    private static let loadLock = NSLock()
    nonisolated(unsafe) private static var lastLoad: (force: [String], block: [String], value: PersonalDictionary)?
    /// 정규화를 실제로 다시 한 횟수. 재사용이 되는지 테스트가 본다.
    nonisolated(unsafe) private(set) static var loadBuildCount = 0

    /// IME 쪽 로더. 글자마다 불리므로 비용이 키 입력 지연에 바로 얹힌다.
    /// 2026-11-07 (#174, 리뷰 input-core F-17): 항목 1000개에서 키당 2.5ms를 썼고 그중 약 95%가 변하지 않는 목록의 재정규화였다.
    /// 배열 읽기는 그대로 매번 해서 설정 반영 시점은 전과 같고, 원본 배열이 같으면 지난 정규화 결과를 돌려준다.
    /// 설정 앱도 같은 함수를 쓰므로 잠금으로 지킨다.
    static func load(from defaults: UserDefaults) -> PersonalDictionary {
        let forceList = defaults.stringArray(forKey: Keys.force) ?? []
        let blockList = defaults.stringArray(forKey: Keys.block) ?? []
        loadLock.lock()
        defer { loadLock.unlock() }
        if let last = lastLoad, last.force == forceList, last.block == blockList { return last.value }
        let value = PersonalDictionary(forceList: forceList, blockList: blockList)
        lastLoad = (forceList, blockList, value)
        loadBuildCount += 1
        return value
    }

    /// 판정. `word`는 실제로 친 키열(대소문자·곱은 따옴표는 여기서 정규화), `hangul`은
    /// 화면에 보이던 조합 결과(marked text 그대로).
    ///   - block이 force보다 먼저: "절대 변환하지 않는다"는 약속은 같은 단어를 실수로 양쪽에
    ///     넣었을 때도 지켜져야 한다 — 안 바뀌는 쪽이 항상 안전한 실패다.
    ///   - force는 혼합 대소문자를 인정하지 않는다(`hasEnglishCasing`). 등록한 표기와 정확히 같은 키열만 예외다.
    ///     금지는 대소문자와 무관하다.
    ///   - nil = 의견 없음 → 호출자가 `EnglishDetector.shouldConvert`에 묻는다.
    func decision(word: String, hangul: String) -> Decision? {
        let key = Self.normalizedEnglish(word)
        let hangulKey = hangul.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
        if block.contains(key) || block.contains(hangulKey) { return .block }
        if force.contains(key), Self.hasEnglishCasing(word) || registeredSpellings.contains(word.replacingOccurrences(of: "’", with: "'")) {
            return .forceConvert
        }
        return nil
    }

    /// 2026-11-07 (#174, 리뷰 F-4): 두벌식에서 Shift로 다른 자모가 되는 키(QWERTOP)가 대문자이면 Title Case나 ALL CAPS만 영어 표기로 본다.
    /// 소문자로만 비교하면 got을 추가했을 때 햇뿐 아니라 했(goT)도, work를 추가했을 때 쟤가(wOrk)도 강제 변환됐다.
    /// 기준은 `EnglishDetector`의 R5와 같다. 숫자가 든 이름(a7R·R2D2)은 한국어로 칠 일이 없어 그대로 force로 본다.
    private static func hasEnglishCasing(_ word: String) -> Bool {
        guard word.contains(where: { $0.isUppercase && "QWERTOP".contains($0) }),
              !word.contains(where: \.isNumber) else { return true }
        let letters = word.filter(\.isLetter)
        return letters.allSatisfy(\.isUppercase) || letters.dropFirst().allSatisfy(\.isLowercase)
    }

    // MARK: - 변환 추가 목록 편집 (설정 앱이 쓴다. 입력기는 읽기만 한다)

    /// 2026-11-07 (#174) 오너 결정: 저장 목록(`Keys.force`)에 사용자가 적은 대소문자를 그대로 둔다. 새 키를 만들지 않은 이유:
    /// 소문자 목록과 원문 목록을 따로 두면 서로 어긋날 수 있고, 예전 빌드도 같은 목록을 소문자로 정규화해 읽으므로 그대로 동작한다.
    /// 옛 항목(전부 소문자)은 옮길 것이 없고, 전체 제거·`defaults read`도 달라지지 않는다.
    static func storedForceEntries(in defaults: UserDefaults) -> [String] {
        forceEntries(defaults.stringArray(forKey: Keys.force) ?? [])
    }

    /// 저장된 목록을 표시·판정용으로 정리한다. 규칙에 안 맞는 항목은 버리고, 같은 낱말(대소문자 무시)은 한 줄로 합치며
    /// (`defaults write`로 넣은 중복만 해당한다) 먼저 나온 대문자 표기를 남긴다. 정렬은 소문자 기준이라 옛 목록의 순서는 그대로다.
    static func forceEntries(_ raw: [String]) -> [String] {
        var byKey: [String: String] = [:]
        for item in raw {
            guard let entry = registeredForceEntry(item), let key = normalizedForceEntry(entry) else { continue }
            if let existing = byKey[key], existing != key { continue }
            byKey[key] = entry
        }
        return byKey.keys.sorted().compactMap { byKey[$0] }
    }

    /// 입력을 목록에 넣은 결과. 규칙에 안 맞으면 nil. 같은 낱말이 이미 있으면 새로 친 표기로 바꾼다.
    static func addingForceEntry(_ input: String, to entries: [String]) -> [String]? {
        guard let entry = registeredForceEntry(input), let key = normalizedForceEntry(entry) else { return nil }
        return forceEntries(entries.filter { normalizedForceEntry($0) != key } + [entry])
    }

    static func removingForceEntry(_ entry: String, from entries: [String]) -> [String] {
        let key = normalizedForceEntry(entry)
        return entries.filter { normalizedForceEntry($0) != key }
    }

    /// 등록 표기: 검사는 `normalizedForceEntry`와 같고 대소문자만 그대로 둔다.
    /// 소문자화로만 ASCII가 되는 문자(켈빈 기호 등)가 섞이면 소문자 항목으로 저장한다.
    private static func registeredForceEntry(_ raw: String) -> String? {
        guard let lowered = normalizedForceEntry(raw) else { return nil }
        let spelled = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'")
        return spelled.allSatisfy(\.isASCII) ? spelled : lowered
    }

    // MARK: - 입력 정규화 (설정 앱의 입력 검증과 저장 시 정규화가 같은 함수를 쓴다)

    /// 변환 추가 항목: 앞뒤 공백 제거 → 소문자 → `’`를 `'`로. 알파벳·숫자와 내부/뒤 아포스트로피 하나, 또는 소수 수량을 허용하고
    /// 글자가 하나 이상이어야 한다(`'`만으로는 단어가 아니다). 아니면 nil.
    static func normalizedForceEntry(_ raw: String) -> String? {
        let s = normalizedEnglish(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard isEnglishEntry(s) else { return nil }
        return s
    }

    /// 변환 금지 항목: 영어(위와 같은 규칙) **또는** 한글 자판 표기(완성형 음절 가–힣과
    /// 호환 낱자모 ㄱ–ㅣ, 축약형 한글형 `애ㅜ'ㅅ`을 위해 `'`도 허용). 섞이거나 그 밖의 문자가
    /// 있으면 nil.
    static func normalizedBlockEntry(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let english = normalizedEnglish(trimmed)
        if isEnglishEntry(english) { return english }
        let hangul = trimmed.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
        if isHangulEntry(hangul) { return hangul }
        return nil
    }

    /// 소문자화 + 곱은 아포스트로피(U+2019) 통일. **`Contractions.normalizedKey`와 같은
    /// 규칙**이어야 커밋 때의 조회 키와 정확히 맞는다 — 여기서 따로 구현하는 이유는 이 파일이
    /// 메인 앱 타겟에도 컴파일되는데 `Contractions.swift`는 IME 전용이기 때문이다.
    /// 두 구현이 어긋나지 않도록 테스트가 같은 입력에 대한 결과 일치를 검사한다
    /// (`Tests/ComposerTests.swift` "PD.normalizedEnglish == Contractions.normalizedKey").
    static func normalizedEnglish(_ s: String) -> String {
        String(s.map { c -> Character in
            if c == "'" || c == "\u{2019}" { return "'" }
            return c.lowercased().first ?? c
        })
    }

    private static func isEnglishEntry(_ s: String) -> Bool {
        // #82: 수량 한 개의 소수점만 허용. 되돌린 1.5ml도 전체 항목으로 금지/추가 가능.
        // 도메인·점으로 나눈 임의 이름은 여전히 한 단어가 아니므로 거부한다.
        if let suffix = decimalQuantitySuffix(s) {
            return suffix.allSatisfy { $0.isASCII && $0.isLetter }
        }
        // #5/#78: 숫자 이름은 허용하되 앞 따옴표/두 번째 따옴표는 조합기가
        // 한 단어로 취급하지 않으므로 등록하지 않는다. 숫자뿐인 항목도 제외.
        guard !s.isEmpty, s.first != "'", s.filter({ $0 == "'" }).count <= 1 else { return false }
        return s.contains { $0.isASCII && $0.isLetter }
            && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "'") }
    }

    private static func isHangulEntry(_ s: String) -> Bool {
        if let suffix = decimalQuantitySuffix(s) { return isHangulEntry(String(suffix)) }
        guard s.first != "'", s.filter({ $0 == "'" }).count <= 1 else { return false }
        var hasHangul = false
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7A3, 0x3131...0x318E: hasHangul = true
            case 0x30...0x39: continue
            case 0x27: continue // `'` — 축약형의 한글형(애ㅜ'ㅅ)
            default: return false
            }
        }
        return hasHangul
    }

    private static func decimalQuantitySuffix(_ s: String) -> Substring? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let digits = parts[1].prefix { $0.isASCII && $0.isNumber }
        let suffix = parts[1].dropFirst(digits.count)
        return !digits.isEmpty && !suffix.isEmpty ? suffix : nil
    }
}

/// 2026-09-21 (#53): 최근 되돌린 변환 — Shift+Space로 **영어→한글로 되돌린** 변환의
/// (한글 표기, 영어) 쌍. 최신이 앞, 같은 쌍은 최신으로 올리고, 상한을 넘으면 꼬리를 버린다.
///
/// 무엇을 담지 않는가(키로거가 되지 않기 위한 선): 키스트로크·앞뒤 문맥·앱 이름·시각.
/// 담는 것은 "IME가 방금 화면에 넣었다가 사용자가 취소한 영어 단어"와 그 한글 표기뿐이고,
/// secure input 중에는 컨트롤러 진입부에서 이미 걸러져 여기까지 오지 않는다.
///
/// 저장 규약: **IME만 쓴다**(되돌린 순간 `recording` 후 저장). 설정 앱은 읽기와 삭제만 —
/// "금지" 버튼의 항목 제거(`removing(blockedBy:)`)와 "최근 기록 지우기". "금지" 버튼이 두
/// 프로세스가 같은 키를 쓰는 유일한 경우인데, 경쟁이 나도 잃는 것은 참고 기록 한 줄이라
/// 허용한다(설정값이 아니다).
///
/// 저장 형식 = `[[String: String]]`(항목마다 `hangul`·`english` 키). JSON 문자열이 아니라
/// plist 원시 타입을 고른 이유: 인코더/디코더 없이 `defaults read`로 그대로 읽히고, 항목이
/// 자기 설명적이며, 깨진 항목은 개별로 버릴 수 있다(문자열 하나가 깨지면 전체를 잃는다).
struct RecentReverts: Equatable {
    struct Entry: Hashable {
        var hangul: String
        var english: String

        /// 혼합 결과(github에)는 영어 전용 금지 형식이 아니므로 원래 한글 전체를 금지한다.
        /// 기존 저장 형식을 유지하면서 설정의 「변환 금지 추가」가 조용히 실패하지 않게 한다.
        var blockEntry: String? {
            PersonalDictionary.normalizedBlockEntry(english)
                ?? PersonalDictionary.normalizedBlockEntry(hangul)
        }
    }

    static let key = "haneul.recentReverts"
    static let maxCount = 50

    /// 최신이 앞.
    private(set) var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = Array(entries.prefix(Self.maxCount))
    }

    /// plist 값에서 복원. 형식이 다르거나 키가 빠진 항목은 버린다(빈 문자열도 버림).
    init(plist: Any?) {
        let raw = plist as? [[String: String]] ?? []
        var seen = Set<Entry>()
        var list: [Entry] = []
        for item in raw {
            guard let h = item["hangul"], let e = item["english"], !h.isEmpty, !e.isEmpty else { continue }
            let entry = Entry(hangul: h, english: e)
            if seen.insert(entry).inserted { list.append(entry) }
        }
        self.init(entries: list)
    }

    var plist: [[String: String]] {
        entries.map { ["hangul": $0.hangul, "english": $0.english] }
    }

    static func load(from defaults: UserDefaults) -> RecentReverts {
        RecentReverts(plist: defaults.array(forKey: key))
    }

    func save(to defaults: UserDefaults) {
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(plist, forKey: Self.key)
        }
    }

    /// 되돌린 쌍을 맨 앞에 넣는다. 같은 쌍이 이미 있으면 그 자리를 비우고 맨 앞으로(최신화),
    /// `maxCount`를 넘으면 가장 오래된 것부터 버린다.
    func recording(hangul: String, english: String) -> RecentReverts {
        let entry = Entry(hangul: hangul, english: english)
        var list = entries.filter { $0 != entry }
        list.insert(entry, at: 0)
        return RecentReverts(entries: list)
    }

    /// "금지" 버튼 뒤 — 실제로 추가한 금지 키에 해당하는 기록만 지운다.
    /// `Apple`/`apple`은 함께 지우고, 서로 다른 한글 원문을 쓰는 혼합 기록은 구분한다.
    func removing(blockedBy raw: String) -> RecentReverts {
        guard let target = PersonalDictionary.normalizedBlockEntry(raw) else { return self }
        return RecentReverts(entries: entries.filter { $0.blockEntry != target })
    }
}

import Foundation

/// 2026-09-21 (#53): 개인 사전 — 사용자가 설정 창에서 직접 관리하는 두 목록(변환 추가·
/// 변환 금지)과 그 판정. IMK·UI 비의존 순수 값 타입이라 테스트 하네스
/// (`scripts/run_ime_tests.sh`)가 판정을 직접 검증한다.
///
/// 원칙 세 가지:
///   1. **기기 안에만.** IME 설정 도메인(`com.hyunjincho.inputmethod.haneul`)의 defaults 키에
///      저장되고 네트워크·자동 수집은 없다(PRIVACY.md). 전체 제거 시
///      `Uninstaller.clearUserDefaults`·`OrphanWatcher.clearLeftovers`가 `haneul.*` 접두어로
///      함께 지운다 — 여기서 따로 할 일은 없다.
///   2. **판정은 순수 함수.** 로딩(`load(from:)`)과 판정(`decision`)을 분리한다.
///   3. **저장 형식은 plist 원시 타입(`[String]`)만.** `defaults read`로 사용자가 직접 확인할
///      수 있어야 "무엇을 저장하는가"라는 주장이 검증 가능하다.
///
/// 저장 규약(설정 앱 ↔ IME, 두 프로세스):
///   - 설정 앱이 `UserDefaults(suiteName:)`으로 쓰고, IME가 `UserDefaults.standard`로
///     활성 경계(변환 직전)마다 읽는다 — 기존 `haneul.autoEnglishEnabled` 패턴과 같다.
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

    /// 변환 추가 — 소문자 a–z와 `'`만(`normalizedForceEntry`로 정규화된 값).
    var force: Set<String>
    /// 변환 금지 — 영어(소문자) 또는 그 한글 자판 표기(`normalizedBlockEntry`로 정규화된 값).
    /// 커밋 때 영어 키열과 한글 표기를 **둘 다** 이 집합에 대조한다.
    var block: Set<String>

    static let empty = PersonalDictionary(force: [], block: [])

    init(force: Set<String> = [], block: Set<String> = []) {
        self.force = force
        self.block = block
    }

    /// 저장된 목록에서 만든다. 저장 시 이미 정규화됐더라도 다시 정규화한다 —
    /// `defaults write`로 손으로 넣은 값도 같은 규칙을 타게 하고, 규칙에 안 맞는 항목은
    /// 조용히 버린다(빈 문자열·공백·한글이 force에 섞여도 판정이 오염되지 않게).
    init(forceList: [String], blockList: [String]) {
        self.init(
            force: Set(forceList.compactMap(Self.normalizedForceEntry)),
            block: Set(blockList.compactMap(Self.normalizedBlockEntry))
        )
    }

    /// IME 쪽 로더. 목록은 작아서(수십~수백) 활성 경계마다 읽어도 부담이 없다.
    static func load(from defaults: UserDefaults) -> PersonalDictionary {
        PersonalDictionary(
            forceList: defaults.stringArray(forKey: Keys.force) ?? [],
            blockList: defaults.stringArray(forKey: Keys.block) ?? []
        )
    }

    /// 판정. `word`는 실제로 친 키열(대소문자·곱은 따옴표는 여기서 정규화), `hangul`은
    /// 화면에 보이던 조합 결과(marked text 그대로).
    ///   - block이 force보다 먼저: "절대 변환하지 않는다"는 약속은 같은 단어를 실수로 양쪽에
    ///     넣었을 때도 지켜져야 한다 — 안 바뀌는 쪽이 항상 안전한 실패다.
    ///   - nil = 의견 없음 → 호출자가 `EnglishDetector.shouldConvert`에 묻는다.
    func decision(word: String, hangul: String) -> Decision? {
        let key = Self.normalizedEnglish(word)
        if block.contains(key) || block.contains(hangul) { return .block }
        if force.contains(key) { return .forceConvert }
        return nil
    }

    // MARK: - 입력 정규화 (설정 앱의 입력 검증과 저장 시 정규화가 같은 함수를 쓴다)

    /// 변환 추가 항목: 앞뒤 공백 제거 → 소문자 → `’`를 `'`로. 결과가 `^[a-z']+$`이고
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
        if isHangulEntry(trimmed) { return trimmed }
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
        guard !s.isEmpty else { return false }
        var hasLetter = false
        for c in s {
            if c.isASCII, c.isLetter, c.isLowercase { hasLetter = true; continue }
            if c == "'" { continue }
            return false
        }
        return hasLetter
    }

    private static func isHangulEntry(_ s: String) -> Bool {
        var hasHangul = false
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7A3, 0x3131...0x318E: hasHangul = true
            case 0x27: continue // `'` — 축약형의 한글형(애ㅜ'ㅅ)
            default: return false
            }
        }
        return hasHangul
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
/// "금지" 버튼의 항목 제거(`removing(english:)`)와 "최근 기록 지우기". "금지" 버튼이 두
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

    /// "금지" 버튼 뒤 — 그 영어 단어의 항목을 전부 지운다(대소문자·곱은 따옴표 무시:
    /// `Apple`과 `apple`은 같은 금지 항목에 걸리므로 목록에서도 함께 빠진다).
    func removing(english: String) -> RecentReverts {
        let target = PersonalDictionary.normalizedEnglish(english)
        return RecentReverts(entries: entries.filter {
            PersonalDictionary.normalizedEnglish($0.english) != target
        })
    }
}

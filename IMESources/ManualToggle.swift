import Foundation

/// 2026-09-21 (#15): 되돌리기 키를 **모든 단어**로 확대하는 수동 한↔영 토글의 순수 로직.
///
/// 자동 변환(`EnglishDetector`)은 일부러 포기한 영역이 있다 — 우리말샘 표제어라 veto가 막는
/// `재가`(work), 사전에 존재할 수 없는 `ㅡ5`(m5)·`ㅏ3`(k3). 사용자가 되돌리기 키를 **직접**
/// 누른 것은 "내가 영어를 치려던 거였다"는 명시적 의사표시이므로, 그 경우엔 veto도 사전도
/// 건너뛰고 자판 배열만으로 한↔영을 바꾼다. 그래서 이 파일은 사전을 전혀 보지 않는다.
///
/// 두 방향 모두 **기존 자산의 역/정방향 사용**이다. 새 규칙을 만들지 않는다:
///   - 한 → 영(`hangulToKeys`): 완성형 음절을 유니코드 산술로 초·중·종성으로 풀고,
///     복합 모음·겹받침은 `Vowel.combine`·`CompoundFinal.index`를 **역으로 훑어** 낱자모로
///     되돌린 뒤 `KeyboardLayout2Set` 표의 역인덱스로 키를 얻는다.
///   - 영 → 한(`keysToHangul`): 새 조합기를 만들지 않고 `KoreanComposer`를 그대로 돌린다
///     (자동 변환은 꺼서 끼워 넣지 않는다). 그래서 `Vismo` → `퍄느ㅐ`처럼 자동변환 경로와
///     **같은 결과**가 보장된다 — 테스트가 완성형 11,172자 전부로 왕복을 검증한다.
///
/// 역매핑 표는 **손으로 적지 않고 기존 표에서 만든다**(`KeyboardLayout2Set.table`·
/// `Vowel.combine`·`Consonant.finalIndex`·`CompoundFinal.index`를 훑어 뒤집는다). 자모가
/// 추가돼도 표가 저절로 따라오고, 손으로 베낀 사본이 낡는 사고가 없다. 유일한 예외는
/// 겹자모의 **호환 자모 표기**(ㄳ·ㄺ…)로, 코드베이스 어디에도 그 글자가 없어 이 파일에
/// 적는다 — 테스트가 각 쌍을 `CompoundFinal.index`와 대조한다.
///
/// IMK·UI 비의존이라 `scripts/run_ime_tests.sh`가 직접 검증한다.
enum ManualToggle {
    /// 커서 앞 단어가 어느 쪽인가.
    enum Kind: Equatable {
        /// 한글(완성형 음절 또는 호환 낱자모)이 들어 있다 → 영어 키열로 바꾼다.
        case hangul
        /// 두벌식 자판의 라틴 키(a–z·A–Z)만 들어 있다 → 한글로 조합한다.
        case english
        /// 바꿀 수 없다 — 빈 문자열, 한글·영어 혼합, 자모도 통과 문자도 아닌 글자(공백·이모지 등).
        case unsupported
    }

    /// 커서 앞에서 읽어 올 최대 길이(UTF-16). `KoreanComposer`의 단어 상한(40유닛)보다 넉넉히
    /// 잡되 무한정 읽지는 않는다 — 단어가 이 창을 가득 채우면 좌측 경계를 알 수 없어
    /// `KoreanComposer.wordBeforeCursor`가 안전하게 포기한다.
    static let readSpan = 64

    // MARK: - 공개 판정

    /// 자모도 라틴 키도 아니지만 **그대로 통과**시키는 글자 — 숫자와 아포스트로피.
    /// 숫자는 이 기능의 핵심 사례다(`ㅡ5` ↔ `m5`: 사전에 존재할 수 없어 자동변환이 원리적으로
    /// 불가능한 조합). 통과 문자만으로 이뤄진 단어는 바꿀 게 없으므로 `.unsupported`다.
    static func isPassthrough(_ character: Character) -> Bool {
        (character.isASCII && character.isNumber) || Contractions.isApostrophe(character)
    }

    static func classify(word: String) -> Kind {
        guard !word.isEmpty else { return .unsupported }
        var hasHangul = false
        var hasLatin = false
        for character in word.precomposedStringWithCanonicalMapping {
            if isHangul(character) {
                hasHangul = true
            } else if isLatinKey(character) {
                hasLatin = true
            } else if isPassthrough(character) {
                continue
            } else {
                return .unsupported
            }
        }
        // 한글과 라틴이 섞인 단어(`재work`)는 어느 방향으로 바꿔도 사용자 의도를 알 수 없다.
        if hasHangul && hasLatin { return .unsupported }
        if hasHangul { return .hangul }
        if hasLatin { return .english }
        return .unsupported
    }

    /// 방향을 스스로 정해 바꾼다. 바꿀 수 없으면 nil(호출자는 아무것도 하지 않는다).
    static func manualToggle(word: String) -> String? {
        switch classify(word: word) {
        case .hangul: return hangulToKeys(word)
        case .english: return keysToHangul(word)
        case .unsupported: return nil
        }
    }

    // MARK: - 한글 → 영어 키열

    /// 완성형 음절·호환 낱자모를 **그 글자를 만들어 낸 두벌식 키열**로 되돌린다.
    /// 쌍자음(ㄲㄸㅃㅆㅉ)과 ㅒ·ㅖ는 Shift 키라 대문자로 나온다(`ㄲ` → `R`).
    /// 통과 문자(숫자·`'`)는 그대로 두고, 그 외 글자가 하나라도 섞이면 nil.
    static func hangulToKeys(_ word: String) -> String? {
        // NFD(자모가 풀린 형태)로 들어와도 같게 다룬다 — 다른 입력기·붙여넣기 출처 대비.
        let normalized = word.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { return nil }
        var out = ""
        for character in normalized {
            let scalars = character.unicodeScalars
            if scalars.count == 1, let syllableKeys = keysForSyllable(scalars.first!.value) {
                out += syllableKeys
            } else if scalars.count == 1, let jamoKeys = keysForCompatibilityJamo(character) {
                out += jamoKeys
            } else if isPassthrough(character) {
                out.append(character)
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    /// 완성형 음절(가–힣) 한 글자 → 키열. 범위 밖이면 nil.
    ///
    /// 표준 분해 공식: `s = code - 0xAC00`, 종성 = `s % 28`, 중성 = `(s / 28) % 21`,
    /// 초성 = `s / 28 / 21` (초성 19 × 중성 21 × 종성 28 = 11,172자).
    private static func keysForSyllable(_ code: UInt32) -> String? {
        guard (0xAC00...0xD7A3).contains(code) else { return nil }
        let s = Int(code - 0xAC00)
        guard let initial = Consonant(rawValue: s / 28 / 21),
              let medial = Vowel(rawValue: (s / 28) % 21),
              let initialKey = consonantKey[initial],
              let medialKeys = keys(for: medial) else { return nil }
        var out = String(initialKey) + medialKeys
        let finalIndex = s % 28
        if finalIndex != 0 {
            guard let parts = finalConsonants[finalIndex] else { return nil }
            for consonant in parts {
                guard let key = consonantKey[consonant] else { return nil }
                out.append(key)
            }
        }
        return out
    }

    /// 호환 자모(ㄱ–ㅣ, U+3131–U+3163) 한 글자 → 키열. 겹자모(ㄳ·ㅘ…)는 낱자로 풀어 2키.
    private static func keysForCompatibilityJamo(_ character: Character) -> String? {
        if let consonant = compatibilityConsonant[character] {
            return consonantKey[consonant].map(String.init)
        }
        if let vowel = compatibilityVowel[character] {
            return keys(for: vowel)
        }
        if let pair = compoundFinalCompatibility[character] {
            guard let first = consonantKey[pair.0], let second = consonantKey[pair.1] else { return nil }
            return String([first, second])
        }
        return nil
    }

    /// 모음 → 키열. 복합 모음(ㅘㅙㅚㅝㅞㅟㅢ)은 직접 키가 없어 두 낱자로 푼다(ㅘ → ㅗ+ㅏ → `hk`).
    private static func keys(for vowel: Vowel) -> String? {
        if let key = vowelKey[vowel] { return String(key) }
        guard let parts = vowelDecomposition[vowel],
              let first = vowelKey[parts.0], let second = vowelKey[parts.1] else { return nil }
        return String([first, second])
    }

    // MARK: - 영어 키열 → 한글

    /// 라틴 키열을 **기존 조합기**(`KoreanComposer`)에 그대로 태워 한글로 만든다.
    /// 새 조합기를 만들지 않는 이유: 도깨비불(받침이 다음 음절로 넘어감)·복합 모음·겹받침
    /// 규칙이 이미 거기 있고, 사본을 만들면 자동변환 경로와 결과가 갈린다.
    /// 자동 변환은 꺼 둔다 — 이 경로의 일은 "조합"이지 "영어 판정"이 아니다.
    /// 자모가 아닌 통과 문자(숫자·`'`)는 조합을 끊고 친 그대로 남긴다(`m5` → `ㅡ5`).
    static func keysToHangul(_ word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let sink = CollectingClient()
        let composer = KoreanComposer()
        composer.autoEnglishEnabled = false
        var out = ""
        for character in word {
            if KeyboardLayout2Set.jamo(for: character) != nil {
                _ = composer.handleInput(String(character), client: sink)
            } else if isPassthrough(character) {
                composer.commit(to: sink)
                out += sink.take()
                out.append(character)
            } else {
                return nil
            }
        }
        composer.commit(to: sink)
        out += sink.take()
        return out.isEmpty ? nil : out
    }

    /// `KoreanComposer`가 확정해 내보내는 글자만 모으는 최소 클라이언트. marked text는 버린다
    /// (조합 중간 모습은 결과와 무관하고, 마지막 `commit`이 전부 확정해 준다).
    private final class CollectingClient: ComposerClient {
        private var buffer = ""
        func insertText(_ text: String) { buffer += text }
        func setMarkedText(_ text: String) {}
        func take() -> String {
            defer { buffer = "" }
            return buffer
        }
    }

    // MARK: - 글자 분류

    private static func isHangul(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return false }
        // 완성형 음절 가–힣 + 호환 낱자모 ㄱ–ㅣ. `KoreanComposer.isWordChar`가 단어로 인정하는
        // 범위(0x3130–0x318F)보다 좁다 — 옛한글 낱자모는 두벌식 키가 없어 어차피 nil이 된다.
        return (0xAC00...0xD7A3).contains(scalar.value)
            || (0x3131...0x3163).contains(scalar.value)
    }

    private static func isLatinKey(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    // MARK: - 역매핑 표 (전부 기존 표에서 생성)

    /// 두벌식 키 후보. **소문자를 먼저** 훑어 같은 자모면 소문자 키를 고른다 — Shift가
    /// 의미 없는 키(`a`/`A` 둘 다 ㅁ)에서 `A`가 뽑히면 왕복 결과가 이상해진다. 쌍자음·ㅒ·ㅖ는
    /// 대문자에만 있어 자연히 대문자로 남는다.
    private static let keyCandidates: [Character] =
        Array("abcdefghijklmnopqrstuvwxyz") + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static let reverseLayout: (consonants: [Consonant: Character], vowels: [Vowel: Character]) = {
        var consonants: [Consonant: Character] = [:]
        var vowels: [Vowel: Character] = [:]
        for key in keyCandidates {
            switch KeyboardLayout2Set.jamo(for: key) {
            case .consonant(let consonant):
                if consonants[consonant] == nil { consonants[consonant] = key }
            case .vowel(let vowel):
                if vowels[vowel] == nil { vowels[vowel] = key }
            case nil:
                break
            }
        }
        return (consonants, vowels)
    }()

    private static var consonantKey: [Consonant: Character] { reverseLayout.consonants }
    private static var vowelKey: [Vowel: Character] { reverseLayout.vowels }

    /// `Vowel.combine`의 역 — 복합 모음 → 그것을 만드는 낱자 쌍. 표를 훑어 만든다.
    private static let vowelDecomposition: [Vowel: (Vowel, Vowel)] = {
        var map: [Vowel: (Vowel, Vowel)] = [:]
        for first in Vowel.allCases {
            for second in Vowel.allCases {
                if let combined = Vowel.combine(first, second), map[combined] == nil {
                    map[combined] = (first, second)
                }
            }
        }
        return map
    }()

    /// 종성 인덱스(1–27) → 그 받침을 이루는 낱자 자음. 홑받침은 `Consonant.finalIndex`,
    /// 겹받침은 `CompoundFinal.index`를 역으로 훑어 만든다.
    private static let finalConsonants: [Int: [Consonant]] = {
        var map: [Int: [Consonant]] = [:]
        for consonant in Consonant.allCases {
            if let index = consonant.finalIndex { map[index] = [consonant] }
        }
        for first in Consonant.allCases {
            for second in Consonant.allCases {
                if let index = CompoundFinal.index(first: first, second: second) {
                    map[index] = [first, second]
                }
            }
        }
        return map
    }()

    private static let compatibilityConsonant: [Character: Consonant] =
        Dictionary(uniqueKeysWithValues: Consonant.allCases.map { ($0.compatibility, $0) })

    private static let compatibilityVowel: [Character: Vowel] =
        Dictionary(uniqueKeysWithValues: Vowel.allCases.map { ($0.compatibility, $0) })

    /// 홀로 쓰인 겹자모의 호환 자모 표기 → 낱자 쌍. 코드베이스에 이 글자들의 표기가 없어
    /// 여기서만 적는다(`ㄳ`처럼 축약 표현으로 실제로 쓰인다 — ㄳ → `rt`).
    /// 테스트가 각 쌍을 `CompoundFinal.index`와 대조하므로 짝이 어긋나면 잡힌다.
    private static let compoundFinalCompatibility: [Character: (Consonant, Consonant)] = [
        "ㄳ": (.giyeok, .siot),
        "ㄵ": (.nieun, .jieut),
        "ㄶ": (.nieun, .hieut),
        "ㄺ": (.rieul, .giyeok),
        "ㄻ": (.rieul, .mieum),
        "ㄼ": (.rieul, .bieup),
        "ㄽ": (.rieul, .siot),
        "ㄾ": (.rieul, .tieut),
        "ㄿ": (.rieul, .pieup),
        "ㅀ": (.rieul, .hieut),
        "ㅄ": (.bieup, .siot),
    ]

    /// 테스트 전용 훅 — 위 겹자모 표가 `CompoundFinal`과 짝이 맞는지 확인한다.
    static var compoundFinalCompatibilityPairs: [(Character, Consonant, Consonant)] {
        compoundFinalCompatibility.map { ($0.key, $0.value.0, $0.value.1) }
    }
}

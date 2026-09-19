import Foundation

/// 2026-09-19 (#34): 아포스트로피 축약형(i'm·don't·it's·you're)을 영타 자동
/// 변환의 대상으로 삼기 위한 판정 로직 — IMK·파일 I/O 비의존 순수 함수.
///
/// 왜 사전 파일이 아니라 코드인가: `EnglishDetector.loadWords`는 비알파벳이
/// 섞인 줄과 3글자 미만을 버린다. 그래서 `i'm`·`it's` 같은 표제어는 번들
/// 사전에 넣어도 절대 로드되지 않는다 — 축약형은 데이터가 아니라 코드로
/// 풀어야 한다.
///
/// 한국어 안전성: 여기까지 오는 단어는 "키열에 `'`가 들어간 단어"뿐이다.
/// 한국어 단어 중간에 `'`가 오는 정상 입력은 사실상 없고, `안녕'하세요`처럼
/// 쳐도 아래 두 관문(소사전 정확 일치 / 허용 접미 + base 변환 가능)을 모두
/// 통과하지 못해 그대로 한글로 남는다. 그래서 이 경로가 우리말샘 veto를
/// 거치지 않아도 오변환 위험이 없다.
enum Contractions {
    /// 단어 내부 아포스트로피로 취급하는 문자.
    ///
    /// 우리는 `overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")`로
    /// 레이아웃을 ABC로 강제하므로 keyCode 39는 U+0027 APOSTROPHE로 올라온다.
    /// 하드웨어/레이아웃에 따라 U+2019(’)가 올라오는 경우가 있어 둘 다 받고,
    /// 사전 조회 시에만 U+0027로 정규화한다(출력은 친 글자 그대로 유지).
    static func isApostrophe(_ c: Character) -> Bool {
        c == "'" || c == "\u{2019}"
    }

    /// 사전 조회용 정규화 — 대문자를 낮추고 `’`를 `'`로 통일한다.
    /// (대소문자 보존은 출력 쪽 `String(keys)`가 맡는다: `I'm` → `I'm`.)
    static func normalizedKey(_ keys: [Character]) -> String {
        String(keys.map { isApostrophe($0) ? "'" : ($0.lowercased().first ?? $0) })
    }

    /// 키열을 **첫** `'` 기준으로 base / suffix 로 나눈다. `'`가 없으면 nil.
    /// (조합기가 단어당 `'`를 하나만 허용하므로 실제로는 항상 첫 개가 유일하다.)
    static func split(_ keys: [Character]) -> (base: [Character], suffix: [Character])? {
        guard let i = keys.firstIndex(where: isApostrophe) else { return nil }
        return (Array(keys[..<i]), Array(keys[(i + 1)...]))
    }

    /// (a) 축약형 소사전 정확 일치 — 대소문자 무시. 닫힌 집합이다.
    static func matchesDictionary(_ keys: [Character]) -> Bool {
        words.contains(normalizedKey(keys))
    }

    /// (b) `'` 뒤가 허용된 접미인가. base가 기존 규칙으로 변환되는지는
    /// 호출자(`KoreanComposer`)가 `EnglishDetector.shouldConvert`에 따로 묻는다
    /// — 축약형 전용 판정을 새로 만들지 않고 이미 검증된 규칙을 재사용한다.
    static func hasAllowedSuffix(_ keys: [Character]) -> Bool {
        guard let parts = split(keys) else { return false }
        return allowedSuffixes.contains(normalizedKey(parts.suffix))
    }

    /// `'` 뒤에 올 수 있는 어미 — 소유격·복수(s), 'd, 'm, 't, 're, 've, 'll,
    /// 그리고 빈 문자열(`ㅑ'` + 스페이스 = `i'`).
    /// 닫힌 집합이라 뒤가 한국어면(`안녕'하세요`) 여기서 걸러진다.
    static let allowedSuffixes: Set<String> = ["", "s", "d", "m", "t", "re", "ve", "ll"]

    /// 축약형 소사전 — base만으로는 영어 판정이 안 서는 것들(`i`·`you`·`isn`·
    /// `wasn`처럼 base가 사전에 없거나 너무 짧은 경우)을 통째로 구제한다.
    ///
    /// ⚠️ 목록을 늘릴 때: 한글형에 `'`가 반드시 포함되므로 한국어 충돌은
    /// 구조적으로 불가능하다. 대신 **실제로 쓰이는 축약형만** 넣는다 —
    /// 오타가 우연히 영어로 둔갑하는 채널을 넓히지 않기 위해서다.
    static let words: Set<String> = [
        // 대명사 + be/will/have/would
        "i'm", "i'll", "i've", "i'd",
        "you're", "you'll", "you've", "you'd",
        "we're", "we'll", "we've", "we'd",
        "they're", "they'll", "they've", "they'd",
        "he's", "he'll", "he'd",
        "she's", "she'll", "she'd",
        "it's", "it'll", "it'd",
        // 부정형 (base가 isn/wasn/couldn… 이라 사전에 없다 = 소사전 필수)
        "isn't", "aren't", "wasn't", "weren't",
        "don't", "doesn't", "didn't",
        "can't", "couldn't", "won't", "wouldn't", "shouldn't",
        "hasn't", "haven't", "hadn't",
        "mustn't", "needn't", "shan't", "ain't",
        // 의문·지시사 + is/has/will/would
        "that's", "that'll", "that'd",
        "what's", "what'll",
        "who's", "who'll",
        "there's", "there'll",
        "here's", "where's", "how's", "when's", "why's",
        "let's",
        // 관용
        "o'clock", "y'all", "ma'am",
    ]
}

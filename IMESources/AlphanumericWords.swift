import Foundation

/// 2026-10-06 (#5): 오너가 지정한 영숫자 이름. 패턴 추론 없이 전체 일치만 허용한다.
/// 조회는 소문자, 출력은 조합기가 보관한 실제 키열(Shift 포함)을 사용한다.
enum AlphanumericWords {
    static let words: Set<String> = ["800t", "t800", "a24", "a16z", "a7r"]

    private static let prefixes: Set<String> = Set(words.flatMap { word in
        (1...word.count).map { String(word.prefix($0)) }
    })

    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    static func contains(_ keys: String) -> Bool { words.contains(keys.lowercased()) }
    static func hasPrefix(_ keys: String) -> Bool { prefixes.contains(keys.lowercased()) }
}

import Foundation

/// #84 · 2026-10-09: 명시적으로 누른 한영 키에서만 쓰는 한글 표기 → 영문 사전.
/// 검토한 발음과 지정 의미(축구→football)를 모두 담되 일반 번역/문맥 추론은 하지 않는다.
/// 자동 영타 판정 사전과 합치지 않는다. NFC 정규화 외의 오타/발음 추측은 하지 않는다.
struct PhoneticDictionary {
    struct Entry: Decodable {
        let hangul: String
        let english: String
        let category: String
        let subcategory: String?
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    enum LoadError: Error { case invalidSchema, invalidEntry, duplicateEntry }

    let entries: [Entry]
    private let index: [String: String]
    static let empty = PhoneticDictionary(entries: [], index: [:])

    /// 제품은 앱에 함께 서명된 사전만 읽는다. 누락/손상이면 발음 변환만 비활성화한다.
    static let bundled: PhoneticDictionary = {
        guard let url = Bundle.main.url(forResource: "phonetic_dictionary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? load(data: data) else { return .empty }
        return dictionary
    }()

    static func load(data: Data) throws -> PhoneticDictionary {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else { throw LoadError.invalidSchema }
        var index: [String: String] = [:]
        let categories: Set<String> = ["everyday", "computing", "creative", "brand", "product", "sports", "mobility", "gaming", "finance", "phone-confirmed", "phone-reserved"]
        for entry in document.entries {
            let key = entry.hangul.precomposedStringWithCanonicalMapping
            guard key == entry.hangul, !key.isEmpty, key.utf16.count <= 40,
                  key.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }),
                  key.unicodeScalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) || (0x30...0x39).contains($0.value) }),
                  !entry.english.isEmpty, entry.english.utf16.count <= 64,
                  entry.english == entry.english.trimmingCharacters(in: .whitespaces),
                  !entry.english.contains("  "),
                  entry.english.contains(where: { $0.isASCII && $0.isLetter }),
                  entry.english.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " || $0 == "-" }),
                  categories.contains(entry.category) else { throw LoadError.invalidEntry }
            guard index.updateValue(entry.english, forKey: key) == nil else { throw LoadError.duplicateEntry }
        }
        return PhoneticDictionary(entries: document.entries, index: index)
    }

    func english(for hangul: String) -> String? {
        index[hangul.precomposedStringWithCanonicalMapping]
    }

    /// 문서의 단어 중간에 커서를 둔 경우에는 발음 변환하지 않는다.
    /// nil/빈 문자열은 클라이언트가 이웃 글자를 제공하지 않은 문서 끝이다.
    static func isBoundary(_ neighbor: String?) -> Bool {
        guard let character = neighbor?.first else { return true }
        return !character.isLetter && !character.isNumber && character != "'" && character != "’"
    }
}

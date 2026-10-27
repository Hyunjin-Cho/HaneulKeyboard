import Foundation

/// IMK 왕복을 시험 가능한 경계로 격리한다. 문서 전체 길이는 조회하지 않는다.
protocol ExternalEnglishContextClient {
    func contextSelection() -> NSRange
    func contextMarkedRange() -> NSRange
    func contextSubstring(in range: NSRange) -> String?
}

/// 2026-10-14 · #14: 새 조합 바로 앞의 확정 영어 한 단어만 읽는다.
/// 활성화 콜백에서는 호출하지 않는다. 원문은 호출 동안만 존재하고 저장/로그하지 않는다.
enum ExternalEnglishContext {
    static let readSpan = 128 // UTF-16; IMK 문서 좌표와 같은 단위
    static let maximumWordLength = 64

    static func capture(
        from client: ExternalEnglishContextClient,
        enabled: Bool,
        secureInput: () -> Bool,
        isKnownEnglishWord: (String) -> Bool
    ) -> String? {
        guard enabled, !secureInput() else { return nil }
        let selection = client.contextSelection()
        guard !secureInput(), selection.location != NSNotFound,
              selection.location > 0, selection.length == 0 else { return nil }
        let marked = client.contextMarkedRange()
        // NSNotFound/0은 일반적인 '조합 없음'. NSNotFound/NSNotFound는 미지원이다.
        guard !secureInput(), marked.length == 0 else { return nil }
        let start = max(0, selection.location - readSpan)
        let range = NSRange(location: start, length: selection.location - start)
        guard let before = client.contextSubstring(in: range), !secureInput(),
              (before as NSString).length == range.length,
              let word = previousWord(before: before, atDocumentStart: start == 0),
              isKnownEnglishWord(word) else { return nil }
        // 클라이언트 왕복 동안 커서가 바뀌었으면 과거 위치의 단어를 새 조합에 적용하지 않는다.
        guard !secureInput(), client.contextSelection() == selection, !secureInput() else { return nil }
        return word
    }

    /// Space/쉼표 뒤만 영어 문맥을 이어간다. 줄바꿈/구두점/따옴표 끝은 문맥을 끊는다.
    /// 잘린 창의 첫 토큰, 식별자 일부, 한영 붙여쓰기, 오타는 문맥의 근거로 쓰지 않는다.
    static func previousWord(before: String, atDocumentStart: Bool) -> String? {
        let text = before as NSString
        guard text.length > 0, text.length <= readSpan else { return nil }
        var end = text.length
        while end > 0, isContinuationBoundary(text.character(at: end - 1)) { end -= 1 }
        guard end < text.length, end > 0 else { return nil }
        var start = end
        while start > 0, isEnglishToken(text.character(at: start - 1)) { start -= 1 }
        guard end - start > 0, end - start <= maximumWordLength,
              start > 0 || atDocumentStart else { return nil }
        if start > 0 {
            let left = text.character(at: start - 1)
            guard isLeftBoundary(left) else { return nil }
        }
        let token = text.substring(with: NSRange(location: start, length: end - start))
        let characters = Array(token)
        guard characters.first?.isASCII == true, characters.first?.isLetter == true,
              characters.last?.isASCII == true, characters.last?.isLetter == true else { return nil }
        for i in characters.indices where Contractions.isApostrophe(characters[i]) {
            guard i > 0, i + 1 < characters.count,
                  characters[i - 1].isASCII, characters[i - 1].isLetter,
                  characters[i + 1].isASCII, characters[i + 1].isLetter else { return nil }
        }
        let normalized = Contractions.normalizedKey(characters)
        // #82의 수량+단위는 다음 한글로 영어 문맥을 넘기지 않는다. ABC에서 입력한
        // '100 ml '도 같은 보호를 적용한다. 숫자를 읽거나 새로 변환/저장하지 않는다.
        if MeasurementUnits.contains(token) || MeasurementUnits.contains(normalized) {
            var amountEnd = start
            while amountEnd > 0, text.character(at: amountEnd - 1) == 0x20 { amountEnd -= 1 }
            var amountStart = amountEnd
            while amountStart > 0 {
                let character = text.character(at: amountStart - 1)
                guard (0x30...0x39).contains(character) || character == 0x2E else { break }
                amountStart -= 1
            }
            if amountStart < amountEnd,
               MeasurementUnits.isQuantity(text.substring(with:
                    NSRange(location: amountStart, length: amountEnd - amountStart))) {
                return nil
            }
        }
        return normalized
    }

    private static func isContinuationBoundary(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x2C
    }

    private static func isEnglishToken(_ character: unichar) -> Bool {
        (0x41...0x5A).contains(character) || (0x61...0x7A).contains(character)
            || character == 0x27 || character == 0x2019
    }

    private static func isLeftBoundary(_ character: unichar) -> Bool {
        // 경계 목록을 명시해 숫자·밑줄·하이픈·한글/유니코드 단어 일부를 읽지 않는다.
        [0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x2E, 0x3B, 0x3A,
         0x21, 0x3F, 0x28, 0x5B, 0x7B, 0x22, 0x201C].contains(character)
    }
}

import Foundation

/// #82: 사전 단어 검사와 달리 숫자·소수점·Space까지 실제 조합기로 처리한다.
/// 판정을 재구현하지 않고 HaneulInputController.handle의 문자 분배만 재현한다.
private final class UnitAuditClient: ComposerClient {
    var text = ""
    func insertText(_ text: String) { self.text += text }
    func setMarkedText(_ text: String) {}
}

private func typeQuantity(_ input: String, enabled: Bool = true) -> String {
    let composer = KoreanComposer(), client = UnitAuditClient()
    composer.autoEnglishEnabled = enabled
    for key in input {
        if Contractions.isApostrophe(key), composer.handleApostrophe(key, client: client) { continue }
        if AlphanumericWords.isDigit(key), composer.handleDigit(key, client: client) { continue }
        if KeyboardLayout2Set.jamo(for: key) != nil {
            _ = composer.handleInput(String(key), client: client)
        } else {
            // 2026-11-07 (#178): 2026-11-04 컨트롤러 변경(붙잡지 않은 숫자·소수점은 앱에 바로 보내고 보낸 숫자열만 기억)을
            // 따라가지 않아 수량 열 결과가 실제와 달라졌다. Tests/ComposerTests.swift의 typeKeyViaController와 같은 분배로 맞춘다.
            let run: String? = AlphanumericWords.isDigit(key) ? composer.digitRunAfterSending(key)
                : key == "." ? composer.pointRunAfterSending() : nil
            composer.commit(to: client, convertEnglish: true)
            client.insertText(String(key))
            composer.completeBoundary(key)
            if AlphanumericWords.isDigit(key) || key == "." { composer.setSentDigits(run) }
        }
    }
    composer.commit(to: client, convertEnglish: true)
    return client.text
}

@main private enum MeasurementUnitAudit {
    static func main() {
        EnglishDetector.bundledTablePath = "Resources/IM/english_bundled.txt"
        EnglishDetector.wordlistPaths = EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.curatedPaths = Set(EnglishDetector.wordlistPaths)
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        guard KoreanDictionary.isLoaded else { fatalError("한국어 사전 로드 실패") }
        print("unit,hangul,korean_veto,standalone,attached,spaced,decimal")
        for unit in MeasurementUnits.symbols.sorted() {
            let hangul = typeQuantity(unit, enabled: false)
            print([unit, hangul, String(KoreanDictionary.contains(hangul)),
                   typeQuantity(unit), typeQuantity("100" + unit),
                   typeQuantity("100 " + unit), typeQuantity("1.25" + unit)].joined(separator: ","))
        }
    }
}

import Foundation

/// 영어+조사의 확정 판정과 입력 중 표시. 규칙 설명: docs/input-conversion-rules.md.
enum EnglishParticleSplitter {
    enum Decision: Equatable {
        case mixed(String)
        case preserveHangul
    }

    // 조사의 역할과 결합 순서를 정의한다. 실행 목록을 다른 곳에 중복 보관하지 않는다.
    static let particles: Set<String> = {
        let caseMarkers: Set<String> = ["이", "가", "을", "를", "의", "께서", "이나", "나"]
        let standalone: Set<String> = ["은", "는", "도", "만", "조차", "마저",
                                       "밖에", "뿐", "라도", "이라도"]
        let connectors: Set<String> = ["와", "과", "하고", "랑", "이랑"]
        let relations: Set<String> = [
            "에", "에서", "에게", "한테", "께", "에게서", "한테서",
            "로", "으로", "로서", "으로서", "로써", "으로써",
            "처럼", "보다", "만큼", "부터", "까지",
        ]
        let origins = Set(["에서", "에게서", "한테서", "로", "으로"].map { $0 + "부터" })
        let extensible = relations.union(connectors).union(origins).union(["만", "조차", "마저"])
        var forms = caseMarkers.union(standalone).union(extensible)
        for base in extensible {
            // 받침에 따라 '이랑은', '에서는'처럼 보조사를 결합한다.
            let final = base.unicodeScalars.last!.value
            let topic = (final - 0xAC00) % 28 == 0 ? "는" : "은"
            forms.insert(base + topic)
            forms.insert(base + "도")
            if base != "만" { forms.insert(base + "만") }
        }
        // 2026-10-28 (#101): 국립국어원 한글맞춤법 제41항의 조사 연속 원칙과
        // 한국어기초사전 '라도/이라도'에 맞춘 관계·출발점 뒤 선택 조사다.
        // 앞 영어의 발음은 추측하지 않고 실제 친 라도/이라도만 보존한다.
        for base in relations.union(origins).union(["만"]) {
            let final = base.unicodeScalars.last!.value
            forms.insert(base + ((final - 0xAC00) % 28 == 0 ? "라도" : "이라도"))
        }
        forms.formUnion(["밖에는", "뿐만", "뿐만은", "뿐만이라도"])
        forms.formUnion(["에선", "에겐", "한텐", "으론"])
        // 대화체의 '를요', '에서요', '에서부터는요'도 입력한 그대로 보존한다.
        // 조사 '뿐' 뒤의 서술 표현(뿐이요/뿐이에요)은 별도 활용형이다.
        forms.formUnion(forms.filter { $0 != "뿐" }.map { $0 + "요" })
        return forms
    }()

    private struct Ending {
        let text: String
        let keys: String
    }

    // 조사 규칙을 두벌식 키 패턴으로 한 번만 만든다. 매 키 입력에서는 호출하지 않는다.
    private static let endings: [Ending] = particles.sorted().compactMap { text in
        ManualToggle.hangulToKeys(text).map { Ending(text: text, keys: $0) }
    }

    struct Preview {
        let prefix: String
        let text: String
    }

    /// 완성된 조사에서 시작한 표시만 유효한 조사 연장 동안 유지한다.
    /// 확정은 split으로 다시 판단하며, 미완성 조사를 새 변환 규칙으로 인정하지 않는다.
    static func preview(keys: [Character], hangul: String,
                        personalDictionary: PersonalDictionary, previousPrefix: String?) -> Preview? {
        guard maySplit(keys: keys, hangul: hangul, personalDictionary: personalDictionary) else { return nil }
        switch split(keys: keys, hangul: hangul, personalDictionary: personalDictionary) {
        case .mixed(let text):
            return Preview(prefix: String(text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }), text: text)
        case .preserveHangul:
            return nil
        case nil:
            break
        }
        let typed = String(keys)
        guard let prefix = previousPrefix, typed.hasPrefix(prefix), keys.count > prefix.count,
              let prefixHangul = ManualToggle.keysToHangul(prefix) else { return nil }
        guard prefixDecision(prefix, hangul: prefixHangul, personalDictionary: personalDictionary) == .accept else {
            return nil
        }
        let suffix = String(typed.dropFirst(prefix.count))
        let matchingSuffix = String(suffix.map(canonicalParticleKey))
        guard endings.contains(where: { $0.keys.hasPrefix(matchingSuffix) }),
              let suffixHangul = ManualToggle.keysToHangul(suffix) else { return nil }
        return Preview(prefix: prefix, text: prefix + suffixHangul)
    }

    private static func maySplit(keys: [Character], hangul: String,
                                 personalDictionary: PersonalDictionary) -> Bool {
        guard keys.count >= 4, keys.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              KoreanDictionary.isLoaded else { return false }
        let typed = String(keys)
        return personalDictionary.decision(word: typed, hangul: hangul) == nil
            && !KoreanDictionary.contains(hangul)
            && !AlphanumericWords.contains(typed)
            && !EnglishDetector.isExplicitEnglishContextWord(typed.lowercased())
    }

    private enum PrefixDecision { case accept, reject, block }

    /// 숫자 접두어는 등록 제품명 또는 개인 사전 전체 일치만 허용한다.
    /// 일반 영어의 문맥/복합어 추론, 수량이나 임의 영숫자를 새 근거로 쓰지 않는다.
    private static func prefixDecision(_ prefix: String, hangul: String,
                                       personalDictionary: PersonalDictionary) -> PrefixDecision {
        let preference = personalDictionary.decision(word: prefix, hangul: hangul)
        if preference == .block { return .block }
        if prefix.contains(where: AlphanumericWords.isDigit) {
            // 기존 수량 경로와 같이 단위 금지는 개인 전체 추가보다 우선한다.
            if let quantity = MeasurementUnits.splitQuantity(prefix),
               personalDictionary.decision(word: quantity.unit,
                   hangul: String(hangul.dropFirst(quantity.amount.count))) == .block { return .block }
            guard prefix.contains(where: { $0.isASCII && $0.isLetter }),
                  preference == .forceConvert || AlphanumericWords.contains(prefix) else { return .reject }
            return .accept
        }
        if preference == .forceConvert { return .accept }
        // '내+가', '재가+에서'는 한글이다. 문맥이나 복합어 추론으로 우회하지 않는다.
        return !KoreanDictionary.contains(hangul)
            && EnglishDetector.shouldConvert(units: hangul.map(String.init), keys: Array(prefix)) ? .accept : .reject
    }

    static func split(keys: [Character], hangul: String,
                      personalDictionary: PersonalDictionary) -> Decision? {
        // 전체 항목의 개인 지정과 사전 일치는 기존 단어 판정에서 처리한다.
        guard maySplit(keys: keys, hangul: hangul, personalDictionary: personalDictionary) else { return nil }
        let typed = String(keys)

        // 조사 비교에만 같은 자모의 키를 통일한다. 영어 대소문자와 되돌릴 원문은 보존한다.
        let matchingKeys = String(keys.map(canonicalParticleKey))
        var outputs: Set<String> = []
        var containsBlockedPrefix = false
        for ending in endings where matchingKeys.hasSuffix(ending.keys) {
            let prefix = String(typed.dropLast(ending.keys.count))
            guard prefix.count >= 2,
                  let prefixHangul = ManualToggle.keysToHangul(prefix) else { continue }

            switch prefixDecision(prefix, hangul: prefixHangul, personalDictionary: personalDictionary) {
            case .block:
                containsBlockedPrefix = true
                continue
            case .reject:
                continue
            case .accept:
                outputs.insert(prefix + ending.text)
            }
        }

        // 금지 또는 복수 해석을 전체 영어 굴절형 추정이 다시 덮지 못하게 한다.
        if containsBlockedPrefix || outputs.count > 1 { return .preserveHangul }
        guard let only = outputs.first else { return nil }
        return .mixed(only)
    }

    /// 같은 자모를 만드는 Shift만 동등하게 취급한다. ㄲ·ㅒ·ㅖ 등은 구분한다.
    private static func canonicalParticleKey(_ key: Character) -> Character {
        let lower = Character(String(key).lowercased())
        switch (KeyboardLayout2Set.jamo(for: key), KeyboardLayout2Set.jamo(for: lower)) {
        case let (.consonant(original)?, .consonant(unshifted)?) where original == unshifted:
            return lower
        case let (.vowel(original)?, .vowel(unshifted)?) where original == unshifted:
            return lower
        default:
            return key
        }
    }
}

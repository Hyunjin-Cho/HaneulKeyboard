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
        let standalone: Set<String> = ["은", "는", "도", "만", "조차", "마저"]
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
        forms.formUnion(["에선", "에겐", "한텐", "으론"])
        // 대화체의 '를요', '에서요', '에서부터는요'도 입력한 그대로 보존한다.
        forms.formUnion(forms.map { $0 + "요" })
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
            return Preview(prefix: String(text.prefix { $0.isASCII && $0.isLetter }), text: text)
        case .preserveHangul:
            return nil
        case nil:
            break
        }
        let typed = String(keys)
        guard let prefix = previousPrefix, typed.hasPrefix(prefix), keys.count > prefix.count,
              let prefixHangul = ManualToggle.keysToHangul(prefix) else { return nil }
        let preference = personalDictionary.decision(word: prefix, hangul: prefixHangul)
        guard preference != .block else { return nil }
        if preference != .forceConvert {
            guard !KoreanDictionary.contains(prefixHangul),
                  EnglishDetector.shouldConvert(units: prefixHangul.map(String.init), keys: Array(prefix)) else { return nil }
        }
        let suffix = String(typed.dropFirst(prefix.count))
        let matchingSuffix = String(suffix.map(canonicalParticleKey))
        guard endings.contains(where: { $0.keys.hasPrefix(matchingSuffix) }),
              let suffixHangul = ManualToggle.keysToHangul(suffix) else { return nil }
        return Preview(prefix: prefix, text: prefix + suffixHangul)
    }

    private static func maySplit(keys: [Character], hangul: String,
                                 personalDictionary: PersonalDictionary) -> Bool {
        guard keys.count >= 4, keys.allSatisfy({ $0.isASCII && $0.isLetter }),
              KoreanDictionary.isLoaded else { return false }
        let typed = String(keys)
        return personalDictionary.decision(word: typed, hangul: hangul) == nil
            && !KoreanDictionary.contains(hangul)
            && !EnglishDetector.isExplicitEnglishContextWord(typed.lowercased())
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

            let preference = personalDictionary.decision(word: prefix, hangul: prefixHangul)
            if preference == .block {
                containsBlockedPrefix = true
                continue
            }
            if preference != .forceConvert {
                // '내+가', '재가+에서'는 한글이다. 문맥이나 복합어 추론으로 우회하지 않는다.
                guard !KoreanDictionary.contains(prefixHangul),
                      EnglishDetector.shouldConvert(units: prefixHangul.map(String.init),
                                                    keys: Array(prefix)) else { continue }
            }
            outputs.insert(prefix + ending.text)
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

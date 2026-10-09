// 2026-10-06. Offline preview data; reads the real core, never user preferences.
import Foundation

@main struct PreviewData {
    final class Sink: ComposerClient {
        var text = ""
        func insertText(_ text: String) { self.text += text }
        func setMarkedText(_ text: String) {}
    }
    static func main() throws {
        let paths = EnglishDetector.bundledWordlistNames.map { "Resources/IM/\($0).txt" }
        EnglishDetector.wordlistPaths = ["/usr/share/dict/words"] + paths
        EnglishDetector.curatedPaths = Set(EnglishDetector.curatedWordlistNames.map { "Resources/IM/\($0).txt" })
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        var layout: [String: [String: Any]] = [:]
        for ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            switch KeyboardLayout2Set.jamo(for: ch) {
            case .consonant(let c): layout[String(ch)] = ["kind":"c", "index":c.rawValue]
            case .vowel(let v): layout[String(ch)] = ["kind":"v", "index":v.rawValue]
            case nil: break
            }
        }
        var vowelPairs: [String: Int] = [:], finalPairs: [String: Int] = [:]
        for a in Vowel.allCases { for b in Vowel.allCases {
            if let c = Vowel.combine(a,b) { vowelPairs["\(a.rawValue),\(b.rawValue)"] = c.rawValue }
        }}
        for a in Consonant.allCases { for b in Consonant.allCases {
            if let c = CompoundFinal.index(first:a,second:b) { finalPairs["\(a.rawValue),\(b.rawValue)"] = c }
        }}
        var jamoKeys: [String: String] = [:]
        for n in 0x3131...0x3163 {
            let s = String(UnicodeScalar(n)!)
            if let keys = ManualToggle.hangulToKeys(s) { jamoKeys[s] = keys }
        }
        let finalChars = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map(String.init)
        let vowels = Vowel.allCases.map { String($0.compatibility) }
        let consonants = Consonant.allCases.map { String($0.compatibility) }
        var candidates = Set<String>()
        for path in ["Resources/IM/english_common.txt", "Resources/IM/english_supplement.txt"] {
            for line in try String(contentsOfFile:path,encoding:.utf8).split(separator:"\n") {
                let s = line.trimmingCharacters(in:.whitespacesAndNewlines)
                if !s.hasPrefix("#"), s.range(of:"^[A-Za-z]+$",options:.regularExpression) != nil, s.count <= 24 { candidates.insert(s) }
            }
        }
        candidates.formUnion(["apple","hello","tangerine","vismo","opencode","anti","cinestill","superia","velvia","camera","film","don't","i'm","T800","a24","a16z","a7r","banana","orange","lemon","canon","nikon","sony"])
        var autoWords: [String: String] = [:]
        for word in candidates.sorted() {
            let composer = KoreanComposer(), sink = Sink()
            for ch in word {
                if AlphanumericWords.isDigit(ch) {
                    if !composer.handleDigit(ch,client:sink) { composer.commit(to:sink,convertEnglish:true);sink.insertText(String(ch));composer.completeBoundary(ch) }
                } else if Contractions.isApostrophe(ch) {
                    if !composer.handleApostrophe(ch,client:sink) { composer.commit(to:sink,convertEnglish:true);sink.insertText(String(ch));composer.completeBoundary(ch) }
                } else { _ = composer.handleInput(String(ch),client:sink) }
            }
            composer.commit(to:sink,convertEnglish:true)
            if sink.text == word, let hangul = ManualToggle.keysToHangul(word) { autoWords[word] = hangul }
        }
        var fixtures = [[String]]()
        for n in 0xAC00...0xD7A3 {
            let hangul = String(UnicodeScalar(n)!), keys = ManualToggle.hangulToKeys(hangul)!
            fixtures.append([keys,ManualToggle.keysToHangul(keys)!,hangul])
        }
        for word in candidates.sorted() + ["gksrmf","dkssud","rkrk","rhkrtk","abc123","m5","xyz","ABC","don't","a16z","ㅏ3"] {
            if let hangul = ManualToggle.keysToHangul(word) { fixtures.append([word,hangul,ManualToggle.hangulToKeys(hangul) ?? ""]) }
        }
        let data: [String:Any] = ["layout":layout,"consonants":consonants,"vowels":vowels,"finalChars":finalChars,
            "finalIndices":Consonant.allCases.map { $0.finalIndex ?? -1 },"vowelPairs":vowelPairs,"finalPairs":finalPairs,
            "jamoKeys":jamoKeys,"autoWords":autoWords]
        try JSONSerialization.data(withJSONObject:data,options:[.sortedKeys]).write(to:URL(fileURLWithPath:"work/onboarding-preview/preview-data.json"))
        try JSONSerialization.data(withJSONObject:fixtures).write(to:URL(fileURLWithPath:".tmp/onboarding-icon/core-fixtures.json"))
        print("Exported \(autoWords.count) verified automatic words; \(fixtures.count) manual composition fixtures.")
    }
}

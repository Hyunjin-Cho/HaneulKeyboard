import Foundation

// 2026-10-14: 어휘 추가가 실제 조합기 경계/개인 사전/한국어 보호를 지키는지 검사한다.
// 독립 실행: python3 Tests/run_vocabulary_extension_tests.py
// 공통 ComposerTests/실행기에 의존하지 않으며 설치 앱·UserDefaults를 사용하지 않는다.
private final class VocabularyClient: ComposerClient {
    var inserted = ""
    var marked = ""
    func insertText(_ text: String) { inserted += text }
    func setMarkedText(_ text: String) { marked = text }
}

@main
private struct VocabularyExtensionTests {
    private static var passes = 0
    private static var failures = 0

    private static func expect(_ condition: Bool, _ label: String) {
        if condition { passes += 1 }
        else { failures += 1; print("FAIL: \(label)") }
    }

    private static func words(_ path: String) throws -> [String] {
        try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func type(_ keys: String, auto: Bool = true, active: Bool = true,
                             personal: PersonalDictionary = .empty,
                             previousEnglish: String? = nil) -> (String, KoreanComposer) {
        let client = VocabularyClient()
        let composer = KoreanComposer()
        composer.autoEnglishEnabled = auto
        composer.personalDictionary = personal
        if let previousEnglish {
            for key in previousEnglish { _ = composer.handleInput(String(key), client: client) }
            composer.commit(to: client, convertEnglish: true)
            expect(client.inserted == previousEnglish && composer.lastEnglishWord == previousEnglish,
                   "실제 앞 단어 확정으로 영어 문맥 생성: \(previousEnglish)")
            client.inserted = ""
            composer.completeBoundary(" ")
        }
        for key in keys { _ = composer.handleInput(String(key), client: client) }
        let returned = composer.commit(to: client, convertEnglish: active)
        expect(returned == client.inserted, "반환/실제 삽입 일치: \(keys)")
        expect(client.marked.isEmpty, "확정 뒤 미완성 글자 없음: \(keys)")
        return (client.inserted, composer)
    }

    static func main() throws {
        let manifest = try words("dict_work/dict_manifest.tsv")
        var paths = ["/usr/share/dict/words"]
        var curated = Set<String>()
        for line in manifest {
            let fields = line.split(separator: "\t").map(String.init)
            let path = "Resources/IM/\(fields[0]).txt"
            paths.append(path)
            if fields[1] == "curated" { curated.insert(path) }
        }
        EnglishDetector.wordlistPaths = paths
        EnglishDetector.curatedPaths = curated
        KoreanDictionary.wordlistPath = "Resources/IM/korean_words.txt"
        expect(KoreanDictionary.isLoaded, "실제 한국어 보호 사전 온전한 로드")

        let additions = try words("dict_work/2026-10-14-nature-camera-coverage.txt")
        expect(additions.count == 91 && Set(additions).count == 91, "출처 확인된 확장 표본 91개")
        for word in additions {
            let original = type(word, auto: false).0
            expect(original != word, "OFF는 조합한 글자 그대로: \(word)")
            let converted = type(word)
            expect(converted.0 == word, "활성 경계에서 정확한 입력 철자 변환: \(word)")
            expect(converted.1.lastConversion?.hangul == original,
                   "되돌릴 원래 글자 보존: \(word)")
            expect(converted.1.lastConversion?.english == word,
                   "되돌릴 영어 철자 보존: \(word)")
            expect(type(word, active: false).0 == original, "수동 경계에서 변환 금지: \(word)")
            expect(type(word, personal: PersonalDictionary(force: [word], block: [word])).0 == original,
                   "같이 등록해도 변환 금지 우선: \(word)")
            expect(type(word, personal: PersonalDictionary(block: [original])).0 == original,
                   "한글 표기 금지 우선: \(word)")
            expect(ManualToggle.manualToggle(word: word) == original,
                   "수동 영어→한글 되돌리기는 원래 표기: \(word)")
        }

        let originals = try words("dict_work/2026-10-06-nature-film-coverage.txt")
        expect(originals.count == 201, "기존 범주 표본 201개 유지")
        for word in originals {
            expect(type(word).0 == word, "기존 201 표본 회귀: \(word)")
        }

        // #74 본문의 명시 예시 후속8개: broad만으로 도달하며 한국어 보호를 우회하지 않는다.
        let originalExamples = ["contax", "summicron", "remjet", "microcontrast", "filmomat",
                                "zwilling", "lecreuset", "locknlock"]
        for word in originalExamples {
            let original = type(word, auto: false).0
            expect(!KoreanDictionary.contains(original), "추가 예시 전체 한글형 veto 충돌 없음: \(word)")
            expect(original.unicodeScalars.contains { (0x3131...0x3163).contains($0.value) },
                   "추가 예시는 깨진 한글형: \(word)")
            for context in ["the", "want"] {
                expect(type(word, previousEnglish: context).0 == word,
                       "기존 명시 예시의 실제 영어 문맥 변환: \(context) \(word)")
                expect(type(word, personal: PersonalDictionary(force: [word], block: [original]),
                            previousEnglish: context).0 == original,
                       "문맥에서도 한글형 금지가 force보다 우선: \(context) \(word)")
            }
        }
        for hangul in ["문채", "학교", "쟤가", "노래가"] {
            let keys = ManualToggle.hangulToKeys(hangul)!
            for context in ["the", "want"] {
                expect(type(keys, previousEnglish: context).0 == hangul,
                       "기존 명시 예시 보강 뒤 영어 문맥의 한국어 보호: \(context) \(hangul)")
            }
        }

        let protected = ["책", "하늘", "학교", "한국", "안녕", "선물", "힘찬", "모든",
                         "사과", "바나나", "도움", "오류", "거북이", "산호", "영화", "카메라",
                         "겨울", "앞으로", "ㅇㅇ", "ㄴㄴ", "ㄱㄱ", "ㅠㅠ", "ㅋㅋㅋ", "ㅡㅁㅡ",
                         "ㅗㅜㅑ", "니뮤", "니뮤ㅠ", "책이", "노래가", "오래가"]
        for hangul in protected {
            guard let keys = ManualToggle.manualToggle(word: hangul) else {
                expect(false, "보호 표본 역매핑: \(hangul)"); continue
            }
            // 낱자모 역매핑은 순차 입력 때 재조합될 수 있다(ㅡㅁㅡ → ㅡ므).
            // 실제 화면에 조합된 글자를 변환 전/후로 비교한다.
            let displayed = type(keys, auto: false).0
            expect(type(keys).0 == displayed, "한국어/반복/얼굴 자모 보호: \(hangul)")
        }
        expect(!EnglishDetector.shouldConvert(units: ["ㅡ", "ㅁ", "ㅡ"], keys: Array("mam")),
               "분리된 얼굴 자모도 실제 판정기가 보호")
        for typo in ["aplle", "applle", "qvzxcam"] {
            let displayed = type(typo, auto: false).0
            expect(type(typo).0 == displayed, "미등록 오타를 사전 보강으로 변환하지 않음: \(typo)")
            for context in ["the", "want"] {
                expect(type(typo, previousEnglish: context).0 == displayed,
                       "문맥에서도 미등록 오타 그대로 유지: \(context) \(typo)")
            }
        }
        expect(type("www").0 == type("www", auto: false).0, "www는 반복 자모 보호 유지")
        expect(!EnglishDetector.shouldConvert(units: ["ㅈ", "ㅈ", "ㅈ"], keys: Array("www"),
                                             previousEnglishWord: "hello"),
               "www는 영어 문맥에서도 반복키 관문 보호")
        print("\(passes) passed, \(failures) failed (vocabulary extension)")
        if failures > 0 { exit(1) }
    }
}

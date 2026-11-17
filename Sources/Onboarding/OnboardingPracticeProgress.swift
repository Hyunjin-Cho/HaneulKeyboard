import Foundation

/// 읽기 전용 관찰 결과만 안내에 전달한다. 실제 텍스트를 생성하거나 IME에 되돌려 쓰지 않는다.
enum OnboardingPracticeStage: Equatable {
    case empty, composing, readyToCommit, english, converted, reverted, other
}

struct OnboardingPracticeProgress {
    private struct Pair {
        let hangul: String
        let english: String
    }
    private var pending: Pair?
    private var pendingPhonetic: Pair?
    private var lastPair: Pair?
    private let dictionary: PhoneticDictionary
    private(set) var stage: OnboardingPracticeStage = .empty

    init(dictionary: PhoneticDictionary = .bundled) { self.dictionary = dictionary }

    mutating func reset() {
        pending = nil
        pendingPhonetic = nil
        lastPair = nil
        stage = .empty
    }

    mutating func finishEditingBatch() {
        // 한 이벤트 안의 marked-text 비우기→영어 삽입은 허용하되, 실제로 칸을 지운 뒤의
        // 다음 입력/붙여넣기까지 이전 변환 증거를 가져가지 않는다.
        if stage == .empty { reset() }
    }

    mutating func observe(text: String, hasMarkedText: Bool, markedRange: NSRange? = nil) -> OnboardingPracticeStage {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasMarkedText {
            // NSTextView의 실제 조합 범위만 역산한다. 앞에 이미 쓴 문장이 있어도
            // 그 부분까지 영어 키열로 바꾸거나 성공으로 추정하지 않는다.
            let document = text as NSString
            let range = markedRange ?? NSRange(location: 0, length: document.length)
            pending = nil
            pendingPhonetic = nil
            if range.location != NSNotFound, range.location <= document.length,
               range.length <= document.length - range.location,
               let english = ManualToggle.hangulToKeys(document.substring(with: range)) {
                pending = Pair(hangul: word, english: document.replacingCharacters(in: range, with: english)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                if let english = dictionary.english(for: document.substring(with: range)) {
                    pendingPhonetic = Pair(hangul: word, english: document.replacingCharacters(in: range, with: english)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            lastPair = nil
            stage = pending != nil && range.length > 1 ? .readyToCommit : .composing
        } else if let pair = [pending, pendingPhonetic].compactMap({ $0 }).first(where: { Self.sameLetters(word, $0.english) }) {
            // 2026-11-13 (#227, 리뷰 app-ui-F-1): 조합 중 글자(메ㅔㅣㄷ)를 키열로 되돌리면 대소문자를 알 수 없다(A·a 둘 다 ㅁ).
            // 입력기는 친 그대로(Apple·APPLE) 내보내므로 글자가 같고 대소문자만 다르면 성공이다. 예전엔 소문자 기대값(apple)과
            // 정확히 같아야 해서 Apple·Camera 성공을 "영어가 입력됐어요(직접 친 영어)"로 알렸다.
            // 왕복(Shift+Space) 비교에 쓰도록 기대값이 아니라 실제로 확정된 글자를 기억한다.
            stage = .converted
            lastPair = Pair(hangul: pair.hangul, english: word)
            pending = nil
            pendingPhonetic = nil
        } else if let pair = lastPair, word == pair.hangul {
            stage = .reverted
            pending = nil
            pendingPhonetic = nil
        } else if let pair = lastPair, word == pair.english {
            stage = stage == .converted || stage == .reverted ? .converted : .english
            pending = nil
            pendingPhonetic = nil
        } else if word.isEmpty {
            stage = .empty
            // IME가 marked text를 비운 직후 영어를 삽입할 수 있어 변환 증거는 여기서 지우지 않는다.
        } else {
            pending = nil
            pendingPhonetic = nil
            lastPair = nil
            if let hangul = ManualToggle.keysToHangul(word) {
                // 직접 영문 입력/붙여넣기는 성공이 아니다. 이후 수동 왕복만 관찰한다.
                stage = .english
                lastPair = Pair(hangul: hangul, english: word)
            } else {
                stage = word == "메ㅔㅣㄷ" ? .readyToCommit : .other
                if let english = dictionary.english(for: word) {
                    pendingPhonetic = Pair(hangul: word, english: english)
                }
            }
        }
        return stage
    }

    /// 대소문자만 다른 같은 글자인가. 조합 중 글자에서 만든 기대값과 실제 확정 글자를 비교할 때만 쓴다.
    private static func sameLetters(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .literal]) == .orderedSame
    }
}

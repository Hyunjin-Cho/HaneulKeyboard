import Foundation

/// 읽기 전용 관찰 결과만 안내에 전달한다. 실제 텍스트를 생성하거나 IME에 되돌려 쓰지 않는다.
enum OnboardingPracticeStage: Equatable {
    case empty, composing, readyToCommit, english, converted, reverted, other
}

struct OnboardingPracticeProgress {
    private var sawMarkedExample = false
    private var lastCommitted = ""
    private(set) var stage: OnboardingPracticeStage = .empty

    mutating func reset() {
        sawMarkedExample = false
        lastCommitted = ""
        stage = .empty
    }

    mutating func finishEditingBatch() {
        // 한 이벤트 안의 marked-text 비우기→영어 삽입은 허용하되, 실제로 칸을 지운 뒤의
        // 다음 입력/붙여넣기까지 이전 변환 증거를 가져가지 않는다.
        if stage == .empty { reset() }
    }

    mutating func observe(text: String, hasMarkedText: Bool) -> OnboardingPracticeStage {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasMarkedText {
            if word == "메ㅔㅣㄷ" { sawMarkedExample = true }
            else if !word.isEmpty { sawMarkedExample = false }
            stage = word == "메ㅔㅣㄷ" ? .readyToCommit : .composing
        } else if word.lowercased() == "apple" {
            // 영문을 바로 입력/붙여넣기한 경우는 자동 변환 성공으로 표시하지 않는다.
            stage = sawMarkedExample || stage == .converted ? .converted : .english
            lastCommitted = "apple"
            sawMarkedExample = false
        } else if word == "메ㅔㅣㄷ" {
            stage = lastCommitted == "apple" || stage == .reverted ? .reverted : .readyToCommit
            lastCommitted = word
        } else if word.isEmpty {
            stage = .empty
            // IME가 marked text를 비운 직후 영어를 삽입할 수 있어 변환 증거는 여기서 지우지 않는다.
        } else {
            stage = .other
            sawMarkedExample = false
            lastCommitted = word
        }
        return stage
    }
}

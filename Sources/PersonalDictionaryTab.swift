import SwiftUI

/// 설정 → 「개인 사전」 탭. (2026-09-21, #60)
///
/// "**어떤 단어**를 바꾸고 안 바꾸나"를 모았다. 절 두 개:
///   1. 개인 사전 — 변환 추가 / 변환 금지 / 최근 되돌림 (`PersonalDictionarySettingsSection`,
///      세그먼트로 한 번에 하나만 보인다)
///   2. 단어 제안 — 모두의 사전에 반영할 제안. 종전에는 입력 폼이 설정 화면에 펼쳐져 있었는데,
///      긴 폼이 탭 높이를 혼자 잡아먹어 **시트**로 뺐다(버튼 문구의 `...`이 "창이 하나 더 뜬다"는
///      macOS 신호다).
struct PersonalDictionaryTab: View {
    @State private var showingSuggestionSheet = false

    var body: some View {
        Form {
            // 2026-09-21 (#53): 개인 사전 — 본문은 PersonalDictionarySettingsSection.swift.
            PersonalDictionarySettingsSection()

            Section("단어 제안") {
                Text("모두의 사전에 반영할 단어를 알려 주세요. 이 기기에서만 고치려면 위의 개인 사전을 쓰세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("단어 제안하기...") { showingSuggestionSheet = true }
                }
            }
        }
        .formStyle(.grouped)
        // 2026-09-21 (#55·#60): 제안 폼은 시트 본문(WordSuggestionSettingsSection.swift)이다.
        .sheet(isPresented: $showingSuggestionSheet) {
            WordSuggestionSettingsSection()
        }
    }
}

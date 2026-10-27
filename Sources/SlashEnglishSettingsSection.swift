import SwiftUI

/// #87 · 2026-10-12: IME와 저장 키·기본값을 공유하는 독립 입력 기능.
struct SlashEnglishSettingsSection: View {
    // 저장 도메인은 EnglishConversionSettingsTab.imeDefaults 주석 참조.
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")
    @State private var enabled = SlashEnglishSettingsSection.imeDefaults.map { SlashEnglishSession.isEnabled(in: $0) }
        ?? SlashEnglishSession.defaultEnabled

    var body: some View {
        HaneulSettingsSection("슬래시 영어 입력") {
            Toggle("슬래시(/) 뒤 영어 입력", isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    Self.imeDefaults?.set(value, forKey: SlashEnglishSession.defaultsKey)
                }
            Text("한글 모드에서 /를 치면 이어지는 글자가 영어로 바로 입력됩니다. 일반 Space, 슬래시 삭제 또는 닫는 괄호 ) ] } 뒤에는 한글 입력으로 돌아옵니다. 예: /help")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
            Text("영타 자동 변환과 앱별 자동 변환 설정에 관계없이 동작합니다.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        }
    }
}

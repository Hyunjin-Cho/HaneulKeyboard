import SwiftUI

/// #87 · 2026-10-12: IME와 저장 키·기본값을 공유하는 독립 입력 기능.
struct SlashEnglishSettingsSection: View {
    // 저장 도메인은 EnglishConversionSettingsTab.imeDefaults 주석 참조.
    private static let imeDefaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)
    @State private var enabled = SlashEnglishSettingsSection.imeDefaults.map { SlashEnglishSession.isEnabled(in: $0) }
        ?? SlashEnglishSession.defaultEnabled

    var body: some View {
        HaneulSettingsSection("슬래시 영어 입력") {
            SettingsToggleRow(title: "슬래시(/) 뒤는 바로 영어로",
                detail: "한글 모드에서 /help를 치면 / 뒤의 글자가 바로 영어로 나와요. Space나 Return을 누르거나, /를 지우거나, 닫는 괄호 ) ] }를 치면 다시 한글로 돌아와요. 자동 변환을 꺼 둔 앱에서도 동작해요. 글 속의 /도 똑같으니, 글에 /를 자주 쓴다면 꺼 주세요.",
                isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    Self.imeDefaults?.set(value, forKey: SlashEnglishSession.defaultsKey)
                }
        }
    }
}

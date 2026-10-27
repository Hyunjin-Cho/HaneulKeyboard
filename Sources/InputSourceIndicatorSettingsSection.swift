import SwiftUI

/// #81 · 2026-10-12: 메인 앱에서만 표시하므로 메인 앱의 설정 도메인을 쓴다.
struct InputSourceIndicatorSettingsSection: View {
    @AppStorage(InputSourceTransitionPolicy.defaultsKey)
    private var enabled = InputSourceTransitionPolicy.defaultEnabled

    var body: some View {
        HaneulSettingsSection("한영 전환 안내") {
            Toggle("하늘 입력기로 전환할 때 안내 표시", isOn: $enabled)
                .onChange(of: enabled) { _, _ in
                    NotificationCenter.default.post(name: .haneulInputSourceIndicatorPreferencesChanged, object: nil)
                }
            Text("Caps Lock 등으로 하늘 입력기로 바꾸면 화면 위에 ‘하늘’을 잠깐 보여줍니다. 하늘키보드 앱이 실행 중일 때 표시됩니다.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)
        }
    }
}

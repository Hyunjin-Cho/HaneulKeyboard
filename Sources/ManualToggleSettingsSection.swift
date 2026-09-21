import SwiftUI

/// 설정 → "모든 단어 되돌리기" 절. (#15, 2026-09-21)
///
/// `SettingsView`의 `RevertKeySettingsSection()` 바로 뒤에 붙는다. 본문을 이 파일로 뺀 이유는
/// #54·#53 절과 같다 — 같은 시기에 여러 절이 `SettingsView.swift`에 들어와 충돌 면을 줄이려고.
///
/// 저장 키·기본값은 IME와 공유하는 `IMESources/RevertKey.swift`가 단일 진실이고, 여기는
/// 화면과 defaults 쓰기만 한다. 실제 변환 로직은 IME 전용 `IMESources/ManualToggle.swift`에 있다.
struct ManualToggleSettingsSection: View {
    /// IME 도메인 — `SettingsView.imeDefaults`와 같은 이유로 `UserDefaults.standard`가 아니다
    /// (IME 헬퍼는 자기 도메인 `com.hyunjincho.inputmethod.haneul`만 읽는다).
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var enabled: Bool =
        ManualToggleSettingsSection.imeDefaults?
            .object(forKey: RevertKey.manualToggleAllWordsKey) as? Bool
            ?? RevertKey.manualToggleAllWordsDefault

    var body: some View {
        Section("모든 단어 되돌리기") {
            Toggle("자동으로 바뀌지 않은 단어도 되돌리기", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    Self.imeDefaults?.set(newValue, forKey: RevertKey.manualToggleAllWordsKey)
                }
            Text("자동으로 바뀌지 않은 단어도 되돌리기 키로 한↔영 바꿉니다. 예: 재가 ↔ work, ㅡ5 ↔ m5. 터미널에서는 동작하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

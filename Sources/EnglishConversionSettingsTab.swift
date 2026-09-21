import SwiftUI

/// 설정 → 「영타 변환」 탭. (2026-09-21, #60)
///
/// "자동 변환이 **언제·어떻게** 동작하나"만 모은 탭이다. 절 세 개:
///   1. 자동 변환 — 전역 토글(C09·C10, 종전 `SettingsView`의 `Section("입력")`)
///   2. 되돌리기 — 되돌리기 키 + 바뀌지 않은 단어도 되돌리기 (`RevertKeySettingsSection`)
///   3. 앱별 자동 변환 끄기 (`RevertKeySettingsSection`)
struct EnglishConversionSettingsTab: View {
    /// IME 헬퍼는 자기 프로세스의 defaults 도메인(`com.hyunjincho.inputmethod.haneul`)만 읽는다.
    /// `UserDefaults.standard`로 쓰면 메인 앱 도메인에 들어가 IME는 영영 보지 못한다.
    /// **이 주석이 설정 화면 전체의 `imeDefaults` 설명 정본이다** — 다른 절 파일들이 여기를 가리킨다.
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var autoEnglishEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults?
            .object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true

    var body: some View {
        Form {
            Section("자동 변환") {
                Toggle("영타 자동 변환", isOn: $autoEnglishEnabled)
                    .onChange(of: autoEnglishEnabled) { _, newValue in
                        Self.imeDefaults?.set(newValue, forKey: "haneul.autoEnglishEnabled")
                    }
                Text("한글 모드에서 영어를 치면(메ㅔㅣㄷ) 스페이스를 누를 때 영어(apple)로 바꿉니다. 올바른 한글은 그대로 둡니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 2026-09-21 (#54·#15): 되돌리기 키 + 바뀌지 않은 단어도 되돌리기 + 앱별 끄기.
            // 본문은 RevertKeySettingsSection.swift (Section 두 개를 돌려준다).
            RevertKeySettingsSection()
        }
        .formStyle(.grouped)
    }
}

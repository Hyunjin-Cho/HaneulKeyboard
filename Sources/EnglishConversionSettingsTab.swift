import SwiftUI

/// 2026-11-07 오너(#189): 「입력 기능」을 왼쪽 메뉴 둘로 나눴다(#88의 미결 선택). 이 화면이 「자동 변환」이다.
/// 세 토글을 제목 없이 첫 카드에 모으고 앱별 끄기를 그 아래에 둔다. 스크롤 없이 한 화면에 들어간다.
struct EnglishConversionSettingsTab: View {
    /// IME 헬퍼는 자기 프로세스의 defaults 도메인(`com.hyunjincho.inputmethod.haneul`)만 읽는다.
    /// `UserDefaults.standard`로 쓰면 메인 앱 도메인에 들어가 IME는 영영 보지 못한다.
    /// **이 주석이 설정 화면 전체의 `imeDefaults` 설명 정본이다** — 다른 절 파일들이 여기를 가리킨다.
    private static let imeDefaults = UserDefaults(suiteName: IMEInstaller.imeBundleID)

    @State private var autoEnglishEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults?
            .object(forKey: HaneulDefaultsKey.autoEnglishEnabled) as? Bool ?? true
    @State private var externalEnglishContextEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults.map { InputInferencePolicy.externalEnglishContextEnabled(in: $0) }
            ?? InputInferencePolicy.externalEnglishContextDefault
    @State private var dictionaryCompoundEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults.map { InputInferencePolicy.dictionaryCompoundEnabled(in: $0) }
            ?? InputInferencePolicy.dictionaryCompoundDefault

    // 2026-11-08 오너(#201): 설명은 그 기능이 무엇을 하는지만 짧게 말한다. 끄라고 권하거나 세부 조건을 늘어놓지 않는다.
    // 예시는 줄 끝에서 쪼개지지 않게 붙임표 없는 공백(U+00A0)으로 묶는다.
    var body: some View {
        Form {
            HaneulSettingsSection {
                SettingsToggleRow(title: "영어 자동 변환",
                    detail: "한글 모드에서 영어 단어를 치면 Space를 누를 때 영어로 바꿔요. 예: ㅠ무뭄 → banana",
                    isOn: $autoEnglishEnabled)
                    .onChange(of: autoEnglishEnabled) { _, newValue in
                        Self.imeDefaults?.set(newValue, forKey: HaneulDefaultsKey.autoEnglishEnabled)
                    }
                // 2026-11-08 오너(#209): 'ABC로 친'은 입력 소스 이름이라 헷갈린다 → '영타로 친'.
                SettingsToggleRow(title: "영타로 친 영어 뒤에 이어 칠 때",
                    detail: "영타로 친 영어 바로 뒤에서는 한글로도 읽히는 짧은 영어까지 바꿔요. 예:\u{00A0}want\u{00A0}새\u{00A0}→\u{00A0}want\u{00A0}to",
                    isOn: $externalEnglishContextEnabled)
                    .onChange(of: externalEnglishContextEnabled) { _, value in
                        Self.imeDefaults?.set(value, forKey: InputInferencePolicy.externalEnglishContextKey)
                    }
                SettingsToggleRow(title: "영어 단어 두 개를 붙여 쳤을 때",
                    detail: "helloworld처럼 영어 단어 두 개를 붙여 쳐도 바꿔요. 두 단어 모두 네 글자 이상이어야 해요.",
                    isOn: $dictionaryCompoundEnabled)
                    .onChange(of: dictionaryCompoundEnabled) { _, value in
                        Self.imeDefaults?.set(value, forKey: InputInferencePolicy.dictionaryCompoundKey)
                    }
            }
            AppAutoConversionSettingsSection()
        }
        .formStyle(.grouped)
    }
}

/// 2026-11-07 오너(#189): 왼쪽 메뉴 「단축키·슬래시」.
struct ShortcutSettingsTab: View {
    var body: some View {
        Form {
            RevertKeySettingsSection()
            SlashEnglishSettingsSection()
        }
        .formStyle(.grouped)
    }
}

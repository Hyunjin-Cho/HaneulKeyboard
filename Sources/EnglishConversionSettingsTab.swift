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

    var body: some View {
        Form {
            HaneulSettingsSection {
                SettingsToggleRow(title: "영어 자동 변환",
                    detail: "한글 모드에서 banana를 치면 화면에 ㅠ무뭄으로 보여요. Space를 누르면 banana로 바뀌어요. 한글 단어는 되도록 그대로 두고, 틀린 철자(aplle)는 고치지 않아요.",
                    isOn: $autoEnglishEnabled)
                    .onChange(of: autoEnglishEnabled) { _, newValue in
                        Self.imeDefaults?.set(newValue, forKey: HaneulDefaultsKey.autoEnglishEnabled)
                    }
                SettingsToggleRow(title: "ABC로 친 영어 뒤에 이어 칠 때",
                    detail: "ABC로 I를 치고 Space를 누른 뒤, 한글 모드에서 새를 치면 to로 바꿔요. 커서 앞 글자를 잠깐 읽어 바로 앞 영어 단어를 확인하고, 저장하지 않아요.",
                    isOn: $externalEnglishContextEnabled)
                    .onChange(of: externalEnglishContextEnabled) { _, value in
                        Self.imeDefaults?.set(value, forKey: InputInferencePolicy.externalEnglishContextKey)
                    }
                SettingsToggleRow(title: "영어 단어 두 개를 붙여 쳤을 때",
                    detail: "helloworld처럼 사전에 있는 영어 단어 두 개를 띄지 않고 쳐도 바꿔요. 두 단어 모두 네 글자 이상이어야 하고, 철자가 틀리면 그대로 둬요. 바꾼 설정은 다음 단어부터 적용돼요.",
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

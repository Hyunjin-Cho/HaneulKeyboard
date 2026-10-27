import SwiftUI

/// 2026-10-11 (#88): 「입력 기능」의 자동 변환과 수동 변환 설정.
///
/// 자동 변환과 단축키 변환을 두 페이지로 나누고, 현재 페이지의 제어만 화면과 접근성에 노출한다.
struct EnglishConversionSettingsTab: View {
    enum Page: String, CaseIterable, Identifiable {
        case automatic = "자동 변환"
        case shortcuts = "단축키 변환"
        var id: Self { self }
    }

    /// IME 헬퍼는 자기 프로세스의 defaults 도메인(`com.hyunjincho.inputmethod.haneul`)만 읽는다.
    /// `UserDefaults.standard`로 쓰면 메인 앱 도메인에 들어가 IME는 영영 보지 못한다.
    /// **이 주석이 설정 화면 전체의 `imeDefaults` 설명 정본이다** — 다른 절 파일들이 여기를 가리킨다.
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var autoEnglishEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults?
            .object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
    @State private var externalEnglishContextEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults.map { InputInferencePolicy.externalEnglishContextEnabled(in: $0) }
            ?? InputInferencePolicy.externalEnglishContextDefault
    @State private var dictionaryCompoundEnabled: Bool =
        EnglishConversionSettingsTab.imeDefaults.map { InputInferencePolicy.dictionaryCompoundEnabled(in: $0) }
            ?? InputInferencePolicy.dictionaryCompoundDefault
    @State private var selectedPage: Page

    /// 2026-10-14: 화면 검사도 제품과 같은 두 페이지를 사용한다. 앱 기본 페이지는 자동 변환이다.
    init(initialPage: Page = .automatic) {
        _selectedPage = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("입력 기능 화면", selection: $selectedPage) {
                ForEach(Page.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("입력 기능 화면 선택")
            .font(SettingsTypography.control)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Form {
                if selectedPage == .automatic {
                    HaneulSettingsSection("자동 변환") {
                        Toggle("영타 자동 변환", isOn: $autoEnglishEnabled)
                            .onChange(of: autoEnglishEnabled) { _, newValue in
                                Self.imeDefaults?.set(newValue, forKey: "haneul.autoEnglishEnabled")
                            }
                        Text("한글 모드에서 영문 자판으로 잘못 친 글자(ㅠ무뭄)를 Space나 문장부호로 끝낼 때 영어(banana)로 바꿉니다. 올바른 한글과 사전에 없는 영어 철자는 그대로 둡니다.")
                            .font(SettingsTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    HaneulSettingsSection("자동 변환 범위") {
                        Toggle("다른 입력기로 친 영어 문맥 사용", isOn: $externalEnglishContextEnabled)
                            .onChange(of: externalEnglishContextEnabled) { _, value in
                                Self.imeDefaults?.set(value, forKey: InputInferencePolicy.externalEnglishContextKey)
                            }
                        Text("ABC 등에서 영어를 쓴 뒤에도 커서 앞의 영어 문맥을 함께 확인합니다. 확인에 쓰는 주변 글자는 저장하지 않습니다.")
                            .font(SettingsTypography.body)
                            .foregroundStyle(.secondary)
                        Toggle("등록 단어를 붙여 쓴 영어 인식", isOn: $dictionaryCompoundEnabled)
                            .onChange(of: dictionaryCompoundEnabled) { _, value in
                                Self.imeDefaults?.set(value, forKey: InputInferencePolicy.dictionaryCompoundKey)
                            }
                        Text("사전에 있는 영어 단어 두 개를 붙여 친 경우만 인식합니다. 각 단어는 네 글자 이상이어야 하며, 오타는 그대로 둡니다. 두 설정은 다음 단어부터 반영됩니다.")
                            .font(SettingsTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    AppAutoConversionSettingsSection()
                } else {
                    RevertKeySettingsSection()
                    SlashEnglishSettingsSection()
                }
            }
            .formStyle(.grouped)
            // 페이지마다 스크롤은 위에서 시작하고, 설정값은 기존 IME 도메인에서 유지한다.
            .id(selectedPage)
        }
    }
}

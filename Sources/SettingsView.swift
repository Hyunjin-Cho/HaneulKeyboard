import SwiftUI

struct SettingsView: View {
    @Bindable var core: AppCore
    @State private var installError: Error?
    @State private var showingUninstallConfirm = false
    @State private var uninstallResult: Uninstaller.Outcome?

    /// The IME helper runs as its own process with its own defaults domain
    /// (com.hyunjincho.inputmethod.haneul) — UserDefaults.standard here would
    /// write to the main app's domain and the IME would never see it.
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")
    @State private var autoEnglishEnabled: Bool =
        SettingsView.imeDefaults?.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
    @State private var predictionEnabled: Bool =
        SettingsView.imeDefaults?.object(forKey: "haneul.predictionEnabled") as? Bool ?? true
    @State private var showingClearDataConfirm = false
    @State private var didClearData = false

    var body: some View {
        Form {
            Section("한글 입력기 (IME)") {
                if core.imeInstalled {
                    Label("HaneulKeyboardIM 설치됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Caps Lock으로 한글/영어 모드를 전환합니다.")
                            .font(.subheadline.bold())
                        Text("짧게 누름 → 한글/영어 전환")
                        Text("길게 누름 (1초 이상) → Caps Lock LED 전환")
                    }
                    .font(.caption)

                    Text("정상적으로 설치됐다면, 시스템 입력 소스에서 기존 \"두벌식\"은 제거하세요. (자모 깨짐 방지)")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    HStack {
                        Button("입력 소스 설정 열기") {
                            IMEInstaller.openInputSourcesSettings()
                        }
                        Button("IME 제거", role: .destructive) {
                            do {
                                try IMEInstaller.uninstall()
                                core.refreshIMEStatus()
                            } catch {
                                installError = error
                            }
                        }
                    }
                } else {
                    Text("HaneulKeyboard 자체 한국어 입력기를 ~/Library/Input Methods/에 설치합니다. 설치 후 시스템 설정에서 입력 소스로 추가해야 합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let installError {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(installError.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Button("IME 설치") {
                        do {
                            try IMEInstaller.install()
                            core.refreshIMEStatus()
                            installError = nil
                        } catch {
                            installError = error
                        }
                    }
                }
            }

            Section("입력") {
                Toggle("영타 자동 변환", isOn: $autoEnglishEnabled)
                    .onChange(of: autoEnglishEnabled) { _, newValue in
                        Self.imeDefaults?.set(newValue, forKey: "haneul.autoEnglishEnabled")
                    }
                Text("한글 모드에서 영어 단어를 치면 (예: \"메ㅔㅣㄷ\") 스페이스를 누를 때 자동으로 영어(\"apple\")로 바꿔줍니다. 올바른 한글과 ㅋㅋㅋ 같은 자모는 건드리지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("예측 입력 (자동완성)", isOn: $predictionEnabled)
                    .onChange(of: predictionEnabled) { _, newValue in
                        Self.imeDefaults?.set(newValue, forKey: "haneul.predictionEnabled")
                    }
                Text("자주 쓰는 한글 단어를 학습해 커서 옆에 연하게 제안합니다. Tab으로 완성. 학습 데이터(한글 단어·빈도)는 이 기기 안에만 저장됩니다 — PRIVACY.md 참조.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("학습 데이터 삭제...", role: .destructive) {
                        showingClearDataConfirm = true
                    }
                    if didClearData {
                        Text("삭제됨")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("상태") {
                LabeledContent("현재 입력 모드") {
                    Text(core.isKoreanActive ? "한국어 (한)" : "영어 (A)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("전체 제거") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HaneulKeyboard와 관련된 모든 파일·설정을 정리합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("전체 제거...", role: .destructive) {
                            showingUninstallConfirm = true
                        }
                        Spacer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 600)
        .alert("학습 데이터를 삭제할까요?", isPresented: $showingClearDataConfirm) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                // 파일 삭제 + IME 프로세스의 메모리 사본은 다음 활성화 때
                // 이 플래그를 보고 비움 (HaneulInputController.activateServer).
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("HaneulKeyboard")
                try? FileManager.default.removeItem(at: dir)
                Self.imeDefaults?.set(true, forKey: "haneul.clearLearnedData")
                didClearData = true
            }
        } message: {
            Text("지금까지 학습한 한글 단어·빈도 기록을 모두 지웁니다. 예측 제안은 다시 처음부터 학습합니다.")
        }
        .alert("정말 제거하시겠어요?", isPresented: $showingUninstallConfirm) {
            Button("취소", role: .cancel) { }
            Button("제거", role: .destructive) {
                uninstallResult = Uninstaller.run()
                core.refreshIMEStatus()
            }
        } message: {
            Text("HaneulKeyboard의 IME 번들, LaunchServices 등록, 사용자 설정을 모두 지웁니다.")
        }
        .alert("제거 결과", isPresented: Binding(
            get: { uninstallResult != nil },
            set: { if !$0 { uninstallResult = nil } }
        )) {
            Button("확인", role: .cancel) {
                uninstallResult = nil
            }
            if uninstallResult?.stillEnabledInPicker == true {
                Button("시스템 설정 열기") {
                    IMEInstaller.openInputSourcesSettings()
                    uninstallResult = nil
                }
            }
        } message: {
            if let r = uninstallResult {
                let status = """
                IME 프로세스 종료: \(r.killedProcess ? "OK" : "—")
                번들 삭제: \(r.removedBundle ? "OK" : "실패")
                LaunchServices 등록 해제: \(r.unregisteredLS ? "OK" : "실패")
                사용자 설정 초기화: \(r.clearedUserDefaults ? "OK" : "실패")

                \(r.stillEnabledInPicker
                    ? "마지막 단계 — 시스템 설정 → 키보드 → 입력 소스에서 \"하늘키보드 (두벌식)\"을 \"-\" 로 제거하세요."
                    : "완료. 메인 앱(HaneulKeyboard.app)을 휴지통으로 이동해 주세요.")
                """
                Text(status)
            } else {
                Text("")
            }
        }
    }
}

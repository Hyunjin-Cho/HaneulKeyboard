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
        .alert("정말 제거하시겠어요?", isPresented: $showingUninstallConfirm) {
            Button("취소", role: .cancel) { }
            Button("제거", role: .destructive) {
                uninstallResult = Uninstaller.run()
                core.refreshIMEStatus()
            }
        } message: {
            Text("HaneulKeyboard의 메인 앱·IME 번들·LaunchServices 등록·사용자 설정·학습 데이터를 모두 지웁니다. 다시 쓰려면 재설치해야 합니다.")
        }
        .alert("제거 결과", isPresented: Binding(
            get: { uninstallResult != nil },
            set: { if !$0 { uninstallResult = nil } }
        )) {
            Button("확인", role: .cancel) {
                uninstallResult = nil
                // 전체 제거 후 앱 자신(메뉴바)도 종료 — 파일만 지우면 실행 중인
                // 프로세스가 남아 메뉴바가 그대로 보인다(#11).
                NSApp.terminate(nil)
            }
            if uninstallResult?.stillEnabledInPicker == true {
                Button("시스템 설정 열기") {
                    IMEInstaller.openInputSourcesSettings()
                    uninstallResult = nil
                    // 설정 창이 뜬 뒤 앱 종료(메뉴바 정리).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSApp.terminate(nil)
                    }
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
                    ? "마지막 단계 — 시스템 설정 → 키보드 → 입력 소스에서 \"하늘키보드 (두벌식)\"을 \"-\" 로 제거한 뒤 재부팅하세요."
                    : "완료. 메인 앱·IME·설정이 모두 삭제됐습니다. 입력 소스 목록을 완전히 비우려면 재부팅하세요.")
                """
                Text(status)
            } else {
                Text("")
            }
        }
    }
}

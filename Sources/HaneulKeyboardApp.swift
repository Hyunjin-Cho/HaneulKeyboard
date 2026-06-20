import SwiftUI
import AppKit

/// 메뉴바·IME 초기화보다 먼저(willFinishLaunching) 앱 위치를 점검 — 응용
/// 프로그램 폴더 밖이면 옮기도록 해 App Translocation으로 첫 실행에 메뉴바가
/// 안 뜨는 문제를 막는다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppMover.moveToApplicationsIfNeeded()
    }
}

@main
struct HaneulKeyboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var core = AppCore()
    @AppStorage("haneul.hasCompletedOnboarding") private var hasCompleted = false

    var body: some Scene {
        MenuBarExtra {
            HaneulMenu(core: core, hasCompleted: hasCompleted)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "character.bubble")
                Text(core.isKoreanActive ? "한" : "A")
                if !hasCompleted {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 6))
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Window("HaneulKeyboard 시작하기", id: "onboarding") {
            OnboardingView(core: core)
                .onAppear { NSApp.activate() }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(core: core)
        }
    }
}

private struct HaneulMenu: View {
    let core: AppCore
    let hasCompleted: Bool
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("HaneulKeyboard \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
        Text(core.isKoreanActive ? "현재: 한국어" : "현재: 영어")
            .font(.caption)

        Divider()

        if !hasCompleted {
            Button {
                openWindow(id: "onboarding")
            } label: {
                Label("시작하기...", systemImage: "sparkles")
            }
            Divider()
        }

        Button {
            core.toggleLanguage()
        } label: {
            Label(
                core.isKoreanActive ? "영어로 전환" : "한국어로 전환",
                systemImage: "arrow.left.arrow.right"
            )
        }

        if !core.imeInstalled {
            Text("한글 입력기(IME) 미설치 — 설정에서 설치 권장")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Divider()

        Button("설정...") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        if hasCompleted {
            Button("시작하기 다시 보기...") {
                openWindow(id: "onboarding")
            }
        }

        Button("HaneulKeyboard 종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

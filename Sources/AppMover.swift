import AppKit

/// 앱이 응용 프로그램 폴더 밖(압축 푼 위치·translocated 임시폴더)에서 실행되면
/// 사용자에게 묻고 /Applications로 옮긴 뒤 재실행한다.
///
/// macOS는 인터넷에서 받은(격리 속성) 앱을 Applications 밖에서 실행하면 읽기전용
/// 임시폴더로 복제해 돌리는데(App Translocation), 이 상태에서 메뉴바(MenuBarExtra)
/// 앱이 첫 실행에 status item을 못 그리는 문제가 있다. Applications로 옮기면
/// translocation이 풀려 항상 첫 실행에 정상 동작한다.
///
/// IME 보안: 외부 라이브러리(LetsMove 등) 없이 AppKit만으로 직접 구현 —
/// 의존성을 추가하지 않는다.
enum AppMover {
    static func moveToApplicationsIfNeeded() {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let appsDir = "/Applications"
        let destURL = URL(fileURLWithPath: appsDir, isDirectory: true)
            .appendingPathComponent(bundleURL.lastPathComponent)

        // 이미 /Applications에서 실행 중이면 아무것도 하지 않는다.
        guard !bundleURL.path.hasPrefix(appsDir + "/") else { return }

        let alert = NSAlert()
        alert.messageText = "HaneulKeyboard를 응용 프로그램 폴더로 옮길까요?"
        alert.informativeText = "압축을 푼 위치에서 바로 실행하면 macOS 보안 기능(앱 격리) 때문에 메뉴바 아이콘이 첫 실행에 안 뜰 수 있어요. 응용 프로그램 폴더로 옮기면 항상 안정적으로 작동합니다."
        alert.addButton(withTitle: "옮기고 다시 열기")
        alert.addButton(withTitle: "옮기지 않고 종료")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        // (#9) 옮기지 않으면 종료한다. translocated 상태로 메뉴바를 띄우면
        // "나중에"가 사실상 거절이 아니게 되어(시작하기 누르면 옮긴 것과 동일)
        // 사용자를 혼란시킨다 — 거절은 깔끔히 종료로 처리.
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: bundleURL, to: destURL)
            // (#12) 옮긴 뒤 원본을 정리 — 안 지우면 원본도 LaunchServices에
            // 등록돼 Launchpad에 중복으로 뜬다. 압축 푼 위치의 원본을 직접
            // 삭제한다. (앱이 translocated 임시본에서 실행된 경우엔 bundleURL이
            // 읽기전용 임시본이라 삭제가 실패할 수 있으나, 임시본은 OS가 자동
            // 정리하므로 무방 — try?로 무시.)
            if bundleURL.standardizedFileURL != destURL.standardizedFileURL {
                try? fm.removeItem(at: bundleURL)
            }
        } catch {
            let fail = NSAlert()
            fail.messageText = "옮기지 못했어요"
            fail.informativeText = "Finder에서 직접 응용 프로그램 폴더로 드래그해 주세요.\n(\(error.localizedDescription))"
            fail.alertStyle = .warning
            fail.runModal()
            return
        }

        // 옮긴 앱을 새 인스턴스로 실행하고, 현재(임시/원위치) 인스턴스는 종료.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

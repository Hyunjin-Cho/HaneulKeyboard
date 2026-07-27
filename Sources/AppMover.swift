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
    /// 메인 앱 bundle identifier — /Applications의 기존 항목이 "우리 앱"인지
    /// 판별하는 기준. (review-0712 P2-1)
    private static let mainAppBundleID = "com.hyunjincho.haneulkeyboard"

    static func moveToApplicationsIfNeeded() {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let appsDir = "/Applications"
        // (review-0712 P2-1) 목적지 파일명은 항상 고정이다. 예전엔 실행 중인
        // 번들의 파일명을 그대로 썼는데, 사용자가 받은 앱을 SomeApp.app으로
        // 바꿔 실행하면 /Applications/SomeApp.app(무관한 남의 앱)을 덮어썼다.
        let destURL = URL(fileURLWithPath: appsDir, isDirectory: true)
            .appendingPathComponent("HaneulKeyboard.app")

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
                // (review-0712 P2-1) 덮어쓰기 전에 목적지가 진짜 우리 앱인지
                // 확인한다. bundle ID가 다르거나 서명 Team이 다르면 남의 앱이므로
                // 절대 건드리지 않고 중단한다(빌드 번호만 보고 교체하던 예전
                // 로직은 무관한 앱의 데이터를 날릴 수 있었다).
                guard isOurApp(at: destURL) else {
                    let block = NSAlert()
                    block.messageText = "응용 프로그램 폴더에 다른 앱이 있어요"
                    block.informativeText = "\(destURL.path)이(가) HaneulKeyboard가 아닙니다. 안전을 위해 덮어쓰지 않고 중단했어요. 그 앱을 옮기거나 이름을 바꾼 뒤 다시 시도해 주세요."
                    block.alertStyle = .warning
                    block.runModal()
                    return
                }
                // (H-02) 다운그레이드 방지 — /Applications의 기존 설치본이 더
                // 최신(빌드 번호 큼)이면 확인받는다. 취소하면 기존 최신본을 열고
                // 현재(구버전) 인스턴스는 종료한다.
                if let existing = buildNumber(at: destURL),
                   let incoming = buildNumber(at: bundleURL),
                   incoming < existing {
                    let warn = NSAlert()
                    warn.messageText = "이미 더 최신 버전이 설치돼 있어요"
                    warn.informativeText = "응용 프로그램 폴더의 HaneulKeyboard가 지금 실행한 버전보다 최신입니다. 그래도 이 (구)버전으로 덮어쓸까요?"
                    warn.addButton(withTitle: "기존 최신 버전 열기")
                    warn.addButton(withTitle: "구버전으로 덮어쓰기")
                    warn.alertStyle = .warning
                    if warn.runModal() == .alertFirstButtonReturn {
                        let cfg = NSWorkspace.OpenConfiguration()
                        cfg.createsNewApplicationInstance = true
                        NSWorkspace.shared.openApplication(at: destURL, configuration: cfg) { _, _ in
                            DispatchQueue.main.async { NSApp.terminate(nil) }
                        }
                        return
                    }
                }
                // (H-02) 원자 교체 — 같은 볼륨(/Applications)에 staging으로 복사한
                // 뒤 replaceItemAt으로 한 번에 바꾼다. 복사 도중 디스크/IO 오류가
                // 나도 기존 설치본이 그대로 보존된다(예전엔 destURL을 먼저 지워서
                // 복사 실패 시 앱이 통째로 사라질 수 있었다 — H-02).
                let staging = destURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(destURL.lastPathComponent).staging-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: staging) }
                try fm.copyItem(at: bundleURL, to: staging)
                _ = try fm.replaceItemAt(destURL, withItemAt: staging)
            } else {
                // 첫 설치 — 교체할 기존본이 없으니 바로 복사.
                try fm.copyItem(at: bundleURL, to: destURL)
            }
            // (#12) 옮긴 뒤 원본을 정리 — 안 지우면 원본도 LaunchServices에
            // 등록돼 Launchpad에 중복으로 뜬다. (translocated 임시본은 읽기전용이라
            // 삭제 실패할 수 있으나 OS가 자동 정리하므로 무방 — try?로 무시.)
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
        NSWorkspace.shared.openApplication(at: destURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                // (L-03) 옮긴 앱 실행이 실패했는데 무조건 종료하면 메뉴바 앱이
                // 설명 없이 사라진다 — 에러를 알리고 현재 인스턴스는 유지한다.
                if let error {
                    let fail = NSAlert()
                    fail.messageText = "옮긴 앱을 여는 데 실패했어요"
                    fail.informativeText = "응용 프로그램 폴더의 HaneulKeyboard를 직접 실행해 주세요.\n(\(error.localizedDescription))"
                    fail.alertStyle = .warning
                    fail.runModal()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// (review-0712 P2-1) 목적지 번들이 우리 제품인가.
    /// ① bundle ID가 우리 것이고 ② (Release) 코드 서명이 유효하며 메인 앱과
    /// 같은 Team Identifier일 때만 true. 하나라도 어긋나면 남의 앱으로 보고
    /// 교체하지 않는다. Debug 빌드는 미서명이라 ②를 건너뛰지만(IMEInstaller와
    /// 같은 정책) ①은 그대로 적용된다.
    private static func isOurApp(at url: URL) -> Bool {
        guard Bundle(url: url)?.bundleIdentifier == mainAppBundleID else { return false }
        return IMEInstaller.isSameTeamSignedBundle(at: url)
    }

    /// 번들의 빌드 번호(CFBundleVersion, 단조증가 정수). 다운그레이드 판별용. (H-02)
    private static func buildNumber(at url: URL) -> Int? {
        guard let bundle = Bundle(url: url),
              let s = bundle.infoDictionary?["CFBundleVersion"] as? String,
              let n = Int(s) else { return nil }
        return n
    }
}

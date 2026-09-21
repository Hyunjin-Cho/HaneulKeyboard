import Cocoa
import InputMethodKit
import os.log

let connectionName = "com.hyunjincho.inputmethod.haneul_Connection"

// 2026-09-21 (#56): NSLog → os.Logger. macOS 26부터 NSLog 포맷 인자의 동적 문자열이 통합 로그에서
// `<private>`로 가려지고(26 릴리스 노트 137129180), #52 프로브(scripts/postinstall_probe.sh)가
// subsystem "com.hyunjincho.haneulkeyboard"의 error 건수를 세므로 IME의 다른 파일(category
// "ime"·"orphan")과 같은 subsystem으로 맞춘다. 번들 ID는 비밀이 아니라 .public.
private let serverLog = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "server")

NSApplication.shared.setActivationPolicy(.accessory)

guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
    serverLog.error("HaneulKeyboardIM: missing bundle identifier")
    exit(EXIT_FAILURE)
}

guard IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) != nil else {
    serverLog.error("HaneulKeyboardIM: failed to create IMKServer for \(bundleIdentifier, privacy: .public)")
    exit(EXIT_FAILURE)
}

// Warm the wordlists off the typing path (used by the wrong-layout
// auto-correction at word boundaries): English dict + 한국어 veto 사전.
EnglishDetector.preload()
KoreanDictionary.preload()
// 2026-09-19 (#32): 메인 앱이 지워진 채로 IME만 남았는지 기동 직후 한 번 확인(5초 뒤, 백그라운드).
OrphanWatcher.shared.scheduleInitialCheck()

NSApplication.shared.run()

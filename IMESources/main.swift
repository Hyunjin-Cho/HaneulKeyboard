import Cocoa
import InputMethodKit

let connectionName = "com.hyunjincho.inputmethod.haneul_Connection"

NSApplication.shared.setActivationPolicy(.accessory)

guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
    NSLog("HaneulKeyboardIM: missing bundle identifier")
    exit(EXIT_FAILURE)
}

guard IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) != nil else {
    NSLog("HaneulKeyboardIM: failed to create IMKServer for \(bundleIdentifier)")
    exit(EXIT_FAILURE)
}

// Warm the wordlists off the typing path (used by the wrong-layout
// auto-correction at word boundaries): English dict + 한국어 veto 사전.
EnglishDetector.preload()
KoreanDictionary.preload()
// 2026-09-19 (#32): 메인 앱이 지워진 채로 IME만 남았는지 기동 직후 한 번 확인(5초 뒤, 백그라운드).
OrphanWatcher.shared.scheduleInitialCheck()

NSApplication.shared.run()

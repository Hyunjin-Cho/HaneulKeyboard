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

NSApplication.shared.run()

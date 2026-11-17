import Foundation
import os.log

/// Dedicated unified-log subsystem so we can filter our messages out of the
/// firehose with `log show --predicate 'subsystem == "com.hyunjincho.haneulkeyboard"'`.
/// NSLog without an explicit subsystem ends up in a generic bucket and is hard
/// to find in modern macOS unified logging — `os_log` with our own subsystem
/// guarantees the messages survive in show/stream output even for LSUIElement
/// apps.
private let logger = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "main")

/// Lightweight wrapper that we use in place of `NSLog(...)` so we can grep
/// "HaneulKeyboard:" in stream output AND search by subsystem.
func haneulLog(_ message: String) {
    logger.log("\(message, privacy: .public)")
}

import Cocoa
import InputMethodKit

/// Ghost-text style suggestion: a chrome-less, non-activating panel floating
/// at the caret showing the faint-gray remainder of the predicted word.
///
/// Pattern follows the surveyed open-source IMEs (azooKey predictionWindow /
/// macSKK CompletionPanel / McBopomofo cursor walk — patterns only, no code
/// reuse):
///   - never query the client inside activateServer (Chromium deadlock)
///   - caret rect via attributes(forCharacterIndex:lineHeightRectangle:),
///     where the index is the CARET position inside the inline session
///     (the marked text's UTF-16 length) — index 0 would anchor at the
///     composition START and draw the ghost over the marked text. Clients
///     that can't answer the caret index get a McBopomofo-style backward
///     walk; if every index fails — hide, never guess
///   - window level = client windowLevel + 1 so it clears full-screen apps
///   - .nonactivatingPanel + ignoresMouseEvents: never steals focus, and
///     clicks on the ghost pass through to the app to move the caret
final class SuggestionPanel {
    private let panel: NSPanel
    private let label: NSTextField

    /// The full suggested word currently shown (nil = hidden). The
    /// controller consumes this on Tab.
    private(set) var suggestedWord: String?

    init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.ignoresMouseEvents = true
        panel.contentView = label
    }

    /// Shows `remainder` (the not-yet-typed tail of `fullWord`) at the
    /// caret. `caretIndex` is the UTF-16 length of the current marked text.
    /// Hides instead if the client cannot report any usable position.
    func show(fullWord: String, remainder: String, caretIndex: Int, client: IMKTextInput) {
        // Query at the caret; clients that return a zero rect for the
        // end-of-text index get a backward walk (McBopomofo pattern). The
        // fallback anchor is the leading edge of the last marked character —
        // the ghost may overlap it by a glyph; acceptable degradation.
        var lineRect = NSRect.zero
        var index = max(0, caretIndex)
        while lineRect == .zero && index >= 0 {
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineRect)
            index -= 1
        }
        guard lineRect != .zero else {
            hide()
            return
        }

        suggestedWord = fullWord

        let fontSize = max(11, min(28, lineRect.height * 0.72))
        label.font = NSFont.systemFont(ofSize: fontSize)
        label.stringValue = remainder
        label.sizeToFit()

        var frame = NSRect(
            x: lineRect.maxX + 2,
            y: lineRect.minY,
            width: label.frame.width + 4,
            height: lineRect.height
        )
        // Keep on-screen; flip to the left of the caret if there's no room.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: lineRect.midX, y: lineRect.midY)) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.maxX > visible.maxX {
                frame.origin.x = lineRect.minX - frame.width - 2
            }
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        }

        panel.level = NSWindow.Level(rawValue: Int(client.windowLevel()) + 1)
        panel.setFrame(frame, display: false)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        suggestedWord = nil
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }
}

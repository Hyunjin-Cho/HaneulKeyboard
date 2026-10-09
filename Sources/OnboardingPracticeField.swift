import AppKit
import SwiftUI

/// 2026-10-07 (#80): 실제 IMK 클라이언트. 연습 글자는 NSTextView만 소유한다.
/// 조합 중 매번 SwiftUI Binding으로 되돌려 보내지 않아 레이아웃/입력 갱신이 충돌하지 않는다.
struct OnboardingPracticeField: NSViewRepresentable {
    var focusRequest: UUID
    var resetRequest: UUID
    var accessibilityName: String
    var placeholder: String
    var onProgressChange: (OnboardingPracticeStage) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = OnboardingPracticeTextView(frame: scroll.contentView.bounds)
        editor.placeholder = placeholder
        editor.onProgressChange = onProgressChange
        editor.setAccessibilityLabel(accessibilityName)
        scroll.documentView = editor
        context.coordinator.focusRequest = focusRequest
        context.coordinator.resetRequest = resetRequest
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // 텍스트 길이/조합 상태가 안내 카드의 크기를 바꾸지 않게 부모의 고정 프레임을 따른다.
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 100)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? OnboardingPracticeTextView else { return }
        editor.placeholder = placeholder
        editor.onProgressChange = onProgressChange
        editor.setAccessibilityLabel(accessibilityName)
        if context.coordinator.resetRequest != resetRequest {
            context.coordinator.resetRequest = resetRequest
            // IME에 조합 종료를 먼저 알린 뒤 명시적인 「비우기」만 수행한다.
            editor.window?.makeFirstResponder(nil)
            editor.string = ""
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.undoManager?.removeAllActions()
            editor.resetProgress()
            editor.needsDisplay = true
            editor.scrollToBeginningOfDocument(nil)
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }

    final class Coordinator {
        var focusRequest: UUID?
        var resetRequest: UUID?
    }
}

/// 조합 문자열은 textDidChange 이전에도 존재하므로 네이티브 입력 상태로 안내 문구를 그린다.
final class OnboardingPracticeTextView: NSTextView {
    var onProgressChange: ((OnboardingPracticeStage) -> Void)?
    private var progress = OnboardingPracticeProgress()
    private var deliveryScheduled = false
    private var observationDepth = 0
    private var deliveredStage: OnboardingPracticeStage = .empty

    func resetProgress() {
        progress.reset()
        scheduleProgressDelivery()
    }

    private func reportProgress() {
        guard observationDepth == 0 else { return }
        _ = progress.observe(text: string, hasMarkedText: hasMarkedText())
        scheduleProgressDelivery()
    }

    private func scheduleProgressDelivery() {
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        // IME의 조합/치환 한 묶음이 끝난 다음 안내만 갱신한다. 텍스트는 NSTextView가 소유한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliveryScheduled = false
            self.progress.finishEditingBatch()
            guard self.deliveredStage != self.progress.stage else { return }
            self.deliveredStage = self.progress.stage
            self.onProgressChange?(self.progress.stage)
        }
    }
    var placeholder = "" {
        didSet { if oldValue != placeholder { needsDisplay = true } }
    }
    var showsPlaceholder: Bool { string.isEmpty && !hasMarkedText() }

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        allowsUndo = true
        font = .systemFont(ofSize: 23)
        textColor = .labelColor
        drawsBackground = false
        textContainerInset = NSSize(width: 12, height: 12)
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.containerSize = NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        observationDepth += 1
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        observationDepth -= 1
        needsDisplay = true
        reportProgress()
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        observationDepth += 1
        super.insertText(string, replacementRange: replacementRange)
        observationDepth -= 1
        needsDisplay = true
        reportProgress()
    }
    override func unmarkText() {
        observationDepth += 1
        super.unmarkText()
        observationDepth -= 1
        needsDisplay = true
        reportProgress()
    }
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        reportProgress()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 5
        (placeholder as NSString).draw(
            in: NSRect(x: origin.x + padding, y: origin.y + 3,
                       width: max(0, bounds.width - 2 * (origin.x + padding)), height: 44),
            withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor])
    }
}

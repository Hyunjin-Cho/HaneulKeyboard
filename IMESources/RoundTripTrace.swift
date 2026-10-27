import Foundation
import os.log

/// R12 · 2026-10-18: explicitly enabled, short-lived diagnosis of IMK session loss.
/// Never accepts text, keys, coordinates, client identifiers, or character hashes.
/// The default is OFF. Two Unix timestamps must describe a window of at most 30 minutes.
final class RoundTripTrace {
    static let startKey = "haneul.roundTripTraceStart"
    static let endKey = "haneul.roundTripTraceEnd"

    enum Event: String {
        case activateBegin, activateEnd, deactivateBegin, deactivateEnd
        case commitBegin, commitEnd, clientChangedBegin, clientChangedEnd
        case toggleBegin, toggleEnd, pairEndedDuringInput
        case callBegin, callEnd
        case deferredStored, deferredConfirmed
        case pendingMarkedUnavailable, pendingMarkedLengthMismatch
        case pendingSelectionNonCaret, pendingSelectionNotAtEnd
    }

    enum Stage: String {
        case idle, handle, selection, markedRange, substring, replacement, readback
        case composerInsert, composerMark
    }

    private let logger = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "roundtrip")
    private let identifier = UUID().uuidString
    private var sequence = 0
    private var currentSequence = 0
    private var remainingRecords = 512
    private var stage: Stage = .idle
    private var insideToggle = false

    static func isEnabled(start: Double, end: Double, now: Double) -> Bool {
        start.isFinite && end.isFinite && now.isFinite && start > 0
            && end > start && end - start <= 30 * 60 && start <= now && now < end
    }

    func record(_ event: Event, composer: KoreanComposer) {
        guard remainingRecords > 0 else { return }
        let defaults = UserDefaults.standard
        guard Self.isEnabled(start: defaults.double(forKey: Self.startKey),
                             end: defaults.double(forKey: Self.endKey),
                             now: Date().timeIntervalSince1970) else { return }
        remainingRecords -= 1
        let pair = composer.lastConversion != nil
        let origin: String
        if !pair { origin = "none" }
        else {
            switch composer.lastConversionOrigin {
            case .automatic: origin = "automatic"
            case .keyboard: origin = "keyboard"
            case .phonetic: origin = "phonetic"
            }
        }
        logger.notice("r12 controller=\(self.identifier, privacy: .public) toggle=\(self.currentSequence, privacy: .public) event=\(event.rawValue, privacy: .public) stage=\(self.stage.rawValue, privacy: .public) pair=\(pair, privacy: .public) origin=\(origin, privacy: .public) composing=\(composer.hasPendingComposition, privacy: .public)")
    }

    struct HandleState {
        fileprivate let previousStage: Stage
        fileprivate let previousToggle: Bool
        fileprivate let previousSequence: Int
        fileprivate let isToggle: Bool
        fileprivate let hadPair: Bool
    }

    func beginHandle(isToggle: Bool, composer: KoreanComposer) -> HandleState {
        let previous = HandleState(previousStage: stage, previousToggle: insideToggle,
                                   previousSequence: currentSequence,
                                   isToggle: isToggle, hadPair: composer.lastConversion != nil)
        stage = .handle
        insideToggle = isToggle
        if isToggle {
            sequence += 1
            currentSequence = sequence
            record(.toggleBegin, composer: composer)
        }
        return previous
    }

    func endHandle(_ previous: HandleState, composer: KoreanComposer) {
        if previous.isToggle { record(.toggleEnd, composer: composer) }
        else if previous.hadPair && composer.lastConversion == nil {
            record(.pairEndedDuringInput, composer: composer)
        }
        stage = previous.previousStage
        insideToggle = previous.previousToggle
        if previous.previousToggle { currentSequence = previous.previousSequence }
    }

    /// Restores the outer stage even if a client RPC services a nested callback.
    func call<T>(_ next: Stage, composer: KoreanComposer?, _ operation: () -> T) -> T {
        let previous = stage
        stage = next
        if insideToggle, let composer { record(.callBegin, composer: composer) }
        defer {
            if insideToggle, let composer { record(.callEnd, composer: composer) }
            stage = previous
        }
        return operation()
    }
}

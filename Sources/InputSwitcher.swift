import Carbon

enum InputSwitcher {
    static let englishLayoutID = "com.apple.keylayout.ABC"
    static let koreanModeID = "com.hyunjincho.inputmethod.haneul.korean"
    static let englishModeID = "com.hyunjincho.inputmethod.haneul.english"

    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return sourceID(of: source)
    }

    static func isKoreanActive() -> Bool {
        guard let id = currentSourceID() else { return false }
        return looksKorean(id)
    }

    @discardableResult
    static func toggle() -> Bool {
        guard let current = currentSourceID() else { return false }
        if current.contains("com.hyunjincho.inputmethod.haneul") {
            if looksKorean(current) {
                return selectMode(englishModeID)
            } else {
                return selectKorean()
            }
        }
        return isKoreanActive() ? selectEnglish() : selectKorean()
    }

    @discardableResult
    static func selectEnglish() -> Bool {
        guard let source = availableSources().first(where: { sourceID(of: $0) == englishLayoutID }) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    @discardableResult
    static func selectKorean() -> Bool {
        let sources = availableSources()
        if let ours = sources.first(where: { sourceID(of: $0) == koreanModeID }) {
            return TISSelectInputSource(ours) == noErr
        }
        if let any = sources.first(where: { src in
            guard let id = sourceID(of: src) else { return false }
            return looksKorean(id)
        }) {
            return TISSelectInputSource(any) == noErr
        }
        return false
    }

    @discardableResult
    static func selectMode(_ modeID: String) -> Bool {
        guard let source = availableSources().first(where: { sourceID(of: $0) == modeID }) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Helpers

    private static func availableSources() -> [TISInputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceIsEnableCapable: true,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }
        return list as! [TISInputSource]
    }

    private static func sourceID(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func looksKorean(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("korean") || lower.contains("hangul")
    }
}

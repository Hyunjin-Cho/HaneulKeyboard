import Carbon

enum InputSwitcher {
    static let englishLayoutID = "com.apple.keylayout.ABC"
    static let koreanModeID = "com.hyunjincho.inputmethod.haneul.korean"
    // (H-01) 하늘 IME엔 한국어 모드만 있고 자체 영어 모드는 없다. 한→영 전환은
    // 시스템 ABC(englishLayoutID)로 한다 — 존재하지 않는 english 모드를 선택하려다
    // toggle이 조용히 no-op이던 버그 수정.

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
                return selectEnglish()
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
        // (M-08) 우리 IME 모드만 선택한다. 예전엔 우리 걸 못 찾으면 ID에
        // korean/hangul이 든 아무 입력 소스(Apple 두벌식 등)로 조용히 전환해,
        // 설치/등록 실패 시 "전용 입력기" 보장이 사용자 모르게 깨졌다. 이제 우리
        // 모드가 없으면 전환하지 않고 false를 반환한다(호출부가 실패를 인지).
        guard let ours = sources.first(where: { sourceID(of: $0) == koreanModeID }) else {
            return false
        }
        return TISSelectInputSource(ours) == noErr
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
        return list as? [TISInputSource] ?? []
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

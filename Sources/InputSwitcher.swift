import Carbon

enum InputSwitcher {
    static let koreanModeID = "com.hyunjincho.inputmethod.haneul.korean"
    // 2026-11-05 (#142): 메뉴 "영어로 전환"을 뺐다. 한영 전환은 Caps Lock과 시스템 입력 메뉴가 맡는다.

    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return sourceID(of: source)
    }

    /// 2026-11-07 (#177, 리뷰 app-ui-F-7): 시스템이 지역화한 현재 입력 소스 이름(예: "ABC", "두벌식").
    /// 예전의 `isKoreanActive()`는 ID에 korean·hangul이 들었는지만 보고 나머지를 전부 "영어"라 말해서 지웠다 — 분류는
    /// `InputSourceDescription.classify`가 한다.
    static func currentSourceLocalizedName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
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
}

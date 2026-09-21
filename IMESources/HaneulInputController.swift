import Cocoa
import Carbon
import InputMethodKit
import os.log

/// Bridges the Foundation-only KoreanComposer to the IMK client.
private struct IMKComposerClient: ComposerClient {
    let client: IMKTextInput

    func insertText(_ text: String) {
        client.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    func setMarkedText(_ text: String) {
        client.setMarkedText(
            text as NSString,
            selectionRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}

@objc(HaneulInputController)
final class HaneulInputController: IMKInputController {
    private let log = Logger(subsystem: "com.hyunjincho.haneulkeyboard", category: "ime")
    private let composer = KoreanComposer()
    private var didOverrideKeyboard = false

    // Listen ONLY for .keyDown. macOS routes CapsLock-based Korean<->ABC
    // switching automatically via TICapsLockLanguageSwitchCapable in plist,
    // and we must NOT subscribe to .flagsChanged — every Shift press fires
    // a flagsChanged event, and if we react to it (even just to read state)
    // it's easy to accidentally flush the in-flight Hangul syllable, which
    // is what breaks 쌍자음 input (ㅆ ㄲ ㄸ ㅉ ㅃ).
    override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        log.log("activateServer")
        // NOTE: never query the client (markedRange/attributes/...) in here —
        // it deadlocks Chromium-based apps. Defaults reads only.
        // 2026-09-19 (#32): 메인 앱이 지워졌는지 확인 — 즉시 반환하고 백그라운드에서
        // 60초에 한 번만 조회한다(전환 경로에 동기 작업을 얹지 않는다).
        OrphanWatcher.shared.checkIfDue()
        composer.autoEnglishEnabled =
            UserDefaults.standard.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true
        // 2026-09-21 (#53): 개인 사전도 같은 시점에 읽는다(defaults 읽기뿐 — 클라이언트 질의 아님).
        composer.personalDictionary = PersonalDictionary.load(from: .standard)
        composer.resetEnglishContext() // 새 필드/앱 — 영어 문맥은 이어지지 않음
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }
    }

    override func deactivateServer(_ sender: Any!) {
        log.log("deactivateServer")
        if let client = sender as? IMKTextInput {
            composer.commit(to: IMKComposerClient(client: client))
        }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        composer.commit(to: IMKComposerClient(client: client))
        composer.resetEnglishContext() // 클릭/포커스 이동 = 문맥 단절
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Key codes/characters are keystroke content — never log them as
        // .public (an IME writing keystrokes to the unified log is a
        // keylogger). Even with .private redaction, emitting one log record
        // per keystroke is poor hygiene for an IME — so the whole typing-path
        // log is Debug-only; release builds write nothing per keystroke.
        #if DEBUG
        log.log("keyDown code=\(event.keyCode, privacy: .private) shift=\(mods.contains(.shift), privacy: .public) caps=\(mods.contains(.capsLock), privacy: .public)")
        #endif

        if !didOverrideKeyboard {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            didOverrideKeyboard = true
        }

        let composerClient = IMKComposerClient(client: client)

        // (secure-input) 정상적인 secure 필드는 macOS가 서드파티 IME를 아예
        // 우회하지만(PRIVACY.md #4), 그 우회가 안 걸리는 예외 상황에 대비한
        // 방어선이다 — 조합 중이던 자모를 흘리지 않고 커밋한 뒤, 이번 키는
        // 조합하지 않고 그대로 통과시킨다(review0706 P3-4).
        if IsSecureEventInputEnabled() {
            composer.commit(to: composerClient)
            composer.resetEnglishContext()
            return false
        }

        if event.keyCode == 51 {
            // (H-08) Cmd/Opt/Ctrl+Backspace(단어·줄 삭제)는 composer가 먹지
            // 않고 클라이언트가 처리하게 한다 — 조합 중에도 일상 단축키가 한
            // 자모 삭제로 둔갑하지 않도록. 무수정 Backspace만 자모를 떼어낸다.
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                composer.commit(to: composerClient)
                composer.resetEnglishContext()
                return false
            }
            let handled = composer.deleteBackward(client: composerClient)
            // Backspace into already-committed text (composer absorbed
            // nothing) breaks any English run — otherwise a wrongly-converted
            // word (새→to) can't be fixed by delete+retype (it re-converts).
            if !handled {
                composer.resetEnglishContext()
            }
            return handled
        }

        // 되돌리기 키(기본 Shift+Space): 마지막 변환을 영어↔한글 토글로 교체(㉠ 직후만).
        // 커서 직전 텍스트를 읽어 boundary(스페이스·구두점)를 건너뛰고 영어/
        // 한글을 정확히 찾아 replace — 변환 시 입력된 공백("i ") 때문에 커서가
        // 영어 바로 뒤가 아니어도 옳게 동작한다. lastConversion을 유지해 연속
        // 되돌리기로 영↔한을 반복 토글(다음 글자 입력/백스페이스 시 리셋).
        // 한글 모드는 CapsLock 전환 방식이라 keyDown의 modifierFlags에
        // .capsLock이 상시 포함될 수 있다 — 엄격 비교하면 한글 모드에서 토글이
        // 발동하지 않는다(영어 모드에선 OK라 더 헷갈린다). capsLock/function을
        // 빼고 비교하는 규칙은 RevertKey.matches 안에 그대로 있다.
        // 2026-09-21 (#54): 키 조합은 설정값(haneul.revertKey, 고정 후보 4종)이다 —
        // 하드코딩 Shift+Space를 순수 타입 RevertKey로 옮겼다. defaults는 키
        // 이벤트마다 읽지 않고 **Space 키코드 + 되돌릴 변환이 있을 때만** 읽는다
        // (autoEnglishEnabled를 경계마다 다시 읽는 것과 같은 비용 수준).
        if event.keyCode == RevertKey.spaceKeyCode, let conv = composer.lastConversion,
           RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
               .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue) {
            let sel = client.selectedRange()
            #if DEBUG
            log.log("ss진단A: selLoc=\(sel.location, privacy: .public) selLen=\(sel.length, privacy: .public)")
            #endif
            // (L3) 드래그 선택 중(length>0)이거나 커서 위치를 모르면 손대지 않음.
            if sel.location != NSNotFound, sel.length == 0 {
                let span = max((conv.english as NSString).length, (conv.hangul as NSString).length) + 4
                let readStart = max(0, sel.location - span)
                let reqLen = sel.location - readStart
                let attr = client.attributedSubstring(
                    from: NSRange(location: readStart, length: reqLen))
                let before = (attr?.string ?? "") as NSString
                #if DEBUG
                log.log("ss진단B: reqLen=\(reqLen, privacy: .public) beforeLen=\(before.length, privacy: .public)")
                #endif
                // (T1) 커서 앞을 읽어줄 수 없는 클라이언트(Ghostty 등 일부 터미널)
                // 에서는 되돌리기가 원리적으로 불가능하다 — 아래로 흘려보내면
                // 되돌리기를 요청한 자리에 엉뚱한 스페이스만 끼어드니, 아무것도
                // 하지 않고 키만 소비한다. 판정은 순수함수로 분리해 테스트한다(#30).
                if KoreanComposer.toggleUnsupported(cursorLocation: sel.location,
                                                    didReadText: attr != nil) {
                    return true
                }
                // (H1) Chromium/Electron 등이 substring을 잘라 반환하면 좌표가
                // 어긋나 인접 글자를 덮어쓴다 — 요청 길이와 다르면 안전하게 포기.
                // boundary skip·좌측경계·매칭은 순수함수 resolveToggle이 담당
                // (M1: IMK 비의존이라 단위테스트로 검증).
                if before.length == reqLen,
                   let r = KoreanComposer.resolveToggle(before: before as String,
                       english: conv.english, hangul: conv.hangul, atDocStart: readStart == 0) {
                    let start = sel.location - r.offsetFromEnd
                    client.insertText(r.text as NSString,
                        replacementRange: NSRange(location: start, length: r.replaceLen))
                    // (T2) Terminal.app 등은 이 교체를 조용히 무시한다 — 교체 자리를
                    // 다시 읽어 옛 글자가 그대로면 거부로 판정하고, 화면·내부 상태를
                    // 손대지 않은 채 키만 소비한다(스페이스가 끼어들지 않게). 연속
                    // 시도해도 같은 결과가 되도록 lastConversion은 유지한다(#30).
                    let previous = r.text == conv.english ? conv.hangul : conv.english
                    let rejected = KoreanComposer.toggleWasRejected(
                        textAtReplacement: client.attributedSubstring(
                            from: NSRange(location: start, length: r.replaceLen))?.string,
                        previousText: previous)
                    #if DEBUG
                    log.log("ss진단C: rejected=\(rejected, privacy: .public)")
                    #endif
                    if rejected { return true }
                    // (M-01) 화면만 바꾸지 말고 내부 영어 문맥도 방향에 맞춰 전이 —
                    // r.text가 영어면 영어 문맥 복원, 한글이면 끊김. (안 하면 다음
                    // 단어가 옛 문맥으로 잘못 변환됨.)
                    composer.applyToggle(toEnglish: r.text == conv.english,
                                         hangul: conv.hangul, english: conv.english)
                    // 2026-09-21 (#53): 영어→한글로 되돌린 순간만 기록한다(한글→영어 재토글은
                    // 기록 대상이 아님 — "오변환이었다"는 신호는 되돌림 쪽뿐).
                    if r.text != conv.english {
                        recordRevert(hangul: conv.hangul, english: conv.english)
                    }
                    return true
                }
            }
            // (M2) 매칭 실패/불안전 → 토글하지 않고 아래 일반 경계 처리로 흘려보낸다
            // (키를 먹지 않게 — 최소한 스페이스는 입력됨).
        }

        // 2026-09-21 (#15): 되돌릴 자동변환이 **없을 때**의 수동 한↔영 토글 — 커서 앞 단어를
        // 자판 배열만으로 바꾼다. 자동변환이 안전을 위해 일부러 포기한 영역(우리말샘 veto로
        // 막히는 `재가`, 사전에 존재할 수 없는 `ㅡ5`)을 사용자 의도로 뚫는 탈출구다.
        //
        // 순서가 곧 사양이다 — **되돌리기 우선**: 위 블록이 먼저이고 `lastConversion`이 있으면
        // 여기까지 오지 않는다(익숙한 동작을 깨지 않는다).
        //
        // 조건은 싼 것부터 — 공짜 상태 검사 → 키코드·수정자 사전 필터 → defaults 두 번.
        // `couldMatch` 덕에 **맨 스페이스는 defaults를 한 번도 읽지 않는다**(종전과 같은 비용).
        //
        // `hasPendingComposition`: 조합 중(marked text)이면 토글하지 않는다. 그 글자는 아직
        // 클라이언트 문서가 아니라 커서 앞을 읽어도 있을지 없을지 앱마다 다르다. 이때는 아래
        // 일반 경계 처리로 흘려보내 평소대로 확정하고(자동 변환도 평소대로 시도된다), 그다음
        // 누름부터 토글 대상이 된다.
        if composer.lastConversion == nil, !composer.hasPendingComposition,
           RevertKey.couldMatch(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue),
           RevertKey.resolve(rawValue: UserDefaults.standard.string(forKey: RevertKey.defaultsKey))
               .matches(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue),
           UserDefaults.standard.object(forKey: RevertKey.manualToggleAllWordsKey) as? Bool
               ?? RevertKey.manualToggleAllWordsDefault,
           handleManualToggle(client: client) {
            return true
        }

        // (M-02) `.numericPad`는 passive 목록에서 뺀다 — 화살표/탐색키는
        // `.function`도 함께 달려 위에서 passive로 잡히지만, 키패드 숫자·Enter는
        // `.numericPad`만 달려 예전엔 변환 없이 그대로 확정됐다. 이제 키패드
        // 문자·Enter는 아래 active boundary로 흘러 영타 변환 대상이 된다.
        if mods.contains(.control) || mods.contains(.command)
           || mods.contains(.option) || mods.contains(.function) {
            composer.commit(to: composerClient) // passive: 변환 안 함
            composer.resetEnglishContext()      // 커서 이동/단축키 = 문맥 단절
            return false
        }

        let shifted = mods.contains(.shift)

        if let inputChar = KeyboardLayout2Set.inputCharacter(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            characters: event.characters,
            keyCode: Int(event.keyCode),
            shifted: shifted
        ) {
            return composer.handleInput(String(inputChar), client: composerClient)
        }

        // 2026-09-19 (#34): 조합 중의 `'`는 경계가 아니라 단어 내부 문자다 —
        // i'm·don't 같은 축약형을 통째로 변환하려면 `'`가 단어에 붙어 있어야
        // 한다. 단어가 비어 있거나(여는 따옴표 `'안녕`) 이미 `'`가 있으면
        // composer가 false를 돌려주고, 그대로 아래 기존 경계 처리로 흘러간다.
        // (L-02와 같은 이유로 실제 출력 문자 기준 — Shift+'는 `"`라 안 걸린다.)
        if let typed = event.characters?.first, Contractions.isApostrophe(typed),
           composer.handleApostrophe(typed, client: composerClient) {
            return true
        }

        // Active boundary: the user typed a non-jamo key (space, punctuation,
        // digit, Enter...) — the only path where English auto-conversion may
        // fire. Re-read the toggle so Settings changes apply immediately.
        // secure input은 이 함수 진입부에서 이미 걸러지므로 여기서는 항상 false.
        // 2026-09-21 (#54): 앱별 끄기 — 목록(haneul.disabledAppBundleIDs)에 이 클라이언트의
        // bundle ID가 있으면 이번 경계에선 변환하지 않는다. 판정은 순수함수
        // AutoConvertPolicy.allowed(테스트 있음). 클라이언트 왕복(bundleIdentifier)은
        // 목록이 비어 있지 않을 때만 — 비어 있으면 결과가 어차피 "허용"이다.
        // bundle ID를 못 얻으면(nil) 허용(기본 동작으로 복귀).
        let defaults = UserDefaults.standard
        let disabledAppIDs = defaults.stringArray(forKey: AutoConvertPolicy.disabledAppsKey) ?? []
        composer.autoEnglishEnabled = AutoConvertPolicy.allowed(
            globalEnabled: defaults.object(forKey: "haneul.autoEnglishEnabled") as? Bool ?? true,
            disabledIDs: disabledAppIDs,
            clientBundleID: disabledAppIDs.isEmpty ? nil : client.bundleIdentifier())
        // 2026-09-21 (#53): 개인 사전(변환 추가·금지)도 여기서 한 번 읽는다 — 키 이벤트마다가
        // 아니라 변환이 실제로 일어날 수 있는 활성 경계에서만. 설정 앱이 쓴 값이 재시작 없이
        // 다음 단어부터 반영된다. 목록은 작아서(수십~수백) 비용은 무시할 수준.
        composer.personalDictionary = PersonalDictionary.load(from: .standard)
        composer.commit(to: composerClient, convertEnglish: true)
        // 영어 문맥("I want to...")은 스페이스/쉼표로만 이어진다 — 마침표·
        // 엔터·기타 문자는 문장 단절로 보고 리셋 ("Nice. 새로운" 보호).
        // (L-02) 실제 출력 문자 기준 — Shift+,는 '<'(문장 단절 경계)이지 ','가
        // 아니다. charactersIgnoringModifiers는 '<'를 ','로 잘못 보고했다.
        let boundary = event.characters?.first
        if boundary != " " && boundary != "," {
            composer.resetEnglishContext()
        }
        return false
    }

    /// 2026-09-21 (#15): 커서 앞 단어를 한↔영으로 바꾼다 — 되돌릴 자동변환이 없을 때의 경로.
    ///
    /// 자동 되돌리기(`handle` 위쪽 블록)와 **같은 재료**를 그대로 쓴다: 커서 앞을 읽고(T1),
    /// 단어를 잘라(`wordBeforeCursor` — `resolveToggle`과 같은 `isWordChar`), 범위를 교체하고,
    /// 교체가 먹었는지 다시 읽어 확인한다(T2). 다른 점은 **무엇으로 바꾸는지**뿐이다 —
    /// 사전이 아니라 `ManualToggle`의 자판 역매핑이라 veto도 사전 수록 여부도 보지 않는다.
    ///
    /// - Returns: 키를 소비했으면 true. false면 호출자가 평소 경계 처리로 흘려보낸다
    ///   (최소한 스페이스는 입력된다).
    private func handleManualToggle(client: IMKTextInput) -> Bool {
        let sel = client.selectedRange()
        // (L3) 드래그 선택 중(length>0)이거나 커서 위치를 모르면 손대지 않음 — 자동 경로와 동일.
        guard sel.location != NSNotFound, sel.length == 0 else { return false }
        let readStart = max(0, sel.location - ManualToggle.readSpan)
        let reqLen = sel.location - readStart
        let attr = client.attributedSubstring(from: NSRange(location: readStart, length: reqLen))
        #if DEBUG
        log.log("mt진단A: selLoc=\(sel.location, privacy: .public) reqLen=\(reqLen, privacy: .public) read=\(attr != nil, privacy: .public)")
        #endif
        // (T1) 커서 앞을 읽어줄 수 없는 클라이언트(Ghostty 등 터미널)에서는 원리적으로 불가능 —
        // 아무것도 하지 않고 키만 소비한다(#30). 아래로 흘려보내면 되돌리기를 요청한 자리에
        // 엉뚱한 스페이스만 끼어든다.
        guard let attr else { return true }
        // 커서가 문서 맨 앞 = 앞에 단어가 없는 **정상 상태**다. 자동 경로의 `toggleUnsupported`는
        // 이걸 "거짓 보고"로 보고 키를 먹는데(변환 직후라면 앞에 글자가 반드시 있으므로),
        // 수동 경로에선 뜻이 다르다 — 빈 필드에서 스페이스가 사라지지 않게 흘려보낸다.
        guard sel.location > 0 else { return false }
        let before = attr.string as NSString
        // (H1) 요청 길이와 다르게 잘라 주는 클라이언트(Chromium/Electron 등)는 좌표가 어긋나
        // 인접 글자를 덮어쓴다 — 안전하게 포기한다.
        guard before.length == reqLen,
              let target = KoreanComposer.wordBeforeCursor(
                  before: before as String, atDocStart: readStart == 0),
              let toggled = ManualToggle.manualToggle(word: target.word) else { return false }
        let wordLength = (target.word as NSString).length
        let start = sel.location - wordLength - target.trailing
        guard start >= 0 else { return false }
        client.insertText(toggled as NSString,
                          replacementRange: NSRange(location: start, length: wordLength))
        // (T2) Terminal.app 등은 범위 교체를 조용히 무시한다 — 그 자리에 옛 글자가 그대로면
        // 거부로 판정하고, 화면·내부 상태를 손대지 않은 채 키만 소비한다(#30).
        let rejected = KoreanComposer.toggleWasRejected(
            textAtReplacement: client.attributedSubstring(
                from: NSRange(location: start, length: wordLength))?.string,
            previousText: target.word)
        #if DEBUG
        log.log("mt진단B: rejected=\(rejected, privacy: .public)")
        #endif
        if rejected { return true }
        // 한 번 더 누르면 되돌아오게 `lastConversion`을 세운다 — 그러면 **기존** 되돌리기 경로가
        // 그대로 매칭해 역토글한다(수동 경로를 두 번 타지 않고, 좌표 로직도 하나만 쓴다).
        //
        // `applyToggle`은 영어 문맥(`lastEnglishWord`)까지 함께 옮기는데, 그 부작용이 여기서도
        // 맞다(코드 확인 후 결정): 화면 끝이 실제로 영어 단어가 됐으면 다음 단어는 영어 문맥으로
        // 판정돼야 하고(M-01과 같은 이유 — 화면과 내부 상태가 어긋나면 다음 단어가 잘못 변환된다),
        // 한글로 바꿨으면 문맥은 끊겨야 한다.
        let toEnglish = ManualToggle.classify(word: target.word) == .hangul
        composer.applyToggle(toEnglish: toEnglish,
                             hangul: toEnglish ? target.word : toggled,
                             english: toEnglish ? toggled : target.word)
        // 수동 경로는 #53 `recordRevert`를 **부르지 않는다**. "최근 되돌린 변환"은 자동변환이
        // 틀렸다는 신호를 모으는 목록인데, 여기서 바꾼 단어는 애초에 자동변환된 적이 없다 —
        // 넣으면 일어나지도 않은 오변환에 "금지" 버튼을 달게 된다.
        return true
    }

    /// 2026-09-21 (#53): 되돌린 변환을 "최근 되돌린 변환" 목록에 남긴다 — (한글 표기, 영어)
    /// 쌍만. 키스트로크·앞뒤 문맥·앱 이름·시각은 담지 않고, 로그에도 남기지 않는다(키로거
    /// 금지). secure input은 `handle` 진입부에서 이미 걸러져 여기까지 오지 않는다.
    /// 이 키는 IME만 쓴다(설정 앱은 읽기+삭제) — 형식·상한은 `RecentReverts`가 정본.
    private func recordRevert(hangul: String, english: String) {
        let defaults = UserDefaults.standard
        RecentReverts.load(from: defaults)
            .recording(hangul: hangul, english: english)
            .save(to: defaults)
    }
}

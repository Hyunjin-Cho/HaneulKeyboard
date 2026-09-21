import Foundation

/// 되돌리기(영타↔한글 토글) 키의 **후보 목록과 매칭**만 모은 순수 타입. (#54, 2026-09-21)
///
/// 종전엔 `HaneulInputController.handle`이 Shift+Space(keyCode 49 + `.shift`)를 하드코딩했다.
/// 설정에서 고를 수 있게 하되 **자유 입력이 아니라 고정 후보**만 둔다 — 임의 조합을 받으면
/// 자모 키나 시스템 단축키와 겹치는 조합을 사용자가 만들 수 있고, 그건 IME가 키를 삼키는
/// 사고로 이어진다. Ctrl+Space는 macOS 기본 "이전 입력 소스 선택" 단축키라 후보에서 뺐다.
///
/// AppKit 비의존: `NSEvent.ModifierFlags`의 rawValue(UInt)를 그대로 받는다. 이 파일은
/// IME·설정 앱 **양쪽 타겟**에 들어가고(저장 키·후보의 단일 진실) `scripts/run_ime_tests.sh`가
/// Foundation만으로 컴파일해 검증한다 — `OrphanDecision`·`InstallDecisions`와 같은 분리 패턴.
enum RevertKey: String, CaseIterable {
    case shiftSpace
    case optionSpace
    case controlShiftSpace
    case optionShiftSpace

    /// 기본값. 저장값이 없거나 알 수 없는 문자열이면 여기로 돌아온다.
    static let `default`: RevertKey = .shiftSpace

    /// IME defaults 도메인(`com.hyunjincho.inputmethod.haneul`)의 키. 값은 `rawValue` 문자열.
    /// 설정 앱은 `UserDefaults(suiteName:)`으로 쓰고, IME는 `UserDefaults.standard`로 읽는다
    /// (`haneul.autoEnglishEnabled`와 같은 경로). "전체 제거"의 `haneul.*` 일괄 삭제에 포함된다.
    static let defaultsKey = "haneul.revertKey"

    /// Space의 가상 키코드(kVK_Space). 되돌리기 후보는 전부 Space 조합이다.
    static let spaceKeyCode: UInt16 = 49

    /// 2026-09-21 (#15): "되돌리기 키를 모든 단어로 확대" 설정(Bool, 기본 켜짐). 꺼 두면
    /// 종전처럼 **직전 자동변환**만 되돌린다.
    ///
    /// 동작 본문은 `IMESources/ManualToggle.swift`인데 저장 키만 여기 있는 이유: ManualToggle은
    /// 조합을 `KoreanComposer`에 위임하느라 IME 코어 전체를 끌고 와서 설정 앱 타겟에 넣을 수
    /// 없다. 키 이름은 설정 앱도 써야 하므로, 이미 양쪽 타겟에 들어가는 이 파일에 둔다
    /// (사본을 두면 반드시 어긋난다 — 되돌리기 키 설정이라 자리도 맞다).
    /// "전체 제거"의 `haneul.*` 일괄 삭제에 함께 포함된다.
    static let manualToggleAllWordsKey = "haneul.manualToggleAllWords"

    /// 저장값이 없을 때의 기본값 — **켜짐**(오너 확정, #15).
    static let manualToggleAllWordsDefault = true

    /// `NSEvent.ModifierFlags`와 비트가 같은 자체 OptionSet — AppKit 없이 비교하기 위한 것.
    /// 값은 macOS SDK `NSEvent.h`의 정의 그대로(2026-09-21 Xcode 27 SDK에서 실측 확인),
    /// 테스트가 이 상수를 SDK 값과 대조한다.
    struct Modifiers: OptionSet, Equatable {
        let rawValue: UInt

        static let capsLock = Modifiers(rawValue: 1 << 16)
        static let shift = Modifiers(rawValue: 1 << 17)
        static let control = Modifiers(rawValue: 1 << 18)
        static let option = Modifiers(rawValue: 1 << 19)
        static let command = Modifiers(rawValue: 1 << 20)
        static let numericPad = Modifiers(rawValue: 1 << 21)
        static let help = Modifiers(rawValue: 1 << 22)
        static let function = Modifiers(rawValue: 1 << 23)
        /// `NSEvent.ModifierFlags.deviceIndependentFlagsMask` — 하위 16비트는 장치별 비트라 버린다.
        static let deviceIndependentMask = Modifiers(rawValue: 0xFFFF_0000)

        /// 비교에서 빼는 플래그. 한글 모드는 CapsLock 전환 방식이라 keyDown의 modifierFlags에
        /// `.capsLock`이 상시 포함될 수 있다 — 엄격 비교하면 한글 모드에서만 되돌리기가 안 먹는다
        /// (영어 모드에선 되니 더 헷갈린다). `.function`도 같은 이유로 뺀다. 종전 컨트롤러의
        /// `mods.subtracting([.capsLock, .function]) == .shift` 규칙을 그대로 옮겼다.
        static let ignoredForMatching: Modifiers = [.capsLock, .function]
    }

    /// 이 후보가 요구하는 수정자 조합 — **정확 일치**여야 한다(Command가 더 붙으면 아님).
    var requiredModifiers: Modifiers {
        switch self {
        case .shiftSpace: return [.shift]
        case .optionSpace: return [.option]
        case .controlShiftSpace: return [.control, .shift]
        case .optionShiftSpace: return [.option, .shift]
        }
    }

    /// 설정 화면·문서에 보이는 이름.
    var displayName: String {
        switch self {
        case .shiftSpace: return "Shift + Space"
        case .optionSpace: return "Option + Space"
        case .controlShiftSpace: return "Control + Shift + Space"
        case .optionShiftSpace: return "Option + Shift + Space"
        }
    }

    /// 저장된 rawValue → 후보. nil·빈 문자열·모르는 값(옛 버전이 남긴 값 포함)은 기본값으로.
    static func resolve(rawValue: String?) -> RevertKey {
        guard let rawValue, let key = RevertKey(rawValue: rawValue) else { return .default }
        return key
    }

    /// 이 keyDown이 되돌리기 키인가.
    /// - keyCode: `NSEvent.keyCode`. Space(49)가 아니면 무조건 false.
    /// - modifierFlagsRaw: `NSEvent.modifierFlags.rawValue`. 컨트롤러가 이미 deviceIndependent로
    ///   걸러 넘기지만, 안 걸러진 값이 와도 같게 동작하도록 여기서 다시 거른다.
    func matches(keyCode: UInt16, modifierFlagsRaw: UInt) -> Bool {
        guard keyCode == Self.spaceKeyCode else { return false }
        let mods = Modifiers(rawValue: modifierFlagsRaw)
            .intersection(.deviceIndependentMask)
            .subtracting(.ignoredForMatching)
        return mods == requiredModifiers
    }

    /// 2026-09-21 (#15): defaults를 읽기 전에 거는 **값싼 사전 필터**.
    ///
    /// 종전엔 "Space 키코드 + 되돌릴 변환이 있을 때"만 defaults를 읽었는데, 모든 단어 토글이
    /// 생기면서 `lastConversion`이 없을 때도 되돌리기 키를 판정해야 한다. 그대로 두면 **맨
    /// 스페이스를 칠 때마다** defaults를 읽게 된다. 후보 4종이 전부 수정자를 하나 이상 요구하므로
    /// (Ctrl+Space는 macOS 예약이라 후보에 없다) "Space + 수정자 있음"으로 먼저 거르면 평범한
    /// 스페이스는 예전처럼 defaults를 건드리지 않는다. 통과해도 실제 판정은 `matches`가 한다.
    static func couldMatch(keyCode: UInt16, modifierFlagsRaw: UInt) -> Bool {
        guard keyCode == spaceKeyCode else { return false }
        let mods = Modifiers(rawValue: modifierFlagsRaw)
            .intersection(.deviceIndependentMask)
            .subtracting(.ignoredForMatching)
        return !mods.isEmpty
    }
}

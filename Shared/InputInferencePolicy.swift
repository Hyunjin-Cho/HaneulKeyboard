import Foundation

/// 2026-10-14 · #14/#24: 설정 앱과 입력기가 공유하는 보수적 입력 보강 계약.
/// 입력 내용이나 주변 문서는 저장하지 않는다. OFF는 다음 조합부터 반영된다.
enum InputInferencePolicy {
    static let externalEnglishContextKey = "haneul.externalEnglishContextEnabled"
    static let externalEnglishContextDefault = true
    static let dictionaryCompoundKey = "haneul.dictionaryCompoundEnabled"
    static let dictionaryCompoundDefault = true

    static func externalEnglishContextEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: externalEnglishContextKey) as? Bool
            ?? externalEnglishContextDefault
    }

    static func dictionaryCompoundEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: dictionaryCompoundKey) as? Bool
            ?? dictionaryCompoundDefault
    }
}

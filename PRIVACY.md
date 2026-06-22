# 개인정보 보호 (Privacy)

입력기(IME)는 키보드 입력을 다루는 민감한 소프트웨어입니다. 하늘키보드가 무엇을 보고, 무엇을 저장하고, 무엇을 하지 않는지 명확하게 적습니다. 아래 모든 내용은 [공개된 소스 코드](https://github.com/Hyunjin-Cho/HaneulKeyboard)로 직접 검증할 수 있습니다.

_최종 수정: 2026-06-22_

## 한눈에 보기

| 질문 | 답 |
|---|---|
| 키 입력을 보나요? | 한국어 입력기가 **활성화된 동안만**, 한글 조합을 위해 봅니다. macOS의 모든 IME가 동일하게 동작합니다. |
| 네트워크로 전송하나요? | **아니요.** 코드에 네트워크 호출이 한 줄도 없습니다. 모든 처리는 기기 안에서 끝납니다. |
| 입력 내용을 저장하나요? | **아니요.** 입력한 내용을 저장하거나 학습하지 않습니다 — 모든 판정은 메모리에서만 일어납니다. |
| 비밀번호도 보나요? | **macOS와 호스트 앱이 보안 입력을 올바르게 활성화한 필드에서는 받지 않습니다.** 다만 일부 브라우저의 웹 비밀번호 칸은 보안 입력이 켜지지 않아 키를 받을 수 있습니다. 민감한 내용은 영문(ABC) 모드로 입력하는 것을 권장합니다. |
| 주장을 검증할 수 있나요? | 네. 전체 소스가 MIT 라이선스로 공개되어 있습니다. |

## 상세

### 1. 키 입력 접근

하늘키보드 입력기는 한글 자모를 음절로 조합하기 위해, **입력 소스로 선택되어 활성화된 동안** 키 입력을 받습니다. 이것은 macOS 입력기(IMKit) 구조상 모든 IME가 동일하게 동작하는 방식입니다. 영어(ABC) 모드로 전환된 동안에는 시스템 기본 입력기가 처리하며 하늘키보드를 거치지 않습니다.

### 2. 네트워크 전송 — 없음

소스 코드(`Sources/`, `IMESources/`)에 네트워크 관련 코드(URLSession, 소켓 등)가 전혀 없습니다. 입력 내용은 물론 어떤 데이터도 기기 밖으로 나가지 않습니다. 통계, 분석, 크래시 리포트 수집도 하지 않습니다.

### 3. 영타 자동 변환 (메ㅔㅣㄷ → apple)

- 판정은 단어 확정 시점에 **메모리에서만** 일어나며, 입력 내용을 어디에도 저장하거나 학습하지 않습니다.
- 판정에는 **읽기 전용 사전**만 사용합니다: macOS의 `/usr/share/dict/words`, 번들 영어 단어·인명 목록, 우리말샘 표제어 목록입니다. Census 원천은 성씨 약 162,000개, SCOWL 원천은 약 167,000단어이지만, 가공 후 실제 앱 탑재 규모는 `english_names.txt` 28,378개(Census/SSA)와 `english_modern.txt` 71,348개(SCOWL)입니다. `english_names_extra.txt`는 Census/SSA 데이터가 아닌 **수작업으로 선별한 유명인 보충 목록**입니다. 기타 번들 목록은 NGSL(CC BY-SA 4.0), SCOWL(MIT-like), Census/SSA(public domain), GeoNames(CC BY 4.0), Wikidata(CC0), 우리말샘(CC-BY-SA 2.0 KR)에서 출처를 밝혔습니다. **모든 사전 파일은 앱에 정적으로 번들된 읽기 전용 데이터**로, 입력을 기록하지 않고 네트워크를 사용하지 않습니다.
- 구현: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)

### 4. 보안 입력 필드 (비밀번호 등)

macOS와 호스트 앱이 보안 입력(secure event input)을 올바르게 활성화한 필드에서는 **macOS가 OS 차원에서 서드파티 IME를 우회**하므로 하늘키보드는 해당 키 입력을 전달받지 않습니다. 다만 일부 브라우저의 웹 비밀번호 칸은 macOS가 보안 입력을 켜지 않아 하늘키보드가 키를 받고 한글을 조합할 수 있습니다. 이는 애플 기본 입력기를 포함한 모든 한글 입력기에 동일한 플랫폼 한계입니다. 민감한 내용은 영문(ABC) 모드로 입력하는 것을 권장합니다. 어느 경우에도 하늘키보드는 입력 내용을 저장하거나 전송하지 않습니다.

### 5. 진단 로그

- Apple 통합 로깅(`os.log`)을 사용하며, 로그는 **기기 내 시스템 로그에만** 남고 macOS가 자동으로 순환 삭제합니다. 하늘키보드가 별도의 로그 파일을 만들거나 어디로 보내지 않습니다.
- 키 입력 내용(키 코드 등)은 로그에서 **기본 가림(`privacy: .private`) 처리**됩니다 — macOS가 `<private>`로 마스킹하며, 사용자가 디버깅 목적으로 private-data 로깅을 직접 켜지 않는 한 보이지 않습니다 ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). 보안 입력이 올바르게 활성화된 필드의 키는 위 4번대로 IME에 전달되지 않으므로 로그에도 남지 않습니다.

### 6. 검증

하늘키보드는 [MIT 라이선스 오픈소스](https://github.com/Hyunjin-Cho/HaneulKeyboard)입니다. 위의 모든 주장은 소스 코드를 직접 읽거나, 소스로부터 직접 빌드해서 확인할 수 있습니다. 의문이 있으면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 질문해주세요.

---

# English

An IME is sensitive software — it handles your keyboard input. This document states plainly what HaneulKeyboard sees, what it stores, and what it does not do. Every claim below is verifiable against the [public source code](https://github.com/Hyunjin-Cho/HaneulKeyboard).

_Last updated: 2026-06-22_

## At a Glance

| Question | Answer |
|---|---|
| Does it see my keystrokes? | Only **while active as the selected input source**, to compose Hangul. Every IME on macOS works this way. |
| Does it send anything over the network? | **No.** There is not a single line of networking code. Everything happens on-device. |
| Does it store what I type? | **No.** Nothing you type is stored or learned — all decisions happen in memory only. |
| Can it see my passwords? | **Not in fields where macOS and the host app correctly enable secure input.** Some browser-based password fields do not enable it, however, so the IME may receive those keystrokes. We recommend using English (ABC) mode for sensitive input. |
| Can I verify these claims? | Yes. The full source is open under the MIT license. |

## Details

### 1. Keystroke access

The IME receives keystrokes **only while it is the active input source**, in order to compose Hangul jamo into syllables — the standard behavior of every macOS input method (IMKit). When you switch to English (ABC), the system input method handles input and HaneulKeyboard is not involved.

### 2. No network transmission

The source code (`Sources/`, `IMESources/`) contains no networking code whatsoever — no URLSession, no sockets. Nothing you type, and no other data, ever leaves your device. No analytics, no telemetry, no crash reporting.

### 3. Wrong-layout auto-conversion (메ㅔㅣㄷ → apple)

- The decision happens **in memory** at word-commit time; nothing is stored or learned.
- It only consults **read-only dictionaries**: macOS's `/usr/share/dict/words`, bundled English word/name lists, and a bundled Urimalsaem Korean headword list. The Census source contains about 162,000 surnames and the SCOWL source about 167,000 words; after processing, the app actually bundles 28,378 Census/SSA entries in `english_names.txt` and 71,348 SCOWL entries in `english_modern.txt`. `english_names_extra.txt` is **a hand-curated famous-person supplement**, not Census or SSA data. Other bundled lists credit NGSL (CC BY-SA 4.0), SCOWL (MIT-like), Census/SSA (public domain), GeoNames (CC BY 4.0), Wikidata (CC0), and Urimalsaem (CC-BY-SA 2.0 KR). **Every dictionary file is static, bundled, read-only data**; nothing typed is stored and no dictionary network API is used.
- Implementation: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)

### 4. Secure input fields (passwords, etc.)

In fields where macOS and the host app correctly enable secure event input, **macOS bypasses third-party IMEs at the OS level**, so HaneulKeyboard does not receive those keystrokes. Some browser-based password fields do not cause macOS to enable secure input, however, and HaneulKeyboard may then receive the keystrokes and compose Hangul. This is a platform limitation that also affects Apple's input methods. We recommend using English (ABC) mode for sensitive input. In all cases, HaneulKeyboard neither stores nor transmits what you type.

### 5. Diagnostic logging

- HaneulKeyboard uses Apple's unified logging (`os.log`). Logs stay **in the on-device system log only** and are rotated/deleted automatically by macOS. The app creates no log files of its own and sends logs nowhere.
- Keystroke content (such as key codes) is **redacted by default** (`privacy: .private`) — macOS masks it as `<private>` unless you deliberately enable private-data logging for a debug session ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). Keystrokes from fields where secure input is correctly enabled do not reach the IME (see #4), so they do not appear in logs.

### 6. Verifiability

HaneulKeyboard is [open source under the MIT license](https://github.com/Hyunjin-Cho/HaneulKeyboard). You can verify every claim above by reading the source or building it yourself. Questions are welcome on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

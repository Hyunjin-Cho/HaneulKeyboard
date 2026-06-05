# 개인정보 보호 (Privacy)

입력기(IME)는 키보드 입력을 다루는 민감한 소프트웨어입니다. 하늘키보드가 무엇을 보고, 무엇을 저장하고, 무엇을 하지 않는지 명확하게 적습니다. 아래 모든 내용은 [공개된 소스 코드](https://github.com/Hyunjin-Cho/HaneulKeyboard)로 직접 검증할 수 있습니다.

_최종 수정: 2026-06-05_

## 한눈에 보기

| 질문 | 답 |
|---|---|
| 키 입력을 보나요? | 한국어 입력기가 **활성화된 동안만**, 한글 조합을 위해 봅니다. macOS의 모든 IME가 동일하게 동작합니다. |
| 네트워크로 전송하나요? | **아니요.** 코드에 네트워크 호출이 한 줄도 없습니다. 모든 처리는 기기 안에서 끝납니다. |
| 입력 내용을 저장하나요? | 예측 입력 기능(**기본 켜짐**, 설정에서 끌 수 있음)이 *확정한 한글 단어와 사용 빈도*만 기기 내 로컬 파일에 저장합니다. 끄면 아무것도 저장하지 않습니다 (아래 상세). |
| 비밀번호도 보나요? | **못 봅니다.** 보안 입력 필드는 macOS가 OS 차원에서 IME를 우회시킵니다. |
| 주장을 검증할 수 있나요? | 네. 전체 소스가 MIT 라이선스로 공개되어 있습니다. |

## 상세

### 1. 키 입력 접근

하늘키보드 입력기는 한글 자모를 음절로 조합하기 위해, **입력 소스로 선택되어 활성화된 동안** 키 입력을 받습니다. 이것은 macOS 입력기(IMKit) 구조상 모든 IME가 동일하게 동작하는 방식입니다. 영어(ABC) 모드로 전환된 동안에는 시스템 기본 입력기가 처리하며 하늘키보드를 거치지 않습니다.

### 2. 네트워크 전송 — 없음

소스 코드(`Sources/`, `IMESources/`)에 네트워크 관련 코드(URLSession, 소켓 등)가 전혀 없습니다. 입력 내용은 물론 어떤 데이터도 기기 밖으로 나가지 않습니다. 통계, 분석, 크래시 리포트 수집도 하지 않습니다.

### 3. 영타 자동 변환 (메ㅔㅣㄷ → apple)

- 판정은 단어 확정 시점에 **메모리에서만** 일어나며, 입력 내용을 어디에도 저장하거나 학습하지 않습니다.
- 판정에는 **읽기 전용 사전**만 사용합니다: macOS에 기본 포함된 `/usr/share/dict/words` + 앱에 번들된 보충 단어 목록(`english_supplement.txt`).
- 구현: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift)

### 4. 예측 입력 (자동완성)

- **기본 켜짐**이며, 설정에서 끌 수 있습니다. **꺼져 있으면 아무것도 저장하지 않습니다** (파일 자체를 만들지 않습니다).
- 저장 단위는 **공백·문장부호로 구분되어 확정된 한글 단위(2–7음절)와 사용 빈도**뿐입니다. 시각·문장·영문·숫자·자모는 저장하지 않으며, **한 번만 입력된 단위는 파일에 기록되지 않습니다** (2회 이상부터).
- 길이 제한(7음절) 때문에 공백 없이 길게 친 문장은 저장 대상에서 제외됩니다. 단, 공백 없이 친 짧은 구는 한 단위로 저장될 수 있습니다.
- 저장 위치는 기기 내 로컬 파일(`~/Library/Application Support/HaneulKeyboard/`)이며, 어떤 경우에도 기기 밖으로 나가지 않습니다.
- 설정에서 **학습 데이터 전체 삭제**가 가능하고, 앱 설정의 **"전체 제거"** 시 학습 데이터도 함께 삭제됩니다.

### 5. 보안 입력 필드 (비밀번호 등)

비밀번호 입력란처럼 보안 입력이 켜진 필드에서는 **macOS가 OS 차원에서 서드파티 IME를 우회**시킵니다. 하늘키보드는 해당 키 입력을 아예 전달받지 못하므로, 볼 수도 저장할 수도 없습니다.

### 6. 진단 로그

- Apple 통합 로깅(`os.log`)을 사용하며, 로그는 **기기 내 시스템 로그에만** 남고 macOS가 자동으로 순환 삭제합니다. 하늘키보드가 별도의 로그 파일을 만들거나 어디로 보내지 않습니다.
- 키 입력 내용(키 코드 등)은 로그에서 **기본 가림(`privacy: .private`) 처리**됩니다 — macOS가 `<private>`로 마스킹하며, 사용자가 디버깅 목적으로 private-data 로깅을 직접 켜지 않는 한 보이지 않습니다 ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). 보안 입력 필드는 위 5번대로 애초에 IME에 전달되지 않으므로 로그에도 남지 않습니다.

### 7. 검증

하늘키보드는 [MIT 라이선스 오픈소스](https://github.com/Hyunjin-Cho/HaneulKeyboard)입니다. 위의 모든 주장은 소스 코드를 직접 읽거나, 소스로부터 직접 빌드해서 확인할 수 있습니다. 의문이 있으면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 질문해주세요.

---

# English

An IME is sensitive software — it handles your keyboard input. This document states plainly what HaneulKeyboard sees, what it stores, and what it does not do. Every claim below is verifiable against the [public source code](https://github.com/Hyunjin-Cho/HaneulKeyboard).

_Last updated: 2026-06-05_

## At a Glance

| Question | Answer |
|---|---|
| Does it see my keystrokes? | Only **while active as the selected input source**, to compose Hangul. Every IME on macOS works this way. |
| Does it send anything over the network? | **No.** There is not a single line of networking code. Everything happens on-device. |
| Does it store what I type? | Predictive input (**on by default**, can be turned off in Settings) stores *committed Hangul words and their usage frequency* — and nothing else — in a local file. When off, nothing is stored (details below). |
| Can it see my passwords? | **No.** macOS bypasses third-party IMEs for secure input fields at the OS level. |
| Can I verify these claims? | Yes. The full source is open under the MIT license. |

## Details

### 1. Keystroke access

The IME receives keystrokes **only while it is the active input source**, in order to compose Hangul jamo into syllables — the standard behavior of every macOS input method (IMKit). When you switch to English (ABC), the system input method handles input and HaneulKeyboard is not involved.

### 2. No network transmission

The source code (`Sources/`, `IMESources/`) contains no networking code whatsoever — no URLSession, no sockets. Nothing you type, and no other data, ever leaves your device. No analytics, no telemetry, no crash reporting.

### 3. Wrong-layout auto-conversion (메ㅔㅣㄷ → apple)

- The decision happens **in memory** at word-commit time; nothing is stored or learned.
- It only consults **read-only dictionaries**: macOS's built-in `/usr/share/dict/words` plus a bundled supplement list (`english_supplement.txt`).
- Implementation: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift)

### 4. Predictive input (autocomplete)

- **On by default**; can be turned off in Settings. **When off, nothing is stored** (no file is even created).
- The stored unit is exactly: **a boundary-delimited committed Hangul unit (2–7 syllables) and its usage count**. No timestamps, no sentences, no English, no digits, no jamo — and **units typed only once are never written to disk** (recorded from the 2nd occurrence).
- The 7-syllable cap keeps long spaceless sentences out of the store; short spaceless phrases may be stored as one unit.
- Everything lives in a local file on your device (`~/Library/Application Support/HaneulKeyboard/`) and never leaves it.
- Settings offers **full deletion of learned data**, and the app's **"Remove Everything"** option deletes it as well.

### 5. Secure input fields (passwords, etc.)

For fields with secure input enabled (e.g. password fields), **macOS bypasses third-party IMEs at the OS level**. HaneulKeyboard never receives those keystrokes, so it cannot see or store them.

### 6. Diagnostic logging

- HaneulKeyboard uses Apple's unified logging (`os.log`). Logs stay **in the on-device system log only** and are rotated/deleted automatically by macOS. The app creates no log files of its own and sends logs nowhere.
- Keystroke content (such as key codes) is **redacted by default** (`privacy: .private`) — macOS masks it as `<private>` unless you deliberately enable private-data logging for a debug session ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). Secure input fields never reach the IME (see #5), so they never appear in logs.

### 7. Verifiability

HaneulKeyboard is [open source under the MIT license](https://github.com/Hyunjin-Cho/HaneulKeyboard). You can verify every claim above by reading the source or building it yourself. Questions are welcome on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

# 개인정보 보호 (Privacy)

입력기(IME)는 키보드 입력을 다루는 민감한 소프트웨어입니다. 하늘키보드가 무엇을 보고, 무엇을 저장하고, 무엇을 하지 않는지 명확하게 적습니다. 아래 모든 내용은 [공개된 소스 코드](https://github.com/Hyunjin-Cho/HaneulKeyboard)로 직접 검증할 수 있습니다.

_최종 수정: 2026-06-19_

## 한눈에 보기

| 질문 | 답 |
|---|---|
| 키 입력을 보나요? | 한국어 입력기가 **활성화된 동안만**, 한글 조합을 위해 봅니다. macOS의 모든 IME가 동일하게 동작합니다. |
| 네트워크로 전송하나요? | **아니요.** 코드에 네트워크 호출이 한 줄도 없습니다. 모든 처리는 기기 안에서 끝납니다. |
| 입력 내용을 저장하나요? | **아니요.** 입력한 내용을 저장하거나 학습하지 않습니다 — 모든 판정은 메모리에서만 일어납니다. |
| 비밀번호도 보나요? | **못 봅니다.** 보안 입력 필드는 macOS가 OS 차원에서 IME를 우회시킵니다. |
| 주장을 검증할 수 있나요? | 네. 전체 소스가 MIT 라이선스로 공개되어 있습니다. |

## 상세

### 1. 키 입력 접근

하늘키보드 입력기는 한글 자모를 음절로 조합하기 위해, **입력 소스로 선택되어 활성화된 동안** 키 입력을 받습니다. 이것은 macOS 입력기(IMKit) 구조상 모든 IME가 동일하게 동작하는 방식입니다. 영어(ABC) 모드로 전환된 동안에는 시스템 기본 입력기가 처리하며 하늘키보드를 거치지 않습니다.

### 2. 네트워크 전송 — 없음

소스 코드(`Sources/`, `IMESources/`)에 네트워크 관련 코드(URLSession, 소켓 등)가 전혀 없습니다. 입력 내용은 물론 어떤 데이터도 기기 밖으로 나가지 않습니다. 통계, 분석, 크래시 리포트 수집도 하지 않습니다.

### 3. 영타 자동 변환 (메ㅔㅣㄷ → apple)

- 판정은 단어 확정 시점에 **메모리에서만** 일어나며, 입력 내용을 어디에도 저장하거나 학습하지 않습니다.
- 판정에는 **읽기 전용 사전**만 사용합니다: macOS에 기본 포함된 `/usr/share/dict/words` + 앱에 번들된 영어 단어·인명 목록(보충 목록 `english_supplement.txt` · NGSL 고빈도 목록 `english_common.txt` — CC BY-SA 4.0 · SCOWL 현대 영어 목록 `english_modern.txt` — MIT-like · 미국 인구조사국 성씨/사회보장국 이름 목록 `english_names.txt`·`english_names_extra.txt` — public domain) + 한국어 실존 단어 확인용 **우리말샘 표제어 목록**(`korean_words.txt`, 국립국어원, CC-BY-SA 2.0 KR). **모든 사전 파일은 앱에 정적으로 번들된 읽기 전용 데이터**로, 읽기만 하며 어떤 입력도 기록하지 않고 네트워크로 아무것도 주고받지 않습니다 (실시간 사전 API 같은 것을 쓰지 않습니다).
- 구현: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)

### 4. 보안 입력 필드 (비밀번호 등)

비밀번호 입력란처럼 보안 입력이 켜진 필드에서는 **macOS가 OS 차원에서 서드파티 IME를 우회**시킵니다. 하늘키보드는 해당 키 입력을 아예 전달받지 못하므로, 볼 수도 저장할 수도 없습니다.

### 5. 진단 로그

- Apple 통합 로깅(`os.log`)을 사용하며, 로그는 **기기 내 시스템 로그에만** 남고 macOS가 자동으로 순환 삭제합니다. 하늘키보드가 별도의 로그 파일을 만들거나 어디로 보내지 않습니다.
- 키 입력 내용(키 코드 등)은 로그에서 **기본 가림(`privacy: .private`) 처리**됩니다 — macOS가 `<private>`로 마스킹하며, 사용자가 디버깅 목적으로 private-data 로깅을 직접 켜지 않는 한 보이지 않습니다 ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). 보안 입력 필드는 위 4번대로 애초에 IME에 전달되지 않으므로 로그에도 남지 않습니다.

### 6. 검증

하늘키보드는 [MIT 라이선스 오픈소스](https://github.com/Hyunjin-Cho/HaneulKeyboard)입니다. 위의 모든 주장은 소스 코드를 직접 읽거나, 소스로부터 직접 빌드해서 확인할 수 있습니다. 의문이 있으면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 질문해주세요.

---

# English

An IME is sensitive software — it handles your keyboard input. This document states plainly what HaneulKeyboard sees, what it stores, and what it does not do. Every claim below is verifiable against the [public source code](https://github.com/Hyunjin-Cho/HaneulKeyboard).

_Last updated: 2026-06-19_

## At a Glance

| Question | Answer |
|---|---|
| Does it see my keystrokes? | Only **while active as the selected input source**, to compose Hangul. Every IME on macOS works this way. |
| Does it send anything over the network? | **No.** There is not a single line of networking code. Everything happens on-device. |
| Does it store what I type? | **No.** Nothing you type is stored or learned — all decisions happen in memory only. |
| Can it see my passwords? | **No.** macOS bypasses third-party IMEs for secure input fields at the OS level. |
| Can I verify these claims? | Yes. The full source is open under the MIT license. |

## Details

### 1. Keystroke access

The IME receives keystrokes **only while it is the active input source**, in order to compose Hangul jamo into syllables — the standard behavior of every macOS input method (IMKit). When you switch to English (ABC), the system input method handles input and HaneulKeyboard is not involved.

### 2. No network transmission

The source code (`Sources/`, `IMESources/`) contains no networking code whatsoever — no URLSession, no sockets. Nothing you type, and no other data, ever leaves your device. No analytics, no telemetry, no crash reporting.

### 3. Wrong-layout auto-conversion (메ㅔㅣㄷ → apple)

- The decision happens **in memory** at word-commit time; nothing is stored or learned.
- It only consults **read-only dictionaries**: macOS's built-in `/usr/share/dict/words`; bundled English word and name lists (a supplement list `english_supplement.txt`; an NGSL-derived high-frequency list `english_common.txt` — CC BY-SA 4.0; a SCOWL-derived modern-English list `english_modern.txt` — MIT-like; and surname/first-name lists `english_names.txt`/`english_names_extra.txt` from the US Census Bureau and the Social Security Administration — public domain); and a bundled Korean headword list (`korean_words.txt`, from 국립국어원 우리말샘, CC-BY-SA 2.0 KR) used to verify real Korean words. **Every dictionary file is static, bundled, read-only data** — nothing you type is ever written to them, and nothing is ever sent or fetched over the network (no live dictionary APIs).
- Implementation: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)

### 4. Secure input fields (passwords, etc.)

For fields with secure input enabled (e.g. password fields), **macOS bypasses third-party IMEs at the OS level**. HaneulKeyboard never receives those keystrokes, so it cannot see or store them.

### 5. Diagnostic logging

- HaneulKeyboard uses Apple's unified logging (`os.log`). Logs stay **in the on-device system log only** and are rotated/deleted automatically by macOS. The app creates no log files of its own and sends logs nowhere.
- Keystroke content (such as key codes) is **redacted by default** (`privacy: .private`) — macOS masks it as `<private>` unless you deliberately enable private-data logging for a debug session ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). Secure input fields never reach the IME (see #4), so they never appear in logs.

### 6. Verifiability

HaneulKeyboard is [open source under the MIT license](https://github.com/Hyunjin-Cho/HaneulKeyboard). You can verify every claim above by reading the source or building it yourself. Questions are welcome on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

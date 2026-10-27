# 개인정보 보호 (Privacy)

입력기(IME)는 키보드 입력을 다루는 민감한 소프트웨어입니다. 하늘키보드가 무엇을 보고, 무엇을 저장하고, 무엇을 하지 않는지 명확하게 적습니다. 아래 모든 내용은 [공개된 소스 코드](https://github.com/Hyunjin-Cho/HaneulKeyboard)로 직접 검증할 수 있습니다.

_최종 수정: 2026-10-14_

## 한눈에 보기

| 질문 | 답 |
|---|---|
| 키 입력을 보나요? | 한국어 입력기가 **활성화된 동안만**, 한글 조합을 위해 봅니다. macOS의 모든 IME가 동일하게 동작합니다. |
| 네트워크로 전송하나요? | **입력기는 인터넷에 접속하지 않습니다.** 입력·설정·사전을 자동으로 업로드하지 않습니다. 단어 제안은 사용자가 고른 메일 앱/브라우저에 직접 적은 제안 내용을 넘깁니다(8번). 메뉴바 앱의 업데이트 조회·다운로드는 9번을 따릅니다. |
| 입력 내용을 저장하나요? | **아니요.** 입력한 내용을 저장하거나 학습하지 않습니다 — 모든 판정은 메모리에서만 일어납니다. 예외는 **사용자가 직접 관리하는 개인 사전**뿐입니다: 설정에서 직접 적은 단어 목록과, Shift+Space로 **되돌린** 변환의 (한글 표기, 영어) 쌍 최근 50개가 **이 기기 안의 설정 파일에만** 남습니다 (아래 7번). |
| 비밀번호도 보나요? | **macOS와 호스트 앱이 보안 입력을 올바르게 활성화한 필드에서는 받지 않습니다.** 다만 일부 브라우저의 웹 비밀번호 칸은 보안 입력이 켜지지 않아 키를 받을 수 있습니다. 민감한 내용은 영문(ABC) 모드로 입력하는 것을 권장합니다. |
| 주장을 검증할 수 있나요? | 네. 앱 소스는 Apache License 2.0으로 공개하며 LICENSE·NOTICE를 동봉합니다. 사전·글꼴은 별도 고지를 따릅니다. |

## 상세

### 1. 키 입력 접근

하늘키보드 입력기는 한글 자모를 음절로 조합하기 위해, **입력 소스로 선택되어 활성화된 동안** 키 입력을 받습니다. 이것은 macOS 입력기(IMKit) 구조상 모든 IME가 동일하게 동작하는 방식입니다. 영어(ABC) 모드로 전환된 동안에는 시스템 기본 입력기가 처리하며 하늘키보드를 거치지 않습니다.

**다른 입력기로 친 영어 문맥 사용**이 켜져 있으면(기본 켜짐), 하늘키보드로 새 단어를 입력하기 직전에 커서 앞 **최대 128 UTF-16 단위**를 호스트 앱에 한 번 요청합니다. 이미 확정된 영어 단어 하나가 정확히 사전에 있을 때만 이번 단어의 변환 판단에 사용합니다. 선택 영역·다른 조합이 있거나 보안 입력이 켜져 있거나 호스트가 요청을 지원하지 않으면 사용하지 않습니다. 원문은 읽는 동안에만, 영어 단어는 이번 조합 동안에만 메모리에 유지하며 파일·개인 사전·로그·네트워크에 남기지 않습니다. 설정 → 입력 기능 → 자동 변환에서 끌 수 있습니다. 구현: [`ExternalEnglishContext.capture`](./IMESources/ExternalEnglishContext.swift), [`HaneulInputController.prepareExternalEnglishContext`](./IMESources/HaneulInputController.swift), [`InputInferencePolicy`](./Shared/InputInferencePolicy.swift).

### 2. 네트워크 — 자동 업로드 없음 (2026-10-10 개정)

**입력 내용·설정·개인 사전·로그를 자동으로 업로드하지 않습니다.** 사용자가 직접 고른 단어 제안 내용을 외부 작성창으로 넘기는 경우는 8번에 따로 설명합니다. 통계, 분석, 크래시 리포트, 사용자 식별자(계정·기기 ID·광고 ID) 수집이 전부 없습니다.

둘을 구분해 적습니다 — 하늘키보드는 **프로세스가 두 개**입니다.

| | 네트워크 |
|---|---|
| **입력기**(`HaneulKeyboardIM.app`, 소스 `IMESources/`) — 키 입력을 보는 쪽 | **코드가 한 줄도 없습니다.** URLSession·소켓 어느 것도 쓰지 않습니다. `grep -r URLSession IMESources/` 로 직접 확인할 수 있습니다. |
| **메뉴바 앱**(`HaneulKeyboard.app`, 소스 `Sources/`) — 설치·설정을 맡는 쪽. 키 입력을 보지 않습니다 | **업데이트 확인과 사용자가 선택한 업데이트 다운로드**에 인터넷을 씁니다. 아래 9번에 설명하며, 요청과 흐름은 [`Sources/Updater.swift`](./Sources/Updater.swift), 제한된 응답·다운로드 수신은 [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift)가 맡습니다(2026-10-14 정정). 단어 제안의 외부 작성창은 8번에 따로 설명합니다. |

즉 **키 입력을 보는 프로세스는 인터넷에 접속하지 않습니다**(네트워크 코드가 한 줄도 없습니다 — `grep`으로 확인할 수 있습니다). 그리고 인터넷에 접속하는 프로세스는 키 입력을 보지 않습니다. *(2026-09-21 정정: 샌드박스가 강제로 막는 것이 아니라 **코드가 없다**는 것이 사실입니다.)*

### 3. 영타 자동 변환 (메ㅔㅣㄷ → apple)

- 판정은 단어 확정 시점에 **메모리에서만** 일어나며, 입력 내용을 어디에도 저장하거나 학습하지 않습니다.
- 판정에는 **읽기 전용 사전**만 사용합니다: macOS의 `/usr/share/dict/words`, 번들 영어 단어·인명 목록, 우리말샘 표제어 목록입니다. Census 원천은 성씨 약 162,000개, SCOWL 원천은 약 167,000단어이지만, 가공 후 실제 앱 탑재 규모는 `english_names.txt` 28,378개(Census/SSA)와 `english_modern.txt` 71,348개(SCOWL)입니다. `english_names_extra.txt`는 Census/SSA 데이터가 아닌 **수작업으로 선별한 이름·생명체·제품·기술 보충 목록**입니다. 기타 번들 목록은 NGSL(CC BY-SA 4.0), SCOWL(MIT-like), Census/SSA(public domain), GeoNames(CC BY 4.0), Wikidata(CC0), 우리말샘(CC-BY-SA 2.0 KR)에서 출처를 밝혔습니다. **모든 사전 파일은 앱에 정적으로 번들된 읽기 전용 데이터**로, 입력을 기록하지 않고 네트워크를 사용하지 않습니다.
- 구현: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)
- *(2026-09-21 추가)* **설정값**은 macOS 사용자 기본값(`UserDefaults`, 입력기 도메인 `com.hyunjincho.inputmethod.haneul`)에 **기기 안에만** 저장됩니다: 영타 자동 변환 켜기/끄기, 되돌리기 키 선택(`haneul.revertKey`), 자동 변환을 끌 앱 목록(`haneul.disabledAppBundleIDs` — 사용자가 고른 앱의 bundle ID 문자열만), 모든 단어 되돌리기 켜기/끄기(`haneul.manualToggleAllWords` — 참/거짓 하나, 2026-09-21 #15). 입력한 내용은 담기지 않고, 어디로도 전송되지 않으며, "전체 제거" 시 함께 지워집니다. 앱별 끄기를 위해 입력기는 변환 시점에 **현재 앱의 bundle ID만** 확인하고(목록이 비어 있으면 그마저 하지 않음) 기록하지 않습니다.

### 3-1. 등록된 한글 표기 변환 (레스토랑 → restaurant, 축구 → football)

- 앱에 함께 포함한 `phonetic_dictionary.json`을 메모리에서 정확히 조회합니다. AI 호출·네트워크·사용자 입력 수집·자동 학습을 하지 않습니다.
- 사용자가 설정한 되돌리기 단축키를 누를 때만 조회하며, 일반 Space 자동 변환 사전과 분리합니다.
- 직전 변환의 원문과 결과는 되돌리기를 위해 메모리에만 유지합니다. 발음 변환을 되돌려도 개인 사전의 ‘최근 되돌린 변환’에는 저장하지 않습니다.
- 켜기/끄기 값 `haneul.phoneticConversionEnabled`만 같은 IME 설정 도메인에 저장하며, 입력기 제거가 성공한 전체 제거 시 함께 지워집니다(실패 시 보존은 7번).
- 구현: `PhoneticDictionary` · `KoreanComposer.commitPhonetic` · `HaneulInputController.handle`.

### 4. 보안 입력 필드 (비밀번호 등)

macOS와 호스트 앱이 보안 입력(secure event input)을 올바르게 활성화한 필드에서는 **macOS가 OS 차원에서 서드파티 IME를 우회**하므로 하늘키보드는 해당 키 입력을 전달받지 않습니다. 다만 일부 브라우저의 웹 비밀번호 칸은 macOS가 보안 입력을 켜지 않아 하늘키보드가 키를 받고 한글을 조합할 수 있습니다. 이는 애플 기본 입력기를 포함한 모든 한글 입력기에 동일한 플랫폼 한계입니다. 민감한 내용은 영문(ABC) 모드로 입력하는 것을 권장합니다. 어느 경우에도 하늘키보드는 입력 내용을 저장하거나 전송하지 않습니다.

### 5. 진단 로그

- Apple 통합 로깅(`os.log`)을 사용하며, 로그는 **기기 내 시스템 로그에만** 남고 macOS가 자동으로 순환 삭제합니다. 하늘키보드가 별도의 로그 파일을 만들거나 어디로 보내지 않습니다.
- 키 입력 내용(키 코드 등)은 로그에서 **기본 가림(`privacy: .private`) 처리**됩니다 — macOS가 `<private>`로 마스킹하며, 사용자가 디버깅 목적으로 private-data 로깅을 직접 켜지 않는 한 보이지 않습니다 ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). 보안 입력이 올바르게 활성화된 필드의 키는 위 4번대로 IME에 전달되지 않으므로 로그에도 남지 않습니다.

### 6. 검증

하늘키보드는 [Apache License 2.0 오픈소스](https://github.com/Hyunjin-Cho/HaneulKeyboard)입니다. 위의 모든 주장은 소스 코드를 직접 읽거나, 소스로부터 직접 빌드해서 확인할 수 있습니다. 의문이 있으면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 질문해주세요.

### 7. 개인 사전 (2026-09-21 추가)

설정 창의 **개인 사전** 절에서 영타 자동 변환을 사용자가 직접 고칠 수 있습니다. 여기서 다루는 데이터는 세 가지이며, **전부 이 기기 안에만** 있습니다.

| 목록 | 무엇이 저장되나 | 누가 쓰나 |
|---|---|---|
| 변환 추가 | 사용자가 설정에 직접 적은 영어 단어 목록 | 사용자(설정 창) |
| 변환 금지 | 사용자가 직접 적은 영어 단어 또는 한글 표기 목록 | 사용자(설정 창, "금지" 버튼) |
| 최근 되돌린 변환 | 입력기가 영어로 바꿨다가 사용자가 Shift+Space로 **되돌린** 단어의 (한글 표기, 영어) 쌍. 최근 50개, 같은 쌍은 하나만 | 입력기(되돌린 순간) |

- **저장 위치**: 입력기의 설정 도메인 `com.hyunjincho.inputmethod.haneul` (`~/Library/Preferences/`)의 `haneul.personalDict.force` · `haneul.personalDict.block` · `haneul.recentReverts` 키. 일반 텍스트 목록이라 `defaults read com.hyunjincho.inputmethod.haneul` 로 직접 확인할 수 있습니다.
- **저장하지 않는 것**: 키 입력 자체, 앞뒤 문맥(문장), 어느 앱에서 쳤는지, 시각. "최근 되돌린 변환"은 입력기가 **스스로 화면에 넣었던** 영어 단어를 사용자가 취소했을 때 그 단어와 한글 표기만 남기며, 변환되지 않은 입력이나 한글 문장은 어떤 경우에도 기록하지 않습니다. 보안 입력이 켜진 필드에서는 위 4번대로 아예 입력기에 도달하지 않으므로 기록될 수 없습니다. 로그에도 남기지 않습니다.
- **자동 수집 없음**: 사용자가 직접 적거나 직접 되돌린 것만 남고, 입력기가 스스로 단어를 모으거나 학습하지 않습니다. 개인 사전은 입력기 쪽에만 있고 입력기에는 네트워크 코드가 없으므로(2번), 어디로도 전송되지 않습니다 — 업데이트 확인 요청(9번)에도 담기지 않습니다.
- **지우는 방법**: 설정 창에서 항목별 삭제(−) 또는 "최근 기록 지우기". **전체 제거**(설정 → 앱 관리 → 하늘키보드 전체 제거…)는 정식 사용자·시스템 입력기 파일의 부재와 실행 종료·필수 등록·입력 소스 정리를 확인한 뒤 개인 설정을 정리합니다. 입력기 제거 실패·관리자 요청 취소·조회 불명 상태에서는 개인 사전과 설정을 보존합니다. 필수 정리가 실패하면 재시도용 메인 앱도 남깁니다. **Finder에서 메인 앱을 휴지통으로 옮겼을 때의 자동 입력기 정리는 개인 사전·설정을 항상 보존합니다**(2026-10-11 사용자 승인 B안). 개발용 복구 CLI `scripts/uninstall.sh`도 같은 `Shared/RemovalPolicy.swift:RemovalSequence`와 관측 함수를 사용하며, 메인 앱은 수동으로 제거하도록 안내합니다. 설정 정리는 제품 설정 키의 부재를 확인하는 방식이며 macOS가 빈 설정 파일을 남길 수 있습니다.
- 구현: [`IMESources/PersonalDictionary.swift`](./IMESources/PersonalDictionary.swift)(판정·형식), [`Sources/PersonalDictionarySettingsSection.swift`](./Sources/PersonalDictionarySettingsSection.swift)(설정 화면), [`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)(되돌리기 기록 시점)

### 8. 단어 제안 (2026-10-10 개정)

설정의 **단어 제안**과 되돌린 단어의 **제안…**은 내용을 확인하는 창을 엽니다. 사용자는 **이메일로 제안** 또는 **GitHub에서 등록**을 고릅니다. 이메일 수신자는 `lifeismotive@gmail.com`입니다. 앱이 자체 서버로 제출하거나 메일을 자동 발송하는 기능은 없습니다.

- 작성창 URL에는 사용자가 적은 친 글자·기대한/원치 않는 결과·메모, 고른 되돌림 쌍, 앱·macOS 버전만 담깁니다. 앞뒤 문맥·키 입력 기록·전체 개인 사전은 담지 않습니다.
- 이메일은 기본 메일 앱의 작성창을 열고, 사용자가 직접 발송합니다. 메일 앱의 임시보관함 저장·동기화는 해당 앱의 설정을 따릅니다.
- GitHub는 미리 채운 작성 페이지를 기본 브라우저로 엽니다. URL의 내용은 브라우저 요청을 통해 GitHub에 전달될 수 있으며, 공개 이슈로 등록하는 동작은 사용자가 직접 합니다. GitHub 계정이 필요합니다.
- 제안 내용에 비밀번호·개인정보를 적지 마세요. 실제 제출 전 내용을 확인할 수 있습니다.
- 구현: `Sources/WordSuggestion.swift`의 `emailURL`·`issueURL`, `Sources/WordSuggestionSettingsSection.swift`의 작성창 열기, `Sources/PersonalDictionarySettingsSection.swift`의 `suggestRecent`.

### 9. 자동 업데이트 (2026-10-08 갱신)

앱이 **처음으로 인터넷에 접속하는** 기능이라 따로 적습니다. 설정 창의 **업데이트** 절에서 켜고 끌 수 있습니다.

**나가는 요청은 두 가지뿐입니다.**

| 언제 | 어디로 | 무엇이 담기나 |
|---|---|---|
| 새 버전 확인 | `https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest` | **요청 본문 없음.** 헤더 2개뿐: `Accept: application/vnd.github+json`, `User-Agent: HaneulKeyboard/<버전>` |
| 새 버전 내려받기 (사용자가 **업데이트** 버튼을 눌렀을 때만) | `https://github.com/.../releases/download/<버전>/HaneulKeyboard_<버전>.zip` (GitHub의 자산 CDN으로 자동 이동) | 같은 헤더 2개뿐 |

- **올려보내는 데이터가 없습니다**: 계정·이메일·기기 식별자·설치 ID·통계 어느 것도 보내지 않습니다. `User-Agent`에 담기는 것은 **앱 버전 하나**이며, 그 값은 공개된 릴리스 번호(예: `HaneulKeyboard/2026.08`)라 사용자를 가리키지 않습니다. 쿠키를 주고받지 않고(`httpCookieAcceptPolicy = .never`), 디스크 캐시 없는 세션(`ephemeral`)을 씁니다.
- **GitHub가 보게 되는 것**: 다른 웹사이트에 접속할 때와 같습니다 — 요청한 주소, 접속 시각, 그리고 IP 주소(모든 인터넷 요청에 따라옵니다). 하늘키보드가 여기에 무언가를 **더해 보내지 않습니다**. GitHub의 처리 방침은 [GitHub 개인정보처리방침](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement)을 따릅니다.
- **끄면 요청이 0입니다**: "업데이트 자동 확인"을 끄면 앱은 스스로 인터넷에 나가지 않습니다. 그 상태에서는 **"지금 확인" 버튼을 누른 그 순간에만** 위 첫 번째 요청이 한 번 나갑니다.
- **켜져 있을 때(기본값)**: 앱 실행 약 15초 뒤와 실행 중 매시간 마지막 성공 확인에서 24시간이 지났는지 살펴보고, 확인할 때가 되면 위 첫 번째 요청만 보냅니다. 실패하면 다음 시간에 재시도합니다. 새 버전을 발견하면 현재·새 버전 안내창을 한 번 띄우며, 같은 버전은 재실행 뒤에도 자동으로 반복해서 알리지 않습니다. ‘지금 확인’은 같은 버전도 다시 알려줍니다. 새 버전이 있어도 **알리기만 하고 자동으로 설치하지 않습니다** — 내려받기는 사용자가 **업데이트**를 눌러야 시작합니다.
- **받은 파일을 검증한 뒤에만 설치합니다**: 번들 ID, 서명 Team(개발자 인증서), `codesign --verify --deep --strict`(**애플이 발급한 인증서 사슬로 우리 Team이 서명했는지**까지 요구합니다 — 2026-09-21 강화), `spctl -a -t exec`(애플 공증), 버전이 실제로 올라갔는지 — **다섯 가지가 전부 통과할 때만** 응용 프로그램 폴더의 앱을 바꿉니다. 하나라도 어긋나면 받은 파일을 버리고 기존 앱을 그대로 둡니다. 검증에 앞서 압축을 푼 결과가 **추출 폴더 안의 실제 앱 폴더인지**(심볼릭 링크가 아닌지)도 확인합니다. 주소는 HTTPS의 GitHub 도메인으로 제한하며, 다른 곳으로 이동시키려는 응답은 따라가지 않습니다.
- **기기에 남는 것**: 메인 앱 설정 도메인 `com.hyunjincho.haneulkeyboard`의 `haneul.updateAutoCheck`(켜짐/꺼짐), `haneul.updateLastCheck`(마지막 성공 확인 시각), `haneul.updateLatestVersion`(최근 확인한 최신 버전), `haneul.updateLastNotifiedVersion`(이미 알린 버전) 네 값입니다. 어디로도 전송되지 않습니다.
- 구현: [`Sources/Updater.swift`](./Sources/Updater.swift)(요청·업데이트 흐름), [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift)(응답·다운로드 크기 제한), [`Sources/UpdateReplacement.swift`](./Sources/UpdateReplacement.swift)(교체·실패 복구), [`Sources/UpdateDecisions.swift`](./Sources/UpdateDecisions.swift)(판단 규칙), [`Sources/UpdateSettingsSection.swift`](./Sources/UpdateSettingsSection.swift)(설정 화면)

---

# English

An IME is sensitive software — it handles your keyboard input. This document states plainly what HaneulKeyboard sees, what it stores, and what it does not do. Every claim below is verifiable against the [public source code](https://github.com/Hyunjin-Cho/HaneulKeyboard).

_Last updated: 2026-10-14_

## At a Glance

| Question | Answer |
|---|---|
| Does it see my keystrokes? | Only **while active as the selected input source**, to compose Hangul. Every IME on macOS works this way. |
| Does it send anything over the network? | **The IME does not access the internet.** Input, settings, and dictionaries are not automatically uploaded. Word suggestions hand the user-selected draft to a mail app/browser (#8). The menu bar app checks/downloads updates as described in #9. |
| Does it store what I type? | **No.** Nothing you type is stored or learned — all decisions happen in memory only. The one exception is the **personal dictionary you manage yourself**: the word lists you enter in Settings, and the (Hangul form, English) pairs of the last 50 conversions you **reverted** with Shift+Space, kept **only in this device's preferences** (see #7). |
| Can it see my passwords? | **Not in fields where macOS and the host app correctly enable secure input.** Some browser-based password fields do not enable it, however, so the IME may receive those keystrokes. We recommend using English (ABC) mode for sensitive input. |
| Can I verify these claims? | Yes. App code is open under Apache License 2.0 with LICENSE and NOTICE; bundled data/fonts retain their own licenses. |

## Details

### 1. Keystroke access

The IME receives keystrokes **only while it is the active input source**, in order to compose Hangul jamo into syllables — the standard behavior of every macOS input method (IMKit). When you switch to English (ABC), the system input method handles input and HaneulKeyboard is not involved.

With **Use English context typed with another input source** enabled (the default), the IME requests at most **128 UTF-16 units before the caret** once, immediately before a new word starts in HaneulKeyboard. Only one already-committed English word found exactly in the dictionary may guide that word's conversion. It skips selected text, existing composition, secure input, and unsupported host responses. The original substring exists only during the read; the English word exists only for the current composition. Neither is stored in files, personal dictionaries, logs, or network requests. This can be disabled in Settings → Input features → Automatic conversion. Implementation: [`ExternalEnglishContext.capture`](./IMESources/ExternalEnglishContext.swift), [`HaneulInputController.prepareExternalEnglishContext`](./IMESources/HaneulInputController.swift), [`InputInferencePolicy`](./Shared/InputInferencePolicy.swift).

### 2. Network — no automatic uploads (revised 2026-10-10)

**Typing, settings, personal dictionaries, and logs are not automatically uploaded.** User-selected suggestion drafts passed to an external composer are described in #8. No analytics, no telemetry, no crash reporting, and no identifiers of any kind (account, device ID, advertising ID).

The distinction matters because HaneulKeyboard is **two processes**.

| | Networking |
|---|---|
| **The IME** (`HaneulKeyboardIM.app`, source `IMESources/`) — the part that sees your keystrokes | **Not a single line.** No URLSession, no sockets. Verify with `grep -r URLSession IMESources/`. |
| **The menu bar app** (`HaneulKeyboard.app`, source `Sources/`) — the part that handles installation and settings, and never sees keystrokes | Uses the internet for **update checks and user-selected update downloads**, described in #9. [`Sources/Updater.swift`](./Sources/Updater.swift) handles requests and flow; [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift) receives bounded responses and downloads (corrected 2026-10-14). External word-suggestion drafts are described separately in #8. |

In other words: **the process that can see your typing does not reach the internet** (it contains no networking code — verifiable with grep), and the process that reaches the internet cannot see your typing. *(corrected 2026-09-21: this is the absence of networking code, not a sandbox that forbids it.)*

### 3. Wrong-layout auto-conversion (메ㅔㅣㄷ → apple)

- The decision happens **in memory** at word-commit time; nothing is stored or learned.
- It only consults **read-only dictionaries**: macOS's `/usr/share/dict/words`, bundled English word/name lists, and a bundled Urimalsaem Korean headword list. The Census source contains about 162,000 surnames and the SCOWL source about 167,000 words; after processing, the app actually bundles 28,378 Census/SSA entries in `english_names.txt` and 71,348 SCOWL entries in `english_modern.txt`. `english_names_extra.txt` is **a hand-curated supplement of names, organisms, products, and technical terms**, not Census or SSA data. Other bundled lists credit NGSL (CC BY-SA 4.0), SCOWL (MIT-like), Census/SSA (public domain), GeoNames (CC BY 4.0), Wikidata (CC0), and Urimalsaem (CC-BY-SA 2.0 KR). **Every dictionary file is static, bundled, read-only data**; nothing typed is stored and no dictionary network API is used.
- Implementation: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)
- *(added 2026-09-21)* **Settings** are stored **on-device only**, in macOS user defaults (`UserDefaults`, IME domain `com.hyunjincho.inputmethod.haneul`): the auto-correction on/off toggle, the chosen revert key (`haneul.revertKey`), the per-app off list (`haneul.disabledAppBundleIDs` — only the bundle ID strings of apps you picked), and the manual Hangul↔English toggle on/off flag (`haneul.manualToggleAllWords` — a single true/false, 2026-09-21 #15). Nothing you type is part of these values, nothing is transmitted, and "Uninstall everything" removes them. For the per-app list the IME checks **only the current app's bundle ID** at conversion time (and skips even that when the list is empty); it records nothing.

### 4. Secure input fields (passwords, etc.)

In fields where macOS and the host app correctly enable secure event input, **macOS bypasses third-party IMEs at the OS level**, so HaneulKeyboard does not receive those keystrokes. Some browser-based password fields do not cause macOS to enable secure input, however, and HaneulKeyboard may then receive the keystrokes and compose Hangul. This is a platform limitation that also affects Apple's input methods. We recommend using English (ABC) mode for sensitive input. In all cases, HaneulKeyboard neither stores nor transmits what you type.

### 5. Diagnostic logging

- HaneulKeyboard uses Apple's unified logging (`os.log`). Logs stay **in the on-device system log only** and are rotated/deleted automatically by macOS. The app creates no log files of its own and sends logs nowhere.
- Keystroke content (such as key codes) is **redacted by default** (`privacy: .private`) — macOS masks it as `<private>` unless you deliberately enable private-data logging for a debug session ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift)). Keystrokes from fields where secure input is correctly enabled do not reach the IME (see #4), so they do not appear in logs.

### 6. Verifiability

HaneulKeyboard is [open source under Apache License 2.0](https://github.com/Hyunjin-Cho/HaneulKeyboard). You can verify every claim above by reading the source or building it yourself. Questions are welcome on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

### 7. Personal dictionary (added 2026-09-21)

The **Personal dictionary** section in Settings lets you correct the wrong-layout auto-conversion yourself. It involves three lists, and **all of them stay on this device**.

| List | What is stored | Who writes it |
|---|---|---|
| Always convert | English words you typed into Settings | You (Settings) |
| Never convert | English words or Hangul-layout forms you typed into Settings | You (Settings, or the "Block" button) |
| Recently reverted | (Hangul form, English) pairs of conversions the IME made and you **reverted** with Shift+Space. Last 50, one entry per pair | The IME, at the moment you revert |

- **Where**: the IME's defaults domain `com.hyunjincho.inputmethod.haneul` (`~/Library/Preferences/`), keys `haneul.personalDict.force`, `haneul.personalDict.block`, `haneul.recentReverts`. They are plain lists — `defaults read com.hyunjincho.inputmethod.haneul` shows exactly what is there.
- **What is not stored**: keystrokes, surrounding text, which app you were typing in, timestamps. "Recently reverted" records only an English word **the IME itself had inserted** and you then cancelled, plus its Hangul form; unconverted input and Korean sentences are never recorded. Fields with secure input enabled never reach the IME (#4), so nothing from them can be recorded. Nothing is written to logs.
- **No automatic collection**: only what you enter or revert yourself is kept; the IME does not gather or learn words on its own. The personal dictionary lives in the IME, which has no networking code at all (#2), so it is never transmitted — and it is not part of the update check either (#9).
- **How to delete**: delete entries or clear recent records in Settings. Full removal verifies absence of both canonical IME bundles, stopped IME processes, required registrations, and disabled input sources before clearing product preferences. Failed or unobservable IME cleanup preserves personal data; a failed required step preserves the main app for retry. **Finder-triggered IME self-cleanup always preserves personal dictionaries and preferences** (owner-approved option B, 2026-10-11). The developer recovery CLI uses the same Swift policy and observations, and leaves main-app removal to Finder. Empty preference files can remain after macOS confirms the product keys are absent.
- Implementation: [`IMESources/PersonalDictionary.swift`](./IMESources/PersonalDictionary.swift) (decision and format), [`Sources/PersonalDictionarySettingsSection.swift`](./Sources/PersonalDictionarySettingsSection.swift) (Settings UI), [`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift) (when a revert is recorded)

### 8. Word suggestions (revised 2026-10-10)

Settings and **Suggest…** in the reverted-word list open a review form. Choose **Email** or **GitHub**. Email drafts are addressed to `lifeismotive@gmail.com`. HaneulKeyboard does not submit issues or send email automatically.

- Draft URLs contain only the typed spelling, expected/unwanted result, optional note, selected reverted pair, and app/macOS versions. They do not contain surrounding text, keystroke history, or the whole personal dictionary.
- Email opens the default mail application's composer; the user sends it. Draft storage/synchronization follows that application's settings.
- GitHub opens a pre-filled issue page in the default browser. The URL contents may reach GitHub through the browser request; the user creates the public issue manually. A GitHub account is required.
- Do not include passwords or personal information. Review the draft before submitting.
- Implementation: `Sources/WordSuggestion.swift` (`emailURL`, `issueURL`), `Sources/WordSuggestionSettingsSection.swift`, and `Sources/PersonalDictionarySettingsSection.swift` (`suggestRecent`).

### 9. Automatic updates (updated 2026-10-08)

This is the **first feature that reaches the internet**, so it gets its own section. You can turn it on or off in the **Updates** section of Settings.

**There are exactly two outgoing requests.**

| When | Where | What it carries |
|---|---|---|
| Version check | `https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest` | **No request body.** Two headers only: `Accept: application/vnd.github+json` and `User-Agent: HaneulKeyboard/<version>` |
| Download (only after you click **Update**) | `https://github.com/.../releases/download/<version>/HaneulKeyboard_<version>.zip` (redirected to GitHub's asset CDN) | The same two headers, nothing else |

- **Nothing about you is uploaded**: no account, email, device identifier, install ID, or usage statistics. The `User-Agent` carries **one thing — the app version** (e.g. `HaneulKeyboard/2026.08`), a public release number that does not identify you. Cookies are refused (`httpCookieAcceptPolicy = .never`) and the session is `ephemeral` (no disk cache).
- **What GitHub sees**: the same as visiting any website — the URL requested, the time, and your IP address (which accompanies every internet request). HaneulKeyboard adds nothing to that. GitHub's own handling is covered by the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement).
- **Off means zero requests**: with "Check for updates automatically" turned off, the app never reaches the network on its own. The first request above is then made **only at the moment you press "Check now"**.
- **On (the default)**: the app checks whether 24 hours have passed since its last successful check, about 15 seconds after launch and hourly while running. It sends the first request only when due; failed checks retry on the next hourly tick. A notice shows the current and new versions once per new version, including across restarts. “Check now” can show the same version again. Even when a new version exists, it is **only announced, never installed automatically** — downloading begins only when you click **Update**.
- **Downloads are verified before anything is installed**: bundle ID, signing Team (developer certificate), `codesign --verify --deep --strict` (which since 2026-09-21 also requires that an Apple-issued certificate chain and **our Team** produced the signature), `spctl -a -t exec` (Apple notarization), and a genuine version increase — the app in your Applications folder is replaced **only if all five pass**. If any check fails, the download is discarded and your existing app is left untouched. Before any of that, the extracted bundle must be a **real directory inside the extraction folder**, not a symbolic link. Addresses are restricted to GitHub's HTTPS domains, and redirects pointing elsewhere are not followed.
- **What stays on your device**: four values in the main app's defaults domain `com.hyunjincho.haneulkeyboard` — `haneul.updateAutoCheck` (on/off), `haneul.updateLastCheck` (last successful check), `haneul.updateLatestVersion` (last known latest version), and `haneul.updateLastNotifiedVersion` (already announced version). None is transmitted.
- Implementation: [`Sources/Updater.swift`](./Sources/Updater.swift) (requests and update flow), [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift) (response/download size limits), [`Sources/UpdateReplacement.swift`](./Sources/UpdateReplacement.swift) (replacement and failure recovery), [`Sources/UpdateDecisions.swift`](./Sources/UpdateDecisions.swift) (decision rules), [`Sources/UpdateSettingsSection.swift`](./Sources/UpdateSettingsSection.swift) (Settings UI)

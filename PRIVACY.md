# 개인정보 보호 (Privacy)

입력기(IME)는 키보드 입력을 다루는 민감한 소프트웨어입니다. 하늘키보드가 무엇을 보고, 무엇을 저장하고, 무엇을 하지 않는지 명확하게 적습니다. 아래 모든 내용은 [공개된 소스 코드](https://github.com/Hyunjin-Cho/HaneulKeyboard)로 직접 검증할 수 있습니다.

_최종 수정: 2026-11-13_ (2026-11-12 전체 코드 리뷰 수정과 대조: 보안 입력 재확인, 커서 위치 확인, 업데이트 요청 헤더 실측과 검증 항목. 그 전 2026-11-07에 호스트 앱에서 읽는 범위·저장되는 값·로그·진단을 고쳤습니다)

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

**ABC로 친 영어 뒤에 이어 칠 때**이 켜져 있으면(기본 켜짐), 하늘키보드로 새 단어를 입력하기 직전에 커서 앞 **최대 128 UTF-16 단위**를 호스트 앱에 한 번 요청합니다. 이미 확정된 영어 단어 하나가 정확히 사전에 있을 때만 이번 단어의 변환 판단에 사용합니다. 선택 영역·다른 조합이 있거나 보안 입력이 켜져 있거나 호스트가 요청을 지원하지 않으면 사용하지 않습니다. 원문은 읽는 동안에만, 영어 단어는 이번 조합 동안에만 메모리에 유지하며 파일·개인 사전·로그·네트워크에 남기지 않습니다. 설정 → 자동 변환에서 끌 수 있습니다. 구현: [`ExternalEnglishContext.capture`](./IMESources/ExternalEnglishContext.swift), [`HaneulInputController.prepareExternalEnglishContext`](./IMESources/HaneulInputController.swift), [`InputInferencePolicy`](./Shared/InputInferencePolicy.swift).

**입력기가 호스트 앱에 글자를 요청하는 곳은 위 영어 문맥과 아래 둘이 전부입니다**(2026-11-07 `IMESources/`의 호스트 글자 요청 호출을 하나씩 대조해 확인했습니다). 요청한 순간의 판정에만 쓰고 메모리에서만 다루며, 파일·개인 사전·로그·네트워크에 남기지 않습니다. 키 처리를 시작할 때와, 호스트에 커서·글자를 묻거나 바꾸기 **직전마다** 보안 입력을 다시 확인해 켜져 있으면 묻지 않고 그 작업을 멈춥니다(2026-11-12 #224).

- **변환 단축키(기본 Shift+Space)를 눌렀을 때:** 직전에 바꾼 단어를 찾으려고 커서 앞 글자를 읽습니다. 읽는 길이는 그 단어 길이에 4글자를 더한 만큼이고, 못 찾으면 64글자를 더한 만큼까지 넓혀 다시 읽습니다(UTF-16 단위). 직전에 바꾼 단어가 없을 때는 커서 앞 **최대 64 UTF-16 단위**를 읽습니다. 단어 바로 뒤 경계를 확인하려고 커서 뒤 1글자를, 문서 맨 앞에서는 맨 앞 1글자를 읽을 수 있습니다. 글자를 바꾼 뒤에는 그 자리를 다시 읽어 호스트가 교체를 받아들였는지 확인하고, 반영이 늦는 앱에서는 다음 키를 칠 때 한 번 더 확인합니다. 아직 확정하지 않은 조합 글자(밑줄 글자)에서 단축키를 누르면 그 조합 글자 자체와 바로 앞·뒤 1글자를 읽어, 화면이 입력기가 보낸 것과 같은지와 등록 단어의 경계인지를 확인합니다.
- **슬래시(`/`) 영어 입력 중:** 시작 기호 `/` 한 글자와 선택·조합 범위의 위치를 읽어, 그 `/`가 지워졌는지 알아봅니다. 읽은 글자는 저장하지 않고, 읽었다는 사실과 시작 기호의 위치(숫자)만 그 입력 중에 기억합니다. 시작 직후 첫 키에서 시작 자리 글자가 `/`가 아니면(커서 값을 늦게 알려 주는 앱) 커서 바로 앞 1글자를 한 번 더 읽어 `/` 자리를 다시 잡습니다(2026-11-12 #224).

조합 중인 글자의 범위와 커서·선택의 위치(숫자)는 조합과 교체를 위해 그때그때 묻습니다. 앞 낱말의 영어 문맥·숫자를 기억하는 동안에는 낱말 경계 직후와 다음 키에서 **커서 위치(숫자)만** 한 번씩 물어 마우스 클릭 등으로 커서가 옮겨졌는지 보고, 옮겨졌으면 그 기억을 버립니다. 글자는 읽지 않습니다(2026-11-12 #224).

### 2. 네트워크 — 자동 업로드 없음 (2026-10-10 개정)

**입력 내용·설정·개인 사전·로그를 자동으로 업로드하지 않습니다.** 사용자가 직접 고른 단어 제안 내용을 외부 작성창으로 넘기는 경우는 8번에 따로 설명합니다. 통계, 분석, 크래시 리포트, 사용자 식별자(계정·기기 ID·광고 ID) 수집이 전부 없습니다.

둘을 구분해 적습니다 — 하늘키보드는 **프로세스가 두 개**입니다.

| | 네트워크 |
|---|---|
| **입력기**(`HaneulKeyboardIM.app`, 소스 `IMESources/`) — 키 입력을 보는 쪽 | **코드가 한 줄도 없습니다.** URLSession·소켓 어느 것도 쓰지 않습니다. `grep -r URLSession IMESources/` 로 직접 확인할 수 있습니다. 2026-11-07부터 `scripts/run_ime_tests.sh`가 입력기 소스(`IMESources/`·`Shared/`)에 알려진 네트워크 API 이름이 없는지 검사하고, 빌드한 입력기 바이너리가 네트워크 심볼을 가져다 쓰지 않는지도 번들 검증(`scripts/verify_license_resources.py`)이 봅니다. 이 검사는 알려진 이름을 지키는 장치이지 운영체제가 막아 주는 것은 아닙니다. |
| **메뉴바 앱**(`HaneulKeyboard.app`, 소스 `Sources/`) — 설치·설정을 맡는 쪽. 키 입력을 보지 않습니다 | **업데이트 확인과 사용자가 선택한 업데이트 다운로드**에 인터넷을 씁니다. 아래 9번에 설명하며, 요청과 흐름은 [`Sources/Updater.swift`](./Sources/Updater.swift), 제한된 응답·다운로드 수신은 [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift)가 맡습니다(2026-10-14 정정). 단어 제안의 외부 작성창은 8번에 따로 설명합니다. |

즉 **키 입력을 보는 프로세스(입력기)는 인터넷에 접속하지 않습니다**(네트워크 코드가 한 줄도 없습니다 — `grep`으로 확인할 수 있습니다). 그리고 인터넷에 접속하는 메뉴바 앱은 **다른 앱에서 치는 키 입력**을 보지 않습니다. *(2026-09-21 정정: 샌드박스가 강제로 막는 것이 아니라 **코드가 없다**는 것이 사실입니다.)*

*(2026-11-07 범위 정정)* 메뉴바 앱 자신의 입력칸 — 시작하기의 연습칸, 개인 사전과 단어 제안의 입력칸 — 에서는 입력기를 거친 글자를 앱이 받습니다. 설정 화면은 입력기가 남긴 최근 되돌림 기록(7번)을 읽습니다. 이 글자들이 앱 바깥으로 나가는 경우는 사용자가 단어 제안의 작성창 열기 버튼을 눌렀을 때뿐이며 8번을 따릅니다.

### 3. 영어 자동 변환 (메ㅔㅣㄷ → apple)

- 판정은 단어 확정 시점에 **메모리에서만** 일어나며, 입력 내용을 어디에도 저장하거나 학습하지 않습니다.
- 판정에는 **읽기 전용 사전**만 사용합니다: macOS의 `/usr/share/dict/words`(시스템 파일을 복사하지 않고 그 자리에서 읽습니다), 앱에 들어 있는 영어 사전 표 `english_bundled.txt`(영어 단어·인명·지명 목록 여섯 개를 합쳐 정렬한 것), 보충 목록 `english_supplement.txt`·`english_common.txt`, 우리말샘 표제어 목록입니다. Census 원천은 성씨 약 162,000개, SCOWL 원천은 약 167,000단어이지만, 가공 후 실제 규모는 `english_names.txt` 28,378개(Census/SSA)와 `english_modern.txt` 71,348개(SCOWL)이고, 이 둘은 2026-11-07부터 입력기 번들에 따로 들어 있지 않고 `english_bundled.txt` 표 안에 합쳐져 들어갑니다. `english_names_extra.txt`는 Census/SSA 데이터가 아닌 **수작업으로 선별한 이름·생명체·제품·기술 보충 목록**이고, 2026-11-13(#225)부터 요일·달·나라·국적·언어 이름이 들어 있습니다. 기타 번들 목록은 NGSL(CC BY-SA 4.0), SCOWL(MIT-like), Census/SSA(public domain), GeoNames(CC BY 4.0), Wikidata(CC0), 우리말샘(CC-BY-SA 2.0 KR)에서 출처를 밝혔습니다. **모든 사전 파일은 앱에 정적으로 번들된 읽기 전용 데이터**로, 입력을 기록하지 않고 네트워크를 사용하지 않습니다.
- 구현: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)
- *(2026-09-21 추가, 2026-11-07 코드와 대조해 정정)* **설정값**은 macOS 사용자 기본값(`UserDefaults`)에 **기기 안에만** 저장됩니다. 입력기 도메인 `com.hyunjincho.inputmethod.haneul`에는 기능 켜기/끄기 값(영어 자동 변환 `haneul.autoEnglishEnabled`, 등록 단어 변환 `haneul.phoneticConversionEnabled`, 슬래시 영어 입력 `haneul.slashEnglishEnabled`, 다른 입력기 영어 문맥 `haneul.externalEnglishContextEnabled`, 등록 단어 조합 인식 `haneul.dictionaryCompoundEnabled`), 되돌리기 키 선택(`haneul.revertKey`), 자동 변환을 끌 앱 목록(`haneul.disabledAppBundleIDs` — 사용자가 고른 앱의 bundle ID 문자열만), 개인 사전(7번), 그리고 **메인 앱의 설치 위치 기록**(`haneul.mainAppPath`, `haneul.mainAppFileID`)이 들어갑니다. 설치 위치 기록은 메인 앱이 실행할 때마다 자기 파일 경로와 파일 번호(inode)를 남기는 것으로, 입력기가 메인 앱이 지워졌는지 알아보고 스스로 정리할 때 씁니다. 경로에 macOS 사용자 계정 이름이 들어갈 수 있습니다. 메인 앱 도메인 `com.hyunjincho.haneulkeyboard`에는 안내를 마쳤는지, 메뉴바 아이콘을 보일지(`haneul.showsMenuBarIcon`), 로그인 항목 자동 등록을 이미 시도했는지(`haneul.loginItemAutoRegistered`), 시스템 설정 목록을 다시 열어야 하는지(`haneul.inputSourceSettingsNeedsReload`), 업데이트 관련 값(9번) 같은 앱 상태가 들어갑니다. 입력한 내용은 어느 값에도 담기지 않고, 어디로도 전송되지 않으며, "전체 제거" 시 함께 지워집니다. *(2026-11-10 #216: 미리 친 단어 한/영 바꾸기 설정 `haneul.manualToggleAllWords`를 없앴습니다. 이전 버전이 남긴 값은 더 읽지 않으며 "전체 제거" 시 함께 지워집니다.)* 앱별 끄기를 위해 입력기는 변환 시점에 **현재 앱의 bundle ID만** 확인하고(목록이 비어 있으면 그마저 하지 않음) 기록하지 않습니다.

### 3-1. 등록된 한글 표기 변환 (레스토랑 → restaurant, 축구 → football)

- 앱에 함께 포함한 `phonetic_dictionary.json`을 메모리에서 정확히 조회합니다. AI 호출·네트워크·사용자 입력 수집·자동 학습을 하지 않습니다.
- 사용자가 설정한 되돌리기 단축키를 누를 때만 조회하며, 일반 Space 자동 변환 사전과 분리합니다. 그때 호스트 앱에서 읽는 글자의 범위는 1번에 적었습니다.
- 직전 변환의 원문과 결과는 되돌리기를 위해 메모리에만 유지합니다. 발음 변환을 되돌려도 개인 사전의 ‘최근 되돌린 변환’에는 저장하지 않습니다.
- 켜기/끄기 값 `haneul.phoneticConversionEnabled`만 같은 IME 설정 도메인에 저장하며, 입력기 제거가 성공한 전체 제거 시 함께 지워집니다(실패 시 보존은 7번).
- 구현: `PhoneticDictionary` · `KoreanComposer.commitPhonetic` · `HaneulInputController.handle`.

### 4. 보안 입력 필드 (비밀번호 등)

macOS와 호스트 앱이 보안 입력(secure event input)을 올바르게 활성화한 필드에서는 **macOS가 OS 차원에서 서드파티 IME를 우회**하므로 하늘키보드는 해당 키 입력을 전달받지 않습니다. 다만 일부 브라우저의 웹 비밀번호 칸은 macOS가 보안 입력을 켜지 않아 하늘키보드가 키를 받고 한글을 조합할 수 있습니다. 이는 애플 기본 입력기를 포함한 모든 한글 입력기에 동일한 플랫폼 한계입니다. 민감한 내용은 영문(ABC) 모드로 입력하는 것을 권장합니다. 어느 경우에도 하늘키보드는 입력 내용을 저장하거나 전송하지 않습니다.

### 5. 진단 로그 (2026-11-07 코드와 대조해 고침)

- Apple 통합 로깅(`os.log`)을 사용하며, 로그는 **기기 내 시스템 로그에만** 남고 macOS가 자동으로 순환 삭제합니다. 하늘키보드가 별도의 로그 파일을 만들거나 어디로 보내지 않습니다.
- **출시 빌드의 입력기는 키 입력을 로그에 남기지 않습니다.** 키 코드를 기록하는 줄은 개발용 Debug 빌드에만 컴파일되고(그 줄도 키 코드를 `privacy: .private`로 가립니다), 출시 빌드에는 없습니다. 커서 위치·읽은 길이 같은 되돌리기 진단 줄도 Debug 빌드에만 있습니다. 출시 빌드의 입력기가 남기는 것은 입력기가 활성화·비활성화되는 시점을 알리는 `activateServer`·`deactivateServer` 문자열(대개 입력칸이나 앱을 옮길 때 찍힙니다), 입력기 시작 실패 오류, 메인 앱이 지워졌을 때 입력기가 스스로 정리하는 단계의 결과(`orphan:` 줄)입니다 ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift), [`IMESources/OrphanWatcher.swift`](./IMESources/OrphanWatcher.swift)).
- **선택 진단 추적(R12):** 기본은 꺼짐입니다. `haneul.roundTripTraceStart`·`haneul.roundTripTraceEnd`(시작·끝 Unix 시각, 간격 30분 이하) 두 값을 직접 `defaults write`로 넣었을 때만 켜지고, 그 시간 안에서 최대 512건을 `roundtrip` 범주에 남깁니다. 기록하는 것은 이벤트 이름·단계 이름·조합 중인지·직전 변환 쌍이 있는지와 그 변환의 종류(자동·자판·등록 단어)·되돌리기 번호와, 입력기의 컨트롤러 객체마다 새로 만드는 무작위 식별자(UUID — 사용자나 기기를 가리키지 않습니다)뿐입니다. 글자·키 코드·좌표·앱 이름·입력칸 식별자는 받지 않습니다. 이 줄은 공개(public)로 기록되어 `log show`로 읽을 수 있습니다 ([`IMESources/RoundTripTrace.swift`](./IMESources/RoundTripTrace.swift)).
- **메인 앱의 로그:** 설치·업데이트·입력기 갱신의 진행 상황과 실패 사유를 남깁니다. 설치 위치(파일 경로)와 업데이트 버전 번호가 공개로 기록될 수 있고, 경로에 macOS 사용자 계정 이름이 들어갈 수 있습니다. 입력한 내용은 담기지 않습니다.
- 보안 입력이 올바르게 활성화된 필드의 키는 위 4번대로 IME에 전달되지 않으므로 로그에도 남지 않습니다.

### 6. 검증

하늘키보드는 [Apache License 2.0 오픈소스](https://github.com/Hyunjin-Cho/HaneulKeyboard)입니다. 위의 모든 주장은 소스 코드를 직접 읽거나, 소스로부터 직접 빌드해서 확인할 수 있습니다. 의문이 있으면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 질문해주세요.

### 7. 개인 사전 (2026-09-21 추가)

설정 창의 **개인 사전** 절에서 영어 자동 변환을 사용자가 직접 고칠 수 있습니다. 여기서 다루는 데이터는 세 가지이며, **전부 이 기기 안에만** 있습니다.

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

### 8-1. 응원하기 (2026-11-07 추가)

**응원하기** 창의 **GitHub에서 후원하기**는 GitHub Sponsors 후원 페이지(`https://github.com/sponsors/Hyunjin-Cho`)를 기본 브라우저로 엽니다. 앱은 이 주소를 여는 것 외에 아무것도 보내지 않으며, 후원 여부와 결제 정보를 알 수 없습니다. 결제는 GitHub에서 이루어지고 GitHub의 약관과 개인정보 처리방침을 따릅니다. 후원 여부는 기능에 영향을 주지 않습니다.

### 9. 새 버전 알림과 설치 (2026-10-24 갱신)

앱이 **처음으로 인터넷에 접속하는** 기능이라 따로 적습니다. 설정 창의 **설치·업데이트**에서 **새 버전 알림**을 켜고 끌 수 있습니다.

**나가는 요청은 두 가지뿐입니다.**

| 언제 | 어디로 | 무엇이 담기나 |
|---|---|---|
| 새 버전 확인 | `https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest` | **요청 본문 없음.** 앱이 넣는 헤더는 3개: `Accept: application/vnd.github+json`, `User-Agent: HaneulKeyboard/<버전>`, `Accept-Language: en`(누구에게나 같은 고정값 — macOS가 붙이던 이 Mac의 언어 설정 순서를 보내지 않도록 2026-11-13에 바꿨습니다). macOS 네트워크 기능(URLSession)이 표준 헤더를 덧붙입니다: 압축 방식(`Accept-Encoding`)·연결(`Connection`)·호스트(`Host`) — 2026-11-13 로컬 서버로 실측(#226). |
| 새 버전 내려받기 (사용자가 **새 버전 설치** 버튼을 눌렀을 때만) | `https://github.com/.../releases/download/<버전>/HaneulKeyboard_<버전>.zip` (GitHub의 자산 CDN으로 자동 이동) | 위와 같은 헤더 |

- **올려보내는 데이터가 없습니다**: 계정·이메일·기기 식별자·설치 ID·통계 어느 것도 보내지 않습니다. `User-Agent`에 담기는 것은 **앱 버전 하나**이며, 그 값은 공개된 릴리스 번호(예: `HaneulKeyboard/2026.08`)라 사용자를 가리키지 않습니다. 쿠키를 주고받지 않고(`httpCookieAcceptPolicy = .never`), 디스크 캐시 없는 세션(`ephemeral`)을 씁니다.
- **GitHub가 보게 되는 것**: 다른 웹사이트에 접속할 때와 같습니다 — 요청한 주소, 접속 시각, 그리고 IP 주소(모든 인터넷 요청에 따라옵니다). 하늘키보드가 여기에 무언가를 **더해 보내지 않습니다**. GitHub의 처리 방침은 [GitHub 개인정보처리방침](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement)을 따릅니다.
- **끄면 요청이 0입니다**: "새 버전 알림"을 끄면 앱은 스스로 인터넷에 나가지 않습니다. 그 상태에서는 **"지금 확인" 버튼을 누른 그 순간에만** 위 첫 번째 요청이 한 번 나갑니다.
- **켜져 있을 때(기본값)**: 한 달에 한 번 확인합니다(2026-11-08 변경, 예전에는 하루에 한 번). 앱 실행 약 15초 뒤와 실행 중 매시간 마지막 성공 확인이 이번 달 1일보다 앞인지 살펴보고, 확인할 때가 되면 위 첫 번째 요청만 보냅니다. 1일에 Mac을 켜지 않았으면 그다음 처음 켤 때 확인합니다. 실패하면 다음 시간에 재시도합니다. 새 버전을 발견하면 현재·새 버전 안내창을 한 번 띄우며, 같은 버전은 재실행 뒤에도 자동으로 반복해서 알리지 않습니다. ‘지금 확인’의 결과는 같은 설정 화면에 표시하고 별도 알림창을 띄우지 않습니다. 설정에서 확인한 버전도 이후 자동으로 반복 안내하지 않습니다. 새 버전이 있어도 **알리기만 하고 자동으로 설치하지 않습니다** — 내려받기는 사용자가 **새 버전 설치**를 눌러야 시작합니다.
- **받은 파일을 검증한 뒤에만 설치합니다**: 번들 ID, 서명 Team(개발자 인증서), `codesign --verify --deep --strict`(**애플이 발급한 인증서 사슬로 우리 Team이 서명했는지**까지 요구합니다 — 2026-09-21 강화), `spctl -a -t exec`(애플 공증), 버전이 실제로 올라갔는지, 받은 앱의 버전이 안내한 새 버전과 같은지(2026-11-13 #226) — **여섯 가지가 전부 통과할 때만** 응용 프로그램 폴더의 앱을 바꿉니다. 하나라도 어긋나면 받은 파일을 버리고 기존 앱을 그대로 둡니다. 검증에 앞서 압축을 푼 결과가 **추출 폴더 안의 실제 앱 폴더인지**(심볼릭 링크가 아닌지)도 확인합니다. 압축은 풀기 전에 목록(항목 수·크기·경로)을 보고, 푸는 동안에도 쌓인 양을 지켜봐 2,000항목·512MiB·120초를 넘으면 멈추고 지웁니다(2026-11-13 #226). 설치 직전에는 복사본의 번들 ID·버전·서명을 한 번 더 확인합니다. 주소는 HTTPS의 GitHub 도메인으로 제한하며, 다른 곳으로 이동시키려는 응답은 따라가지 않습니다.
- **기기에 남는 것(업데이트 기능 한정 — 다른 설정값은 3번)**: 메인 앱 설정 도메인 `com.hyunjincho.haneulkeyboard`의 `haneul.updateAutoCheck`(켜짐/꺼짐), `haneul.updateLastCheck`(마지막 성공 확인 시각), `haneul.updateLatestVersion`(최근 확인한 최신 버전), `haneul.updateLastNotifiedVersion`(이미 알린 버전) 네 값입니다. 어디로도 전송되지 않습니다.
- 구현: [`Sources/Updater.swift`](./Sources/Updater.swift)(요청·업데이트 흐름), [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift)(응답·다운로드 크기 제한), [`Sources/UpdateReplacement.swift`](./Sources/UpdateReplacement.swift)(교체·실패 복구), [`Sources/UpdateDecisions.swift`](./Sources/UpdateDecisions.swift)(판단 규칙), [`Sources/UpdateSettingsSection.swift`](./Sources/UpdateSettingsSection.swift)(설정 화면)

---

# English

An IME is sensitive software — it handles your keyboard input. This document states plainly what HaneulKeyboard sees, what it stores, and what it does not do. Every claim below is verifiable against the [public source code](https://github.com/Hyunjin-Cho/HaneulKeyboard).

_Last updated: 2026-11-13_ (checked against the fixes from the 2026-11-12 full code review: secure-input re-checks, caret-position checks, measured update request headers and the added verification steps; on 2026-11-07 the host-app reads, stored values, logs and diagnostics were re-checked)

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

With **Use English context typed with another input source** enabled (the default), the IME requests at most **128 UTF-16 units before the caret** once, immediately before a new word starts in HaneulKeyboard. Only one already-committed English word found exactly in the dictionary may guide that word's conversion. It skips selected text, existing composition, secure input, and unsupported host responses. The original substring exists only during the read; the English word exists only for the current composition. Neither is stored in files, personal dictionaries, logs, or network requests. This can be disabled in Settings → Automatic conversion. Implementation: [`ExternalEnglishContext.capture`](./IMESources/ExternalEnglishContext.swift), [`HaneulInputController.prepareExternalEnglishContext`](./IMESources/HaneulInputController.swift), [`InputInferencePolicy`](./Shared/InputInferencePolicy.swift).

**The English context above and the two cases below are the only times the IME asks a host app for text** (checked on 2026-11-07 by going through the host-text request calls in `IMESources/` one by one). The text is used only for that decision, held in memory, and never written to files, personal dictionaries, logs, or the network. Secure input is checked when a key starts being handled **and again right before every** caret or text request or replacement; if it is on, the IME does not ask and stops that step (2026-11-12, #224).

- **When you press the conversion shortcut (Shift+Space by default):** to find the word it just converted, the IME reads the text before the caret — the length of that word plus 4 characters, widened to plus 64 if it is not found (UTF-16 units). When there is no word it just converted, it reads **at most 64 UTF-16 units** before the caret. It may read 1 character after the caret to check the boundary right after the word, and 1 character at the very start of a document. After replacing text it reads that spot again to confirm the host accepted the replacement, and with hosts that update late it checks once more on the next key. When you press the shortcut on a composition that is not yet committed (the underlined text), it reads that composed text itself and 1 character before and after it, to confirm the screen matches what the IME sent and that it sits on a registered-word boundary.
- **During slash (`/`) English input:** it reads the one starting `/` character and the positions of the selection and composition ranges to find out whether that `/` was deleted. The text read is not stored; only the fact that it was read and the starting position (a number) are remembered during that input. If, on the first key right after starting, the character at the start position is not `/` (an app that reports the caret late), it reads the one character right before the caret once more to find the `/` again (2026-11-12, #224).

The range of the composition in progress and the caret/selection positions (numbers) are asked for on the spot to compose and replace text. While the previous word's English context or digits are remembered, the IME asks **only for the caret position (a number)** once right after the word boundary and once on the next key, to notice that the caret was moved (for example by a mouse click); if it moved, that memory is dropped. No text is read for this (2026-11-12, #224).

### 2. Network — no automatic uploads (revised 2026-10-10)

**Typing, settings, personal dictionaries, and logs are not automatically uploaded.** User-selected suggestion drafts passed to an external composer are described in #8. No analytics, no telemetry, no crash reporting, and no identifiers of any kind (account, device ID, advertising ID).

The distinction matters because HaneulKeyboard is **two processes**.

| | Networking |
|---|---|
| **The IME** (`HaneulKeyboardIM.app`, source `IMESources/`) — the part that sees your keystrokes | **Not a single line.** No URLSession, no sockets. Verify with `grep -r URLSession IMESources/`. Since 2026-11-07 `scripts/run_ime_tests.sh` also checks that the IME sources (`IMESources/`, `Shared/`) contain no known networking API names, and the bundle verification (`scripts/verify_license_resources.py`) checks that the built IME binary imports no networking symbols. These checks guard known names; they are not enforced by the operating system. |
| **The menu bar app** (`HaneulKeyboard.app`, source `Sources/`) — the part that handles installation and settings, and never sees keystrokes | Uses the internet for **update checks and user-selected update downloads**, described in #9. [`Sources/Updater.swift`](./Sources/Updater.swift) handles requests and flow; [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift) receives bounded responses and downloads (corrected 2026-10-14). External word-suggestion drafts are described separately in #8. |

In other words: **the process that can see your typing (the IME) does not reach the internet** (it contains no networking code — verifiable with grep), and the menu bar app that reaches the internet cannot see **what you type in other apps**. *(corrected 2026-09-21: this is the absence of networking code, not a sandbox that forbids it.)*

*(scope correction 2026-11-07)* In the menu bar app's own text fields — the practice field in the introduction and the personal dictionary and word-suggestion fields — the app receives the text that passed through the IME. The Settings screen reads the recent-reverts list the IME keeps (#7). That text leaves the app only when you press the button that opens a suggestion draft, as described in #8.

### 3. Wrong-layout auto-conversion (메ㅔㅣㄷ → apple)

- The decision happens **in memory** at word-commit time; nothing is stored or learned.
- It only consults **read-only dictionaries**: macOS's `/usr/share/dict/words` (read in place from the system file, not copied), the English dictionary table bundled with the app, `english_bundled.txt` (six English word, name and place lists merged and sorted), the supplement lists `english_supplement.txt` and `english_common.txt`, and a bundled Urimalsaem Korean headword list. The Census source contains about 162,000 surnames and the SCOWL source about 167,000 words; after processing the lists hold 28,378 Census/SSA entries (`english_names.txt`) and 71,348 SCOWL entries (`english_modern.txt`), and since 2026-11-07 those two are no longer separate files in the IME bundle but are merged into the `english_bundled.txt` table. `english_names_extra.txt` is **a hand-curated supplement of names, organisms, products, and technical terms**, not Census or SSA data; since 2026-11-13 (#225) it also holds the names of weekdays, months, countries, nationalities, and languages. Other bundled lists credit NGSL (CC BY-SA 4.0), SCOWL (MIT-like), Census/SSA (public domain), GeoNames (CC BY 4.0), Wikidata (CC0), and Urimalsaem (CC-BY-SA 2.0 KR). **Every dictionary file is static, bundled, read-only data**; nothing typed is stored and no dictionary network API is used.
- Implementation: [`IMESources/EnglishDetector.swift`](./IMESources/EnglishDetector.swift), [`IMESources/KoreanDictionary.swift`](./IMESources/KoreanDictionary.swift)
- *(added 2026-09-21; corrected against the code 2026-11-07)* **Settings** are stored **on-device only**, in macOS user defaults (`UserDefaults`). The IME domain `com.hyunjincho.inputmethod.haneul` holds the feature on/off values (auto-correction `haneul.autoEnglishEnabled`, registered-word conversion `haneul.phoneticConversionEnabled`, slash English input `haneul.slashEnglishEnabled`, English context typed with another input source `haneul.externalEnglishContextEnabled`, registered-word compound recognition `haneul.dictionaryCompoundEnabled`), the chosen revert key (`haneul.revertKey`), the per-app off list (`haneul.disabledAppBundleIDs` — only the bundle ID strings of apps you picked), the personal dictionary (#7), and **a record of where the main app is installed** (`haneul.mainAppPath`, `haneul.mainAppFileID`). That record is the main app's own file path and file number (inode), written each time the main app starts; the IME uses it to find out whether the main app was removed so it can clean itself up. The path can contain your macOS account name. The main app domain `com.hyunjincho.haneulkeyboard` holds app state such as whether you finished the introduction, whether to show the menu bar icon (`haneul.showsMenuBarIcon`), whether login-item registration was already attempted (`haneul.loginItemAutoRegistered`), whether the system settings list needs to be reopened (`haneul.inputSourceSettingsNeedsReload`), and the update values (#9). Nothing you type is part of these values, nothing is transmitted, and "Uninstall everything" removes them. For the per-app list the IME checks **only the current app's bundle ID** at conversion time (and skips even that when the list is empty); it records nothing.

### 3-1. Registered Hangul-to-English conversion (레스토랑 → restaurant, 축구 → football) *(added to this English text 2026-11-07 to match the Korean text)*

- The bundled `phonetic_dictionary.json` is looked up exactly, in memory. No AI calls, no networking, no collection of what you type, no automatic learning.
- It is looked up only when you press the revert shortcut you set, and it is separate from the dictionaries used by Space auto-conversion. The range of text read from the host app at that moment is described in #1.
- The original and result of the last conversion are kept in memory only, for reverting. Reverting a registered-word conversion is not saved to the personal dictionary's "recently reverted" list.
- Only the on/off value `haneul.phoneticConversionEnabled` is stored, in the same IME defaults domain, and it is removed by a full removal that succeeds in removing the IME (preserved on failure, see #7).
- Implementation: `PhoneticDictionary`, `KoreanComposer.commitPhonetic`, `HaneulInputController.handle`.

### 4. Secure input fields (passwords, etc.)

In fields where macOS and the host app correctly enable secure event input, **macOS bypasses third-party IMEs at the OS level**, so HaneulKeyboard does not receive those keystrokes. Some browser-based password fields do not cause macOS to enable secure input, however, and HaneulKeyboard may then receive the keystrokes and compose Hangul. This is a platform limitation that also affects Apple's input methods. We recommend using English (ABC) mode for sensitive input. In all cases, HaneulKeyboard neither stores nor transmits what you type.

### 5. Diagnostic logging (corrected against the code 2026-11-07)

- HaneulKeyboard uses Apple's unified logging (`os.log`). Logs stay **in the on-device system log only** and are rotated/deleted automatically by macOS. The app creates no log files of its own and sends logs nowhere.
- **The release IME does not log keystrokes.** The line that records key codes is compiled only into developer Debug builds (and even it redacts the key code with `privacy: .private`); it is not in release builds. The diagnostic lines about caret positions and read lengths during a revert are Debug-only as well. What the release IME does log is the `activateServer`/`deactivateServer` strings marking when the IME is activated or deactivated (typically when you switch fields or apps), an error if the input method server cannot start, and the step results of its own cleanup when the main app was removed (`orphan:` lines) ([`IMESources/HaneulInputController.swift`](./IMESources/HaneulInputController.swift), [`IMESources/OrphanWatcher.swift`](./IMESources/OrphanWatcher.swift)).
- **Optional diagnostic trace (R12):** off by default. It turns on only when you set the two values `haneul.roundTripTraceStart` and `haneul.roundTripTraceEnd` yourself with `defaults write` (start and end Unix times no more than 30 minutes apart); inside that window it writes at most 512 records to the `roundtrip` category. A record holds an event name, a stage name, whether a composition is in progress, whether a last-conversion pair exists and which kind of conversion it was (automatic, keyboard-layout, or registered word), a revert sequence number, and a random identifier (a UUID created per controller object in the IME; it identifies neither you nor your device). It never receives text, key codes, coordinates, app names, or client identifiers. These lines are logged as public and can be read with `log show` ([`IMESources/RoundTripTrace.swift`](./IMESources/RoundTripTrace.swift)).
- **The menu bar app's logs:** progress and failure reasons of installation, updates, and IME refresh. The install location (a file path) and update version numbers may be logged as public, and the path can contain your macOS account name. Nothing you type is included.
- Keystrokes from fields where secure input is correctly enabled do not reach the IME (see #4), so they do not appear in logs.

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

### 9. New-version notices and installation (updated 2026-10-24)

This is the **first feature that reaches the internet**, so it gets its own section. You can turn it on or off using **New-version notifications** in the **Version & Updates** section of Settings.

**There are exactly two outgoing requests.**

| When | Where | What it carries |
|---|---|---|
| Version check | `https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest` | **No request body.** The app adds three headers: `Accept: application/vnd.github+json`, `User-Agent: HaneulKeyboard/<version>`, and `Accept-Language: en` (the same fixed value for everyone — since 2026-11-13 it replaces the language preference order of your Mac that macOS would otherwise send). macOS networking (URLSession) adds standard headers: compression (`Accept-Encoding`), `Connection`, and `Host` — measured against a local server on 2026-11-13 (#226). |
| Download (only after you click **Install new version**) | `https://github.com/.../releases/download/<version>/HaneulKeyboard_<version>.zip` (redirected to GitHub's asset CDN) | The same headers as above |

- **Nothing about you is uploaded**: no account, email, device identifier, install ID, or usage statistics. The `User-Agent` carries **one thing — the app version** (e.g. `HaneulKeyboard/2026.08`), a public release number that does not identify you. Cookies are refused (`httpCookieAcceptPolicy = .never`) and the session is `ephemeral` (no disk cache).
- **What GitHub sees**: the same as visiting any website — the URL requested, the time, and your IP address (which accompanies every internet request). HaneulKeyboard adds nothing to that. GitHub's own handling is covered by the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement).
- **Off means zero requests**: with "New-version notifications" turned off, the app never reaches the network on its own. The first request above is then made **only at the moment you press "Check now"**.
- **On (the default)**: the app checks once a month (changed 2026-11-08; previously once a day). About 15 seconds after launch and hourly while running, it looks at whether its last successful check was before the 1st of the current month. If the Mac was not on that day, it checks the next time the app runs. It sends the first request only when due; failed checks retry on the next hourly tick. A notice shows the current and new versions once per new version, including across restarts. “Check now” displays its result in the same settings screen without a separate notice window. A version seen there is not announced again by automatic checks. Even when a new version exists, it is **only announced, never installed automatically** — downloading begins only when you click **Install new version**.
- **Downloads are verified before anything is installed**: bundle ID, signing Team (developer certificate), `codesign --verify --deep --strict` (which since 2026-09-21 also requires that an Apple-issued certificate chain and **our Team** produced the signature), `spctl -a -t exec` (Apple notarization), a genuine version increase, and a match between the downloaded app's version and the announced release (2026-11-13, #226) — the app in your Applications folder is replaced **only if all six pass**. If any check fails, the download is discarded and your existing app is left untouched. Before any of that, the extracted bundle must be a **real directory inside the extraction folder**, not a symbolic link. The archive's entry list (count, sizes, paths) is checked before extraction and the output is watched while extracting; past 2,000 entries, 512 MiB, or 120 seconds it stops and deletes the files (2026-11-13, #226). Right before installing, the copy's bundle ID, version, and signature are checked once more. Addresses are restricted to GitHub's HTTPS domains, and redirects pointing elsewhere are not followed.
- **What stays on your device (update feature only — other settings are in #3)**: four values in the main app's defaults domain `com.hyunjincho.haneulkeyboard` — `haneul.updateAutoCheck` (on/off), `haneul.updateLastCheck` (last successful check), `haneul.updateLatestVersion` (last known latest version), and `haneul.updateLastNotifiedVersion` (already announced version). None is transmitted.
- Implementation: [`Sources/Updater.swift`](./Sources/Updater.swift) (requests and update flow), [`Sources/UpdateTransport.swift`](./Sources/UpdateTransport.swift) (response/download size limits), [`Sources/UpdateReplacement.swift`](./Sources/UpdateReplacement.swift) (replacement and failure recovery), [`Sources/UpdateDecisions.swift`](./Sources/UpdateDecisions.swift) (decision rules), [`Sources/UpdateSettingsSection.swift`](./Sources/UpdateSettingsSection.swift) (Settings UI)

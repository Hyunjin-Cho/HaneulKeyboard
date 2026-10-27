# 슬래시 영어 입력

기준일: 2026-10-14. 기준 커밋: `de126699e5a2017806d3bcb2746ecf276f26448d` + 빌드87 미커밋 테스트 후보. [요구사항 #87](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/87). 사용자가 이번 구현과 기본 ON을 승인했고, OFF 토글을 요구했다. 실제 설치본 검증 전에는 테스트 후보다.

한글 모드에서 `/help`를 치면 슬래시가 그대로 남고 뒤의 글자는 즉시 영어로 들어간다. 일반 Space가 공백을 한 번 넣은 뒤 다음 키부터 한글을 조합한다. 단어 시작 제한은 없다. 슬래시 앞의 조합에는 기존 자동 변환·앱별 예외·개인 사전 정책을 적용하고 그 뒤의 임시 영어는 사전 판단을 거치지 않는다.

저장 키·기본값·순수 상태 전이는 `Shared/SlashEnglishSession.swift`의 `defaultsKey/defaultEnabled/process/reset`가 소유한다. 기본 ON이며 `Sources/SlashEnglishSettingsSection.swift`가 IME defaults 도메인 `com.hyunjincho.inputmethod.haneul`에 ON/OFF를 쓴다. 위치는 입력 기능 → 단축키 변환 → 슬래시 영어 입력. 자동 변환 토글과 앱별 예외 목록은 이 명시적인 영어 상태와 독립적이다.

`IMESources/HaneulInputController.swift::handle`에서 보안 입력 검사 뒤, 기존 Backspace·변환 단축키 앞에 상태 분기를 둔다. 시작은 `commitActiveBoundary("/")`로 앞 조합을 확정하고, 이후에는 키를 소비/재삽입하지 않고 false로 원래 앱에 전달한다. 일반 Space도 앱이 한 번 입력한다. Backspace·Shift+Space·지정 변환 키·Enter·Tab·Esc·구두점·Option/Ctrl/Cmd 단축키는 원래 앱 동작을 따른다. event 문자가 nil일 때만 기존 물리 키 fallback 원칙에 따라 슬래시/키패드와 Space를 판단한다. 실제 문자가 있으면 항상 문자가 우선이다.

입력 소스 활성/비활성, 클라이언트 객체 교체, 보안 입력, 설정 OFF, **앱의 명시적인 commitComposition 요청**에서는 초기화한다. [Apple의 commitComposition 계약](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/commitcomposition%28_%3A%29)은 입력 세션 종료와 상태 정리를 요구하고 종료 원인을 전달하지 않는다. 따라서 **일부 앱이 Enter/Tab/Esc 뒤 세션 종료를 요청하면 임시 영어도 끝날 수 있다.** 마지막 키 이후 commit 한 번을 무시하는 토큰은 다음 마우스·입력칸 이동을 잘못 무시할 수 있어 넣지 않았다. 이 제한과 같은 브라우저 프록시에서의 입력칸 이동은 실제 지원 앱에서 검증해야 한다. 정상적인 Space 종료와 안전 초기화는 구분한다.

입력 내용은 저장하거나 로그로 남기지 않고 클립보드·전역 이벤트 감시·추가 손쉬운 사용 권한을 사용하지 않는다. 활성화 callback에서 클라이언트의 커서/속성을 새로 읽지 않아 기존 Chromium 교착 방지 규칙을 보존한다.

검증: `bash scripts/run_slash_tests.sh`의 `Tests/SlashEnglishTests.swift`는 기본/저장값·모든 수정자 조합·nil fallback·OFF·초기화·실제 KoreanComposer와 앞 조합/영어 전달/Space 한 번/한글 복귀·개인 사전/문맥 정리를 검사한다. 2026-10-14 재검사는553/0이고 실제IME 전체 타입 검사도0이다. 현재 기록은 `.tmp/slash-doublecheck-2026-10-14/validation.json`·`integration-review.json`·`slash-tests.log`·`ime-typecheck.log`를 따른다. 입력기의 실제 호출 순서·설정도메인·Release87 포함을 독립 대조했으며 새 확정 기능 버그는 발견하지 않았다. 이 검사는 OS IMK 이벤트 라우팅을 대신하지 않는다. 실제 설치·지원 앱 검증 완료 전 #87은 OPEN.


설정/안내 실기 확인: 같은 앱의 설정 창에서 ON/OFF를 바꾸고 바로 안내6페이지로 돌아오면 안내문 상태가 늦게 갱신될 가능성이 있다. `OnboardingView.refresh`의 재조회 계기를 읽어 발견한 낮은 UI 확인 항목이며 실제 두 창 조작으로 재현하지 않았다. 입력기는 매 키마다 설정을 읽으므로 실제 영어 입력 OFF 실패로 확대하지 않는다.

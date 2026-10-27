# 슬래시 영어 입력

기준일: 2026-10-25. 기준 커밋: `de126699e5a2017806d3bcb2746ecf276f26448d` + `feat/T01-particle-rebuild`의 빌드93 미커밋 테스트 후보. [요구사항 #87](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/87). 사용자가 구현·기본 ON·삭제 후 한글 복귀를 요청했고, OFF 토글을 요구했다. 실제 설치본의 새 동작 검증 전에는 테스트 후보다.

한글 모드에서 `/help`를 치면 슬래시가 그대로 남고 뒤의 글자는 즉시 영어로 들어간다. 일반 Space가 공백을 한 번 넣은 뒤 다음 키부터 한글을 조합한다. 닫는 괄호 `) ] }`도 한 번만 앱에 전달하고 다음 키부터 한글로 돌아온다. 종료 기호는 추천 범위로 구현했으며 추가 선호 답변이 있으면 반영한다. `.`·`:`·`/`·`_` 등은 URL·경로 입력을 위해 임시 영어를 유지한다. 단어 시작 제한은 없다. 슬래시 앞의 조합에는 기존 자동 변환·앱별 예외·개인 사전 정책을 적용하고 그 뒤의 임시 영어는 사전 판단을 거치지 않는다.

시작 `/`를 삭제하면 다음 키부터 한글로 돌아온다. 앞 조합 확정 후의 UTF-16 위치를 기억하고, 세션 중 해당 위치의 한 글자·선택 범위·조합 유무를 일시 조회한다. 정확히 `/`를 지우는 Backspace/forward Delete/선택 삭제는 키를 앱에 한 번 전달하고 영어 상태를 끝낸다. 다른 글자로 대체된 것이 확인되어도 끝낸다. `/` 뒤 문자만 지울 때는 영어 상태를 유지한다. 수정키로 단어/줄 전체를 지우는 범위를 추측하지 않는다.

2026-10-25: 시작 `/` 바로 다음 키가 일반 Backspace이면 주변 글자 조회를 제공하지 않는 앱에서도 임시 영어를 끝낸다. 위치 조회가 가능하면 커서가 시작 기호 바로 뒤인지 확인한다. 위치 조회 자체가 불가능한 경우는 `/` 직후라는 단일 키 순서만 사용한다. 중간에 문자·커서 이동·단축키가 끼거나 Fn·Cmd·Option·Ctrl 삭제, 선택 범위 불일치, 조합 중인 범위가 있으면 이 보완 규칙을 쓰지 않는다. 실제 삭제는 원래 앱이 한 번만 수행한다.

위 조회는 `handle`에서만 하며 RPC 중 세션이 바뀌면 즉시 중단한다. 활성화 콜백에는 새 조회가 없다. 근거: `SlashEnglishSession.Context/captureTrigger/process/deletesTrigger`, `HaneulInputController.handle`. 새 상태에 보관하는 값은 시작 위치이며 원문 내용은 아니다.

저장 키·기본값·순수 상태 전이는 `Shared/SlashEnglishSession.swift`의 `defaultsKey/defaultEnabled/process/reset`가 소유한다. 기본 ON이며 `Sources/SlashEnglishSettingsSection.swift`가 IME defaults 도메인 `com.hyunjincho.inputmethod.haneul`에 ON/OFF를 쓴다. 위치는 입력 기능 → 단축키 변환 → 슬래시 영어 입력. 자동 변환 토글과 앱별 예외 목록은 이 명시적인 영어 상태와 독립적이다.

`IMESources/HaneulInputController.swift::handle`에서 보안 입력 검사 뒤, 기존 Backspace·변환 단축키 앞에 상태 분기를 둔다. 시작은 `commitActiveBoundary("/")`로 앞 조합을 확정하고, 이후에는 키를 소비/재삽입하지 않고 false로 원래 앱에 전달한다. 일반 Space도 앱이 한 번 입력한다. Backspace·Shift+Space·지정 변환 키·Enter·Tab·Esc·구두점·Option/Ctrl/Cmd 단축키는 원래 앱 동작을 따른다. event 문자가 nil일 때만 기존 물리 키 fallback 원칙에 따라 슬래시/키패드와 Space를 판단한다. 실제 문자가 있으면 항상 문자가 우선이다.

입력 소스 활성/비활성, 클라이언트 객체 교체, 보안 입력, 설정 OFF, **앱의 명시적인 commitComposition 요청**에서는 초기화한다. [Apple의 commitComposition 계약](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/commitcomposition%28_%3A%29)은 입력 세션 종료와 상태 정리를 요구하고 종료 원인을 전달하지 않는다. 따라서 **일부 앱이 Enter/Tab/Esc 뒤 세션 종료를 요청하면 임시 영어도 끝날 수 있다.** 마지막 키 이후 commit 한 번을 무시하는 토큰은 다음 마우스·입력칸 이동을 잘못 무시할 수 있어 넣지 않았다. 이 제한과 같은 브라우저 프록시에서의 입력칸 이동은 실제 지원 앱에서 검증해야 한다. 정상적인 Space 종료와 안전 초기화는 구분한다.

입력 내용은 저장하거나 로그로 남기지 않고 클립보드·전역 이벤트 감시·추가 손쉬운 사용 권한을 사용하지 않는다. 활성화 callback에서 클라이언트의 커서/속성을 새로 읽지 않아 기존 Chromium 교착 방지 규칙을 보존한다.

검증(2026-10-25): `bash scripts/run_slash_tests.sh` **781/0**, `python3 scripts/run_controller_tests.py` **825/0・145시나리오**. 실제 컨트롤러 메서드와 가상 IMK 호스트에서 수정 전 새 검사 12건의 실패를 재현한 뒤 수정했다. 조회 불가/위치 미지원, 앞 이모지, 즉시 삭제, 중간 입력 후 삭제, 세 닫는 괄호와 수정키를 검사했다. 근거는 `.tmp/priority-work-2026-10-25/{controller-reproduction,slash-final,controller-final}.log`. 이 검사는 OS IMK 이벤트 라우팅을 대신하지 않는다. 실제 설치·지원 앱 검증 완료 전 #87은 OPEN.


설정/안내 실기 확인: 같은 앱의 설정 창에서 ON/OFF를 바꾸고 바로 안내6페이지로 돌아오면 안내문 상태가 늦게 갱신될 가능성이 있다. `OnboardingView.refresh`의 재조회 계기를 읽어 발견한 낮은 UI 확인 항목이며 실제 두 창 조작으로 재현하지 않았다. 입력기는 매 키마다 설정을 읽으므로 실제 영어 입력 OFF 실패로 확대하지 않는다.

# HaneulKeyboard 수동 테스트 체크리스트

> **기준일:** 2026-09-21 · "(프로브가 확인 — scripts/postinstall_probe.sh N번)"이 붙은 줄은 `bash scripts/postinstall_probe.sh`의 N번 항목이 기계로 대신 확인한다(#52). 표기 없는 줄은 사람이 본다.

대상: **빌드 41 이상**의 서명·설치 완료된 배포본. 테스트 전에 앱과 `HaneulKeyboardIM.app` 빌드 번호가 대상 빌드와 일치하는지 확인한다. (프로브가 확인 — scripts/postinstall_probe.sh 1번)

## 메뉴바와 설정

- [ ] 앱 실행 후 메뉴바 **오른쪽** 상태 영역에 HaneulKeyboard `한` 또는 `A` 아이콘이 나타난다.
- [ ] 아이콘을 클릭하면 메뉴가 아이콘 아래의 정상 위치에 열린다(화면 왼쪽 위 등 엉뚱한 위치에 열리지 않는다).
- [ ] `설정...`을 누르면 설정 창이 열리고 조작 가능하다.
- [ ] 설정 창을 닫은 뒤 다시 `설정...`을 누르면 창이 정상적으로 재열린다.

## 온보딩

- [ ] 첫 실행 시 `시작하기...` 온보딩을 열고 모든 단계를 완료할 수 있다.
- [ ] 온보딩 완료 후 메뉴에 `시작하기 다시 보기...`가 나타난다.
- [ ] `시작하기 다시 보기...`로 온보딩을 재열고 단계 이동·닫기가 정상 동작한다.

## 입력 소스와 전환 키

- [ ] macOS 입력 메뉴에서 하늘키보드를 선택하면 메뉴바 표시가 `한`으로 갱신된다.
- [ ] ABC 입력 소스로 바꾸면 메뉴바 표시가 `A`로 갱신된다.
- [ ] 입력 소스를 여러 번 바꿔도 `한`/`A` 표시가 누락·지연 없이 현재 상태와 일치한다.
- [ ] 하늘키보드 활성 상태에서 Caps Lock을 짧게 누르면 한↔영 입력 소스가 전환되고 이어서 입력한 문자가 올바른다.
- [ ] Caps Lock을 길게 누르는 macOS 대문자 Caps Lock 동작과 짧게 누르는 한영 전환이 구분된다.
- [ ] **Caps Lock 시스템 옵션 OFF** (#56, 2026-09-21): 시스템 설정 → 키보드 → 입력 소스의 "Caps Lock으로 ABC 전환" 옵션을 **꺼둔** 상태에서 Caps Lock을 눌러도 언어가 바뀌지 않는다(바뀌면 OS 버그 — 우리는 `TICapsLockLanguageSwitchCapable`로 OS에 위임하므로 우리 코드로 못 고친다. Apple Community 2025-09 리포트: 옵션이 꺼져 있어도 Caps Lock이 언어를 바꿈). 확인 후 옵션을 다시 켠다.
- [ ] 영타 자동 변환 대상 단어를 확정한 뒤 Shift+Space를 누르면 영타↔한글 결과가 되돌려지고, 다시 누르면 역방향으로 토글된다.
- [ ] 토글 대상이 아닌 문장에서 Shift+Space가 인접 텍스트를 훼손하지 않는다.
- [ ] **ABC 없음** (#45, 2026-09-20): 입력 소스에서 ABC를 빼고 U.S.(또는 British·Dvorak) 같은 다른 영문 자판만 둔 상태에서 메뉴 "영어로 전환"을 누르면 **그 자판으로** 전환되고 메뉴바가 `A`가 된다.
- [ ] **영문 자판 없음**: 영문 자판이 하나도 켜져 있지 않을 때 "영어로 전환"을 누르면 "영어로 전환하지 못했어요" 알림이 뜬다(조용히 실패하지 않는다). 하늘키보드를 입력 소스에서 뺀 상태에서 "한국어로 전환"을 누르면 "한국어로 전환하지 못했어요" 알림이 뜬다.

### 터미널 — Shift+Space 되돌리기 미지원 (#30)

터미널에 입력된 글자는 즉시 셸 프로세스 소유가 되어 앱조차 IME 요청으로 회수할 수단이 없다. 따라서 되돌리기는 **원리적으로 불가능**하며, 이 항목들은 "되게 만드는 것"이 아니라 **실패가 조용하고 일관되게 끝나는지**를 확인한다. (2026-09-21, #54: 되돌리기 키를 다른 조합으로 바꿔도 같다 — 키가 아니라 클라이언트의 문제.)

- [ ] Terminal.app에서 영타 변환 후 Shift+Space를 여러 번 눌러도 텍스트가 훼손되지 않는다(변화 없음이 정상).
- [ ] Ghostty에서도 같은 동작 — 되돌려지지 않고, **스페이스가 대신 끼어들지도 않는다**(과거엔 스페이스만 늘어났다).
- [ ] 두 터미널의 동작이 서로 같다.
- [ ] 터미널에서 영타 자동 변환 자체는 정상 동작한다(되돌리기만 불가).
- [ ] 터미널에서 오변환이 나면 백스페이스로 지우고 다시 칠 때 재변환되지 않는다(수동 복구 경로).
- [ ] (#54) 설정 → "되돌리기 키" 절 아래에 터미널에서는 되돌리기가 안 된다는 안내 문구가 보이고, README "알려진 문제"에도 같은 항목이 있다.

### 되돌리기 키 선택 · 앱별 자동 변환 끄기 (#54, 2026-09-21)

자동 테스트는 순수 판정(`RevertKey.matches`·`AutoConvertPolicy.allowed`, `Tests/ComposerTests.swift`)까지만 본다. 실제 키 이벤트의 modifier 플래그, 설정 앱 → IME defaults 도메인 전달, `client.bundleIdentifier()`가 돌려주는 값은 사람이 확인한다. **구현 시점(2026-09-21) 실기기 미검증.**

- [ ] 설정 → "되돌리기 키" 팝업에 Shift+Space(기본) · Option+Space · Control+Shift+Space · Option+Shift+Space **네 가지만** 보이고, Control+Space는 없다.
- [ ] 설정을 만진 적 없는 상태(`defaults read com.hyunjincho.inputmethod.haneul haneul.revertKey`가 없음)에서 Shift+Space 되돌리기가 종전과 똑같이 동작한다(회귀 없음).
- [ ] Option+Space로 바꾼 뒤 설정 창을 닫지 않아도 **다음 변환부터** Option+Space가 되돌리고, Shift+Space는 그냥 스페이스가 입력된다.
- [ ] Control+Shift+Space · Option+Shift+Space도 각각 같은 방식으로 되돌린다. 한글 모드(CapsLock 플래그가 붙는 상태)와 ABC 모드 양쪽에서 확인한다.
- [ ] 되돌릴 변환이 없을 때(한글만 친 뒤, 또는 되돌린 뒤 다른 글자를 친 뒤) 고른 조합을 누르면 종전처럼 앱에 그대로 전달된다 — IME가 키를 삼키지 않는다. (Option+Space는 앱에 따라 줄바꿈 없는 공백이 들어갈 수 있음 — 그 앱의 정상 동작.)
- [ ] `defaults write com.hyunjincho.inputmethod.haneul haneul.revertKey garbage` 뒤에도 Shift+Space(기본값)로 동작하고, 설정 창을 열면 팝업이 Shift+Space를 가리킨다.
- [ ] 앱별 끄기: "실행 중인 앱에서 추가..."에 Dock에 보이는 앱만 **이름순**으로 나오고, 메뉴바 전용 앱(HaneulKeyboard 자신 등)·백그라운드 프로세스는 안 나온다. 이미 추가한 앱은 "추가됨"으로 보인다.
- [ ] TextEdit을 목록에 넣은 뒤 TextEdit에서 `apple`을 치면 `메ㅔㅣㄷ`로 남고, 그 상태로 다른 앱(예: 메모)에서는 `apple`로 변환된다 — 설정 창을 닫지 않아도 즉시 반영된다.
- [ ] 목록에서 TextEdit을 지우면 TextEdit에서 다시 변환된다.
- [ ] 위 "영타 자동 변환" 토글을 끄면 목록과 무관하게 모든 앱에서 변환하지 않고, 다시 켜면 목록에 없는 앱만 변환한다.
- [ ] 목록에 있는 앱을 종료한 뒤에도 목록에 이름(또는 bundle ID)이 남아 있고 삭제할 수 있다.
- [ ] 터미널(Terminal.app 또는 Ghostty)을 목록에 넣으면 그 터미널에서 영타 변환이 일어나지 않는다(#30의 "터미널에서 변환 자체가 싫은" 경우의 우회).
- [ ] "전체 제거" 뒤 `defaults read com.hyunjincho.inputmethod.haneul`에 `haneul.revertKey`·`haneul.disabledAppBundleIDs`가 남지 않는다(`haneul.*` 일괄 삭제 경로).
- [ ] 설정 창(580×600 고정)에서 새 절 두 개가 스크롤로 보이고, 팝업·추가/제거 버튼·시트가 키보드와 VoiceOver로 조작된다.

### 영타 축약형 — 아포스트로피 (#34, 2026-09-19)

조합 중의 `'`는 이제 경계가 아니라 **단어 내부 문자**다(marked text에 그대로 보인다). 자동 테스트는 composer 층까지만 검증하므로, 실제 앱에서 `'` 키가 IME까지 도달하는지·마크드 텍스트가 어떻게 그려지는지는 사람이 확인한다. 앱마다 스마트 따옴표(`'`→`’`) 치환이 다르므로 **최소 두 종류의 앱**에서 본다.

- [ ] TextEdit에서 한글 모드로 `i'm don't` 를 치면 `i'm don't` 로 변환된다.
- [ ] Chrome 주소창이 아닌 웹 입력창(예: 검색창·댓글창)에서도 같은 결과가 나온다.
- [ ] 치는 동안 `'`가 조합 중 글자(marked text) 안에 보인다 — `ㅑ'` → `ㅑ'ㅡ`.
- [ ] `i'm` 확정 직후 Shift+Space를 누르면 `ㅑ'ㅡ` 로 통째로 되돌려지고, 다시 누르면 `i'm` 으로 돌아온다.
- [ ] `it's a test` 처럼 축약형 뒤 단어도 영어 문맥으로 이어져 변환된다.
- [ ] 한글 입력 중 `안녕'하세요` 를 치면 그대로 `안녕'하세요` 로 남는다(오변환 없음).
- [ ] 여는 따옴표로 시작하는 `'안녕` 이 그대로 입력된다.
- [ ] `'` 를 친 뒤 Backspace를 누르면 `'` 만 지워지고 앞 글자는 남아 조합이 이어진다.
- [ ] `ㅑ'` 까지 친 상태에서 다른 곳을 클릭하면 화면에 보이던 `ㅑ'` 가 그대로 확정된다.
- [ ] 설정에서 영타 자동 변환을 끄면 `i'm` 이 `ㅑ'ㅡ` 로 남는다.

### 개인 사전 (#53, 2026-09-21)

자동 테스트는 판정(`PersonalDictionary.decision`)·composer 합성·되돌리기 기록의 순수 함수까지만 검증한다. **설정 앱 ↔ IME 두 프로세스 사이의 defaults 전달, Shift+Space 시점의 실제 기록, 설정 화면의 렌더링은 자동으로 못 보므로 여기서 사람이 확인한다.** 확인용 명령: `defaults read com.hyunjincho.inputmethod.haneul` (세 키 `haneul.personalDict.force` · `haneul.personalDict.block` · `haneul.recentReverts`).

- [ ] 설정 창에 "개인 사전 — 변환 추가" · "개인 사전 — 변환 금지" · "최근 되돌린 변환" 세 절이 "입력" 절 아래에 보이고, 창 크기(580×600)는 그대로이며 Form이 스크롤된다.
- [ ] **변환 추가**: `vismo`를 추가한 뒤 TextEdit 한글 모드에서 `vismo`(퍄느ㅐ) + 스페이스 → **재시작 없이** `vismo`로 변환된다. 목록에서 −로 지우면 다시 `퍄느ㅐ`로 남는다.
- [ ] **변환 추가 — veto 우선**: `cor`을 추가하면 우리말샘 표제어 `책`(cor)도 `cor`로 변환된다. 지우면 다시 `책`.
- [ ] **변환 추가 — 입력 검증**: `Apple`은 `apple`로 저장되고, `app le` · `메ㅔㅣㄷ` · `abc1` · `'`는 빨간 안내 문구와 함께 거부된다. 같은 단어를 두 번 추가해도 한 줄만 있다.
- [ ] **변환 금지(영어)**: `apple`을 금지하면 `apple`(메ㅔㅣㄷ) + 스페이스가 `메ㅔㅣㄷ`로 남고, `apple's`도 `메ㅔㅣㄷ'ㄴ`로 남는다.
- [ ] **변환 금지(한글 표기)**: `메ㅔㅣㄷ`으로 적어도 같은 결과. 영한 혼합(`apple메`)·공백은 거부된다.
- [ ] **양쪽 등록**: 같은 단어를 추가·금지 둘 다에 넣으면 변환되지 않는다(금지 우선).
- [ ] **최근 되돌린 변환 — 기록**: `apple` 변환 직후 Shift+Space로 `메ㅔㅣㄷ`로 되돌리면, 설정 창으로 돌아왔을 때(창을 다시 활성화) 목록 맨 위에 `메ㅔㅣㄷ → apple`이 보인다. `defaults read`에도 같은 쌍이 있다.
- [ ] **기록 방향**: 되돌린 뒤 다시 Shift+Space로 `apple`로 재토글해도 새 항목이 늘지 않는다(영어→한글 방향만 기록). 같은 단어를 다시 되돌리면 중복 없이 맨 위로 올라온다.
- [ ] **기록에 없는 것**: `defaults read` 출력에 되돌린 단어의 한글 표기·영어 외에 문장·앱 이름·시각 같은 값이 **없다.** 되돌리지 않은 일반 한글 입력은 어떤 키에도 남지 않는다.
- [ ] **보안 입력**: 시스템 설정 등 네이티브 비밀번호 칸에서는 변환·되돌리기 자체가 일어나지 않으므로 기록도 생기지 않는다.
- [ ] **"금지" 버튼**: 최근 목록의 항목에서 "금지"를 누르면 그 영어 단어가 변환 금지 목록에 들어가고 최근 목록에서는 사라지며, 이후 그 단어는 변환되지 않는다.
- [ ] **최근 기록 지우기**: 누르면 목록이 비고 `defaults read`에서 `haneul.recentReverts` 키가 사라진다.
- [ ] **자동 변환 끔**: "영타 자동 변환"을 끄면 변환 추가 목록의 단어도 변환되지 않는다(마스터 스위치 우선).
- [ ] **전체 제거**: 세 목록을 채운 뒤 설정 → 전체 제거 → `defaults read com.hyunjincho.inputmethod.haneul`이 도메인 없음/`haneul.*` 없음이다.
- [ ] **키보드·VoiceOver**: 세 절의 텍스트 필드·추가·−·금지·지우기 버튼에 Tab으로 도달하고 VoiceOver가 "vismo 삭제" · "apple 변환 금지"처럼 읽는다.

## 키보드 접근성·VoiceOver

- [ ] 키보드만 사용해 메뉴 항목과 설정 창의 모든 제어요소로 포커스를 이동하고 실행할 수 있다.
- [ ] 포커스 표시가 보이고, Tab/Shift+Tab 순서가 화면의 논리적 순서와 일치한다.
- [ ] VoiceOver를 켠 뒤 메뉴바 아이콘이 `HaneulKeyboard`로 읽힌다.
- [ ] VoiceOver가 메뉴 항목, 설정 제어, 온보딩 제목·버튼의 이름과 현재 상태를 이해 가능하게 읽는다.
- [ ] VoiceOver가 켜진 상태에서 입력 소스 전환, 설정 열기, 온보딩 진행이 정상 동작한다.

## 설치 도메인과 전체 제거 (review0706 P2-2)

- [ ] `/Library/Input Methods`에 system-domain 설치본이 있는 상태에서 앱의 "IME 설치" 버튼을 누르면, 새로 복사하지 않고 기존 시스템 설치본을 재등록/활성화한다.
- [ ] system-domain 설치본과 `~/Library/Input Methods`의 user-domain 잔재가 동시에 존재하는 상태에서 "IME 설치"를 실행하면 user-domain 잔재가 정리되고 system-domain만 남는다.
- [ ] `/Applications`에 이름이 다른 HaneulKeyboard 복사본(예: 파일명을 바꾼 앱)이 있는 상태에서 "전체 제거"를 실행하면, 두 복사본 모두 파일이 삭제되고 macOS 재부팅 후 Launchpad/Spotlight에 중복 항목이 남지 않는다.

## 실패 시나리오 (review-0712 P3-8)

자동 테스트는 "무엇을 결정하는가"까지만 검증한다(`Tests/ComposerTests.swift`의 설치·제거 결정 로직 항목 — `AppMoveDecision`·`UninstallDecision`·`UninstallOutcome`). 실제 관리자 프롬프트·파일 삭제·GUI 경고는 아래에서 사람이 확인한다.

### 전체 제거 — 관리자 암호 취소

- [ ] "전체 제거" 실행 중 관리자 암호 창에서 **취소**를 누르면 결과 창이 `IME 번들 삭제: 실패` / `메인 앱 삭제: 건너뜀(재시도용 보존)`으로 표시되고, "완료"라고 말하지 않는다.
- [ ] 위 상태에서 "확인"을 눌러도 **앱이 종료되지 않고** 남아, 같은 화면에서 "전체 제거"를 곧바로 다시 실행할 수 있다.
- [ ] 재실행에서 암호를 올바르게 입력하면 IME·메인 앱이 모두 삭제되고 "완료" 문구가 나온다.

### 앱 이동 — 관계없는 목적지 앱

- [ ] `/Applications`에 **관계없는 앱**을 `HaneulKeyboard.app`이라는 이름으로 둔 상태에서(다른 앱을 복사·개명), 다운로드 폴더의 HaneulKeyboard를 실행해 "옮기고 다시 열기"를 누르면 → "응용 프로그램 폴더에 다른 앱이 있어요" 경고가 뜨고 **그 앱이 덮어써지지 않는다**.
- [ ] 앱 파일명을 바꿔서(예: `내키보드.app`) 실행한 뒤 이동을 진행하면 `/Applications/HaneulKeyboard.app`으로 들어간다(바꾼 이름 그대로 들어가지 않는다).

### 온보딩 — 완료 시 창 닫힘

- [ ] `defaults delete com.hyunjincho.haneulkeyboard haneul.hasCompletedOnboarding` 후 앱을 실행해, 온보딩 마지막 단계의 **"완료"를 누르면 창이 즉시 닫힌다**(빨간 닫기 버튼을 쓰지 않아도 된다).

### 시스템 설치 스크립트 — 중단

- [ ] `scripts/build_notarize_install.sh` 실행 중 staging 검증 단계에서 실패했을 때(예: 일부러 서명을 깨뜨려서), `/Library/Input Methods`의 **기존 설치본이 그대로 남아 있다**(설치 전 상태 보존).

## 앱 삭제 ↔ IME 연동 (#32, 2026-09-19)

자동 테스트는 판단 함수(`OrphanDecision`)만 검증한다. 실제 삭제·비활성화·종료는 아래에서 사람이 확인한다. 로그: `/usr/bin/log show --predicate 'subsystem == "com.hyunjincho.haneulkeyboard" AND category == "orphan"' --last 30m`.

> ⚠️ **전제 조건 (2026-09-20, #43 · 리뷰 F-4)** — 개발 머신에서는 이 절이 **그냥은 통과할 수 없다.** IME는 후보 경로를 LaunchServices(`urlsForApplications`)에서도 가져오는데, `.build/*DerivedData*/Build/Products/*/HaneulKeyboard.app` 같은 빌드 산출물이 등록돼 있고 디스크에 실존하면 휴지통 밖에 살아 있는 복사본으로 세어 **항상 `present`** 가 된다(2026-09-20 Mac Studio 실측: 메인 앱 bundle ID로 10개 경로, 그중 9개가 `.build` 산출물). 그러면 앱을 휴지통에 버려도 자기 정리는 절대 발동하지 않고 "연동이 안 된다"는 오판이 난다. 검증 전에:
> 1. 저장소 안 `.build/*DerivedData*` 산출물을 지우거나(`rm -rf`는 오너 결정) `lsregister -u <산출물 경로>`로 등록만 뺀다. (2026-09-21 #52: `scripts/build_notarize_install.sh`는 끝날 때 자기 산출물 `.build/DerivedData/Build/Products/Release/`의 등록을 자동으로 뺀다 — 다른 DerivedData·Debug 산출물은 여전히 손으로.)
> 2. 확인 — 아래 프로브가 `/Applications/HaneulKeyboard.app` **하나만** 돌려줘야 한다 (프로브가 확인 — scripts/postinstall_probe.sh 4번):
>    `swift -e 'import AppKit; NSWorkspace.shared.urlsForApplications(withBundleIdentifier: "com.hyunjincho.haneulkeyboard").forEach { print($0.path) }'`
> 3. 최종 사용자 머신에는 DerivedData가 없으므로 이 전제는 개발 머신 전용이다(제품 결함 아님).

- [ ] `/Applications/HaneulKeyboard.app`을 휴지통에 버린 뒤(메뉴바 앱 종료) 한글 모드로 계속 쓰면, **2분 이상 지나** 입력이 ABC로 넘어가고 `~/Library/Input Methods/HaneulKeyboardIM.app`이 사라진다. 로그에 `in the Trash — waiting` → `on repeated observations` → `removed own bundle`이 남는다.
- [ ] 위 상태에서 로그의 `TISDisableInputSource=true/false`를 기록한다 — 프로그램 비활성화가 IME 프로세스 컨텍스트에서 되는지가 여기서 처음 확정된다. false면 입력 소스 목록의 "하늘키보드" 항목은 재로그인 후 사라지는 것이 정상.
- [ ] **복원 유예**: 앱을 휴지통에 버렸다가 **2분 안에 "제자리에 놓기"**로 되돌리면 IME가 사라지지 않고 설정도 남아 있다.
- [ ] **오탐 없음**: 앱을 새 버전으로 교체(Finder "대치")한 직후 한글 모드로 전환해도 IME가 사라지지 않는다(옛 번들이 휴지통에 있어도 `/Applications`에 새 번들이 있으면 present).
- [ ] **오탐 없음**: 앱을 `/Applications/Utilities/` 같은 하위 폴더나 `~/Desktop`으로 **옮기기만 하고 실행하지 않은** 상태에서 한글 모드로 30분 이상 써도 IME가 사라지지 않는다(휴지통에 옛 버전 사본이 있어도 inode가 달라 무시 — 기록 경로의 사본이든 LaunchServices가 기억하는 사본이든, #47).
- [ ] **(#47 확인, 2026-09-20)** 옛 버전 `HaneulKeyboard.app` 사본을 휴지통에 둔 상태에서 위 전제 조건의 프로브(`urlsForApplications`)를 돌려 `~/.Trash` 경로가 **포함되는지** 기록한다 — 포함되면 LaunchServices 후보에 대한 inode 필터가 실제로 작동하는 경로이고, 그 상태에서 앱을 `~/Desktop`으로 옮겨 두면 로그가 `not found — waiting`(30분 유예)이어야 한다(`in the Trash`가 아님).
- [ ] **오탐 없음**: 앱이 외장 볼륨에 있고 볼륨을 **마운트하지 않은** 세션에서 한글 모드를 30분 미만으로 쓰면 아무 일도 없다(30분 이상이면 정리되는 것이 현재 설계 — 재설치로 복구).
- [ ] **ABC 없음**: 시스템 설정 입력 소스에서 ABC를 빼 둔 상태로 앱을 휴지통에 버리면, IME는 정리를 **보류**하고(로그 `could not switch … deferred`) 계속 쓸 수 있다. 입력 소스를 잃는 상태가 생기지 않는다.
- [ ] 휴지통을 비운 뒤(앱이 어디에도 없음) IME는 **30분 이상** 지나 두 번째 관찰에서 정리된다 — 첫 관찰에서 바로 사라지지 않는다.
- [ ] 역방향: 시스템 설정 → 입력 소스에서 "하늘키보드"를 "-"로 뺀 뒤 메뉴바 메뉴를 열면 "한글 입력기가 꺼져 있음 — 다시 켜기"가 보이고, 누르면 입력 소스 목록에 다시 나타난다.
- [ ] 전체 제거: "전체 제거"를 실행하면 결과 창에서 "시스템 설정에서 직접 빼세요" 안내가 **더 이상 나오지 않는지**(프로그램 비활성화 성공 시) 또는 종전처럼 나오는지 기록한다.
- [ ] 설정 → "IME 제거" (#46, 2026-09-20): 실행 뒤 시스템 설정 입력 소스 목록에서 "하늘키보드"가 **사라지는지**(프로그램 비활성화 성공) 또는 종전처럼 남는지 기록한다 — 전체 제거·자기 정리와 같은 `TISDisableInputSource` 경로. 로그 `IME 제거 — TISDisableInputSource=true/false`(subsystem `com.hyunjincho.haneulkeyboard`, category `main`).


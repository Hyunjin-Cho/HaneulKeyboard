# 하늘키보드 (HaneulKeyboard)

<p align="center">
  <a href="https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest"><img src="https://img.shields.io/github/v/release/Hyunjin-Cho/HaneulKeyboard?style=flat-square" alt="latest release"></a>
  <a href="https://github.com/Hyunjin-Cho/HaneulKeyboard/releases"><img src="https://img.shields.io/github/downloads/Hyunjin-Cho/HaneulKeyboard/total?style=flat-square" alt="downloads"></a>
  <a href="https://github.com/Hyunjin-Cho/HaneulKeyboard/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Hyunjin-Cho/HaneulKeyboard?style=flat-square" alt="license"></a>
  <a href="https://github.com/Hyunjin-Cho/HaneulKeyboard/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Hyunjin-Cho/HaneulKeyboard/ci.yml?branch=main&amp;label=CI&amp;style=flat-square" alt="CI"></a>
  <a href="#요구사항"><img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&amp;logo=apple" alt="macOS 14+"></a>
</p>

빠른 한↔영 전환과 안정적인 한글 입력을 위한 macOS 메뉴바 유틸리티 + 입력기(IME).

사랑하는 딸 **하늘**이의 이름에서 따왔습니다.

## 데모

> 한글 모드인 채로 영어를 치면 — 깨진 한글이 **스페이스를 누르는 순간** 자동으로 영어로 바뀝니다.

<p align="center">
  <img src="haneul-demo-3.gif" width="520" alt="영타 자동 변환"><br><br>
  <img src="haneul-demo-4.gif" width="520" alt="영타 자동 변환"><br><br>
  <img src="haneul-demo-1.gif" width="520" alt="thank you 문장 변환">
</p>

## 주요 기능

- **안정적인 한글 조합** — 전용 입력 소스로 자모 깨짐 없이 한글을 조합합니다.
- **빠른 한/영 전환** — Caps Lock(짧게)으로 즉시 전환. 시스템 native 경로를 사용해 결정적으로 동작합니다.
- **영타 자동 변환** *(2026.02 신규 · 2026.03 사전 현대화)* — 한글 모드인 줄 모르고 영어를 쳤을 때, 스페이스를 누르는 순간 자동으로 영어로 바꿔줍니다. `메ㅔㅣㄷ`→`apple`, `ㅡ드ㅐ교`→`memory`, `how ㅁㄱㄷ you`→`how are you`. 올바른 한글과 ㅋㅋㅋ·ㅗㅜㅑ 같은 표현은 건드리지 않습니다 — **우리말샘 표제어 67.7만 개**로 실존 한국어를 확인합니다 (단 하나의 예외: 영어 문맥 직후의 새→to·무→an·내→so·랙→for·뭉→and 명시 목록). 2026.03부터 `and`·`city`·`playlist` 같은 기본·현대어와 `davinci`·`ronaldo` 같은 인명까지 변환합니다.
- **Caps Lock 대문자 모드** — Caps Lock 길게 LED 토글(대문자 모드).
- **메뉴바에서 제어** — 한국어/영어 전환, 설정을 메뉴바 아이콘에서. 영타 변환은 설정에서 켜고 끌 수 있고, 되돌리기 키와 앱별 끄기도 설정에서 고릅니다.
- **자동 업데이트** *(2026-09-21 신규)* — 새 버전이 나오면 알려주고, 버튼 한 번으로 내려받아 서명·애플 공증을 검증한 뒤 스스로 교체합니다. 설정에서 끌 수 있습니다 (아래 [자동 업데이트](#자동-업데이트-2026-09-21)).

한↔영 입력에만 집중합니다. 다른 언어 지원 및 다른 기능은 없습니다.

## 설치

[GitHub Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases)에서 최신 버전을 받으세요.

### 설치 방법 (일반 사용자)

1. 다운로드한 `.zip` 압축 풀고 `HaneulKeyboard.app`을 **응용 프로그램(`/Applications/`)** 폴더로 복사
2. `HaneulKeyboard.app` 더블클릭 → 메뉴바에 아이콘 표시
3. 메뉴바 아이콘 → **"시작하기..."** → 온보딩 따라가기
   - **"IME 설치"** 버튼 클릭 (`~/Library/Input Methods/`에 설치)
4. **시스템 설정 → 키보드 → 입력 소스 → "+" → 한국어 → "하늘키보드 (두벌식)"** 추가
5. (선택) 기존 시스템 한국어 입력기(두벌식)는 제거 권장 — 자모 깨짐 방지 효과

> **제거**: 메뉴바 → 설정 → **고급** 탭 → "전체 제거..."가 앱·입력기·설정을 한 번에 지웁니다. `HaneulKeyboard.app`을 그냥 휴지통에 버려도 입력기가 이를 감지해 몇 분 안에 스스로 정리됩니다(한글 모드를 쓰는 동안 확인하며, 2분 안에 "제자리에 놓기"로 되돌리면 그대로 유지). <!-- 2026-09-23 (#72) 탭 경로 -->

> **⚠️ 참고**: 한/영 전환은 **Caps Lock**으로 합니다 — macOS 시스템 기능(`TICapsLockLanguageSwitchCapable`)에 위임하므로 **별도 권한이 필요 없습니다.** 짧게 눌러 한/영 전환, 길게(1초+) 눌러 대문자 Caps Lock.

## 사용법

- **Caps Lock** 짧게 누름 → 한/영 전환
- **Caps Lock** 길게 누름 → Caps Lock LED 토글 (대문자 모드)
- 하늘 키보드에서 영어단어를 치면 전환 가능

### 영타 자동 변환 (2026.02 · 2026.03 사전 현대화)

한글 모드에서 영어 단어를 치면 — 예: `apple`이 `메ㅔㅣㄷ`로 보임 — **스페이스/문장부호를 누르는 순간 자동으로 영어로 교정**됩니다. 별도 조작이 필요 없습니다.

- 직전 단어가 영어면 짧은 단어도 이어서 교정: `how ㅁㄱㄷ you` → `how are you`, `thank you 내 much 랙` → `thank you so much for`, `apples 뭉 oranges` → `apples and oranges`
- **올바른 한글은 건드리지 않습니다**: 실존 한국어 단어(우리말샘 67.7만 표제어 대조), ㅋㅋㅋ·ㅎㄷㄷ·ㅇㄱㄹㅇ 같은 초성체, ㅗㅜㅑ·ㅡㅁㅡ 같은 표현은 전부 보호됩니다. (단 하나의 예외: 영어 문맥 직후의 새→to·무→an·내→so·랙→for·뭉→and 명시 화이트리스트 — "thank you 내 much"처럼 영어 흐름 안에서는 영어 의도가 우세하다고 봅니다.)
- *(2026.03)* **영어 사전 현대화** — 1934년판 시스템 사전의 빈자리를 공개 데이터로 보강했습니다: 고빈도 일상어 [NGSL](https://www.newgeneralservicelist.com)(`city`·`with`), 현대어·굴절형 [SCOWL](https://wordlist.aspell.net)(`playlist`·`internet`·`selfie`), 영어 인명 US Census·SSA + 유명인(`davinci`·`ronaldo`·`garcia`). 추가된 모든 단어는 **한국어 충돌 검역**(실제 조합 엔진 시뮬레이션, [`scripts/audit_wordlist.sh`](./scripts/audit_wordlist.sh))을 통과한 것만 — 한국어 보호 원칙은 그대로입니다.
- 변환은 직접 타이핑한 경계에서만 일어나고, 마우스 클릭·앱 전환 시에는 화면에 보이던 그대로 입력됩니다.
- **되돌리기** — 자동으로 바뀐 직후 **Shift+Space**를 누르면 원래 한글로 되돌리고, 다시 누르면 영어로 돌아옵니다. 키는 설정 → **영타 변환** 탭 → "되돌리기 키"에서 Option+Space · Control+Shift+Space · Option+Shift+Space 중 하나로 바꿀 수 있습니다(시스템·앱 단축키와 겹치면 다른 조합을 고르세요). <!-- 2026-09-21 (#54) · 2026-09-23 (#72) 탭 경로 -->
- **앱별로 끄기** — 설정 → **영타 변환** 탭 → "앱별 자동 변환 끄기"에서 실행 중인 앱을 고르면 그 앱에서만 영타 변환을 하지 않습니다(예: 코드 편집기·터미널). <!-- 2026-09-21 (#54) · 2026-09-23 (#72) 탭 경로 -->
- **자동으로 바뀌지 않은 단어도 되돌리기** *(2026-09-21)* — 되돌리기 키는 이제 **커서 앞 단어 전부**에 듣습니다. 자동 변환이 일부러 손대지 않는 것들 — 실존 한국어 단어와 겹쳐 막히는 `재가`(work), 사전에 있을 수 없는 `ㅡ5`(m5)·`ㅏ3`(k3) — 도 키 한 번이면 한↔영으로 바뀌고, 한 번 더 누르면 돌아옵니다. 직전에 자동 변환이 있었다면 **그 되돌리기가 먼저**입니다(종전 동작 그대로). 조합 중인 글자에는 듣지 않습니다 — 스페이스 등으로 확정한 다음 누르세요. 설정 → **영타 변환** 탭 → "바뀌지 않은 단어도 되돌리기"에서 끌 수 있습니다. 터미널에서는 아래 "알려진 문제"와 같은 이유로 동작하지 않습니다. <!-- 2026-09-21 (#15) · 2026-09-23 (#72) 탭 경로 -->

### 개인 사전 (2026-09-21)

자동 변환이 내 쓰임새와 다를 때 **설정 → 개인 사전** 탭에서 직접 고칩니다. 세 목록 전부 **이 Mac 안에만** 저장되고 어디로도 보내지 않습니다 ([PRIVACY.md](./PRIVACY.md) 7번). <!-- 2026-09-23 (#72) 탭 경로 -->

- **변환 추가** — 사전에 없거나 한국어 단어와 겹쳐서 안 바뀌던 영어(사내 용어·이름 등)를 적으면 **항상** 변환됩니다. 한글 모드에서 그 단어를 그대로 쳤을 때만.
- **변환 금지** — 적힌 단어는 **절대** 변환하지 않습니다. 영어(`apple`)로 적어도, 한글 모드에서 보이는 표기(`메ㅔㅣㄷ`)로 적어도 됩니다.
- **최근 되돌린 변환** — Shift+Space로 되돌린 변환이 (한글 표기 → 영어)로 최근 50개까지 쌓입니다. 잘못 바뀐 단어는 옆의 **금지** 버튼 한 번으로 변환 금지 목록에 들어갑니다.

저장한 즉시 다음 단어부터 반영됩니다(재시작 불필요).

### 자동 업데이트 (2026-09-21)

**설정 → 업데이트** 탭에서 새 버전을 확인하고 설치합니다. <!-- 2026-09-23 (#72) 탭 경로 -->

- **업데이트 자동 확인** (기본 켜짐) — 앱을 실행할 때 한 번, 그 뒤 24시간마다 GitHub 릴리스에 새 버전이 있는지만 물어봅니다. 새 버전이 있으면 설정 화면과 메뉴바에 알려 주고, **자동으로 설치하지는 않습니다.**
- **지금 확인** — 지금 한 번 확인합니다. 자동 확인을 꺼 두었어도 이 버튼은 동작하며, **꺼 두면 이 버튼을 누를 때 말고는 앱이 인터넷에 접속하지 않습니다.**
- **업데이트** — 눌렀을 때만 내려받습니다. 받은 파일은 **번들 ID · 서명 Team · `codesign` · 애플 공증(`spctl`) · 버전 상승** 다섯 가지를 **전부** 통과해야 설치되고, 하나라도 어긋나면 받은 파일을 버리고 **지금 쓰던 앱을 그대로 둡니다.** 설치는 기존 앱을 먼저 지우지 않는 원자적 교체라 중간에 실패해도 앱이 사라지지 않습니다. 끝나면 새 버전으로 다시 열립니다.
- 앱이 새 버전으로 바뀌면 **입력기(IME)도 함께 갱신**됩니다. 관리자 권한으로 `/Library/Input Methods`에 설치한 경우에는 자동 갱신이 안 되므로 설정에 "IME 갱신 필요" 안내가 뜹니다.
- 자동 업데이트는 앱이 **응용 프로그램 폴더(`/Applications`)** 에 있을 때만 동작합니다. 다른 위치에서 실행 중이면 안내만 하고 중단합니다.
- 나가는 데이터는 **없습니다** — 무엇을 요청하고 무엇을 보내지 않는지는 [PRIVACY.md](./PRIVACY.md) 9번에 전부 적혀 있습니다.

## 요구사항

- **macOS Sonoma (14.0) 이상** — macOS 26 (Tahoe)·27에서 테스트 완료
- Apple Silicon (M1/M2/M3/M4) 및 Intel 모두 지원 — Intel Mac은 macOS 14~26에서만 지원됩니다 (macOS 27부터 Apple silicon 전용 OS — 빌드는 계속 Universal)

## 알려진 문제

- **후보 창(팝업)에서 입력 중인 글자가 연하게 표시됨** — 사용상 문제는 없어 현재 상태를 유지합니다.
- **현재 두벌식만 지원** — 다른 자판(세벌식 등)이 필요하면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 요청해주세요. 수요가 있으면 추가를 검토합니다.
- **일부 사이트/앱에서 동작하지 않을 수 있음** — 애초에 자모 결합 입력을 지원하지 않는 특정 웹사이트/앱에서는 입력기 종류와 무관하게 입력이 깨질 수 있습니다.
- **웹 브라우저의 비밀번호 칸에 한글이 입력될 수 있음** — 네이버 등 브라우저의 비밀번호 칸은 macOS가 입력기를 차단하지 않아, **모든 한글 입력기(애플 기본 입력기 포함)에서 한글이 조합됩니다.** 입력기 종류와 무관한 macOS·브라우저의 동작이며, 비밀번호는 영문 모드(Caps Lock 짧게)로 입력하시면 됩니다. (시스템 설정 등 네이티브 비밀번호 칸은 macOS가 정상적으로 입력기를 차단합니다.)
- **터미널(Terminal.app·Ghostty 등)에서는 변환 되돌리기가 동작하지 않음** — 터미널에 입력된 글자는 그 즉시 셸 프로세스의 것이 되어, 입력기가 다시 읽거나 바꿀 수단이 없습니다(macOS 구조상 한계라 입력기 종류와 무관하며, 되돌리기 키를 바꿔도 마찬가지입니다). 자동 변환 자체는 정상 동작하고, 되돌리기 키를 눌러도 아무 일도 일어나지 않습니다(텍스트가 훼손되거나 스페이스가 끼어들지 않습니다). 오변환은 백스페이스로 지우고 다시 치면 재변환되지 않습니다. 터미널에서 변환 자체가 싫다면 설정 → **영타 변환** 탭 → "앱별 자동 변환 끄기"에 터미널 앱을 추가하세요. <!-- 2026-09-21 (#54, 근거 #30) · 2026-09-23 (#72) 탭 경로 -->
- 위와 같은 문제를 겪는 사이트/앱이 있다면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 제보해주시면 큰 도움이 됩니다.
- 지원되는 OS에서 광범위한 테스트가 필요합니다. 편하게 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 제보해주시면 개발에 큰 도움이 됩니다.

## 버전 체계

하늘키보드는 **CalVer(Calendar Versioning)** 를 따릅니다: `연도.릴리스[.핫픽스]`

- `2026.01`, `2026.02`, `2026.03` … — `2026`은 **연도**, 두 번째 칸은 **그 해의 릴리스 순번**입니다(달력의 월과 무관). 2026년 첫 릴리스가 `2026.01`, 두 번째가 `2026.02`.
- `2026.02.01`, `2026.02.02` … — **핫픽스(긴급 수정)가 있을 때만** 세 번째 칸을 덧붙입니다. 예) `2026.02` 출시 후 버그 수정본이 `2026.02.01`.

> 점으로 나뉜 각 칸은 독립된 정수이며 소수점이 아닙니다. 예) `2026.02.10`이 `2026.02.09`보다 최신입니다.

## 개발자용 빌드

```bash
# 1. 의존성 설치
brew install xcodegen

# 2. 프로젝트 생성
xcodegen generate

# 3. 빌드 (Debug)
xcodebuild -scheme HaneulKeyboard -configuration Debug build

# 4. 실행
open ~/Library/Developer/Xcode/DerivedData/HaneulKeyboard-*/Build/Products/Debug/HaneulKeyboard.app
```

메인 앱이 IME 번들(`HaneulKeyboardIM.app`)을 `Contents/Helpers/`에 자동 포함하므로 타겟 하나만 빌드하면 됩니다.

### 배포용 빌드 (Developer ID + Notarization)

```bash
ZIP_ONLY=1 scripts/build_notarize_install.sh HaneulKeyboard
```

Apple Developer ID 인증서 + notarytool 키체인 프로필(`haneul-notary`)이 사전에 등록되어 있어야 합니다. 결과물은 repo 루트의 `HaneulKeyboard_<버전>.zip`입니다. <!-- 2026-09-23 (#72) ZIP_ONLY·릴리스 체크리스트 -->

> **릴리스를 올릴 때는 [`docs/release-checklist.md`](./docs/release-checklist.md)를 따르세요.** 앱의 자동 업데이트가 태그·파일 이름·버전 형식에 의존해서, 한 번이라도 어긋나면 모든 사용자에게 업데이트 알림이 조용히 사라집니다.

### 구조

```text
HaneulKeyboard.app              # 메뉴바 앱
└── Contents/Helpers/
    └── HaneulKeyboardIM.app    # 입력기 번들 (IMKit)

~/Library/Input Methods/
└── HaneulKeyboardIM.app        # 설치 시 복사됨
```

| 번들 | 역할 | 기술 |
|---|---|---|
| `HaneulKeyboard.app` | 메뉴바 앱 — 언어 전환, IME 설치 | SwiftUI, TIS API |
| `HaneulKeyboardIM.app` | 한글 입력기 — 자모 조합 | IMKit, IMKInputController |

## 라이선스

MIT License — 자유롭게 사용, 수정, 배포하세요. 자세한 내용은 [`LICENSE`](./LICENSE) 파일을 참고하세요.

**데이터 파일 예외** (앱 코드는 MIT 그대로, 번들 데이터만 파일별 라이선스):

- 한국어 단어 목록([`Resources/IM/korean_words.txt`](./Resources/IM/korean_words.txt)) — 국립국어원 **우리말샘**에서 추출, [**CC-BY-SA 2.0 KR**](https://creativecommons.org/licenses/by-sa/2.0/kr/)
- 현대 영어 단어 목록 — **NGSL**(New General Service List, Browne·Culligan·Phillips)에서 추출, [**CC BY-SA 4.0**](https://creativecommons.org/licenses/by-sa/4.0/)
- 영어 단어 목록 보강 — **SCOWL/ESDB**([English Speller Database](https://wordlist.aspell.net), Kevin Atkinson)에서 추출, **MIT-like** (Copyright 2000-2026 by Kevin Atkinson)
- 영어 인명 목록 — **미국 인구조사국**(2010 Census 성씨)·**미국 사회보장국**(Baby Names) 데이터에서 추출, **public domain**
- 지명 목록([`english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt) 일부) — **[GeoNames](https://www.geonames.org)**(북미·유럽 주/도·도시)에서 추출, [**CC BY 4.0**](https://creativecommons.org/licenses/by/4.0/)
- 축구 클럽·선수 목록(`english_sports_geo.txt` 일부) — **[Wikidata](https://www.wikidata.org)**(잉글랜드·프랑스·스페인·이탈리아 9개 리그)에서 추출, **CC0 1.0**(퍼블릭 도메인)

## 감사의 글

하늘키보드는 앞서 길을 닦아준 오픈소스와 도구들 위에 서 있습니다:

- **[McBopomofo](https://github.com/openvanilla/McBopomofo)** (OpenVanilla, MIT) — IME의 TIS(Text Input Services) 등록·설치 패턴에 큰 도움을 받았습니다.
- **[국립국어원 우리말샘](https://opendict.korean.go.kr)** (CC-BY-SA 2.0 KR) — 영타 자동 변환의 한국어 실존 단어 판정에 표제어 데이터를 사용합니다.
- **[Claude](https://claude.com/claude-code)** (Anthropic) — 개발 과정에 함께했습니다.

그리고 이 모든 것을 가능케 한, 인류가 쌓아 올린 오픈소스와 지식에 감사합니다. 전체 내용은 [감사의 글](./ACKNOWLEDGEMENTS.md)을 참고하세요.

## 제보 / 기여

실제로 써보고 불편한 점이나 버그를 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 알려주세요. 특히 한글 입력이 깨지는 사이트/앱을 발견하면 제보해주시면 개선에 큰 도움이 됩니다. 적극적인 실사용과 피드백을 환영합니다.

**단어 제안**은 앱에서 바로 할 수 있습니다 — **설정 → 개인 사전 탭**의 "단어 제안하기..."에서 친 글자와 기대한 결과를 적고 "GitHub에서 열기"를 누르면 미리 채워진 이슈 작성 화면이 브라우저로 열립니다("최근 되돌린 변환" 목록의 **제안** 버튼도 같은 화면). 앱은 창을 열 뿐 아무것도 전송하지 않고, 등록은 GitHub에서 직접 합니다 ([PRIVACY.md](./PRIVACY.md) 8번). <!-- 2026-09-23 (#72) 탭 경로 -->

<!-- 후원 링크 자리 (URL 확정 후 추가) -->

---

# English

A macOS menu bar utility for fast Korean ↔ English input switching and reliable Hangul typing, with a dedicated input method (IME).

Named after my daughter, 하늘 (Haneul) — "sky" in Korean.

## Features

- **Reliable Hangul composition** via a dedicated input source — no broken jamo.
- **Fast Korean/English switching** with Caps Lock (short press), using the system-native path for deterministic behavior.
- **Wrong-layout auto-correction** *(new in 2026.02, dictionaries modernized in 2026.03)* — typed English while in Korean mode? It fixes itself on commit: `메ㅔㅣㄷ`→`apple`, `how ㅁㄱㄷ you`→`how are you`. Genuine Korean is left alone — every candidate is checked against **677k Korean headwords** (국립국어원 우리말샘) plus slang/emoticon guards, with one deliberate exception (an explicit whitelist of 새→to/무→an/내→so/랙→for/뭉→and right after English context). 2026.03 modernizes the English dictionaries with [NGSL](https://www.newgeneralservicelist.com) high-frequency words (`city`, `with`), [SCOWL](https://wordlist.aspell.net) modern vocabulary (`playlist`, `internet`, `selfie`), and personal names from US Census/SSA data (`davinci`, `ronaldo`, `garcia`) — every addition passed a Korean-collision audit driven by the real composition engine.
- **Caps Lock uppercase mode** with a long press.
- **Menu bar control** for language switching, settings, and shortcuts. Wrong-layout auto-correction can be toggled in Settings; the revert key (default Shift+Space, also Option+Space / Control+Shift+Space / Option+Shift+Space) and a per-app off list are configurable there too (**영타 변환** / Conversion tab). Note: reverting cannot work in terminals (Terminal.app, Ghostty…) — typed text is owned by the shell the moment it lands, so the IME has no way to take it back. <!-- 2026-09-21 (#54) · 2026-09-23 (#72) 탭 경로 -->
- **Manual Hangul↔English toggle** *(2026-09-21)* — the revert key now works on **any word before the cursor**, not just one the IME auto-corrected: `재가` ↔ `work` (blocked from auto-correction because 재가 is a real Korean word), `ㅡ5` ↔ `m5` (impossible to auto-correct — no dictionary can hold it). Press again to switch back. Reverting an actual auto-correction still takes priority, and the whole feature can be turned off in Settings (**영타 변환** tab → 바뀌지 않은 단어도 되돌리기). Terminals are excluded for the same structural reason as above. <!-- 2026-09-21 (#15) · 2026-09-23 (#72) 탭 경로 -->
- **Personal dictionary** *(2026-09-21)* — in Settings → **개인 사전** (Personal dictionary) tab, list words that should **always** convert (in-house terms, names) or **never** convert (as English or as their Hangul-layout form), and review the conversions you reverted with Shift+Space (last 50) with a one-click "Block" button. Everything stays on your Mac — see [PRIVACY.md](./PRIVACY.md) #7. <!-- 2026-09-23 (#72) 탭 경로 -->
- **Automatic updates** *(2026-09-21)* — Settings → **업데이트** (Updates) tab checks GitHub Releases for a newer version (at launch and every 24 hours, on by default, and you can turn it off). A new version is only announced, never installed on its own; when you click **Update**, the download must pass all five checks — bundle ID, signing Team, `codesign`, Apple notarization (`spctl`), and a real version increase — before your app is replaced atomically and relaunched. If any check fails, the download is discarded and your existing app is untouched. Nothing about you is uploaded — see [PRIVACY.md](./PRIVACY.md) #9. <!-- 2026-09-21 (#19) · 2026-09-23 (#72) 탭 경로 -->

Korean ↔ English input only. No other languages, no extra features.

## Install

Download the latest build from [GitHub Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases), copy `HaneulKeyboard.app` to `/Applications/`, double-click it, and follow the 3-step onboarding wizard. <!-- 2026-09-23 (#72) 탭 경로 -->

## Requirements

macOS Sonoma (14.0) or later — tested on macOS 26 (Tahoe) and 27. Both Apple Silicon and Intel; Intel Macs are supported on macOS 14–26 only (macOS 27 and later run on Apple silicon only — the build stays Universal).

## Versioning

CalVer: `YEAR.RELEASE[.HOTFIX]`. The second field is the release number within the year (not the calendar month): `2026.01`, `2026.02`, `2026.03` … A third field is added only for hotfixes (e.g. `2026.02.01`). Each dot-separated field is an independent integer, not a decimal.

## License

MIT. See [`LICENSE`](./LICENSE).

**Data exceptions** (the app code remains MIT; only bundled data files carry their own licenses):

- Korean wordlist ([`Resources/IM/korean_words.txt`](./Resources/IM/korean_words.txt)) — extracted from the National Institute of Korean Language's **Urimalsaem (우리말샘)**, [**CC-BY-SA 2.0 KR**](https://creativecommons.org/licenses/by-sa/2.0/kr/)
- Modern English wordlist — derived from the **NGSL** (New General Service List, Browne, Culligan & Phillips), [**CC BY-SA 4.0**](https://creativecommons.org/licenses/by-sa/4.0/)
- English wordlist augmentation — derived from **SCOWL/ESDB** ([English Speller Database](https://wordlist.aspell.net), Kevin Atkinson), **MIT-like** (Copyright 2000-2026 by Kevin Atkinson)
- English name lists — derived from **US Census Bureau** (2010 Census surnames) and **US Social Security Administration** (Baby Names) data, **public domain**
- Place names (part of [`english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt)) — derived from **[GeoNames](https://www.geonames.org)** (North American & European states/cities), [**CC BY 4.0**](https://creativecommons.org/licenses/by/4.0/)
- Football club & player names (part of `english_sports_geo.txt`) — derived from **[Wikidata](https://www.wikidata.org)** (9 leagues across England, France, Spain, Italy), **CC0 1.0** (public domain)

## Acknowledgements

Built on the shoulders of open source — gratitude to [McBopomofo](https://github.com/openvanilla/McBopomofo) (TIS registration patterns), [국립국어원 우리말샘](https://opendict.korean.go.kr) (Korean headword data, CC-BY-SA 2.0 KR), [Claude](https://claude.com/claude-code) (development), and the wider body of human knowledge. See [Acknowledgements](./ACKNOWLEDGEMENTS.md).

## Feedback

Please report bugs and broken sites/apps on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

For dictionary suggestions, use **Settings → 개인 사전 (Personal dictionary) tab → 단어 제안하기... (Suggest a word)**: fill in what you typed and what you expected, and the **GitHub에서 열기** (Open on GitHub) button opens a pre-filled issue form in your browser. The app only opens the page and sends nothing; you submit it yourself on GitHub ([PRIVACY.md](./PRIVACY.md) #8). <!-- 2026-09-23 (#72) 탭 경로 -->

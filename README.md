<p align="center">
  <img src="docs/media/readme-banner.jpg" alt="리소그래프로 찍은 마을 어귀. 산과 기와집 아래 길을 한복 입은 세 사람이 걸어간다">
</p>

<p align="center">
  <img src="docs/media/app-icon-512.png" width="128" alt="하늘키보드 아이콘 — 하늘 아래 단청 처마 끝"><br>
  <b>하늘키보드</b> · HaneulKeyboard
</p>

<p align="center">
  <b>한글 모드 그대로 영어까지.</b><br>
  자판을 바꾸지 않아도 영어 단어가 제자리를 찾는 macOS 한글 입력기
</p>

<p align="center">
  <a href="https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest"><img src="https://img.shields.io/github/v/release/Hyunjin-Cho/HaneulKeyboard?style=flat-square&label=release" alt="최신 릴리스"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-green?style=flat-square" alt="Apache-2.0"></a>
  <a href="#요구-사항과-알려진-한계"><img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&amp;logo=apple" alt="macOS 14 이상"></a>
</p>

<p align="center"><a href="#english">English</a></p>

<!-- 2026-11-04 (#133): 데모 영상 자리. 새 영상이 준비되면 여기에 넣는다(옛 GIF 3개는 뺐다). -->

---

## 이런 입력기예요

한글 모드인 줄 모르고 영어를 쳐도 괜찮아요. 단어를 끝내는 순간 영어로 바로잡아요. 한글로 쓴 진짜 단어는 그대로 둬요.

| 이렇게 치면 | 이렇게 돼요 |
|---|---|
| `메ㅔㅣㄷ` + Space | `apple` |
| `how ㅁㄱㄷ you` | `how are you`. 영어 흐름을 이어서 읽어요 |
| 바뀐 단어 뒤에서 **Shift+Space** | 방금 바뀐 단어를 되돌려요. 한 번 더 누르면 다시 영어 |
| `레스토랑` + **Shift+Space** | `restaurant`. 등록된 한글 표기만 바꿔요 |
| `/help` | 슬래시 뒤에는 바로 영어. Space·Return 뒤 한글로 돌아와요 |
| `10` + `ㅏㅎ` + Space | `10kg`. 숫자는 누르는 즉시 들어가요 |
| `github에` | 영어 + 조사도 자연스럽게 |
| **Caps Lock** | 한글 ↔ 영어 전환. 길게 누르면 대문자 |

딸 **하늘**이의 이름에서 따왔어요.

## 설치

1. [릴리스 페이지](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest)에서 `HaneulKeyboard_<버전>.dmg`를 받아 열어요.
2. 하늘키보드를 **Applications** 폴더로 끌어다 놓고, 응용 프로그램 폴더에서 실행해요.
3. **시작하기** 안내가 열리면 1단계의 **하늘키보드 설치**를 누르고, 2단계에서 입력 소스를 선택해요.
   - 직접 추가할 때: 시스템 설정 → 키보드 → 텍스트 입력 → 편집 → **+** → 한국어 → **하늘키보드 (두벌식)**
   - 영어 입력용 **ABC는 남겨 두세요.** Caps Lock 전환은 macOS 기능이라 따로 권한을 요구하지 않아요.

입력 소스 목록에 보이지 않으면 앱의 **키보드 설정 열기**를 눌러 주세요. 오래된 목록을 새로 고쳐요.

> GitHub의 **Source code** 압축 파일은 설치용 앱이 아니에요. `2026.07` 이하 베타를 쓰고 있었다면 업데이트 기능이 없는 버전이라, 이번 한 번은 DMG를 직접 받아 주세요.

## 두루마리 안내 — 시작하기

<p align="center">
  <img src="Resources/Onboarding/OnboardingP7End.png" width="420" alt="안내 마지막 장면. 하늘 아래 단청 처마 끝, 앱 아이콘과 같은 구도">
</p>

처음 실행하면 말린 두루마리가 펼쳐지고, 한복 입은 세 사람이 마을 어귀부터 처마 밑까지 일곱 장면을 걸어가요. 장면마다 기능 하나를 소개하고, 3~6장면에서는 그 자리에서 직접 쳐 볼 수 있어요.

| | 장면 | 배우는 것 |
|---|---|---|
| 1 | 마을 어귀 | 만나보기와 입력기 설치 |
| 2 | 장승 갈림길 | 입력 소스 선택 |
| 3 | 징검다리 | 영타 자동 변환 |
| 4 | 널뛰기 | 한영 되돌리기 |
| 5 | 장터 | 등록 단어 변환 |
| 6 | 연 언덕 | 슬래시 영어 입력 |
| 7 | 처마 밑 | 메뉴바와 응원하기 |

메뉴바 → **시작하기 다시 보기...**로 언제든 다시 열 수 있어요. 손쉬운 사용의 **동작 줄이기**를 켜면 움직임 없이 보여 줘요.

아이콘부터 안내, 설치 화면까지 그림은 분홍·파랑·노랑 세 판으로 찍는 **리소그래프** 방식으로 만들었어요. 다크 모드에서는 종이가 따뜻한 먹색으로 바뀌어요.

## 기능 자세히

### 영타 자동 변환과 한국어 보호
- 영어 사전, 한국어 사전(국립국어원 우리말샘), 앞 단어의 문맥을 함께 봐요. 실제 한국어 단어, 초성체, 자모 이모티콘(`ㅋㅋ`, `ㅠㅠ`)과 겹치는 입력은 보호해요.
- 직접 누른 Space·문장부호에서 판정해요. 클릭이나 앱 전환으로 끝난 입력은 보이는 그대로 둬요.
- 사전에 없는 철자(`aplle`)는 추측해서 고치지 않고 그대로 둬요.
- 다른 입력기(ABC)로 쓴 커서 앞 영어 단어도 문맥으로 쓸 수 있어요. 사전에 있는 영어 두 단어를 붙여 쓴 것도 알아봐요(각 4글자 이상). 둘 다 설정에서 끌 수 있어요.
- 전체 자동 변환을 끄거나, 앱마다 끌 수 있어요.

### 되돌리기와 직접 전환
- **Shift+Space**로 방금 바뀐 단어를 되돌려요. 다시 누르면 영어로 돌아가요.
- 자동으로 바뀌지 않은 커서 앞 단어도 Shift+Space로 직접 바꿀 수 있어요(`ㅡ5` ↔ `m5`).
- 단축키는 Option+Space · Control+Shift+Space · Option+Shift+Space로 바꿀 수 있어요.

### 등록 단어 변환
`레스토랑 → restaurant`, `애플 → Apple`, `축구 → football`, `색보정 → color grading`처럼 **정확히 등록된 한글 표기**만 변환 단축키로 바꿔요. 일반 Space에서는 한글을 그대로 둬요. 다시 누르면 처음 입력한 한글로 돌아와요. 번역기처럼 뜻을 추측하지는 않아요. 범위는 [발음 변환 명세](docs/phonetic-conversion.md)와 [범주](docs/vocabulary-categories.md)에 있어요.

### 슬래시 영어 입력
`/help`, `/clear`처럼 슬래시 뒤에는 바로 영어가 나와요. Claude Code 같은 터미널 명령에 편해요. Space, Return, 닫는 괄호 `) ] }` 뒤나 슬래시를 지우면 한글로 돌아와요. 설정에서 끌 수 있어요.

### 숫자·단위·이름
- 숫자는 누르는 즉시 들어가요. 터미널의 `1. Yes / 2. No` 선택지도 한글 모드 그대로 고를 수 있어요.
- `10kg`, `1.5kg`, `35mm`, `12mp`처럼 숫자 뒤 단위를 알아봐요. 값 환산은 하지 않아요. [단위 지원](docs/measurement-units.md)
- `800T`, `a24`, `a7r`처럼 등록된 숫자 섞인 이름도 바꿔요. `800T는`, `a24에서`처럼 조사가 붙어도 돼요.

### 개인 사전
**설정 → 개인 사전**에서 관리해요. 이 Mac에만 저장돼요.
- **변환 추가:** 기본 사전에 없는 영어 단어·제품명
- **변환 금지:** 바뀌지 않았으면 하는 단어. 추가와 겹치면 금지가 이겨요
- **최근 되돌린 변환:** 최근 50개. 금지로 돌리거나 단어 제안으로 보낼 수 있어요

조합 중인 글자에는 회색 밑줄이 그어져요.

## 설정

메뉴바 아이콘 → **설정...**

| 메뉴 | 들어 있는 것 |
|---|---|
| 입력 기능 | 자동 변환(영타 변환·문맥·앱별 끄기) / 단축키 변환(변환 키·자판 변환·등록 단어·되돌리기·슬래시) |
| 개인 사전 | 변환 추가·금지·최근 되돌린 변환·단어 제안 |
| 버전·업데이트 | 설치된 버전과 최신 버전, 새 버전 알림 |
| 앱 관리 | 입력기 설치 상태, 하늘키보드 전체 제거 |

**전체 제거**는 앱·입력기·설정을 정리해요. 입력기 제거가 실패하거나 관리자 암호 창을 취소하면 개인 사전과 설정은 지우지 않아요.

## 업데이트와 버전

- 새 버전은 하루에 한 번 GitHub에서 확인하고, 처음 발견했을 때 한 번 알려요. 설정에서 알림을 끄거나 **지금 확인**을 누를 수 있어요.
- 설치는 **새 버전 설치**를 눌렀을 때만 시작해요. 서명·Apple 공증·버전 상승을 모두 확인하고, 하나라도 어긋나면 기존 앱을 그대로 둬요.
- 버전은 실제 배포 날짜예요. 예를 들어 11월 4일에 배포하면 `2026.11.04`, 그 판의 급한 수정은 `2026.11.04_hotfix1`, `_hotfix2` …예요. `2026.01`~`2026.07`은 순번으로 매긴 베타 이력이에요.

## 개인정보

**입력한 내용과 개인 사전을 어디에도 보내지 않아요.** 한글을 조합하는 입력기에는 네트워크 코드가 없어요. 메뉴바 앱은 업데이트를 확인하고 받을 때만 GitHub에 접속해요. 단어 제안은 사용자가 직접 GitHub나 메일 작성 화면에서 보내는 방식이에요. 자세한 내용은 [개인정보 안내](PRIVACY.md)에 있어요.

## 응원하기

하늘키보드는 무료예요. 메뉴바나 설정의 **응원하기**에서 후원 안내를 볼 수 있어요. 후원 여부가 기능을 제한하지 않아요.

<!-- 2026-11-04 (#20 #29): 후원 방식·주소가 정해지면 여기에 링크를 넣는다. -->

## 요구 사항과 알려진 한계

- **macOS Sonoma 14 이상** · Apple Silicon과 Intel(Universal)
- 지금은 **두벌식**만 지원해요.
- **터미널(Terminal·Ghostty 등)에서는 이미 들어간 글자를 바꿀 수 없어서 되돌리기·직접 전환이 안 돼요.** 자동 변환과 슬래시 입력은 동작해요. 원치 않으면 앱별로 꺼 주세요.
- 웹의 비밀번호 칸이 보안 입력을 제대로 켜지 않으면 한글이 조합될 수 있어요. 민감한 입력은 **ABC**로 해 주세요.
- 앱이나 사이트의 입력 처리 방식에 따라 동작이 조금 다를 수 있어요. 이상하면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 알려 주세요.

## 개발

```text
Sources/        메뉴바 앱 · 설정 · 두루마리 안내 · 설치 · 업데이트
IMESources/     두벌식 조합 · 영타 판정 · 직접 전환 · 개인 사전
Shared/         앱과 입력기가 함께 쓰는 판단(슬래시 입력 등)
Resources/      입력기 사전 · 아이콘 · 안내/설치 그림 · 글꼴
Tests/ scripts/ 테스트 · 사전 검역 · 빌드 · 공증 도구
dict_work/      사전 목록 정본(manifest) · 출처 · 검역 결과
docs/           기능 명세 · 배포/실기기 확인 목록
```

메인 앱 `HaneulKeyboard.app` 안에 입력기 `Contents/Helpers/HaneulKeyboardIM.app`이 들어 있고, 안내가 `~/Library/Input Methods/`에 설치해요. 메뉴바는 AppKit, 설정과 안내는 SwiftUI, 입력기는 IMKit이에요.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme HaneulKeyboard -configuration Debug build

# 테스트
bash scripts/run_ime_tests.sh              # 조합·영타·업데이트 판단
python3 scripts/run_controller_tests.py    # 입력 컨트롤러 시나리오
bash scripts/run_slash_tests.sh            # 슬래시 영어 입력
bash scripts/run_input_inference_tests.sh  # 문맥 추론
bash scripts/run_onboarding_tests.sh       # 안내
bash scripts/run_updater_tests.sh          # 업데이트·제거
python3 scripts/test_postinstall_probe.py
python3 scripts/test_uninstall.py

# 사전 검역
bash scripts/audit_wordlist.sh --smoke
bash scripts/audit_units.sh
```

배포 파일(서명·공증된 DMG와 업데이트용 ZIP)은 메인 앱 타깃으로 만들어요. Developer ID 인증서와 `haneul-notary` 키체인 프로필이 필요해요. 순서는 [배포 체크리스트](docs/release-checklist.md), 실기기 확인은 [수동 확인 목록](docs/manual-test-checklist.md)에 있어요.

```bash
PACKAGE_ONLY=1 bash scripts/build_notarize_install.sh HaneulKeyboard
```

## 라이선스와 감사의 글

앱 코드는 **Apache License 2.0**이에요. [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 확인해 주세요. 예전 MIT 배포본에 준 권리는 그대로이고, 고지는 [MIT 원문](LICENSES/HaneulKeyboard-MIT-legacy.txt)에 남겨 뒀어요. 사전과 글꼴에는 각자의 라이선스가 있어요.

| 자료 | 라이선스 |
|---|---|
| 국립국어원 우리말샘 한국어 목록 | CC BY-SA 2.0 KR |
| NGSL 영어 목록 | CC BY-SA 4.0 |
| SCOWL/ESDB 영어 목록 | MIT-like |
| US Census·SSA 인명 데이터 | Public Domain |
| GeoNames 지명 | CC BY 4.0 |
| Wikidata 축구 클럽·선수 | CC0 1.0 |
| 고운바탕·나눔손글씨 펜 | SIL Open Font License 1.1 |

[McBopomofo](https://github.com/openvanilla/McBopomofo)의 입력기 등록·설치 구조, 공개 사전과 글꼴, 오픈소스 기여자들에게 감사해요. **[Claude](https://claude.com/claude-code)(Anthropic)**와 **[Codex · ChatGPT](https://openai.com/codex/)(OpenAI)**가 설계·개발·검증·문서·그림 작업에 함께했어요. 만드는 도구로 썼다는 뜻이고, 앱이 입력 내용을 AI에 보낸다는 뜻은 아니에요. 출처와 가공 방식은 [감사의 글](ACKNOWLEDGEMENTS.md)에 모았어요.

---

<a id="english"></a>

# English

**HaneulKeyboard** is a Korean input method for macOS that lets you type English without switching layouts. It is named after my daughter Haneul, which means "sky" in Korean.

## What it does

| You type | You get |
|---|---|
| `메ㅔㅣㄷ` + Space | `apple`. English typed in Korean mode is fixed as you finish the word |
| `how ㅁㄱㄷ you` | `how are you`. The English context carries over |
| **Shift+Space** after a conversion | Reverts it. Press again to go back |
| `레스토랑` + **Shift+Space** | `restaurant`. Only exact, curated Hangul spellings |
| `/help` | English right after a slash. Korean resumes after Space or Return |
| `10` + `ㅏㅎ` + Space | `10kg`. Digits are sent immediately |
| **Caps Lock** | Korean ↔ English. Long press for capitals |

Real Korean words, initial-consonant slang and jamo emoticons are protected. Unknown misspellings are left as typed, not guessed. Automatic conversion can be turned off entirely or per app, and a personal dictionary lets you add or block words. Composing text is shown with a gray underline.

## Install

1. Download `HaneulKeyboard_<version>.dmg` from [Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest) and open it.
2. Drag HaneulKeyboard into **Applications** and launch it from there.
3. In the **시작하기** (Getting Started) guide, press **하늘키보드 설치** in step 1 and select the input source in step 2. Keep **ABC** for English.

Users of the `2026.07` and older betas need to download the DMG once; those builds have no updater. GitHub's "Source code" archives are not installable apps.

## The scroll guide

On first launch, a rolled scroll unfurls and three people in hanbok walk through seven scenes, from the village gate to the eaves. Each scene introduces one feature, and scenes 3–6 let you try it right there. Every illustration, from the app icon to the installer, is printed in a risograph style with pink, blue and yellow plates. In dark mode the paper turns a warm ink black.

## Updates and versions

The menu bar app checks GitHub once a day and tells you once about a new version. It installs only when you click **새 버전 설치** (Install new version), after checking the signature, Apple notarization and that the version actually goes up. Versions are release dates: `2026.11.04` for a November 4 release, then `2026.11.04_hotfix1`, `_hotfix2` and so on for urgent fixes. `2026.01`–`2026.07` were sequential beta numbers.

## Privacy

Your typing and personal dictionary never leave your Mac. The input method has no networking code; the menu bar app only contacts GitHub for updates. See [Privacy](PRIVACY.md).

## Requirements and limits

- macOS Sonoma 14 or later, Universal (Apple Silicon and Intel)
- Two-set (Dubeolsik) layout only
- In terminals (Terminal, Ghostty and others), committed text cannot be replaced, so reverting and manual toggling do not work. Automatic conversion and slash input still do.
- For sensitive input such as passwords, use **ABC** in case a site does not enable secure input.

## License and credits

App code is licensed under **Apache License 2.0** ([LICENSE](LICENSE), [NOTICE](NOTICE)). Earlier MIT releases keep their terms ([legacy notice](LICENSES/HaneulKeyboard-MIT-legacy.txt)). Bundled dictionaries and fonts keep their own licenses: Urimalsaem (CC BY-SA 2.0 KR), NGSL (CC BY-SA 4.0), SCOWL/ESDB (MIT-like), US Census/SSA (public domain), GeoNames (CC BY 4.0), Wikidata (CC0), Gowun Batang and Nanum Pen Script (OFL 1.1). See [Acknowledgements](ACKNOWLEDGEMENTS.md).

Thanks to [McBopomofo](https://github.com/openvanilla/McBopomofo), the open-source community, **[Claude](https://claude.com/claude-code) (Anthropic)** and **[Codex · ChatGPT](https://openai.com/codex/) (OpenAI)** for help with design, development and artwork. Report problems or suggest words in [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

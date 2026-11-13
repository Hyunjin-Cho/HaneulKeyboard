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

> **정식 버전 준비 중입니다.** 설치 파일은 준비가 끝나면 [릴리스 페이지](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases)에 올라옵니다. 아래는 정식 버전 기준의 안내입니다.

<!-- 2026-11-04 (#133): 데모 영상 자리. 새 영상이 준비되면 여기에 넣는다(옛 GIF 3개는 뺐다). -->

---

## 이런 입력기입니다

한글 모드인 줄 모르고 영어를 쳐도 괜찮습니다. 단어를 끝내는 순간 영어로 바로잡습니다. 한글로 쓴 진짜 단어는 그대로 둡니다.

| 이렇게 치면 | 이렇게 됩니다 |
|---|---|
| `메ㅔㅣㄷ` + Space | `apple` |
| `how ㅁㄱㄷ you` | `how are you`. 영어 흐름을 이어서 읽습니다 |
| 바뀐 단어 뒤에서 **Shift+Space** | 방금 바뀐 단어를 되돌립니다. 한 번 더 누르면 다시 영어로 바뀝니다 |
| `레스토랑` + **Shift+Space** | `restaurant`. 등록된 한글 표기만 바꿉니다 |
| `/help` | 슬래시 뒤에는 바로 영어가 나옵니다. Space·Enter 뒤에는 한글로 돌아옵니다 |
| `10` + `ㅏㅎ` + Space | `10kg`. 숫자는 누르는 즉시 들어갑니다 |
| `github에` | 영어 뒤에 조사를 붙여 쳐도 됩니다 |
| **Caps Lock** | 한글 ↔ 영어를 전환합니다. 길게 누르면 대문자입니다 |

**하늘**키보드는 사랑하는 우리 딸 이름을 따왔습니다.

## 설치

1. [릴리스 페이지](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest)에서 `HaneulKeyboard_<버전>.dmg`를 받아 엽니다.
2. 하늘키보드를 **Applications** 폴더로 끌어다 놓고, 응용 프로그램 폴더에서 실행합니다.
3. **시작하기** 안내가 열리면 1단계의 **하늘키보드 설치**를 누르고, 2단계에서 입력 소스를 선택합니다.
   - 직접 추가할 때: 시스템 설정 → 키보드 → 텍스트 입력 → 편집 → **+** → 한국어 → **하늘키보드 (두벌식)**
   - 영어 입력용 **ABC는 남겨 두세요.** Caps Lock 전환은 macOS 기능이라 따로 권한을 요구하지 않습니다.

입력 소스 목록에 보이지 않으면 앱의 **키보드 설정 열기**를 눌러 주세요. 오래된 목록을 새로 고칩니다.

> GitHub의 **Source code** 압축 파일은 설치용 앱이 아닙니다. `2026.07` 이하 베타에는 업데이트 기능이 없으므로, 이번 한 번은 DMG를 직접 받아 주세요.

## 안내

처음 실행하면 **시작하기** 안내가 열립니다. 일곱 단계로 설치부터 주요 기능까지 익힐 수 있습니다.

1. 만나보기와 입력기 설치
2. 입력 소스 선택
3. 영어 자동 변환
4. 되돌리기
5. 한글 단어를 영어로
6. 슬래시 영어 입력
7. 메뉴바와 응원하기

3~6단계에서는 입력칸에 직접 쳐 볼 수 있습니다. 메뉴바 → **시작하기 다시 보기…**로 언제든 다시 열 수 있습니다. 손쉬운 사용의 **동작 줄이기**를 켜면 움직임 없이 보여 줍니다.

## 기능 자세히

### 영어 자동 변환과 한국어 보호
- 영어 사전, 한국어 사전(국립국어원 우리말샘), 앞 단어의 문맥을 함께 봅니다. 실제 한국어 단어, 초성체, 자모 이모티콘(`ㅋㅋ`, `ㅠㅠ`)과 겹치는 입력은 보호합니다.
- 직접 누른 Space·문장부호에서 판정합니다. 클릭이나 앱 전환으로 끝난 입력은 보이는 그대로 둡니다.
- 사전에 없는 철자(`aplle`)는 추측해서 고치지 않고 그대로 둡니다.
- 영타로 친 영어 바로 뒤에서는 한글로도 읽히는 짧은 영어까지 바꿉니다(`want 새` → `want to`). `helloworld`처럼 영어 단어 두 개를 붙여 쳐도 바꿉니다(두 단어 모두 네 글자 이상). 둘 다 설정에서 끌 수 있습니다.
- 자동 변환은 전체로 끄거나 앱마다 끌 수 있습니다.

### 되돌리기와 미리 친 단어 바꾸기
- **Shift+Space**로 방금 바뀐 단어를 되돌립니다. 다시 누르면 영어로 돌아갑니다.
- 한/영 전환을 깜빡하고 친 단어도 Shift+Space로 바꿉니다(`dkssud` ↔ `안녕`).
- 변환 단축키는 Option+Space · Control+Shift+Space · Option+Shift+Space로 바꿀 수 있습니다.

### 한글 단어를 영어로 바꾸기
`레스토랑 → restaurant`, `애플 → Apple`, `축구 → football`, `색보정 → color grading`처럼 **정확히 등록된 한글 표기**만 변환 단축키로 바꿉니다. 일반 Space에서는 한글을 그대로 둡니다. 다시 누르면 처음 입력한 한글로 돌아옵니다. 범위는 [발음 변환 명세](docs/phonetic-conversion.md)와 [범주](docs/vocabulary-categories.md)에 있습니다.

### 슬래시 영어 입력
`/help`, `/clear`처럼 슬래시 뒤에는 바로 영어가 나옵니다. Claude Code 같은 터미널 명령에 쓰기 좋습니다. Space·Enter·닫는 괄호 `) ] }` 뒤나 Backspace로 슬래시를 지우면 한글로 돌아옵니다. 설정에서 끌 수 있습니다.

### 숫자·단위·이름
- 숫자는 누르는 즉시 들어갑니다. 터미널의 `1. Yes / 2. No` 선택지도 한글 모드 그대로 고를 수 있습니다.
- `10kg`, `1.5kg`, `35mm`, `12mp`처럼 숫자 뒤 단위를 알아봅니다. 값 환산은 하지 않습니다. [단위 지원](docs/measurement-units.md)
- `800T`, `a24`, `a7r`처럼 등록된 숫자 섞인 이름도 바꿉니다. `800T는`, `a24에서`처럼 조사가 붙어도 됩니다.

### 개인 사전
**설정 → 개인 사전**에서 관리합니다. 이 Mac에만 저장됩니다.
- **변환 추가:** 기본 사전에 없는 영어 단어·제품명
- **변환 금지:** 바뀌지 않았으면 하는 단어. 추가와 겹치면 금지가 우선합니다
- **되돌린 단어:** 직접 되돌린 단어 최근 50개. 변환 금지에 넣거나 단어 제안으로 보낼 수 있습니다

조합 중인 글자에는 회색 밑줄이 그어집니다.

## 설정

메뉴바 아이콘 → **설정…**에서 엽니다. 메뉴바 아이콘은 **앱 관리**에서 끌 수 있고, 꺼도 한글 입력은 그대로 동작합니다. 아이콘을 꺼 둔 경우에는 응용 프로그램 폴더에서 하늘키보드를 열면 설정이 열립니다.

| 메뉴 | 들어 있는 것 |
|---|---|
| 자동 변환 | 영어 자동 변환·영타로 친 영어 뒤에 이어 칠 때·영어 단어 두 개를 붙여 쳤을 때·앱별 끄기 |
| 단축키·슬래시 | 변환 단축키·한글 단어를 영어로 바꾸기·슬래시 영어 입력 |
| 개인 사전 | 변환 추가·변환 금지·되돌린 단어·단어 제안 |
| 설치·업데이트 | 한글 입력기 설치, 설치된 버전과 최신 버전, 새 버전 알림 |
| 앱 관리 | 메뉴바 아이콘 켜고 끄기, 하늘키보드 전체 제거 |

**하늘키보드 전체 제거**는 앱·입력기·설정·개인 사전을 모두 지웁니다. 입력기를 지우지 못하면(관리자 암호 창을 취소한 경우 포함) 개인 사전과 설정은 남겨 둡니다.

## 업데이트와 버전

- 새 버전은 매월 1일에 GitHub에서 확인하고(그날 Mac을 켜지 않았으면 다음에 켤 때), 처음 발견했을 때 한 번 알려 드립니다. 설정에서 알림을 끄거나 **지금 확인**을 누를 수 있습니다.
- 설치는 **새 버전 설치**를 눌렀을 때만 시작합니다. 서명·Apple 공증·버전 상승을 모두 확인하고, 하나라도 어긋나면 기존 앱을 그대로 둡니다.
- 버전은 실제 배포 날짜입니다. 예를 들어 11월 4일에 배포하면 `2026.11.04`, 그 판의 급한 수정은 `2026.11.04_hotfix1`, `_hotfix2` …입니다. `2026.01`~`2026.07`은 순번으로 매긴 베타 이력입니다.

## 개인정보

**입력한 내용과 개인 사전을 어디에도 보내지 않습니다.** 한글을 조합하는 입력기에는 네트워크 코드가 없습니다. 메뉴바 앱은 업데이트를 확인하고 받을 때만 GitHub에 접속합니다. 단어 제안은 사용자가 직접 GitHub나 메일 작성 화면에서 보내는 방식입니다. 자세한 내용은 [개인정보 안내](PRIVACY.md)에 있습니다.

## 응원하기

하늘키보드는 무료입니다. 메뉴바나 설정의 **응원하기**에서 후원 안내를 볼 수 있습니다. 후원 여부가 기능을 제한하지 않습니다.

[GitHub Sponsors](https://github.com/sponsors/Hyunjin-Cho)에서 바로 후원할 수도 있습니다. 한 번만 또는 매달 후원할 수 있고, GitHub 계정이 필요합니다.

## 요구 사항과 알려진 한계

- **macOS Sonoma 14 이상** · Apple Silicon과 Intel(Universal)
- 지금은 **두벌식**만 지원합니다.
- **터미널(Terminal·Ghostty 등)에서는 변환 단축키로 단어를 바꾸거나 되돌릴 수 없습니다.** 자동 변환과 슬래시 입력은 동작합니다.
- 일부 웹사이트의 비밀번호 칸에서는 한글이 입력될 수 있으니, 비밀번호는 **ABC**로 쳐 주세요.
- 앱이나 사이트의 입력 처리 방식에 따라 동작이 조금 다를 수 있습니다. 이상하면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 알려 주세요.

## 개발

```text
Sources/        메뉴바 앱 · 설정 · 안내 · 설치 · 업데이트
IMESources/     두벌식 조합 · 영타 판정 · 직접 전환 · 개인 사전
Shared/         앱과 입력기가 함께 쓰는 판단(슬래시 입력 등)
Resources/      입력기 사전 · 아이콘 · 안내/설치 그림 · 글꼴
Tests/ scripts/ 테스트 · 사전 검역 · 빌드 · 공증 도구
dict_work/      사전 목록 정본(manifest) · 출처 · 검역 결과
docs/           기능 명세 · 배포/실기기 확인 목록
```

메인 앱 `HaneulKeyboard.app` 안에 입력기 `Contents/Helpers/HaneulKeyboardIM.app`이 들어 있고, 안내가 `~/Library/Input Methods/`에 설치합니다. 메뉴바는 AppKit, 설정과 안내는 SwiftUI, 입력기는 IMKit으로 만들었습니다.

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

배포 파일(서명·공증된 DMG와 업데이트용 ZIP)은 메인 앱 타깃으로 만듭니다. Developer ID 인증서와 `haneul-notary` 키체인 프로필이 필요합니다. 순서는 [배포 체크리스트](docs/release-checklist.md), 실기기 확인은 [수동 확인 목록](docs/manual-test-checklist.md)에 있습니다.

```bash
PACKAGE_ONLY=1 bash scripts/build_notarize_install.sh HaneulKeyboard
```

## 라이선스와 감사의 글

앱 코드는 **Apache License 2.0**입니다. [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 확인해 주세요. 예전 MIT 배포본에 드린 권리는 그대로이고, 고지는 [MIT 원문](LICENSES/HaneulKeyboard-MIT-legacy.txt)에 남겨 두었습니다. 사전과 글꼴에는 각자의 라이선스가 있습니다.

| 자료 | 라이선스 |
|---|---|
| 국립국어원 우리말샘 한국어 목록 | CC BY-SA 2.0 KR |
| NGSL 영어 목록 | CC BY-SA 4.0 |
| SCOWL/ESDB 영어 목록 | MIT-like |
| US Census·SSA 인명 데이터 | Public Domain |
| GeoNames 지명 | CC BY 4.0 |
| Wikidata 축구 클럽·선수 | CC0 1.0 |
| 마루 부리(네이버)·나눔손글씨 펜 | SIL Open Font License 1.1 |

[McBopomofo](https://github.com/openvanilla/McBopomofo)의 입력기 등록·설치 구조, 공개 사전과 글꼴, 오픈소스 기여자들에게 감사드립니다. **[Claude](https://claude.com/claude-code)(Anthropic)**가 설계·개발·검증·문서·그림 작업에 함께했습니다. 출처와 가공 방식은 [감사의 글](ACKNOWLEDGEMENTS.md)에 모았습니다.

---

<a id="english"></a>

# English

**HaneulKeyboard** is a Korean input method for macOS that lets you type English without switching layouts.

> **The first stable release is in preparation.** Installers will be posted on the [Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases) page when ready. This README describes the stable version.

## What it does

| You type | You get |
|---|---|
| `메ㅔㅣㄷ` + Space | `apple`. English typed in Korean mode is fixed as you finish the word |
| `how ㅁㄱㄷ you` | `how are you`. The English context carries over |
| **Shift+Space** after a conversion | Reverts it. Press again to go back |
| `레스토랑` + **Shift+Space** | `restaurant`. Only exact, curated Hangul spellings |
| `/help` | English right after a slash. Korean resumes after Space or Enter |
| `10` + `ㅏㅎ` + Space | `10kg`. Digits are sent immediately |
| **Caps Lock** | Korean ↔ English. Long press for capitals |

**Haneul**Keyboard is named after our beloved daughter, Haneul. Her name means "sky" in Korean.

Real Korean words, initial-consonant slang and jamo emoticons are protected. Unknown misspellings are left as typed, not guessed. Automatic conversion can be turned off entirely or per app, and a personal dictionary lets you add or block words. Composing text is shown with a gray underline.

## Install

1. Download `HaneulKeyboard_<version>.dmg` from [Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases/latest) and open it.
2. Drag HaneulKeyboard into **Applications** and launch it from there.
3. In the **시작하기** (Getting Started) guide, press **하늘키보드 설치** in step 1 and select the input source in step 2. Keep **ABC** for English.

Users of the `2026.07` and older betas need to download the DMG once; those builds have no updater. GitHub's "Source code" archives are not installable apps.

## Getting started

On first launch, the **시작하기** guide walks you through installation, choosing the input source and the main features in seven steps. Steps 3–6 have a field where you can try each feature. Reopen it any time from the menu bar with **시작하기 다시 보기…**.

## Updates and versions

The menu bar app checks GitHub on the 1st of each month (or the next time you turn on your Mac, if it was off that day) and tells you once about a new version. It installs only when you click **새 버전 설치** (Install new version), after checking the signature, Apple notarization and that the version actually goes up. Versions are release dates: `2026.11.04` for a November 4 release, then `2026.11.04_hotfix1`, `_hotfix2` and so on for urgent fixes. `2026.01`–`2026.07` were sequential beta numbers.

## Privacy

Your typing and personal dictionary never leave your Mac. The input method has no networking code; the menu bar app only contacts GitHub for updates. See [Privacy](PRIVACY.md).

## Requirements and limits

- macOS Sonoma 14 or later, Universal (Apple Silicon and Intel)
- Two-set (Dubeolsik) layout only
- In terminals (Terminal, Ghostty and others), the conversion shortcut cannot change or revert words. Automatic conversion and slash input still work.
- Some websites' password fields may accept Hangul, so type passwords with **ABC**.

## License and credits

App code is licensed under **Apache License 2.0** ([LICENSE](LICENSE), [NOTICE](NOTICE)). Earlier MIT releases keep their terms ([legacy notice](LICENSES/HaneulKeyboard-MIT-legacy.txt)). Bundled dictionaries and fonts keep their own licenses: Urimalsaem (CC BY-SA 2.0 KR), NGSL (CC BY-SA 4.0), SCOWL/ESDB (MIT-like), US Census/SSA (public domain), GeoNames (CC BY 4.0), Wikidata (CC0), MaruBuri (NAVER) and Nanum Pen Script (OFL 1.1). See [Acknowledgements](ACKNOWLEDGEMENTS.md).

Thanks to [McBopomofo](https://github.com/openvanilla/McBopomofo), the open-source community, and **[Claude](https://claude.com/claude-code) (Anthropic)** for help with design, development and artwork. Report problems or suggest words in [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

# 하늘키보드 (HaneulKeyboard)

빠른 한↔영 전환과 안정적인 한글 입력을 위한 macOS 메뉴바 유틸리티 + 입력기(IME).

사랑하는 딸 **하늘**이의 이름에서 따왔습니다.

<!-- 데모 GIF / 스크린샷 자리 -->

## 주요 기능

- **안정적인 한글 조합** — 전용 입력 소스로 자모 깨짐 없이 한글을 조합합니다.
- **빠른 한/영 전환** — Caps Lock(짧게)으로 즉시 전환. 시스템 native 경로를 사용해 결정적으로 동작합니다.
- **Caps Lock 대문자 모드** — Caps Lock 길게(3초)로 LED 토글(대문자 모드).
- **메뉴바에서 제어** — 한국어/영어 전환, 설정, 단축키 변경을 메뉴바 아이콘에서.
- **단축키 선택** — Caps Lock / R-Option / R-Command / Shift+Space 중 선택 가능.

한↔영 입력에만 집중합니다. 다른 언어, 군더더기 기능은 없습니다.

### 왜 만들었나

macOS Tahoe (26.x)는 한국어 사용자에게 두 가지 불편함이 있습니다:

1. **한글 자모 조합이 때때로 깨짐** — `안녕` 입력 시 `ㅇㅏㄴ녕`처럼 개별 자모가 그대로 출력
2. **Caps Lock 한/영 전환 불안정** — 전환이 가끔 실패

하늘키보드는 전용 입력 소스를 통해 이 두 문제를 처음부터 끝까지 통제합니다.

## 설치

[GitHub Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases)에서 최신 버전을 받으세요.

### 설치 방법 (일반 사용자)

1. 다운로드한 `.zip` 압축 풀고 `HaneulKeyboard.app`을 **응용 프로그램(`/Applications/`)** 폴더로 복사
2. `HaneulKeyboard.app` 더블클릭 → 메뉴바에 아이콘 표시
3. 메뉴바 아이콘 → **"시작하기..."** → 4단계 온보딩 따라가기
   - 접근성 권한 부여 (단축키 가로채기용)
   - **"IME 설치"** 버튼 클릭 (자동으로 `~/Library/Input Methods/`에 설치)
4. **시스템 설정 → 키보드 → 입력 소스 → "+" → 한국어 → "HaneulKeyboard 한국어"** 추가
5. (선택) 기존 시스템 한국어 입력기(두벌식)는 제거 권장 — 자모 깨짐 방지 효과

> **⚠️ 중요**: Caps Lock을 한/영 단축키로 쓰려면 **입력 모니터링 권한**도 필요합니다.
> (온보딩 1단계에서 접근성 권한만 부여하면 기본 전환은 되지만, 길게 눌러 Caps Lock LED를 켜는 기능을 쓰려면 추가 권한이 필요합니다.)

## 사용법

- **Caps Lock** 짧게 누름 → 한/영 전환
- **Caps Lock** 길게 (3초) 누름 → Caps Lock LED 토글 (대문자 모드)
- 메뉴바 아이콘 → "한국어로 전환" / "영어로 전환" 클릭
- 메뉴바 아이콘 → "설정..." → 단축키 변경 가능 (Caps Lock / R-Option / R-Command / Shift+Space)

## 요구사항

- **macOS Sonoma (14.0) 이상** — macOS Tahoe (26.x)에서 테스트 완료
- Apple Silicon (M1/M2/M3/M4) 및 Intel 모두 지원

## 알려진 문제

- **후보 창(팝업)에서 입력 중인 글자가 연하게 표시됨** — 사용상 문제는 없어 현재 상태를 유지합니다.
- **현재 두벌식만 지원** — 다른 자판(세벌식 등)이 필요하면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 요청해주세요. 수요가 있으면 추가를 검토합니다.
- **일부 사이트/앱에서 동작하지 않을 수 있음** — 애초에 자모 결합 입력을 지원하지 않는 특정 웹사이트/앱에서는 입력기 종류와 무관하게 입력이 깨질 수 있습니다.
- 위와 같은 문제를 겪는 사이트/앱이 있다면 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)에 제보해주시면 큰 도움이 됩니다.

## 버전 체계

하늘키보드는 **CalVer(Calendar Versioning)** 를 따릅니다: `연도.릴리스[.핫픽스]`

- `2026.01`, `2026.02`, `2026.03` … — `2026`은 **연도**, 두 번째 칸은 **그 해의 릴리스 순번**입니다(달력의 월과 무관). 2026년 첫 릴리스가 `2026.01`, 두 번째가 `2026.02`.
- `2026.02.01`, `2026.02.02` … — **핫픽스(긴급 수정)가 있을 때만** 세 번째 칸을 덧붙입니다. 예) `2026.02` 출시 후 버그 수정본이 `2026.02.01`.

> 점으로 나뉜 각 칸은 독립된 정수이며 소수점이 아닙니다. 예) `2026.02.10`이 `2026.02.9`보다 최신입니다.

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
scripts/build_notarize_install.sh HaneulKeyboard
```

Apple Developer ID 인증서 + notarytool 키체인 프로필(`haneul-notary`)이 사전에 등록되어 있어야 합니다.

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
| `HaneulKeyboard.app` | 메뉴바 앱 — 단축키, 언어 전환, IME 설치, 권한 관리 | SwiftUI, CGEventTap, IOHID, TIS API |
| `HaneulKeyboardIM.app` | 한글 입력기 — 자모 조합 | IMKit, IMKInputController |

## 라이선스

MIT License — 자유롭게 사용, 수정, 배포하세요. 자세한 내용은 [`LICENSE`](./LICENSE) 파일을 참고하세요.

## 감사의 글

하늘키보드는 앞서 길을 닦아준 오픈소스와 도구들 위에 서 있습니다:

- **[McBopomofo](https://github.com/openvanilla/McBopomofo)** (OpenVanilla, MIT) — IME의 TIS(Text Input Services) 등록·설치 패턴에 큰 도움을 받았습니다.
- **[Claude](https://claude.com/claude-code)** (Anthropic) — 개발 과정에 함께했습니다.

그리고 이 모든 것을 가능케 한, 인류가 쌓아 올린 오픈소스와 지식에 감사합니다. 전체 감사의 글은 [`ACKNOWLEDGEMENTS.md`](./ACKNOWLEDGEMENTS.md)를 참고하세요.

## 제보 / 기여

실제로 써보고 불편한 점이나 버그를 [Issues](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues)로 알려주세요. 특히 한글 입력이 깨지는 사이트/앱을 발견하면 제보해주시면 개선에 큰 도움이 됩니다. 적극적인 실사용과 피드백을 환영합니다.

<!-- 후원 링크 자리 (URL 확정 후 추가) -->

---

# English

A macOS menu bar utility for fast Korean ↔ English input switching and reliable Hangul typing, with a dedicated input method (IME).

Named after my daughter, 하늘 (Haneul) — "sky" in Korean.

## Features

- **Reliable Hangul composition** via a dedicated input source — no broken jamo.
- **Fast Korean/English switching** with Caps Lock (short press), using the system-native path for deterministic behavior.
- **Caps Lock uppercase mode** with a long press (3s).
- **Menu bar control** for language switching, settings, and shortcuts.
- **Selectable shortcut**: Caps Lock / R-Option / R-Command / Shift+Space.

Korean ↔ English input only. No other languages, no extra features.

## Install

Download the latest build from [GitHub Releases](https://github.com/Hyunjin-Cho/HaneulKeyboard/releases), copy `HaneulKeyboard.app` to `/Applications/`, double-click it, and follow the 4-step onboarding wizard.

## Requirements

macOS Sonoma (14.0) or later. Both Apple Silicon and Intel.

## Versioning

CalVer: `YEAR.RELEASE[.HOTFIX]`. The second field is the release number within the year (not the calendar month): `2026.01`, `2026.02`, `2026.03` … A third field is added only for hotfixes (e.g. `2026.02.01`). Each dot-separated field is an independent integer, not a decimal.

## License

MIT. See [`LICENSE`](./LICENSE).

## Acknowledgements

Built on the shoulders of open source — gratitude to [McBopomofo](https://github.com/openvanilla/McBopomofo) (TIS registration patterns), [Claude](https://claude.com/claude-code) (development), and the wider body of human knowledge. See [`ACKNOWLEDGEMENTS.md`](./ACKNOWLEDGEMENTS.md).

## Feedback

Please report bugs and broken sites/apps on the [Issues page](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues).

# 시작하기 화면 샘플

기준일: **2026-10-09** · 기준 제품 커밋: **cdd26cd** + 2026.9(52) 로컬 변경.

이 폴더는 승인된 HTML 시안의 기록이다. 2026-10-06 사용자 승인으로 5단계를 실제 앱의 `Sources/OnboardingView.swift`와 `OnboardingWindow.swift`에 연결했다. 현재 상태·실기 순서는 [2026.9 테스트 안내](../../docs/releases/2026.9-test.md)를 따른다. 설치된 2026.08은 자동 교체하지 않았고 커밋·푸시·릴리스하지 않았다.

실제 제품의 입력 칸은 HTML의 별도 JS 모델 대신 `NSTextView`를 사용한다. 설치된 IME 및 사용자 설정이 그대로 적용되며, 실제 되돌리기는 제품의 최근 기록 규칙을 따른다는 안내를 표시한다. HTML은 그대로 격리된 시안이다. 채팅의 대화형 미리보기를 표시하지 못하는 기기에서는 원본 HTML을 로컬 브라우저에서 열거나 실제 앱을 실행하면 된다.

## 파일

- `haneul-onboarding.html`: 대화/로컬 브라우저에서 볼 수 있는 독립적인 5단계 시안. 반투명 창과 배경 흐림은 CSS 표현이며 실제 SwiftUI Liquid Glass 렌더링은 아니다. macOS 전용 제품을 설명하는 화면이지 모바일 앱이 아니다.
- `onboarding-template.html`, `preview-behavior.js`, `build_preview.py`: 편집 원본과 자체 포함 HTML 생성기. `python3 work/onboarding-preview/build_preview.py`로 생성한다. 실제 `Resources/AppIcon.icns`에서 아이콘을 추출해 포함하며 네트워크 요청은 없다.
- `PreviewData.swift`, `preview-data.json`: 실제 IME 코드로 만든 두벌식 표·대표 자동변환 단어. 브라우저 연습용 데이터이며 실제 앱의 전체 문맥/개인 사전/현재 설정에 연결하지 않는다. 사용자 입력과 샘플 사전은 페이지 메모리에만 두고 widgetState에 저장하지 않는다.
- `NativeControlsSample.swift`: SwiftUI `.glass`/`.glassProminent`와 기본 버튼의 OS 분기를 확인하는 독립적인 코드. 실행 진입점, AppCore, 설치/저장/통신 코드는 없다. 제품 타깃에 포함하지 않는다.
- **2026-10-09 현재:** 메뉴바 원본은 `Resources/Brand/HaneulKeyboard_Menu_Icon_2@2x.png`(사용자 제공 44×44)이다. 앱과 안내 5번은 `HaneulStatusIcon.image`로 이를 공유한다. 구름ㅎ와 이전 5안의 SVG·비교 HTML·전용 생성기는 사용자 삭제 요청에 따라 제거했다.
- `scripts/generate_status_icons.swift --menu-only`는 22×22/44×44 `HaneulRoofTemplate`을 만든다. 44×44는 원본 바이트를 유지한다. 이 HTML의 메뉴 그림도 같은 PNG로 재생성했다.
- 아래 과거 검증 항목의 구름ㅎ/18pt/한·A 표시는 당시 기록이다. 현재 제품 기준은 [실기 안내](../../docs/releases/2026.9-test.md)를 따른다.

## SDK와 최소 버전

- `xcodebuild -version`: Xcode 27.0 / 27A266a.
- `xcrun --sdk macosx --show-sdk-version`: 27.0.
- `project.yml` 양쪽 target 및 생성된 pbxproj: 최소 macOS 14.0.
- SDK SwiftUI 인터페이스 `GlassButtonStyle`: macOS 26.0 이상. 그 아래에서는 기본 버튼으로 분기한다. 투명도 감소 설정도 기본 버튼으로 분기하는 예제다.
- SDK 27, `arm64-apple-macos14.0`과 `x86_64-apple-macos14.0` 모두 NativeControlsSample 타입 검사 통과. 최소 버전 유지 가능성을 확인한 컴파일 검사이며, macOS 14 실기기 실행 검증은 아니다.

```sh
xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos14.0 work/onboarding-preview/NativeControlsSample.swift
xcrun --sdk macosx swiftc -typecheck -target x86_64-apple-macos14.0 work/onboarding-preview/NativeControlsSample.swift
```

출처: 프로젝트 `project.yml`의 deploymentTarget, 생성된 `HaneulKeyboard.xcodeproj/project.pbxproj`의 MACOSX_DEPLOYMENT_TARGET/SDKROOT, 로컬 macOS27.0.sdk SwiftUI.swiftinterface의 `GlassButtonStyle`. 디자인 방향 참고: [Apple의 Liquid Glass 도입 안내](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Onboarding HIG](https://developer.apple.com/design/human-interface-guidelines/onboarding).

## 두 번째 시안의 반영과 검증

- 같은 화면 폭에서 모든 단계의 창 크기를 고정했다. 데스크톱 실측 **720×800 CSS px**로 5단계 동일. 좁은 폭에는 더 높은 고정 규격을 쓰되 단계 이동으로는 크기가 바뀌지 않는다.
- 320px 브라우저 실측 창 크기 **276×1030**로 5단계 동일. 가로 넘침·설명과 본문 겹침·본문의 아래 영역 침범 없음. 제품 자체를 모바일로 확장한 것이 아니라 대화창의 좁은 표시 폭에 대응한 것이다.
- 설치 전/진행/완료를 버튼과 상태 문구로 표시. 설치/등록/선택은 **모의 상태**이며 실제 Mac을 검사한 결과가 아니다.
- 키보드 설정 → 편집 → 한국어/하늘키보드 추가 → 선택을 세 장의 조작 가능한 그림으로 안내. 하늘 등록 후 기본 두벌식 제거, ABC 유지 문구 추가. 기존 두벌식 제거 예시는 등록 이후에만 활성화.
- 제목의 쉼표/마침표 제거. `Mac에서 하늘키보드를 선택`, `하늘키보드로 apple`, `하늘키보드는 영원히 무료입니다.` 반영. 제목 크기 34→32, 굵기 700→650으로 조정.
- 시연과 자유 입력 분리. 실제 키 입력으로 `Apple tangerine ` 변환 확인(대문자 유지), 시연이 입력칸을 덮어쓰지 않음.
- 자유 수동 변환: `m5 → ㅡ5 → m5`를 Shift+Space로, `a16z → ㅁ16ㅋ`를 버튼으로 확인. 사전과 무관하게 자판 배열로 바꾸며 한영 혼합/숫자만인 단어는 보존. 단어 앞뒤와 커서 위치를 유지한다.
- 개인 사전 위치를 `하늘키보드 설정 → 개인 사전`으로 표시. 세 탭 직접 조작, 샘플 추가/금지/되돌린 기록/다시 바꾸지 않기 제공. `mybrand` 추가 + `apple` 금지 후 3단계에서 `mybrand 메ㅔㅣㄷ ` 확인.
- 페이지 본문에도 있던 `data-step`을 이동 버튼 선택자로 함께 잡아, 본문 클릭 때 다시 렌더되던 문제 수정. 선택자를 진행 표시의 버튼으로 한정한 후 시연 완료/단축키/사전 조작 재검증.
- 현재 코드 cdd26cd와 대표 사전으로 자동변환되는 **7,957개 항목**을 오프라인 생성. 이 샘플은 문맥을 포함한 전체 자동변환 엔진을 대체하지 않는다.
- JavaScript 조합/역변환을 실제 `ManualToggle`과 대조: 한글 음절 11,172개 + 대표 단어/숫자/축약형 포함 **19,149개 입력 사례**, 양방향 및 미지원 5건 합계 **38,303개 검사 통과**. 테스트용 원본은 `.tmp/onboarding-icon/core-fixtures.json`이며 PreviewData.swift로 재생성 가능.
- 실화면 검수는 현재 Mac의 어두운 화면에서 수행. 실제 SwiftUI Liquid Glass, 밝은 화면/VoiceOver/이전 OS는 제품 적용 때 별도 검증한다.

설정 경로 참고: [Apple 입력 소스 안내](https://support.apple.com/ko-kr/guide/mac-help/-mchl84525d76/mac). 유리 느낌 표현: [MDN backdrop-filter](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/backdrop-filter).

## 다음 순서와 미결 사항

1. 사용자 시각 검토. 문구·여백·키 입력 체험의 느낌 조정.
2. 실제 앱 연결 승인 범위 확정 후 OnboardingView 교체. 창 자체는 지금의 NSWindow/AppKit 경로 유지 여부부터 검토.
3. 실제 설치/등록/선택 확인, 이미 완료된 단계 처리, 실패·재시도·중복 클릭 차단, 완료 상태 판정 구현.
4. 실제 연습은 AppCore 초기화 부작용과 RecentReverts 기록을 격리하고, 자동변환 OFF/금지/앱별 설정을 존중. 현재 단축키를 표시.
5. 밝은/어두운 화면, VoiceOver/키보드, 동작·투명도 감소, 이전 OS 기본 UI 및 배포 빌드 실기기 검증.

후원 URL/계좌는 사용자 제공 대기. 샘플만으로 제품 완료 또는 티켓 종료로 판단하지 않는다.

## 세 번째 시안과 설치·삭제 연결 조건

- 상단 앱 아이콘 크기는 데스크톱 38×38 CSS px로 유지. 위/오른쪽에 같은 `--hk-brand-inset:12px`를 사용한다. Chrome에서 창 바깥 경계 기준 둘 다 13px(1px 테두리 포함) 실측. 데스크톱 창 720×800 유지, 360px 화면에서도 위/오른쪽 13px 동일 및 제목 겹침/가로 넘침 없음.
- 메뉴바 후보: **하늘 ㅎ / 키캡 ㅎ / 구름 ㅎ / 키보드 ㅎ / 전환 ㅎ**. 큰 앱 아이콘을 축소하지 않고, 메뉴바용 단색 도형으로 별도 제작했다. 현재 제품의 `한/A` 상태 표시는 유지하는 안이다. 5안 데스크톱 및 360px 화면에서 전환/가로 넘침 없음 확인. 추천은 하늘 ㅎ지만 최종 결정은 사용자에게 있다.
- 사용자 확정 요구: **메뉴바 앱과 IME는 하나의 설치·삭제 단위**. 메뉴바 앱을 제품으로 제거하면 IME도 함께 정리되어야 한다. 일시적인 종료·메뉴바 숨김은 삭제로 취급하지 않는다. 이번 범위는 시안과 조건 기록이며 제품의 설치·삭제 동작을 바꾸거나 실행하지 않았다.
- 현재 근거: `Sources/HaneulKeyboardApp.swift::setupStatusItem/updateButtonTitle`는 `character.bubble` + `한/A`를 표시하고, `quit`는 앱 종료만 수행한다. `Sources/SettingsView.swift`의 전체 제거 확인 → `Sources/UninstallManager.swift::Uninstaller.run`은 IME를 먼저 제거하고 성공한 경우 메인 앱을 제거한다. 제거 실패 시 재시도할 앱을 남긴다.
- Finder 삭제 감지는 `IMESources/main.swift::scheduleInitialCheck`, `IMESources/HaneulInputController.swift::activateServer` → `OrphanWatcher.checkIfDue/check/selfRemove` 경로에 있다. **사용자 Input Methods 경로의 Release 설치본에서만** 자기 정리가 작동한다. 초기 검사와 입력기 활성화가 검사 계기이며, 60초 조회 제한과 휴지통 120초/미발견 1800초 확인 유예가 있으므로 Finder 삭제 직후 즉시 제거된다고 보장할 수 없다. 시스템 경로 설치본은 이 감시에서 제외된다.
- 실제 제품 연결 때: 전체 제거와 Finder 삭제를 각각 검증하고, 시스템 경로의 기존 설치본 처리·입력기 미실행/재활성화가 없는 경우·앱 업데이트 중 일시적 부재·삭제 취소·제거 실패 후 재시도까지 확인한다. 샘플의 설치 표시가 현재 실제 상태를 읽는 것으로 오인되지 않게 유지한다. #80 제품 연결 조건으로 기록하고 종료하지 않는다.

## 22:34 요청 — 확정 아이콘과 제작 프롬프트

- 프롬프트 문서: `docs/design/icon-prompts-2026-10-06.md`. 큰 앱 아이콘 3가지 방향, 용도별 크기, 2026-10-06에 실제 조회한 공식 모델/도구 근거. 큰 앱 아이콘은 사용자 후보 생성·선택 대기.
- 제품 수정: `Sources/HaneulKeyboardApp.swift::setupStatusItem`에서 `HaneulMenuTemplate` 18pt를 사용하고 템플릿/한·A 표시 유지. `project.yml`의 IME 키는 검정 기본 `HaneulInputTemplate.png` / 흰색 alternate `HaneulInputSelected.png`로 연결. ‘하늘’ 명칭은 유지하고 22×16/44×32의 굵은 글자로 새로 렌더.
- 재생성: 저장소 루트에서 `swift scripts/generate_status_icons.swift`. 메뉴바 원본은 선택한 벡터, 입력기 원본은 네이티브 글꼴에서 다시 그린 단색 글자다. 기존 PNG의 단순 색 치환이 아니다.
- 패키징: Xcode 기본 동작이 PNG/@2x를 TIFF로 합치는 것을 실측했다. IME는 plist가 파일명을 지정하므로 `COMBINE_HIDPI_IMAGES=NO`로 PNG 유지. 메인 앱은 확장자 없는 `NSImage(named:)`로 TIFF의 1x/2x 표현을 읽는다.
- 검증: `.tmp/icon-candidate-build/Build/Products/Release/HaneulKeyboard.app`, Release 무서명 arm64/x86_64 빌드 성공, 최소 macOS 14. 최종 내장 IME의 아이콘 키 5곳 및 @2x 파일 실재 대조 통과. 원본 픽셀 검수에서 검정/흰색 단색, alpha 최대 1.0, @2x 글자 범위 37×20 확인. 첫 렌더의 Retina 중복 배율은 제거하고 재생성했다. 로그 `.tmp/icon-candidate-build.log`.
- 시스템 전환 표시: #2는 macOS가 그리는 UI이므로 아직 해결 확정 아님. 실제 서명 설치본에서 메뉴/한영 전환 표시/밝고 어두운 모드를 검증해야 한다. 유사 외부 입력기 템플릿 표시 문제가 보고됐지만 우리 원인이라고 단정하지 않음.
- 티켓: 시작하기/선택한 메뉴바 아이콘은 #80, 입력기 표시와 실제 전환 표시 검증은 [#81](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/81). 둘 다 OPEN 유지.
- 샘플 검증: 5단계의 18×18 구름 ㅎ, 2단계의 22×16 단색 ‘하늘’ 렌더와 단계 이동 확인. 입력 알고리즘 변경 없음.

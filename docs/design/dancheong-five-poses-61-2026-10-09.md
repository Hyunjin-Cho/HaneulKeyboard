# 다섯 페이지의 인물 그림과 새 Main 아이콘

기준일: 2026-10-09 · 빌드2026.9(61), 테스트 후보.

## 사용자 결정과 구현

- 색동은 각8×18pt로 높이24pt에서25% 줄였다. 총폭29pt와 색은 유지, 위아래 균형을 맞춰 윗선−9pt에 놓았다.
- `Sources/OnboardingRiso.swift::OnboardingPeopleSequence`는 페이지 번호만 읽는다.1~5에 고정된5장의 합성 그림이며, 다음/이전/단계 점을 눌렀을 때만 바뀐다. 타이머/TimelineView/Task/반복/유휴 복귀를 제거했다. 페이지 전환 외형과 입력기능은 유지한다.
- 첫60검토의0,2,3,4,7선택은1번과5번이 비슷하다는 사용자 피드백이 있어 폐기했다.61은 왼쪽/가운데의0~4자세를 사용한다.5번 가운데는 두 팔을 벌린 점프 자세다.
- 오른쪽 여성은 같은 팔이 자연스럽게 올라가는5자세를 내장imagegen으로 다시 만들었다. `Resources/Onboarding/DancheongPersonGreeting.png`,1536×1024,3열2행. 마지막 셀은 비어 있다. 소매→손목→손 방향을 단순화했고5번은 손을 들고 인사한다. 앱은 PNG의 알파를 그대로 사용한다.
- 새 원본 `Resources/Brand/HaneulKeyboard-Main.png`를 안내 `HaneulBrandIcon.png`와10크기 AppIcon.icns에 반영했다. Main원본은1024×1024, SHA256`cf63a4b7fc181522d447e4d22750885538bb55ca5939875b468f3c4d28e62faf`.
- `Resources/Brand/HaneulKeyboard_sub.png`도 삭제하지 않고 이동·보존했다.1024×1024, SHA256`a485f321733515404b512f2cdcfa3405550a3e0f4f266d1d59d15fb13bb0a4e2`. 두 원본의 이동 전후 해시는 같다. 이전AppIcon/안내아이콘은 `.tmp/dancheong-refine61/before/`에 보존했다.
- 안내 오른쪽위의60pt 원형 틀에는3pt 안쪽 여백을 주어 새 처마 끝이 잘리지 않도록 했다. 앱ICNS는 Main 전체 원본으로 만든다. 메뉴바 처마ㅎ는 이번 교체 대상과 별개다.

## 생성 프롬프트

방식: Codex 내장imagegen. 투명 배경:true. 첫 참조는 `Resources/Onboarding/DancheongPersonWave.png`이며, 두 번째는 첫 생성 출력의 배치 수정이다. 둘 다 원본을 보존했다.

### 손과 팔의 다섯 자세

```text
Use case: precise-object-edit. Asset type: transparent pose sheet for FIVE still onboarding pages, NOT a looping animation. EDIT TARGET: reference Korean risograph woman wearing vivid magenta jeogori, white cuffs, green/yellow full skirt, indigo hair bun and shoes. Preserve character identity, costume palette, right-facing orientation, flat CMY print grain and tiny paper pinholes. Replace the pose sequence with exactly FIVE anatomically natural full-body poses arranged in a regular THREE COLUMNS x TWO ROWS grid; bottom-right sixth cell MUST be fully empty transparent. Canvas ideally1536x1024, square512 cells. Row-major order1-5. Same scale, same hip center and same ground baseline at90% of each cell, head about20% down. All toes and raised hands must remain at least8% inside cell edges. POSE1 relaxed right-facing walking, near arm down beside body and far arm naturally behind. POSE2 small forward step, near elbow softly bends and hand moves forward to waist height. POSE3 near hand rises to chest height, elbow remains softly bent, palm follows forearm naturally. POSE4 near hand gently rises to shoulder/head level, forearm diagonal, elbow bent; far arm loosely back. POSE5 a warm greeting with near hand clearly raised beside and ABOVE her head, elbow gently bent, palm upright, far arm relaxed down, one foot a little forward. Final pose MUST look distinctly different from first. Important anatomy: exactly TWO arms/two hands per person; every hand attaches continuously to its own wrist and sleeve; thumb on correct side; wrists aligned with forearms rather than kinked/backwards; shoulders and elbows in physically plausible positions. Draw hands as small graceful simple print silhouettes with fingers grouped and one thumb, no tiny detailed splayed fingers, no extra digits, no detached hands. Slow natural progression of ONE same arm, never swap arms. Pleasant lightweight walking/greeting rather than rigid straight-arm salute. No scenery, floor, shadow, text, numbering or grid lines. Genuine transparent background. Avoid cutting off hands, large changes in character scale, duplicated figures or extra sprites.
```

### 셀 경계 여백 보완

```text
Use case: compositing. EDIT TARGET: attached FIVE-pose risograph woman sheet. Keep the five same poses, correct connected hands/wrists, costume, face, colors and fine ink texture. Only fix sprite spacing and clean transparent margins. EXACT canvas 1536x1024, regular3columns x2rows, each512x512. Exactly5sprites: top row3,bottom row2, final bottom-right cell empty. Scale EVERY figure uniformly DOWN about15%, place each at same baseline85% down its own cell. EVERY part of each figure including highest hand must be BETWEEN 45px and465px within its OWN512px cell. No ink or hand may cross a cell boundary. Specifically last woman's raised hand must have clear padding ABOVE it in the BOTTOM-MIDDLE cell, with no hand fragment leaking into the top-middle cell. Preserve all five actual poses and same scale. Transparent cutout ONLY: remove all colored halos, blur, glow, shadows and all background RGB bleed; clean alpha-zero outside the actual silhouettes. No scenery, floor, text, labels, grid, extra objects or extra sprites. Keep the far arm and hand anatomically connected, no added fingers, no bent-back wrists.
```

# 단청 인물 걷기와 메뉴바 원본

기준일: 2026-10-09. 아래는 이전 빌드2026.9(58) 기록이다. 현재59에서는 [인물별 여덟 자세](dancheong-people-motion-59-2026-10-09.md)로 교체했고 리뷰 앱에서도 동작을 켰다. 루트 자체 구현·검토, 에이전트 소집 없음.

## 사용자 결정과 적용

풍경 전체를 이동시키는 최초 구현은 사용자 의도와 달라 제거했다. 산·들·해·나무는 고정하고 사람의 발걸음만 바뀐다. `Sources/OnboardingRiso.swift::OnboardingWalkingFrieze`는 고정 풍경 위에 세 인물을 겹치고, 다음/이전 시 4자세를10fps로0.8초 재생하며 인물만 단계당4pt 이동한다. 유휴 시 정지하며 Task 취소로 빠른 연속 이동을 처리한다. 동작 줄이기에서는 정지 자세다. 장식은 클릭/접근성 대상이 아니다.

`Sources/OnboardingView.swift::animatePeople`의 제품 기본값은true다. 사용자가 애니메이션을 제외하고 디자인부터 살펴보도록 별도 `HaneulRefine58.app`만false를 지정한다. 검토 앱은 제품 설치본을 교체하지 않는다. 실제 시각 검수는 앱 실행에 대한 자동 승인 검토 차단 때문에 남아 있다. 아래 검사는 GUI 보행 품질 확인을 대신하지 않는다.

## 자산과 검증

내장 `imagegen` 스킬/도구로 원본 `Resources/Onboarding/DancheongWalkers.png`를 참조해 아래2장을 생성했다. 기존 그림을 덮어쓰지 않았다. 단순 픽셀 분할이 아니라 재생성된 분리 레이어이므로 원본의 모든 픽셀이 그대로라고 주장하지 않는다.

- `Resources/Onboarding/DancheongLandscape.png`:2172×724, 투명 풍경.
- `Resources/Onboarding/DancheongWalkCycle.png`:1448×1086, 4열×3행. 각362×362셀. 행은 노랑/분홍 여성, 청색 남성, 분홍/초록 여성이다.
- 프레임은 앱이 이미지에서 잘라 메모리에 한 번 캐시한다. 12개 모두 투명 배경/인물색이 있으며, 각 인물의4셀은 서로 다른 바이트다. 생성 결과를 눈으로 보아 발·옷의 자세 차이를 확인했으나 실제 앱의 재생 검토는 미결이다.
- 생성 출력 원본: `~/.codex/generated_images/01a10eeb-82a1-7091-8ee8-fc3afc825ed3/exec-0bbfe1b5-a13a-4c1a-a7bd-f5157ae7c6b3.png` 및 `exec-010e20de-6834-455f-b34b-6b56aaf75b3b.png`.
- 메뉴바 최신 정본: `Resources/Brand/HaneulKeyboard_Menu_Icon_2@2x.png`. 사용자가 준44×44 PNG를 이동했고 `Resources/MenuBar/HaneulRoofTemplate@2x.png`에 바이트 동일 복사했다. SHA256 `c6f10b42a3e819f30328b47eb5d6333cd7c4da0d89e9623a3c904f71cefa2552`.
- 처음 준1024×1024 처마ㅎ는 `Resources/Brand/HaneulKeyboard_Menu_Icon.png`에 원본으로 보관한다. 렌더용 정본은 이후 사용자가 준44×44다. 컬러 앱 아이콘/IME ‘하늘’ 글자는 별도 자산이다.
- `scripts/generate_status_icons.swift --menu-only`:22×22출력과44×44동일복사. 컴파일된TIFF의22/44알파는 각원본과완전히일치했다. `Sources/HaneulStatusIcon.swift`를 앱메뉴와안내5번이공유한다.
- 기존 구름SVG/메뉴PNG와5안탐색SVG·비교HTML/생성기는 삭제했고, 이전HTML미리보기의참조도갱신했다. 예전릴리스ZIP이나작업기록은역사자료이므로지우지않았다.
- 근거:`.tmp/dancheong-refine58/{asset-audit.log,review-menu-build.log,package-final.log,artifact.json}`.

## 생성 프롬프트 — 고정 풍경

투명 배경:true. 참조/편집대상:DancheongWalkers.png.

```text
Use case: precise-object-edit. Asset type: stationary background layer for a macOS onboarding walking animation. EDIT TARGET: attached approved wide Korean risograph vignette. Remove ONLY the three human figures and their garments/shoes/ribbons. Reconstruct the small mountains, ground flecks or grass behind the removed figures as needed. Keep the existing mountains, yellow sun, trees, bushes, cyan/pink ground line, overall silhouette, positions, original vivid CMY overprint colors and fine ink texture unchanged. Preserve the original 3:1 wide canvas and transparent margin above/below; genuinely transparent background, no paper rectangle. The landscape must look like the same composition with all three people absent, so separate animated people can be layered on top. No new objects, text, borders, shadows, characters or clouds.
```

## 생성 프롬프트 — 인물 시퀀스

투명 배경:true. 스타일/인물참조:DancheongWalkers.png.

```text
Use case: style-transfer. Asset type: production transparent SPRITE SHEET for a right-facing walking animation. Reference: attached approved Korean risograph scene. Extract/recreate ONLY its THREE human characters; no scenery. Lay out EXACTLY 12 separate sprites in a mathematically regular 4 COLUMNS x 3 ROWS grid, ideally canvas 1536x1152 with 384x384 cells. No visible grid lines. ROW1 same first woman in yellow jeogori, magenta skirt, indigo hair/shoes and flowing hair ribbon; ROW2 same man in cyan coat, cream/yellow trousers, indigo hair/shoes, magenta waist ribbon; ROW3 same woman in magenta jeogori, green/yellow skirt, indigo bun/shoes. All figures face RIGHT, always full body with no clipping. Within each row identical character identity, identical costume colors, same height and head/hip position; each figure centered within its cell with feet on baseline 86% down cell and top of head about14% down. Columns show a real 4-phase gait: 1 right foot forward/left back, 2 feet passing underneath hips/right heel raised and arms counter-swing, 3 LEFT foot forward/right back and opposite arm swing, 4 opposite passing pose. Legs, shoes, arms and garment silhouette MUST visibly change across columns; do NOT just translate/rotate the same static person. Weight shifts subtle, upright relaxed walking, flowing skirts and coat follow the different leg poses. Match existing flat cyan/pink/yellow with green/indigo overlap, tiny white ink pinholes and traditional hanbok silhouettes. Keep camera and scale identical in all cells. Genuine transparent background and generous clear padding between ALL cells. No mountains, trees, sun, ground, paper, shadows, labels, lettering, numbering or cell borders.
```

추가 확인(2026-10-09): 후속5페이지 캡처 요청에서 CUA 실행이 허용됐다. 최종 정적 리뷰1~5페이지의 손글씨/5번배치/새메뉴를 실제로 확인하고 `.tmp/dancheong-captures58/`에 저장했다. 위 실행차단은 해소됐으며, 인물걷기·동작줄이기의 실제 재생 확인은 여전히 남는다. 제품코드/배포ZIP/설치본 변경 없음.

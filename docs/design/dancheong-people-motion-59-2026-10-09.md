# 단청 인물의 여덟 자세 — 빌드59

기준일: 2026-10-09. 제품/검토 앱 모두 동작 활성화. 현재 테스트 후보이며 설치본 교체 전이다.

사용자 요청: 산·들·해·나무는 고정하고, 사람 자체의 동작을 만들어 걷기·점프·큰 팔 흔들기를 표현한다. 원본 `Resources/Onboarding/DancheongWalkers.png`를 참조해 내장 imagegen으로 인물별 투명 시트3장을 생성했다. 기존 그림/이전4자세 자산은 덮어쓰지 않았다.

각 파일은1774×887px,4열×2행의8자세다. `Sources/OnboardingRiso.swift::walkFrames`는 정수 경계를 나누어443/444px 셀을 캐시한다. 같은 파일 내 자세를0~7순으로 읽는다. `OnboardingWalkingFrieze`는10fps로1.6초(두 주기) 재생하고, 인물만 단계당4pt 전진한다. 휴지 시 첫 자세로 멈춘다. 처음 열 때는 움직이지 않으며 동작 줄이기에서는 정지 자세를 사용한다. 하단 전용50pt 안에48pt 인물과 고정 풍경을 겹친다. 전환 작업 취소를 처리한다.

품질/한계: 프레임마다 팔다리·옷 윤곽이 실제로 다르다. 연속 실사 영상처럼 보간하는 방식이 아닌 인쇄 그림의 프레임 애니메이션이다. 원본의 픽셀을 그대로 분리한 결과가 아니라 인물을 재생성했다. 리뷰 앱도 이번에는 `animatePeople:true`다.

## 정확한 생성 프롬프트

모두 `referenced_image_paths:[Resources/Onboarding/DancheongWalkers.png]`, `transparent_background:true`로 생성했다. 요청 해상도와 실제 반환 해상도는 다르므로 제품은 실제 크기를 읽는다.

### 걷기 — DancheongPersonWalk.png

```text
Use case: style-transfer. Production animation SPRITE SHEET. Reference image has three Korean hanbok people; use ONLY the LEFT woman (yellow jeogori, magenta/pink skirt with cream pleats, indigo ponytail and long pink/indigo ribbons, dark blue shoes). Recreate the SAME character in EIGHT CLEARLY DIFFERENT poses of a real relaxed RIGHT-FACING walking cycle, with alternating legs and counter-swinging arms. EXACT grid: 4 COLUMNS x 2 ROWS, eight square cells; frame order left-to-right across top row then bottom. No visible cell borders. Frame1 front foot well forward/back foot behind, arms opposed. Frame2 knees bending and torso lowered. Frame3 trailing leg bends and swings FORWARD past supporting leg, arms near torso. Frame4 lifted knee forward, foot raised. Frame5 OPPOSITE foot now well forward, opposite arm reaches forward. Frame6 knees bend/down pose. Frame7 other leg passes bent, opposite arm near torso. Frame8 leg lifts and extends into frame1. Silhouettes, shoes, knees, arm angles and swaying skirt MUST visibly differ by frame, not a translated still. Full body and ribbons fully inside each cell. Character same width/height and identity; consistent scale, fixed hips center, common invisible ground baseline at 88% cell height, head about20% down. Leave clear transparent padding around each entire body. Beautiful flat Korean risograph style exactly matching reference cyan/magenta/yellow/indigo ink, grain and tiny ink pinholes, no 3D. Genuinely transparent background; absolutely no landscape, sun, trees, floor, paper rectangle, text, numbering, watermarks or shadows. Ideal canvas 2048x1024, each cell512x512. Exactly one woman in each cell.
```

### 점프와 스텝 — DancheongPersonSkip.png

```text
Use case: style-transfer. Production transparent animation sprite sheet. Reference is attached Korean risograph scene. Take ONLY the CENTER MAN wearing a cyan hanbok coat, pale yellow/cream trousers, vivid pink waist ribbon, indigo short hair and indigo shoes. Make EIGHT dramatic DISTINCT key poses of a joyous RIGHT-FACING skipping and hopping step, NOT eight identical walking stills. EXACTLY 4 COLUMNS x 2 ROWS, read left to right then next row, equal square cells; no drawn grid. Frame1 walking contact, both arms down. Frame2 crouch anticipation, BOTH knees bend, torso down. Frame3 push off, one knee lifted HIGH to waist, BOTH elbows swing UP. Frame4 airborne joyful leap, BOTH feet clearly above common ground baseline, knees bent with one leg forward one behind, both hands lifted near or above head. Frame5 apex of leap, arms wide open sideways, legs tucked, coat flares, BOTH feet higher than in frame3. Frame6 descending, one leg reaches down to land, elbows lower. Frame7 land on one foot with bent knee, opposite arm forward. Frame8 step out toward normal walking pose. Full body, hands, coat and ribbon inside each cell with generous transparent margin; one same character per cell. Fixed camera and same body proportions/scale across all8. Common invisible ground baseline at 90% cell height, standing head 35% down; airborne head may rise to15% down. Use the AVAILABLE blank height for a clearly visible actual jump, NOT moving the whole sheet. Horizontal center consistent. Preserve reference face/style/costume/color, flat cyan/magenta/yellow/indigo overlapping inks, grain and speckles, no 3D. Truly transparent background; no mountains, landscape, floor, sun, trees, paper, shadows, labels, text or numbers. Ideal2048x1024 canvas,512squarecells.
```

### 큰 팔 흔들기 — DancheongPersonWave.png

```text
Use case: style-transfer. Production transparent animation sprite sheet. Reference attached Korean risograph scene. Isolate/recreate ONLY the RIGHT WOMAN with magenta hanbok jeogori, green skirt with large yellow/cream triangular pleats, indigo bun and indigo shoes. EXACTLY EIGHT frames in4COLUMNS x2ROWS of EQUAL SQUARE cells, read left to right then next row, no visible grid. Animate an enthusiastic right-facing strolling woman making LARGE SWINGING ARM gestures and one cheerful wave overhead. Frame1 normal wide walking stride and arms down. Frame2 leading arm reaches forward at chest height, opposite arm extends BACK behind hip, knees passing. Frame3 leading arm reaches diagonally UP at45degrees, other arm low behind, new heel steps forward. Frame4 leading hand waves ABOVE HER HEAD with bent elbow, other arm extends sideways, mid step. Frame5 raised hand leans forward in a wave, opposite arm still out, opposite knee lifted a little. Frame6 raised arm sweeps down to shoulder height forward, skirt swings. Frame7 arm swings DOWN behind body with opposite arm forward, feet passing. Frame8 relaxed walking stride returning to frame1. Arm silhouette MUST change dramatically and hands must be visibly at very different heights, never8identical figures. Preserve same clothing/identity/body scale, fixed ground baseline at90% cell height, standing head at30%down leaving plenty of clear room for a raised hand. All hands/head/shoes and sleeves inside each cell with transparent padding. Flat original Korean risograph cyan/magenta/yellow/green/indigo overprint and fine ink grain. GENUINELY transparent background, no scenery, floor, paper, shadows,文字, letters, labels, numbers, borders or watermark. Ideal2048x1024canvas,512squarecells.
```


## 검증과 남은 확인

- min macOS14 대상 네이티브 리뷰 컴파일 및59 Release universal 통과.
- `.tmp/dancheong-refine59/asset-audit.log`: 각8자세는 서로 다른 바이트이며 충분한 투명 여백이 있고 인물의 손·발이 셀 안에 들어온다.1774×887의 비정수 분할 가장자리도 포함했다.
- CUA 실제3번화면의 `동작확인_A.jpg`에서는 가운데 사람이 뛰는 자세와 오른쪽 팔 들기, B에서는 멈춘 첫 자세를 확인했다. 그림 전체가 이동하는 방식이 아니다.1~5페이지 배치 확인/캡처 완료. 리뷰에서도 동작 활성화.
- 시스템 동작 줄이기 상태의 실제 확인과59설치본 실기는 남았다. 환경 값을 임의로 바꾸거나 검증을 했다고 주장하지 않는다.
- 이전4자세 PNG는 보존했지만 현재 코드에서는 참조하지 않는다. 새3개 파일이 배포 ZIP에 바이트 동일하게 들어간다.

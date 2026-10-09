# 페이지별 고정 그림과 인물의 생동감 — 빌드62

기준일: 2026-10-09. 테스트 후보. 기준 코드의 공유 뷰를 컴파일한 검토 앱으로 확인한다.

## 최종 요청과 적용

- 사용자 승인: 다섯 페이지에 서로 다른 고정 자세 한 장씩, 페이지를 넘길 때만 바뀌는 방식. 같은 페이지 안에서 반복하거나 첫 자세로 돌아오지 않는다. 타이머·TimelineView·인물용task/animatePeople 플래그를 제거했다. `Sources/OnboardingRiso.swift::OnboardingPeopleSequence`가 페이지 번호로 직접 그림을 선택한다.
- 왼쪽과 가운데는61의0~4자세를 유지한다. 맨 오른쪽 여자만 새롭게, 준비→무릎 들기→발차기→도약→한 발 착지로 실루엣을 바꿨다.1번과5번이 다르며 각 페이지에서는 해당 자세로 정지한다.풍경은 같은 좌표이고 세 인물만 페이지당4pt 전진한다.
- `Resources/Onboarding/DancheongPersonDance.png`:1536×1024,3열2행 중 앞5셀. 마지막은 빈 투명 셀이다. 같은 팔의 연속성·소매/손목 연결을 고려했고 몸통/치마/다리도 바뀐다. 이전Greeting/Wave 원본은 덮어쓰지 않았다.
- 색동은24→18pt(−25%) 이후 다시18→12.6pt(−30%)로 줄였다.각폭8pt/겹침1pt/총폭29pt는 유지.윗선offset−6.3pt.
- 3·4번의 ‘입력칸으로 이동’ 버튼을 제거했다.텍스트 입력은 기존NSTextView 클릭으로 가능하다.하늘키보드가 아직 선택되지 않았을 때의 ‘하늘키보드 선택’ 버튼은 기능상 필요해 유지한다.선택 성공 뒤 포커스/비우기 콜백은 기존대로다.
- 새Main 아이콘과 원본 두 파일 이동/보존은 [61의 기록](dancheong-five-poses-61-2026-10-09.md)을 따른다.최종 정본은 `Resources/Brand/HaneulKeyboard-Main.png`이고 sub도 같은 폴더에 남아 있다.새AppIcon.icns/안내아이콘/원형3pt여백 모두62에 포함한다.

## 내장 imagegen 생성 프롬프트

참조: `Resources/Onboarding/DancheongPersonGreeting.png`. `transparent_background:true`. 반환본을 위 프로젝트 경로로 복사했다. 최종 생성 경로: `~/.codex/generated_images/01a10eeb-82a1-7091-8ee8-fc3afc825ed3/exec-a8edc722-5b30-4653-b655-c50cd420c539.png`.

```text
Use case: style-transfer. Asset type: FIVE bold energetic full-body poses for five static onboarding pages. REFERENCE identity/style: attached Korean risograph woman with magenta jeogori, white cuffs, green-yellow full hanbok skirt, indigo hair bun, blue shoes. Completely REDESIGN BODY POSES with joyful dance/skip energy; NOT five ordinary walking figures raising one hand. Keep identity, rightward direction, same costume and flat risograph print/pinhole texture. Exactly FIVE figures, THREE COLUMNS x TWO ROWS equal square cells, final bottom-right cell EMPTY transparent; 1536x1024. Keep scale consistent, place all body/hand/foot pixels at least35px inside their own512px cell; no boundary crossing. Pose1 lively anticipation: weight on back leg, front knee soft, torso slightly forward, both elbows naturally bent ready to spring. Pose2 playful high-knee skipping step: front knee lifted and opposite bent arm swings up, skirt lifts/flutters to show blue shoe. Pose3 joyous little side kick: front leg extends diagonally forward, torso leans slightly back, arms counterbalance broadly at different heights, flowing skirt billows. Pose4 clearly AIRBORNE small leap: BOTH feet off ground, knees softly tucked, skirt flares wide, arms spread upward into a relaxed open V, happy slight turn toward viewer. Pose5 distinct celebratory landing: one foot planted, other leg bent behind with heel lifted, body tilted forward in playful balance, one hand raised overhead and other arm open diagonally outward, swishing skirt. Each pose must have a clearly DIFFERENT silhouette even at48px tall, not just a translated or rotated same body. Physical anatomy: exactly2legs/2arms/2hands; continuously attached shoulders/elbows/wrists; natural opposing limb balance; NO dislocated joints/backward wrists/extra fingers. Hands simple graceful grouped-finger silhouettes with one thumb, small relative to body. Preserve dignified playful traditional hanbok character, no cartoon exaggeration or huge face. Transparent CUTOUT figures only: NO landscape, sun, floor, shadows, glow, blur, colored halo, lettering, numbers, gridlines or extra objects.
```


## 확인 근거

`.tmp/dancheong-refine62/`의review-build/asset-audit/icon-audit/package-final.log와artifact.json.인물15자세는상이/투명/셀내팔다리,새앱ICNS1024픽셀은Main정본과일치,Main/sub해시는이동전후동일하다.62검토앱CUA실행과1페이지AX확인.61페이지별방식은사용자가승인했다.62전체스크린샷및설치본검증은아직없다.티켓OPEN,Git커밋/머지/푸시/태그없음.

# 단청 리소그래프 자산 생성 기록

기준일: 2026-10-09. 생성 도구: Codex **내장 imagegen**. 사용자 확정 원본 `HaneulKeyboard_main.png`를 네 번 모두 참조했다. 최종 UI나 문자를 이미지에 굽지 않고, 아래 네 장식만 생성했다.

- `Resources/Onboarding/DancheongPaper.png`: 1254×1254, 불투명 종이
- `Resources/Onboarding/DancheongEaves.png`: 2172×724, 투명 처마
- `Resources/Onboarding/DancheongWalkers.png`: 2172×724, 투명 한복 인물·산·나무
- `Resources/Onboarding/DancheongKnot.png`: 1254×1254, 투명 매듭. 빌드58부터 화면에서 사용하지 않는다.
- `Resources/Onboarding/HaneulBrandIcon.png`: 사용자 원본의 바이트 동일 복사. 생성/수정하지 않았다.
- `Resources/AppIcon.icns`: 위 원본을 sips/iconutil로 표준 아이콘 크기에 패키징. 그림 재생성 없음.

그림의 검정으로 보이는 바깥 영역은 투명 알파다. 이전 빌드 56의 종이/구름 자산은 보존했지만 현재 1~5단계에서는 참조하지 않는다. 제목/본문/버튼은 SwiftUI·AppKit이며 고운바탕/나눔펜의 OFL은 기존 번들에 유지한다.

빌드58은 배경/인물을 분리한2개 자산을 추가했다. 원본·생성프롬프트·규격은 [걷기 자산 기록](dancheong-walk-cycle-2026-10-09.md)에 남겼다. 기존 원본그림은 덮어쓰지 않았다.

## paper

투명 배경: false

Use case: style-transfer. Production raster asset for HaneulKeyboard macOS onboarding. Attached image is the FINAL approved brand reference. Match its Korean risograph printed aesthetic, vivid flat cyan #0396FB, pink #FA109C, yellow #FCDC0C with indigo #2120A2, green #08A866 and orange #FB6F21 only where print layers overlap. Fine ink pinholes 0.5–1.5 pixels at 1024 reference width, 2–5% coverage; halftone dots 1.5–3px spaced3–5px; consistent small 4–8px plate offsets. No gloss, no emboss, no extruded shadows, no watercolor, no coarse long fibers, no artificial multi-color outline around everything. No app UI, no words, no lettering, no logo. Extract/recreate ONLY the fine warm ivory uncoated paper surface, no artwork at all. Flat evenly illuminated front-facing print scan, base RGB247,242,229 #F7F2E5. Gentle dense irregular grain with tiny 1–4px features, brightness variation only about4–6/255, very short faint fibers. Must read as softly tactile clean fine paper, NOT gray, NOT oatmeal, NOT rough recycled cardboard, no long fibers or big lumps. Edge-to-edge seamless-feeling quiet warm paper, absolutely no roof, people, marks, borders or objects. Square1024x1024.

## eaves

투명 배경: true

Use case: style-transfer. Production raster asset for HaneulKeyboard macOS onboarding. Attached image is the FINAL approved brand reference. Match its Korean risograph printed aesthetic, vivid flat cyan #0396FB, pink #FA109C, yellow #FCDC0C with indigo #2120A2, green #08A866 and orange #FB6F21 only where print layers overlap. Fine ink pinholes 0.5–1.5 pixels at 1024 reference width, 2–5% coverage; halftone dots 1.5–3px spaced3–5px; consistent small 4–8px plate offsets. No gloss, no emboss, no extruded shadows, no watercolor, no coarse long fibers, no artificial multi-color outline around everything. No app UI, no words, no lettering, no logo. Isolate/reimagine just the beautiful Korean dancheong roof eaves from the reference as a single wide horizontal decorative strip on genuinely transparent background. Upturned right roof end, repeating indigo blue roof tiles with white/cyan round tile ends, vivid layered pink/cyan/yellow and green flower-painted bracket details beneath. Roof's full isolated silhouette fits inside a wide3:1 canvas with small transparent margin. No building walls, no scenery, no paper rectangle, no text. Print colors retain irregular fine halftone texture and transparent overprints, crisp silhouette.

## walkers

투명 배경: true

Use case: style-transfer. Production raster asset for HaneulKeyboard macOS onboarding. Attached image is the FINAL approved brand reference. Match its Korean risograph printed aesthetic, vivid flat cyan #0396FB, pink #FA109C, yellow #FCDC0C with indigo #2120A2, green #08A866 and orange #FB6F21 only where print layers overlap. Fine ink pinholes 0.5–1.5 pixels at 1024 reference width, 2–5% coverage; halftone dots 1.5–3px spaced3–5px; consistent small 4–8px plate offsets. No gloss, no emboss, no extruded shadows, no watercolor, no coarse long fibers, no artificial multi-color outline around everything. No app UI, no words, no lettering, no logo. Isolate/reimagine the LOWER horizontal scene from the reference: exactly three small stylized people in flowing Korean hanbok walking to the right across a narrow path, with tiny patterned indigo/cyan mountains, a yellow sun, low green/cyan flowering trees at the far edges. Pink/cyan/yellow clothing with overlapped green/orange/indigo. Make a wide flat elegant print vignette, airy tiny ground flecks, group fills a wide3:1 canvas. Genuinely transparent background around figures/landscape, not a paper rectangle. No roof, no characters/letters. Preserve reference's simple flat human silhouettes, no detailed faces.

## knot

투명 배경: true

Use case: style-transfer. Production raster asset for HaneulKeyboard macOS onboarding. Attached image is the FINAL approved brand reference. Match its Korean risograph printed aesthetic, vivid flat cyan #0396FB, pink #FA109C, yellow #FCDC0C with indigo #2120A2, green #08A866 and orange #FB6F21 only where print layers overlap. Fine ink pinholes 0.5–1.5 pixels at 1024 reference width, 2–5% coverage; halftone dots 1.5–3px spaced3–5px; consistent small 4–8px plate offsets. No gloss, no emboss, no extruded shadows, no watercolor, no coarse long fibers, no artificial multi-color outline around everything. No app UI, no words, no lettering, no logo. Isolate/reimagine just the multicolored interlocking Korean decorative knot symbol from upper-right of reference. A single flat simple symmetrical interwoven ribbon-knot emblem formed from cyan, magenta/pink and yellow ink strips whose overlaps create green orange and indigo. Slight authentic ink misregistration and tiny pinholes. The white negative spaces inside must be fully transparent, also the outside must be fully transparent alpha. Centered one motif filling75% of square canvas. No roof/people/clouds/letters, no shadows, no embossing, no paper background. Looks like a colorful printed Korean seal, not a 3D object.

# 어휘 범주와 확장 순서

기준일: **2026-10-09**, 개발 빌드67, #84. 아래 수치는 해당 날짜 작업 트리의 원본에서 산출했다. 설치본 적용 여부와 분리한다.

## 서로 다른 두 사전

1. **기존 영타 자동 변환**: 한글 모드에서 영문 키를 치고 Space로 확정했을 때 잘못된 자판 입력을 복원한다. 일반 영어·고유명사 등 여러 참조 목록과 한국어 보호 규칙을 함께 사용한다.
2. **등록 한글 표기 → 영문**: 레스토랑→restaurant, 축구→football처럼 검토한 대응을 단축키로 호출한다. 1,903개 한글 표기 → 1,880개 영문 결과. 미등록 단어의 뜻을 추론하지 않는다.

따라서 기존 영문 참조 목록에 football이 있어도 축구→football이라는 한글 대응은 별도 등록해야 한다. 이 두 목록의 수를 합쳐 ‘지원 단어 수’로 세지 않는다.

## 기존 자동 변환 사전의 분야

`dict_work/dict_manifest.tsv`와 `Resources/IM/english_supplement.txt`의 구획을 확인했다. 일반 영어, 현대 영어, 인명·지명뿐 아니라 다음 보충 분야가 있다.

- 브랜드·소비자 IT·PC 부품·통신·가전·반도체
- AI·개발자 용어·게임 산업·게임 타이틀·캐릭터
- 스포츠·선수 이름·도시·지역
- 자동차·로보틱스·드론
- 금융·크립토·마케팅·광고·이커머스·직장 용어
- 의료·바이오·헬스케어·교육·시험·학술
- 여행·항공·호텔·숙박
- 음악·K-pop·엔터테인먼트·방송·콘텐츠
- 헬스·피트니스·식단·카페·식음료
- 아트·디자인·UX·타이포그래피·사진·촬영 장비·영상 후반작업

기존 TXT 목록은 단어마다 분야 태그를 갖고 있지 않아 이 분야별 정확한 개수를 추측하지 않는다. 실제 파일별 참조 항목 수(런타임 로더와 같은 소문자 시작 ASCII 알파벳 3자 이상 필터)는 다음과 같다.

| 파일 | 고유 참조 항목 |
|---|---:|
| `english_common.txt` | 2,786 |
| `english_modern.txt` | 71,348 |
| `english_names.txt` | 28,378 |
| `english_names_extra.txt` | 53 |
| `english_sports_geo.txt` | 28,360 |
| `english_supplement.txt` | 5,286 |

여섯 번들 파일의 중복 제거 합계는 **130,211개**다. macOS `/usr/share/dict/words`, 코드의 짧은 약어/단위/숫자 목록은 이 수에 넣지 않았다. 참조 목록에 있는 모든 항목이 무조건 변환되는 것은 아니며 한국어 충돌·문맥 규칙에 따른다.

## 새 대응 사전의 분류

기존1,478개에 분야 확장425개가 남아 **현재1,903개**다. 사용자 결정으로 직전 확장의 인물76명·음악 그룹4개를 제외했다. 유지한 추가량은 애니메이션64·영화111·생활1·금융193·브랜드38·제작 도구18개다. 인물 항목을 제외한 입력·출력·분류와 번호 정책은 유지한다. 여러 분야에 쓰이는 항목도 한 대표 범주에서만 센다.

| 대분류 | 하위 범주 | 표기 수 |
|---|---|---:|
| 생활·음식·여행 | 생활 일반 | 10 |
| 생활·음식·여행 | 음식·식재료 | 114 |
| 생활·음식·여행 | 음료·카페 | 48 |
| 생활·음식·여행 | 여행·숙박 | 54 |
| 생활·음식·여행 | 의류·생활·업무 | 98 |
| 컴퓨터·소프트웨어 | 컴퓨터·앱 일반 | 27 |
| 컴퓨터·소프트웨어 | 하드웨어·네트워크 | 65 |
| 컴퓨터·소프트웨어 | 개발·데이터 | 97 |
| 컴퓨터·소프트웨어 | AI·학습·추론 | 47 |
| 아트·영상·사운드 | 아트 장르·표현 | 44 |
| 아트·영상·사운드 | 인쇄·타이포그래피 | 41 |
| 아트·영상·사운드 | 촬영·조명 | 53 |
| 아트·영상·사운드 | 편집·색보정 | 61 |
| 아트·영상·사운드 | 시각효과·3D | 80 |
| 아트·영상·사운드 | 사운드·음악 | 62 |
| 아트·영상·사운드 | 디자인·UI | 45 |
| 아트·영상·사운드 | 애니메이션 제작 | 65 |
| 아트·영상·사운드 | 영화·제작·장르 | 111 |
| 브랜드 | 기술·미디어·생활 | 43 |
| 브랜드 | 스포츠·아웃도어 | 34 |
| 브랜드 | 자전거·모터사이클 | 37 |
| 브랜드 | 플랫폼·협업 | 18 |
| 브랜드 | 영화·애니메이션 제작사 | 10 |
| 브랜드 | 금융·결제·정보 | 11 |
| 제품·앱 | 제품·앱 일반 | 40 |
| 제품·앱 | 영상·애니메이션·음악 도구 | 18 |
| 스포츠 | 스포츠 공통 | 26 |
| 스포츠 | 축구 | 24 |
| 스포츠 | 야구 | 26 |
| 스포츠 | 농구 | 18 |
| 스포츠 | 미식축구 | 14 |
| 스포츠 | 라켓·배구 | 18 |
| 스포츠 | 수상·겨울 | 23 |
| 스포츠 | 피트니스·아웃도어·기타 종목 | 41 |
| 라이딩·이동수단 | 자전거·라이딩 | 42 |
| 라이딩·이동수단 | 모터사이클·교통 | 34 |
| 확인된 휴대폰 번호 별칭 | 확인된 세대 번호 | 29 |
| 예약 휴대폰 번호 별칭 | 미발표 예약 번호 | 6 |
| 게임 | 장르 | 25 |
| 게임 | 플레이·그래픽 | 51 |
| 금융·경제 | 은행·결제·보험 | 39 |
| 금융·경제 | 투자·증권 | 74 |
| 금융·경제 | 경제·회계·세금 | 53 |
| 금융·경제 | 디지털 자산 | 27 |
| 합계 | 고유 한글 입력 | **1,903** |

## 고정한 대응과 충돌 처리

- 사용자 결정으로 인명·음악 그룹명은 이번 한글→영문 대응 사전에서 제외했다. 관련 분류와 출처 메타데이터도 제거했다. 기존 영타 자동 변환의 인명 참조 목록은 별개이며 유지한다.

- **선물→gift**는 문맥과 관계없는 사용자 지정이다. 선물거래→futures trading, 선물계약→futures contract, 선물시장→futures market으로 금융 의미를 구별한다.
- 메시→mesh, 줌→zoom, 지수→index는 전문·일반 용어로 유지한다. 줌워크플레이스→Zoom Workplace도 유지한다. 기존 라이카→Leica도 유지하며 제작사는 라이카스튜디오→LAIKA로 등록했다.

- 축구/풋볼→football. soccer로 바꾸지 않는다. 미식축구→american football.
- 야구/베이스볼→baseball, 농구/바스켓볼→basketball. 같은 출력의 별칭도 실제 입력한 한글로 되돌린다.
- 라이더→rider, 라이딩→riding, 스포츠→sports, 아메리칸→american.
- 시각효과/브이에프엑스→VFX. 색보정/컬러그레이딩→color grading, 색교정/컬러커렉션→color correction. 폴리→foley, 케닝→kerning, 리깅→rigging, 프록시→proxy.
- 쿨다운→cool-down은 게임 분야에서 다시 등장해도 기존 출력을 덮어쓰지 않는다. 모드처럼 mode/mod가 갈리는 후보는 모딩→modding, 게임모드→game mode로 구체화했다.
- 일반 Space에서 축구를 football로 번역하지 않는다. 등록 단축키에서만 바꾼다.
- 의류 코트→coat가 먼저 등록되어 있으므로 court로 덮어쓰지 않는다. 펑크는 음악 punk와 타이어 puncture가 갈리므로 단독 표기를 추가하지 않고 타이어펑크→puncture로 한정했다.
- 타임은 time/thyme가 갈려 보류했다. 카디건·캐러멜은 해당 입력 표기만 등록했다.
- 아무 한글이나 번역하거나 종목별로 문맥을 판단하지 않는다. 조사/띄어쓰기/오타를 지워 맞추지도 않는다.
- 아포스트로피·비ASCII 영문 표기가 필요한 추가 브랜드는 표기와 출력 제한을 별도 검토한다. 수량을 늘리려고 브랜드 철자를 임의로 변형하지 않는다.

## 이번 확장 예시

| 분야 | 등록한 예시 |
|---|---|
| 아트·인쇄·타이포 | 초현실주의→surrealism, 아르데코→art deco, 케닝→kerning, 망점→halftone |
| 촬영·편집·색보정 | 셔터앵글→shutter angle, 화이트밸런스→white balance, 프록시→proxy, 컬러그레이딩→color grading |
| 시각효과·3D | 시각효과→VFX, 리깅→rigging, 셰이더→shader, 서브서피스스캐터링→subsurface scattering |
| 사운드 | 폴리→foley, 룸톤→room tone, 라우드니스→loudness, 노이즈리덕션→noise reduction |
| 음식·여행·생활 | 베이글→bagel, 아메리카노→americano, 기내수하물→carry-on baggage, 스케줄→schedule |
| 컴퓨터·개발·AI | 와이파이→Wi-Fi, 풀리퀘스트→pull request, 파인튜닝→fine-tuning, 인공지능→AI |
| 게임 | 로그라이크→roguelike, 로그라이트→roguelite, 협동플레이→co-op, 레이트레이싱→ray tracing |
| 애니메이션 | 애니메이션→animation, 스톱모션→stop-motion, 워크사이클→walk cycle, 예비동작→anticipation |
| 영화 | 영화→movie, 촬영감독→director of photography, 시놉시스→synopsis, 쿠키영상→post-credits scene |
| 플랫폼·제작 도구 | 디스코드→Discord, 드림웍스→DreamWorks, 마야→Maya, 누크→Nuke |
| 금융·경제 | 주식→stock, 채권→bond, 인플레이션→inflation, 선물거래→futures trading |

## 이후 확장 후보 (이번에 추가하지 않음)

- 스포츠의 골프·격투·육상·라켓 분야 세부 용어, 구단명(인물 이름 제외).
- 분야별 브랜드·제품의 공식 한글/영문 대응. 숫자 모델은 기존 출시 근거와 예약 정책을 따로 검토한다.
- 입력에 띄어쓰기가 있는 구와 문맥에 따라 영문이 갈리는 표현은 별도 설계가 필요하다. 현재는 등록된 붙여 쓴 한글 전체에만 대응한다.

임의의 목표 숫자를 맞추기 위해 조사형·오타·모든 모델 조합을 증식하지 않는다. 고유 한글 입력 수, 고유 영문 결과 수, 새로 추가한 수를 각각 보고한다. 이번 작업은 루트 Codex의 자체 검토이며 외부 사전 목록을 일괄 가져온 작업이 아니다.

## 용어 참고

2026-10-09 확인. 아래 자료는 용어·영문 표기를 확인하는 데 참고했다. 자료의 설명문이나 사전 데이터베이스를 복제하지 않고 한글→영문 대응을 직접 작성했다. 모든 한글 표기가 공식 표준어로 인증되었다는 뜻은 아니다.

- [Adobe: VFX compositing](https://www.adobe.com/creativecloud/video/hub/guides/what-is-vfx-compositing.html): visual effects의 약어 VFX, 합성 분야의 표현.
- [Adobe: 글자 간격 조정](https://www.adobe.com/au/learn/indesign/web/adjust-letter-spacing): kerning, tracking, leading 구분.
- [Adobe: 색보정 개요](https://helpx.adobe.com/uk/premiere/desktop/correct-color/color-correction-fundamentals/about-color-grading.html): color grading 표기.
- [Blender: Retopology](https://docs.blender.org/manual/en/4.4/modeling/meshes/retopology.html), [Shader](https://docs.blender.org/manual/en/3.6/render/shader_nodes/shader/index.html): 3D 용어 표기.
- [스코틀랜드 국립미술관: Decalcomania](https://www.nationalgalleries.org/art-and-artists/glossary-terms/decalcomania): 데칼코마니.
- [Zentangle 공식 안내](https://zentangle.com/pages/learn): Zentangle 고유명 표기.
- 이전 스포츠·브랜드 참고: [Trek](https://www.trekbikes.com/us/en_US/), [Shimano](https://www.shimano.com/en/), [World Rugby](https://www.world.rugby/the-game/beginners-guide/positions).

- [Disney Animation: Animation](https://www.disneyanimation.com/process/animation/), [Hand Drawn Animation](https://www.disneyanimation.com/process/hand-drawn-animation/): 애니메이션 제작 용어.
- [CME 용어집](https://www.cmegroup.com/education/glossary), [Investor.gov 용어집](https://www.investor.gov/introduction-investing/investing-basics/glossary): 금융·투자 용어. 선물→gift는 이 자료에서 유추한 것이 아니라 사용자 지정이다.
- [Discord 브랜드](https://discord.com/branding), [Atlassian 제품](https://www.atlassian.com/software), [Toon Boom Harmony](https://www.toonboom.com/products/harmony): 플랫폼·도구 표기.

근거: `Resources/IM/phonetic_dictionary.json`, `scripts/audit_phonetic_dictionary.py`, [스포츠 등 319개 TSV](../dict_work/2026-10-09-phonetic-expansion.tsv), [이전 801개 TSV](../dict_work/2026-10-09-phonetic-creative-everyday-computing.tsv), [분야 확장425개 TSV](../dict_work/2026-10-09-phonetic-animation-film-finance.tsv), [기능 명세](phonetic-conversion.md).

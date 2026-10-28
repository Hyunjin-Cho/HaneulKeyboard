# 어휘 범주와 확장 순서

## 2026-10-28 등록 한글→영문 기본 명사 추가

기준 main `d2c451b` 이후 #100 소스: 기본 명사 860개 추가, **한글 4,554표기 / 고유 영문 4,339결과**다. 기존3,694객체와 숫자35별칭을 보존했다. 이 합계는 브랜드·전문용어·별칭도 포함하며 일반 명사만의 수량이 아니다. 학교→school·식당→restaurant·주방→kitchen·가게→store·친구→friend 등을 보강했다. [채택/출처](../dict_work/2026-10-28-phonetic-basic-nouns.tsv), [보류 이유](../dict_work/2026-10-28-phonetic-basic-nouns-held.tsv), [최신 기능 범위](phonetic-conversion.md). 자동 영타 사전이나 영어+조사 분리의 목록과 합산하지 않는다. 아래 이전 날짜는 당시 기록이다.


과거 기록 기준일: **2026-10-18**. 당시 HEAD `de12669` + `feat/T01-particle-rebuild` 미커밋 변경. 최신 등록 한글 사전과 이전 영타 참조 목록 이력을 구분한다. 실제 설치본89와 로컬 후보는 다르다.

## 2026-10-18 당시 — 후속 명사1,507개 추가

첫138개 보강에 이어 일반 명사1,507개를 더했다. 현재 **한글3,694개 / 고유 영문3,564개**, 기본3,659개+번호35개다. 기존2,187개 객체와 분류를 그대로 보존했다. 우리말샘의 품사·뜻 수 대조와 루트의 한영 쌍 검토를 거쳤으며 전체 명사 지원 완료는 아니다. [검토·출처·보류 상세](feedback/2026-10-18-build89/04-noun-expansion-review.md), [새 목록](../dict_work/2026-10-18-phonetic-reviewed-nouns.tsv), 원본 `Resources/IM/phonetic_dictionary.json`. 입력110,683/0·사전 감사·Release Universal 메인/IME 무서명 컴파일 통과. 사전 SHA `98966f22ab6b5a42e6475ac86c09de887544f70355c58b81215b0b6dc0c8db82`.

## 2026-10-14 당시 — 일반 명사62개 추가

사용자 승인으로 일반 명사66개를 검토해62개를 추가했다. 생활용품·장소·자연·동물·언어·명시 용량 표현이며 새 애매한 뜻/사람 지칭 가위·화장지·강아지·호랑이는 제외했다. 단어word·물water·책상desk·저장용량storage capacity를 지원하고 용량 단독은 추가하지 않는다. 기존1,987개 항목 객체를 보존해 **2,049개 한글 / 2,019개 영문 결과**, 기본2,014개+번호35개다. `everyday/nature`는새메타데이터분류이며제품카테고리enum·자동영타사전은변경하지않았다.

정본 [명사62개 대응·검증방식·공개 참고](../dict_work/2026-10-14-phonetic-common-nouns.tsv)와 [등록 사전](phonetic-conversion.md). 대응은직접작성/독립검토했고공식참고확인과자체작성동의어·긴표현을구분했다. 입력33,941/0·문맥215/0·슬래시553/0·독립NSTextView245/0. 일반Space번역·조사제거·인명추론없음. 최신사전SHA `fd357f774ffe1ff10767ffbc405bfa9719cfe54a3776f6590d804499f745ab6c`, `.tmp/nouns88-2026-10-14/dictionary-audit.json` 실측. 아래영타목록보완은다른사전의이력이며발음사전을변경하지않았다는문장은그작업범위기준이다.

## 2026-10-14 — 생명체·촬영·브랜드·개발 영문 참조 목록 보완

기존 [201개 대표 표본](../dict_work/2026-10-06-nature-film-coverage.txt)과 2026-10-06의 45개 보완을 실제 조합기로 다시 확인하고 모두 보존했다. 기존 기록을 전체 미구현으로 해석하지 않았다. 291개 조사 후보에서 이미 지원되는 항목을 제외한 뒤, 박물관·식물원·제조사의 직접 자료로 철자를 확인하여 초기 81개를 보완했다. #16 후속 대조에서 `lsp`·`fork` 두 항목을 추가하고, 완료 범위 대조에서 #74 본문에 남아 있던 카메라·현상·생활 브랜드 8개를 공식 제조사 자료로 확인해 **최종 91개 항목을 보완**했다. `jaboticaba`는 확인 자료에 있었지만 이미 시스템 사전으로 변환되어 중복 추가하지 않았다.

- `Resources/IM/english_names_extra.txt`: 새 이름·약어 **84개**. 전부 깨진 한글형이므로 broad 역할로만 등록했다. 초기 75개의 변경 전 코어 검역과 후속 `lsp`·#74 본문8개의 최신 코어 검역을 합친 기록은 Tier A/B=0, C=84이며 모두 한국어 표제어와 충돌하지 않았다.
- `Resources/IM/english_supplement.txt`: 기존 broad 목록이나 시스템 사전에만 있던 생물 이름 6개와 `fork`, 총 **7개**를 curated에 추가했다. angelfish·cockatiel·coral·eland·guanaco·turtle·fork의 완성 한글형을 각각 검토했으며 전체 한국어 표제어와 충돌하지 않았다. 검역의 Tier A=7은 무맥락 변환이 새로 생긴다는 뜻이며, 경고를 없애거나 veto를 우회했다는 뜻은 아니다. coral의 `책미`·eland의 `디뭉`·fork의 `래가`는 각각 `책`·`디`·`래`에 대한 어근 경고도 기록하고 검토했다.

후속 두 항목은 [Microsoft LSP 공식 설명](https://microsoft.github.io/language-server-protocol/)과 [GitHub Forks 공식 설명](https://docs.github.com/en/pull-requests/reference/forks)에서 철자를 확인했다. `lsp`는 `ㅣ네`로 조합되며 미등재였고, `fork`는 `래가`로 조합되며 broad만으로는 변환되지 않았다. `래` 어근 경고는 보존하고 `래가` 전체의 표제어 미등재를 기록했다. `노래가`·`오래가`의 전체 원문과 `www`의 반복 자모 보호도 별도 회귀로 확인했다. 사전 보완으로 조사나 단어의 일부를 잘라 바꾸지 않으며, 한국어 veto·짧은 단어·반복키의 예외를 추가하지 않았다.

| 확인한 분야 | 보완 항목 | 예시 |
|---|---:|---|
| 생물·식물·과일·멸종 파충류 | 52 | quokka, clownfish, haworthia, salak, parasaurolophus |
| 카메라·촬영 장비·광학 용어 | 19 | Tilta, Viltrox, Atomos, Contax, Summicron, microcontrast |
| 필름·필름 제조사·현상 | 10 | Kentmere, ULTRAMAX, Ferrania, remjet, Filmomat |
| 생활·오디오 브랜드 | 8 | Spigen, Audioengine, ZWILLING, LeCreuset, LocknLock |
| 개발·코드 협업 | 2 | LSP, fork |

#74 본문의 `contax`, `summicron`, `remjet`, `microcontrast`, `filmomat`, `zwilling`, `lecreuset`, `locknlock`도 최신 조합기로 확인해 broad에만 추가했다. 여덟 한글형은 모두 깨진 자모를 포함하고 한국어 전체 표제어와 충돌하지 않았으며, 단독·`the`·`want` 문맥에서 변환된다. [ZEISS 역사](https://www.zeiss.com/corporate/en/about-zeiss/past/history/technological-milestones/camera-and-cine-lenses.html), [Leica 렌즈 이름](https://leica-camera.com/en-US/photography/understanding-leica-lenses), [Kodak 용어집](https://www.kodak.com/en/motion/page/glossary-of-motion-picture-terms/), [ZEISS 광학 설명](https://www.zeiss.com/photonics-and-optics/us/photography/products/lenses-for-videography/otus-ml-lenses.html), [Filmomat](https://www.filmomat.eu/), [ZWILLING](https://www.zwilling.com/us/knives/), [Le Creuset](https://www.lecreuset.com/stores), [LocknLock](https://www.locknlock.com/eng)에서 철자를 확인했다. 공식 페이지 제목의 `LeCreuset`와 본문의 `Le Creuset`를 함께 기록하며, 사용자 지정 `lecreuset`만 정확히 등록했다. 공백을 제거해 모든 브랜드를 합성하는 규칙은 만들지 않았다. `silverfast`는 새 정확 복합어 기능이 켜져 있으면 `silver`+`fast`로 이미 변환되어 중복 등록하지 않았다. 정확 복합어 설정 OFF에서는 그 경로가 동작하지 않으며, 명시 사전 역할과 구분한다.

공룡 17개와 다른 멸종 파충류 3개를 기록에서 구분했다. `Mosasaurus`·`Plesiosaurus`·`Quetzalcoatlus`를 공룡으로 묶지 않았다. 박물관에 기록된 이름 철자를 확인한 작업이며 모든 이름이 최신 분류의 유효명이라는 보증은 아니다. 회사·필름 이름 등록도 현재 판매나 재고를 보증하지 않는다. 출력은 사용자가 실제 친 ASCII 철자와 대소문자를 유지한다.

숫자·공백·하이픈을 제거하거나 다른 문자로 바꾼 `sevenartisans`, `redpanda`, `panf`, `trix` 같은 임의 표기를 넣지 않았다. HP5·FP4·XP2·TRI-X는 알파벳 TXT 로더의 범위 밖이며 기존 별도 숫자 이름 기능을 임의로 넓히지 않았다. 전부 자모가 되는 `bergger`도 신규 broad 기본 제외 정책을 유지했다. 공식 원문 확인이 남은 이름 등 **19개 후보의 제외·보류 이유**는 기록에 남겼다. `aplle`·`applle` 같은 오타를 새 단어로 등록하거나 고치지 않았다.

검증은 실제 `KoreanComposer`·`EnglishDetector`·`PersonalDictionary`를 사용하는 [독립 어휘 테스트](../Tests/VocabularyExtensionTests.swift)로 수행했다. **변경 전 코어와 최신 입력 코어에서 각각 2,632 통과, 0 실패**다. 최종 91개 활성 확정, 자동 변환 OFF, 수동 경계, 원문 되돌림, 개인 금지 우선, #74 본문8개의 단독·영어 문맥 변환과 한국어 veto 보호, 기존 201개 표본과 한국어·반복키·얼굴 자모 보호, 미등록 오타 `aplle`·`applle`의 미변환을 확인했다. 전체 IME 검사도 변경 전/후 각각 **25,281 통과, 0 실패**다. `ㅡㅁㅡ` 같은 분리 자모는 순차 타이핑에서 재조합될 수 있으므로 화면에 조합된 원문과 변환 후를 비교하고 판정기의 분리 자모 보호도 별도로 확인한다. 이 검사는 실제 앱 이벤트·실기 설치 확인을 대신하지 않는다.

- 실행: `python3 Tests/run_vocabulary_extension_tests.py`.
- [철자·공식 출처·역할·판정·제외 기록](../dict_work/2026-10-14-nature-camera-extension.tsv), [추가 91개 표본](../dict_work/2026-10-14-nature-camera-coverage.txt).
- [broad 검역](../dict_work/2026-10-14-nature-camera-broad-audit.csv), [curated 검역](../dict_work/2026-10-14-nature-camera-curated-audit.csv).
- [현재 코어 도달성 결과](../dict_work/2026-10-14-nature-camera-after.csv): 91개 모두 무맥락 변환에 도달, 미도달/검사 불가 0개.
- 후보 검역은 해당 전체 단어와 명시한 도달성 목록의 변화만 측정한다. curated 구성 단어 추가로 생기는 모든 다른 붙여쓰기 조합을 전수 검역했다는 뜻은 아니다. 복합어 정책·한글/개인 금지·모호한 분해의 검증은 `Tests/InputInferenceTests.swift`에 있고, 특정 조합의 변화는 `audit_wordlist.sh --reachability ... --compound on|off`로 별도 비교한다.
- [코어/자원 SHA와 실행 결과](../.tmp/goal86-2026-10-14/vocabulary/test-current-core/vocabulary-tests.json). 이전 코어 결과는 같은 폴더의 `test-baseline-core`에 분리했다.

이는 선별한 표본의 누락 보완이며 세계 전체 생명체·브랜드·장비 이름의 수록 완료가 아니다. 한글 이름을 영어로 번역하는 발음 사전은 이번에 변경하지 않았다. 실제 배포 빌드의 자원 포함과 설치 입력 확인은 남아 있다.

현재 여섯 번들 파일의 로더 기준 중복 제거 참조 항목은 **130,300개**다. `english_names_extra.txt`는 53→137개, `english_supplement.txt`는 5,286→5,293개이며 나머지 네 파일은 보존했다. 단어별 사전 역할이 바뀐 91항목과 고유 참조 항목의 증가 89개는 서로 다른 수치다. macOS `/usr/share/dict/words`·코드 약어/단위/숫자 목록은 이 번들 합계에 넣지 않는다.

## 2026-10-10 확장 이력 — 과일·과학·현물·외형

`dict_work/2026-10-10-phonetic-fruit-science.tsv`의 직접 작성한 대응을 원본 JSON과 대조하여 **84개** 추가했다. 기존1,903개는 전부 보존했다. 총1,987개 한글 →1,962개 영문 결과이며, 최신 전체 수량/분류는 `scripts/audit_phonetic_dictionary.py` 출력이 정본이다.

| 추가 분야 | 새 한글 표기 | 예시 |
|---|---:|---|
| 과일 | 16 | 사과→apple, 딸기→strawberry, 포도→grape, 수박→watermelon |
| 과학·수학 | 64 | 알파→alpha, 원자→atom, 분자→molecule, 행렬→matrix |
| 금융 | 1 | 현물→spot(사용자 지정) |
| 외형·디자인 | 3 | 솔리드→solid, 글래스/글라스→glass |

알파·베타·감마는 그리스 문자 이름이며 수학·물리의 기호나 소프트웨어 버전 이름 등에도 쓰인다. 기존 beta/gamma/lambda 및 파이→pie·시그마→Sigma를 덮어쓰지 않았다. 이 단축키 사전에는 파이상수→pi·시그마기호→sigma를 구분해 등록했다. 일반 Space 자동 영타 기능의 목록은 변경하지 않았다.

아래 표/수량은 **2026-10-09 빌드67 기준의 보존 기록**이다. 이후 발음 사전 변화는 [빌드69 피드백](releases/2026.9-build69-feedback.md), 2026-10-14 영문 참조 목록 변화는 위 최신 보완 기록을 따른다.

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

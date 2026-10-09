# 아트·디자인 용어 보완

기준일: **2026-10-08** · 기준 코드 `cdd26cd` + 로컬 변경 · 2026.9(55) 테스트 후보.

## 범위와 결과

미술 사조·인쇄·타이포그래피·콜라주·디지털 표현·모션 분야의 대표 영어 토큰 202개를 골라 실제 제품 조합기와 판정기에 통과시켰다. 소문자 단독 입력의 자동 변환은 **162 → 201개**다. `english_supplement.txt`에 미도달 40개 중 **39개**를 추가했다. 기존 영어 판정 규칙과 한국어 사전 우회 목록은 바꾸지 않았다.

| 분야 | 표본 | 이전 | 이후 |
|---|---:|---:|---:|
| 미술 사조·디자인 흐름 | 30 | 22 | 30 |
| 인쇄·판화·종이 표현 | 35 | 26 | 35 |
| 타이포그래피·편집 | 33 | 25 | 32 |
| 드로잉·콜라주·재료 | 35 | 31 | 35 |
| 디지털 아트·UI 표현 | 39 | 32 | 39 |
| 영상·모션·시각 구성 | 30 | 26 | 30 |
| 합계 | 202 | 162 | 201 |

`surrealism`은 기존에 변환됐다. `risograph`, `ransomizer`는 없어서 이번에 추가했다. 이 표는 선정한 표본의 결과이며 분야 전체의 수록률이 아니다. 자동 변환 ON, 개인 사전 없음, macOS 시스템 영어 사전과 번들 사전 사용 조건이다. 설치본 키 이벤트 실기와 구분한다.

## 검역 결정

후보 전체를 curated로 넣었을 때 clean 한글의 신규 자동 변환은 4개였다. 검역 CSV는 **후보 전체를 넣는 가정**이며 실제 반영에서 제외한 항목이 있다.

| 후보 | 한글 키 입력 결과 | 결정과 이유 |
|---|---|---|
| `futurism` | 려셔갸느 | 추가. 한국어 표제어·조사 결합으로 판단할 근거가 없는 긴 비단어. |
| `riso` | 갸내 | 추가. 2음절 비단어이며 인쇄 분야의 명시 용어. |
| `rococo` | 개채채 | 추가. 검사기가 `개채` 접두어를 경고했으나 뒤의 `채`는 이 형태에서 통상적인 조사 결합으로 판단하지 않음. |
| `slab` | 니뮤 | **추가 제외.** 한국어 감정 표현과 겹칠 수 있어 무맥락 자동 변환을 늘리지 않음. 필요하면 개인 사전의 변환 추가 또는 수동 단축키 이용. |

위 결정은 루트 자체 검토다. `grattage`(ㅎㄱㅁㅅㅅㅁㅎㄷ), `lineart`(ㅣㅑㅜㄷㅁㄱㅅ)는 전부 자모로 나와 경고되지만 각각 8키·7키의 분야 용어이고 반복/얼굴 자모에 해당하지 않아 추가했다. 짧은 임의의 자모 나열을 허용하는 규칙은 만들지 않았다.

`slab`과 `slabb` 입력은 각각 `니뮤`, `니뮤ㅠ`로 유지하는 회귀 검사를 넣었다. 기존 한글 보호, 자동 변환 OFF, 모든 표본의 개인 사전 금지 우선도 검사했다.

## 단어의 종류와 표현 범위

- **Risograph**: 인쇄 방식/장비에서 온 말이다. 화면에서는 인쇄 질감과 색 겹침을 표현하는 디자인으로 응용할 수 있다.
- **Surrealism**: 초현실주의라는 미술 사조다.
- **The Ransomizer**: 오려 붙인 글자 같은 이미지를 만드는 도구 이름이다. 그 표현을 검색할 때는 `ransom note typography`, `cutout typography`, `paper collage`가 더 넓은 검색어다.
- `art nouveau`, `motion graphics`, `slab serif`처럼 여러 단어인 표현은 공백마다 개별 판정한다. 이번 표본은 토큰 검증이며 문장 전체 보장을 뜻하지 않는다. 붙여 쓰는 실용 검색 표기 `motiongraphics`, `lineart`, `pixelart`, `stopmotion` 등도 일부 포함한다. 전부 정식 미술 사조라는 뜻이 아니다.
- 표본의 `slab`은 의도적으로 보류했다. 숫자·하이픈·악센트가 있는 새 표기 전체를 지원하도록 알고리즘을 확장하지 않았다.

## 검증과 재현

- `bash scripts/run_ime_tests.sh`: **3,147 passed, 0 failed**. 기존 한글/숫자/단위 회귀 + 202개 아트 토큰과 mp/MP/Mp 검사.
- `bash scripts/audit_wordlist.sh --smoke`: PASS.
- `bash scripts/audit_wordlist.sh --reachability dict_work/2026-10-08-art-design-coverage.txt --out /tmp/art-reach.csv`: 미도달 1개(slab), 검사 불가 0개가 의도한 결과.
- [대표 표본](../dict_work/2026-10-08-art-design-coverage.txt), [추가 전](../dict_work/2026-10-08-art-design-before.csv), [후보 전체 검역](../dict_work/2026-10-08-art-design-audit.csv), [실제 추가 후](../dict_work/2026-10-08-art-design-after.csv).
- 제품: `Resources/IM/english_supplement.txt`, `EnglishDetector.shouldConvert`, `KoreanComposer.commit`. 회귀: `Tests/ComposerTests.swift`의 아트·디자인 표본 검사.

## 출처

개별 용어를 직접 선별했으며 외부 용어집이나 설명문 전체를 복제하지 않았다. 아래 자료는 분야·철자·표현 방식 확인에 이용했다. 확인일 2026-10-08.

- [RISOTTO Studio — What is Risograph Printing?](https://risottostudio.com/pages/what-is-risograph-printing): 인쇄 과정, 별색, 중첩, 질감.
- [MoMA — Surrealism](https://www.moma.org/collection/terms/surrealism), [Surrealism and Dreams](https://www.moma.org/collection/terms/surrealism/surrealism-and-dreams): 미술 사조와 작품 참고.
- [The Ransomizer](https://www.ransomizer.com/), [FAQ](https://www.ransomizer.com/faq): 도구명과 표현 방식. 이름을 앱의 새 브랜드로 사용하는 작업은 아님.
- [Swiss National Library — The International Style](https://www.nb.admin.ch/en/the-international-style-1950-1970): 그리드와 타이포그래피.
- [MoMA — The New Typography](https://www.moma.org/calendar/exhibitions/1013): 편집·타이포그래피 참고.
- [Memphis Milano](https://memphis.it/it/): 색·기하학적 디자인의 참고 작품.
- [MLBPARK의 니뮤 사용 질문/응답](https://mlbpark.donga.com/mlbpark/b.php?b=bullpen2&id=3680948): 한국어 표현과 겹칠 수 있음을 확인하는 사용례. 기술 판정은 실제 코어 검역을 근거로 함.

새 UI 아트 방향은 추천 단계다. 이 작업에서 앱의 배경·버튼·폰트·아이콘을 새 스타일로 변경하지 않았다.

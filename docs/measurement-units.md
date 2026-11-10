# 단위 표기 지원 — 2026.9(55)

기준일: **2026-10-08** (2026-11-01 단독 `ml` 갱신 · 2026-11-07 단독 목록 갱신 #174 #178) · 티켓 [#82](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/82) · [#106](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/106) · **테스트 후보, 설치본 실기 확인 대기**.

## 사용 방법

한글 모드에서 `oz`, `km`, `kg` 등을 친 뒤 Space를 누른다. 반복 자모와 겹치는 `mm`(ㅡㅡ)은 `35mm` 또는 `35 mm`처럼 숫자와 함께 입력한다. `ml`은 2026-11-01(#106)부터 단독으로 쳐도 `ml`이 되고, `100ml`·`100 ml`도 종전대로 변환된다. `1.25ml`, `1.25 kg`도 지원한다. 영어로 전환할 때 대소문자·숫자·공백은 입력한 그대로 보존한다.

단위 기호를 환산하거나 철자를 교정하는 기능은 아니다. `mW`와 `MW`를 서로 바꾸지 않고, `um`을 `µm`으로 고치지 않는다.

## 검역 결과

최초 빌드 53의 **174개 표기**를 실제 제품 조합기에 통과시켰다. 아래 전후 표는 2026-10-07의 동일 표본 결과를 보존한 것이며, 기존 사전에서 이미 변환되는 항목도 포함한다.

| 입력 조건 | 변경 전 | 변경 후 |
|---|---:|---:|
| 단독 + 활성 경계 | 37 | 129 |
| `100` + 단위 | 37 | 169 |
| `100 ` + 단위 | 37 | 169 |
| `1.25` + 단위 | 37 | 169 |

조건: macOS 로컬 사전 + 번들 사전, 개인 사전 없음, 자동 변환 ON, 실제 키 대소문자 보존. 변경 전 코어는 `cdd26cdf87cea727c1604cc01dcae502191eecc1`의 KoreanComposer/EnglishDetector/PersonalDictionary, 변경 후는 2026-10-07 빌드 53의 로컬 변경이다. 전후에 동일한 174개 목록과 사전을 사용했다. 이 수치를 모든 국제 단위/모든 접두사 조합에 대한 완전 지원으로 해석하지 않는다.

근거: [변경 전 CSV](../dict_work/2026-10-07-unit-before.csv), [변경 후 CSV](../dict_work/2026-10-07-unit-audit.csv). 각 행에 한글 조합 결과, 한국어 사전 충돌 여부, 네 입력 조건의 실제 출력이 있다.

### 2026-10-08: 메가픽셀 약어 추가

빌드 54에는 `megapixel`이라는 긴 단어만 인식됐으며 `12mp`는 `12ㅡㅔ`, `12MP`는 `12ㅡㅖ`로 남았다. 빌드 55에서 `MeasurementUnits.symbols`에 **mp / MP / Mp**를 추가했다. `MP`, `Mp`는 제조사 표기 사례가 있고 소문자 `mp`는 사용자 요청에 따른 실용 입력 표기다. 출력 대소문자를 교정하지 않는다.

- 코어에서 `mp`, `MP`, `Mp`, `12mp`, `12MP`, `12Mp`, `12 mp`, `12 MP`, `12.5mp`, `12.5MP` 변환 확인.
- OFF·개인 사전 금지·전체 수량 되돌리기·뒤의 한국어 문맥 보호 확인.
- 최신 **177개 목록** 전수 결과: 단독 **132개**, 숫자 붙임/Space 1개/소수 조건 각각 **172개** 변환. 기존 보류 5개는 동일.
- 근거: [2026-10-08 CSV](../dict_work/2026-10-08-unit-audit.csv), `Tests/ComposerTests.swift` 메가픽셀 검사. 설치본 IMK 실기는 남아 있다.

### 2026-11-10: 단위 뒤 '이다' 꼴 (#220)

`20MB예요`·`20MB라`·`10kg이에요`·`3km예요`가 `20ㅡㅠ예요`처럼 자모로 남았다. 영어+조사 목록에 '이다' 꼴이 없어서였다(`20MB는`·`10kg에`는 바뀌었다). 목록에 넣어 단위 뒤에서도 바뀐다. 같은 날 과거형(`20MB였어요`)·추측형(`10kg일걸요`)도 넣었고(41꼴), 3차로 연결·조건 꼴(`20MB면`·`10kg이지만`·`100ml이라면`)과 비표준 표기(`10kg이였어요`)까지 넣었다(79꼴). 범위·보호는 [입력 변환 규칙](input-conversion-rules.md)의 2026-11-10 보완 절과 같다.

- 숫자 덕에만 단위로 읽히는 표기(`16GB`의 `GB`=휴, `35mm`의 `mm`=ㅡㅡ)는 **조사가 붙으면 예전부터 한글이다**(`16휴에`, `35ㅡㅡ는`). `16GB예요`도 같은 결과다. 이번에 넓히지 않았다 — 수량만으로 추론하지 않는다는 기존 규칙(#101·#106, `runExpandedParticleTests`의 `100mm에`).
- 소문자 바이트 단위(`20mb`→`20ㅡㅠ`)와 숫자 뒤 단위+조사(`16GB에`) 정리는 #222에서 다룬다(오너 결정 대기).
- 근거: `Tests/EnglishParticleTests.swift`의 `runCopulaParticleTests`.

### 2026-11-08: `nm`은 숫자가 붙을 때만 (#194)

오너 결정으로 단독 `nm`(`ㅜㅡ`)은 바꾸지 않는다. `10nm`·`10 nm`·`1.5nm`은 그대로 바뀐다. 구현은 `MeasurementUnits.quantityOnlySymbols`이고, 다른 단위의 단독 변환은 바꾸지 않았다.

### 2026-11-01: 단독 `ml` 변환 (#106)

오너 결정으로 `ㅢ` 단독도 `ml`로 바꾼다. 당시의 문맥 전용 목록(`contextOnlyShortWords`, 2026-11-07 #194에 목록째 없앴다)에서 `ml`을 빼서, 다른 짧은 단어(lg·pd)와 같은 R1(모음 시작) 경로로 변환된다. 단위 경로(`MeasurementUnits`)는 바꾸지 않았다.

- `ml`·`mL`은 단독, 두 칸 공백·줄바꿈·쉼표·`1.` 뒤에서도 변환된다. 자동 변환 OFF·앱별 OFF·개인 사전 금지(`ml`/`ㅢ`)·veto 사전 로드 실패에서는 `ㅢ`로 남는다.
- 단독 `ml`은 다른 영어 단어처럼 다음 단어에 영어 문맥을 넘긴다(mg와 같은 동작). 숫자 뒤의 `100ml`은 종전대로 문맥을 넘기지 않는다.
- `100ml에`는 이제 `mg`와 같이 영어+조사로 바뀐다(`100mg에`와 같은 결과).
- `ok`(ㅐㅏ)는 계속 영어 뒤에서만, `mm`(ㅡㅡ)·`cc`(ㅊㅊ)는 계속 단독 보호다.
- 근거: `Tests/ComposerTests.swift`의 `runDict106Tests`, `Tests/EnglishParticleTests.swift` #106 검사.

## 한글 보호

- 단독 입력은 기존 반복 자모·얼굴 자모·한국어 사전·슬랭 보호를 통과해야 한다. `mm=ㅡㅡ`, `cc=ㅊㅊ`, `qt=ㅂㅅ`는 단독으로 강제 변환하지 않는다. `cm=츠`만 검역한 비단어 1음절 예외다. (`ml=ㅢ`은 2026-11-01 #106부터 단독 변환 — 위 절 참고)
- `cl=치`, `dl=이`, `dm=으`, `em=드`, `wk=자` 다섯 표기는 숫자 뒤에서도 기본적으로 보호한다. `10이`가 `10dl`로 바뀌지 않는다.
- `100GB`, `10dB`, `10dL`처럼 **정확한 단위 기호 + 한글 자모를 바꾸지 않는 대문자 키 + 수량**이 함께 있으면 한글 충돌을 통과시킨다. 소문자 `gb`, `db`, `dl`까지 넓히지 않는다. 두벌식 자모를 바꾸는 `QWERTOP` 대문자는 이 예외의 근거로 쓰지 않는다.
- 전체 수량 또는 단위 자체의 개인 사전 금지가 우선이다. `ml`이나 `ㅢ`를 금지하면 `100ml`도 변환하지 않는다. `1.5ml`을 되돌린 뒤 전체 항목으로 금지할 수도 있다.
- 자동 변환 OFF/앱별 OFF/한국어 사전 로드 실패/포커스 이동에서는 자동 변환하지 않는다. 수량 다음의 단위가 다음 한글 단어에 영어 문맥을 넘기지 않는다. 되돌렸다 다시 바꿀 때도 동일하다.

### 2026-11-07: 단독 `sr`·`ton` 제외, `GPa` 유지 (#174, 오너 결정)

- `sr`(ㄴㄱ)은 초성체 보호(`protectedSlang`), `ton`(새ㅜ)은 끝 모음 보호(`해ㅠ`류)에 걸려 **단독으로는 변환하지 않는다.** 숫자 뒤(`100sr`·`10 ton`)는 종전대로 변환된다.
- `GPa`는 단독 변환을 유지한다. 두벌식에서 다른 자모를 내는 Shift 키(Q W E R T O P)가 섞인 혼합 대문자를 영어 경로에서 막는 새 규칙(`englishCasing`)이 있지만, 등록된 단위 기호와 대소문자까지 같으면 이 차단을 건너뛴다.
- 단독 목록은 그 날짜의 `bash scripts/audit_units.sh` 출력(`standalone` 열)으로 만들었다. 이 도구는 2026-11-04 컨트롤러 변경(붙잡지 않은 숫자·소수점을 앱에 바로 보내고 보낸 숫자열만 기억)을 따라가지 않아 수량 열이 실제와 달랐고, 2026-11-07(#178)에 `Tests/ComposerTests.swift`의 `typeKeyViaController`와 같은 분배로 고쳤다. 고친 뒤 수량 열(`attached`·`spaced`·`decimal`)은 각각 172개로 2026-10-08 표본과 같다. 규칙은 [입력 변환 규칙 모음](input-conversion-rules.md).

## 지원 목록

단독 입력에서도 변환되는 132개(공식 기호와 실용 표기/별칭을 합한 입력 목록. 2026-11-07 기준 — `sr`·`ton`은 빠지고 `mL`·`ml`이 들어왔다):

```text
Bq GHz GPa GW Gbps GeV GiB Hz KB KiB MB MBq
MHz MJ MN MPa MW MWh Mbps MeV MiB Mohm PB Pa
PiB Sv TiB Torr acre angstrom atm bar bit bps cal cd
cm dpi eV floz fps ft gal gbps ghz hPa ha hr
hz in kBq kHz kJ kL kN kPa kV kW kWh kat
kbps kcal keV kg khz kl km kohm lb lbs lm lx
mA mAh mGy mH mJ mL mN mS mSv mT mV mW
mWh mbar mbps mg mhz mi mil min ml mmol mol ms
nA nF ng nm nmi nmol ns ohm oz pF pm ppb
ppi ppm ppt ps psi pt px rad rem rpm torr uA
uF uL uSv ug ul um umol us yd
mp MP Mp
```

숫자 조건에서만 변환되는 40개(단독으로는 변환되지 않는다. 2026-11-07 기준 — `sr`·`ton`이 여기로 옮겨 왔고 `mL`·`ml`은 위 단독 목록으로 갔다):

```text
A Ah B C F GB GJ Gy H J K L
N S T TB THz V W Wb Wh cL cc d
dB dBA dL g h hL hl l m mm qt s
sr t thz ton
```

기본 자동 변환을 보류한 5개: `cl`, `dl`, `dm`, `em`, `wk`. 의도적인 변환은 기존 수동 단축키 또는 개인 사전으로 지정할 수 있다.

## 이번 범위의 경계

수량은 단어 시작의 정수 또는 소수 한 개다. 숫자와 단위 사이에는 Space 한 번까지 지원한다. 다른 글자·커서 이동·앱 이동·줄바꿈·두 번째 Space는 수량 문맥을 끊는다. 숫자를 붙잡는 길이도 기존 조합기 상한을 따른다.

`km/h`, `m2`, `m/s²`, `fl oz`처럼 구분자·지수·여러 단어로 구성된 표기 전체, 과학 표기법 `1e3ml`, 숫자 앞뒤에 다른 이름/한글 조사가 붙은 토큰은 이번 완전 지원 대상이 아니다. 이미 문서에 있는 텍스트나 붙여넣은 숫자를 거슬러 읽어 단위 문맥을 추정하지 않는다. 이번에 실제로 입력한 키만 사용한다.

## 코드와 재검증

- `IMESources/MeasurementUnits.swift`: 명시 목록, 정수/소수 판정, 숫자 조건의 한글 충돌 보호.
- `EnglishDetector.shouldConvert`: 기존 공통 보호 뒤의 단독 단위 판정.
- `KoreanComposer.handleDigit/handleQuantityPoint/commit/commitAlphanumeric`: 수량 버퍼, 경계, 개인 사전·되돌리기·문맥.
- `HaneulInputController.handle`: 실제 키 분배에 소수점 경로 연결. 기존 OFF/보안 입력/수동 키 경로 유지.
- `PersonalDictionary`: `1.5ml` 형식의 추가/금지 입력 검증. 임의 점 포함 이름은 허용하지 않음.
- `bash scripts/run_ime_tests.sh`: 2026-10-08 코어 **3,147 passed, 0 failed**. 기존 한글·숫자 제품명 회귀, 전체 단위의 수량/소수/OFF/금지, 메가픽셀 약어, 오류 사전, 편집·되돌리기와 아트 용어 검사.
- `bash scripts/run_onboarding_tests.sh`: 실제 NSTextView와 코어 연결 **49 passed, 0 failed**. OS의 IMK 연결 실기는 별도.
- `bash scripts/audit_units.sh > /tmp/haneul-unit-audit.csv`: 동일 목록 전수 검사 재생성. `audit_wordlist.sh --smoke`도 통과. (2026-11-07 #178: 이 도구의 키 분배를 현재 컨트롤러에 맞췄다 — 위 2026-11-07 절.)

## 단위 표기의 근거

`MP`와 `Mp`의 메가픽셀 표기 사례: [삼성 ISOCELL HP2](https://semiconductor.samsung.com/news-events/tech-blog/the-debut-of-the-isocell-hp2-with-the-galaxy-s23-ultra/), [ISOCELL Bright HMX](https://semiconductor.samsung.com/news-events/tech-blog/samsungs-isocell-bright-hmx-brings-the-high-performance-of-professional-cameras-to-the-smartphone/). 확인일 2026-10-08.

SI 기호와 접두사 표기는 [BIPM SI Brochure](https://www.bipm.org/en/web/guest/publications/si-brochure) 및 [NIST SI 단위·접두사 표](https://www.nist.gov/pml/special-publication-811/nist-guide-si-chapter-4-two-classes-si-units-and-si-prefixes)를 참고했다. 시간·리터·데시벨은 [NIST 비 SI 단위 안내](https://www.nist.gov/pml/special-publication-811/nist-guide-si-chapter-5-units-outside-si), ounce 등은 [NIST SP 811 변환 표](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf)를 참고했다.

`KiB`, `MiB`, `GiB` 등의 표기는 [NIST 이진 접두사 안내](https://physics.nist.gov/cuu/Units/binary.html), `px`, `pt`, `em`, `rem`은 [W3C CSS 길이 단위](https://www.w3.org/TR/css-values-4/#lengths)를 참고했다. `um`, `ohm`, `floz`, `lbs`, `hr`, `wk`, 소문자 `hz` 계열, `bps` 계열, `fps`, `dpi`, `ppi` 등은 실용 ASCII 표기를 위한 입력 목록이며 전부 공식 SI 기호라는 뜻은 아니다. 표기별 한글 변환 허용 여부는 위 표준의 요구가 아니라 하늘키보드의 오변환 방지 정책이다.

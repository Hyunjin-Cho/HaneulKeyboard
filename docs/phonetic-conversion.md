# 등록 한글 표기 → 영문 표기

기준일: **2026-10-09** · 티켓 [#84](https://github.com/Hyunjin-Cho/HaneulKeyboard/issues/84) · 대상 2026.9 개발 빌드 67.
기준 커밋: `cdd26cdf87cea727c1604cc01dcae502191eecc1` + 기존 미커밋 작업과 이번 변경. 커밋만으로 현재 기능을 재현할 수 없다.

## 결정과 범위

오너가 선택한 기본 사전부터 시작한다. 일반적으로 쓰는 외래어, 브랜드, 제품명과 오너가 요청한 종목 등 지정 의미를 명시 목록으로 관리한다. `축구→football`처럼 발음이 다른 대응도 등록된 한글 전체에만 적용한다. 오타 추정·AI 번역·개인 발음 사전 UI는 이번 범위에서 제외한다. 사전과 코드는 루트 Codex가 자체 검토했으며 별도 검토 에이전트를 소집하지 않았다.

- 기본 Shift+Space 또는 사용자가 설정한 되돌리기 키를 사용한다. 별도 단축키는 추가하지 않는다.
- 우선순위: **직전 변환 쌍 되돌리기 → 등록 한글 전체 조회 → 기존 자판 배열 변환**.
- `워크 → work → 워크`와 `재가 → work → 재가`를 구별한다. 출력만으로 원문을 추측하지 않는다.
- `축구 → football`(soccer로 바꾸지 않음), `미식축구 → american football`, `라이더 → rider`, `스포츠 → sports`를 지원한다.
- `시각효과 → VFX`는 오너 지정이다. `브이에프엑스 → VFX`도 명시 별칭으로 등록했으며 원래 입력한 한글로 되돌린다. 약어·고유명사의 영문 대소문자와 공백·하이픈을 보존한다.
- `레스토랑 → restaurant`, `라이트 → light`는 오너 지정이다. `애플 → Apple`, `삼성 → Samsung`, `엔비디아 → NVIDIA`처럼 브랜드 영문 대소문자는 사전에 적는다.
- `갤럭시`·`애플`만 등록하며 `겔럭시`·`에플`은 등록하지 않는다. 미등록 입력은 기존 자판 토글 설정을 따른다. ‘발음 사전 미등록’은 ‘기존 자판 토글도 금지’라는 뜻이 아니다.
- NFC 정규화는 허용한다. 한국어 조사 제거, 오타 교정, 띄어쓰기 제거, 전각 숫자 변환은 하지 않는다. `레스토랑에서`, `맥 스튜디오`는 발음 변환 대상이 아니다.
- 출력에 공백이 있는 `Mac Studio`는 저장된 전체 변환 쌍으로 되돌린다. 처음부터 입력된 영어를 한글 발음으로 역변환하지 않는다.
- 일반 Space/문장부호는 기존 자동 영타 경로만 사용한다. 클릭/포커스 이동은 보이는 조합을 확정한다.

## 실제 수량

원본은 [phonetic_dictionary.json](../Resources/IM/phonetic_dictionary.json) 하나다. **고유 한글 입력 1,903개, 고유 영문 출력 1,880개**다. 첫 후보 358개 → +319개로 677개 → +801개로 1,478개 → 분야 확장505개에서 인물·음악 그룹80개를 제외한 **425개 추가**로 1,903개가 됐다. 직전 1,478개 한글→영문 쌍은 모두 보존했다. 같은 출력에 대응하는 별칭이 있으므로 입력과 출력 수를 따로 센다. 기존 자동 영타 변환 영어 목록과 합산한 수치가 아니다.

| 분류 | 입력 표기 수 |
|---|---:|
| 생활·음식·여행 | 324 |
| 컴퓨터·소프트웨어 | 236 |
| 아트·영상·사운드 | 562 |
| 브랜드 | 153 |
| 제품·앱 | 58 |
| 스포츠 | 190 |
| 라이딩·이동수단 | 76 |
| 확인된 휴대폰 번호 별칭 | 29 |
| 예약 휴대폰 번호 별칭 | 6 |
| 게임 | 76 |
| 금융·경제 | 193 |
| 합계 | **1,903** |

유지한 분야 확장은 애니메이션64 / 영화111 / 생활1 / 금융193 / 브랜드38 / 제작 도구18개다. 사용자 결정으로 인물76명·음악 그룹4개를 제거하고 관련 분류·출처 메타데이터도 정리했다. 나머지1,903개 항목은 입력·출력·분류를 그대로 보존했다. 애니메이션과 디스코드는 이전부터 등록되어 새 수량으로 중복 계산하지 않는다.

전체 분야는 [어휘 분류](vocabulary-categories.md), 추가 목록은 [스포츠 등319개](../dict_work/2026-10-09-phonetic-expansion.tsv), [창작·생활·컴퓨터 등801개](../dict_work/2026-10-09-phonetic-creative-everyday-computing.tsv), [분야 확장425개](../dict_work/2026-10-09-phonetic-animation-film-finance.tsv)로 구분한다.

기본 항목은 1,868개, 숫자 별칭은35개다. JSON 크기는 264,858바이트, SHA-256은 `acbbe9e39f65dac77daee2fe7b418df77ee6048f2da44210e623c56e2e70dee8`다. 수량·크기·해시는 `python3 scripts/audit_phonetic_dictionary.py`로 다시 산출한다.

현재 코드에 단어 총수 상한은 두지 않는다. 사전을 한 번 읽어 해시 조회하므로 목록을 늘릴 수 있지만, 검토되지 않은 단어 수를 목표로 삼지 않는다. 입력 표기는40 UTF-16 단위, 출력은64 UTF-16 단위 이하로 제한한다. 출력은 ASCII 영문·숫자·공백·하이픈 범위를 유지한다. 다음 확장은 실제 사용 요청과 표기 검토를 기준으로 한다.

## 숫자 범위

사용자의 ‘실제 출시 제품 + 다음 3년’ 제안을 **이번 두 제품군의 다음 연간 번호 3개**로 해석했다. 미래 번호는 출시 사실이 아닌 입력 예약 표기다. 날짜를 읽어 범위를 자동 확장하지 않는다. 실제 발표에서 번호가 달라지면 명시 목록을 다시 검토한다.

| 별칭 | 확인된 세대 번호 | 예약 번호 | 변환 예시 |
|---|---|---|---|
| 갤럭시 + 숫자 | 2–10, 20–26 | 27–29 | 갤럭시24 → Galaxy24 |
| 아이폰 + 숫자 | 4–8, 11–18 | 19–21 | 아이폰17 → iPhone17 |

이는 짧은 **세대 번호 별칭** 목록이며 모든 실제 기종 목록이 아니다. Galaxy S의 S 생략과 숫자 앞 공백 생략은 오너가 요청한 `Galaxy24` 형태에 맞췄다. iPhone 18은 발표된 Pro 계열의 세대 번호를 근거로 한다. 최초 Galaxy S를 Galaxy1, iPhone 3G/3GS를 iPhone3, X/XS/XR을 iPhone9/10으로 임의 등록하지 않는다. Ultra/Pro/용량/통신사 조합, Galaxy A·Z 계열은 이번 숫자 확장에 포함하지 않는다.

공식 확인 출처(2026-10-09 조회): [Samsung Galaxy S 역사](https://news.samsung.com/global/from-amoled-to-space-zoom-looking-back-at-the-galaxy-s-series-history-of-innovation), [Galaxy S26 발표](https://news.samsung.com/us/samsung-unveils-galaxy-s26-series-most-intuitive-galaxy-ai-phone-yet/), [Apple iPhone 모델 식별](https://support.apple.com/en-us/108044). 브랜드 표기 참고: [NVIDIA 한국어 홈페이지](https://www.nvidia.com/ko-kr/), [Mac Studio](https://www.apple.com/kr/mac-studio/). 설명문·사전 데이터베이스를 복제하지 않고 대응어를 직접 작성했다.

## 코드 연결과 안전 조건

- `IMESources/PhoneticDictionary.swift` · `PhoneticDictionary.load/english`: 번들 JSON만 사용한다. 누락/중복/잘못된 표기면 발음 사전 전체를 비활성화하고 기존 기능을 남긴다. 개발용 경로를 제품에서 읽지 않는다.
- `IMESources/HaneulInputController.swift` · `handle/handlePendingPhonetic/handleManualToggle`: 보안 입력 검사와 기존 되돌리기를 먼저 실행한다. 등록 조합은 화면 marked text 범위·원문·좌우 경계를 확인한 뒤 한 번에 확정한다. 확정된 숫자 이름은 문서에서 전체 단어를 찾는다.
- `IMESources/ManualToggle.swift` · `resolve`: 발음 조회와 기존 순수 자판 역변환 `manualToggle`을 구분한다.
- `IMESources/KoreanComposer.swift` · `pendingPhoneticConversion/commitPhonetic/applyToggle`: 원문 쌍과 변환 출처를 유지한다. 발음 변환은 뒤 한국어의 자동 변환 문맥을 만들지 않는다. 수동 변환 왕복은 ‘최근 되돌린 자동 변환’에 기록하지 않는다.
- `project.yml` · `Embed HaneulKeyboardIM into Contents/Helpers`: 사전 파일만 바뀐 증분 빌드에서 단독 입력기는 최신인데 앱 안의 사본은 이전 JSON을 담는 문제를 재현했다. 복사 단계를 `basedOnDependencyAnalysis: false`로 설정해 빌드마다 최신 입력기를 포함한다. 옵션 근거: [XcodeGen Build Script 명세](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#build-script).
- `IMESources/RevertKey.swift`, `Sources/RevertKeySettingsSection.swift`: `haneul.phoneticConversionEnabled` 기본 ON. 기존 모든 단어 자판 토글과 독립적으로 끌 수 있다. 이미 저장된 직전 변환의 되돌리기는 설정 변경 후에도 우선한다.
- 개인 사전의 추가/금지와 앱별 자동 변환 OFF는 자동 변환을 제어한다. 사용자가 직접 누르는 발음 변환은 별개의 의도적 조작이다.
- 읽을 수 없는/잘린 문서 범위, 선택 영역, 거부된 교체는 기존 방어선을 유지한다. 이웃 글자 읽기를 제공하는 앱에서 단어 중간을 피한다. 호스트 앱이 잘못된 범위를 보고하거나 일부 읽기를 거부하는 경우의 실기 검증은 남아 있다.
- Terminal/Ghostty의 확정 텍스트 교체 제한을 우회하지 않는다. 입력기는 네트워크·AI 호출·입력 학습을 하지 않는다.

## 분야 확장 기준 (빌드 67)

- 사용자 결정으로 인명·음악 그룹명은 한글→영문 대응에서 제외한다. 별도 people 분류와 이 분류의 출처 메타데이터도 제거했다. 일반 영타 자동 변환의 기존 영어 인명 참조 목록은 이번 삭제 대상이 아니다.
- 애니메이션→animation, 디스코드→Discord와 애니메이션 제작 용어·영화 장르·제작 직무·플랫폼·제작 도구는 유지한다.
- **선물→gift**는 사용자 지정이며 문맥과 무관하다. 금융 의미는 선물거래→futures trading, 선물계약→futures contract, 선물시장→futures market으로 구분한다.
- 메시→mesh, 줌→zoom, 지수→index는 일반·전문 용어로 유지한다. 줌워크플레이스→Zoom Workplace, 라이카스튜디오→LAIKA 같은 브랜드 표기도 유지한다.
- 시각효과/브이에프엑스→VFX, 축구→football, 라이트→light 등 이전 지정, 자동 영타 사전·한국어 보호 알고리즘·숫자 제품 범위도 유지한다.
- 제거한 이름은 미등록 단어와 같이 기존 자판 토글 설정을 따른다. 이를 이름의 영문 표기 변환으로 안내하지 않는다.
- 대응어는 직접 작성하고 루트 Codex가 자체 검토했다. 용어 표기 참고는 [어휘 분류](vocabulary-categories.md#용어-참고)에 남긴다.

## american 영타 자동 변환 보완

`/usr/share/dict/words`에는 대문자로 시작하는 `American`만 있다. `EnglishDetector.loadWords`는 기존 고유명사 보호 정책에 따라 그 항목을 제외한다. `american`은 번들 영어 파일에도 없어서 자동 변환에 도달하지 않았다. `english_supplement.txt`에 소문자 항목 1개만 추가하고 로더/한국어 보호 규칙은 유지했다.

실제 코어 검역에서 한글형 `믇걏무`는 깨진 조합이며 우리말샘과 충돌하지 않았다(Tier C, 변경 전 미변환→변경 후 변환). `rider`·`sports`·`football`·`baseball`은 기존 영타 변환이 이미 동작하여 중복 추가하지 않았다. 근거: [검역 CSV](../dict_work/2026-10-09-american-audit.csv), `Tests/PhoneticTests.swift`의 소문자/첫 대문자/전체 대문자·american football 입력 검사.

## 검증과 현재 상태

- 수정 전 빌드66 코어: 25,173 통과 / 0 실패. 인물 제거 후 `scripts/run_ime_tests.sh`: **24,307 통과 / 0 실패**. 사전1,903개 전체의 조합·확정·원문 왕복·NFD 및 기존 회귀를 검사한다. 제거한 이름·그룹이 발음 사전에서 조회되지 않고 기존 자판 토글로 넘어가는 검사도 포함한다.
- `scripts/run_onboarding_tests.sh`: 실제 NSTextView **159 통과 / 0 실패**. 금융 용어의 공백·fine-tuning의 하이픈·VFX 대문자 등 기존 marked 범위 교체·왕복을 확인한다. OS IMK 설치 검증을 대체하지 않는다.
- `scripts/audit_phonetic_dictionary.py`: 중복·표기·분류·숫자 정책·지정 의미 유지, 인물 분류 부재 확인. 변경 전후 대조로 인물·그룹80개만 제거됐고 나머지1,903개 항목 전체와 번호 정책이 동일함을 확인한다. 유지한 확장TSV425행은 빌드65 대비 원본 JSON 차집합과 일치한다.
- 로컬 무서명 Debug 컴파일 통과. 앱·단독 IME·내장 IME 모두 빌드67이며, 양쪽 IME의 발음·영타 보충 사전이 원본과 바이트 일치한다. 설치용/배포용 빌드가 아니다. 기록은 `.tmp/phonetic-remove-people-2026-10-09/`에 보관한다.
- 공식 배포 스크립트의 Apple 공증 전송은 이전 자동 승인 검토에서 명시 승인 부족으로 거절됐다. 이번에는 재시도하지 않았다. 기존 루트 ZIP는 빌드62로 새 사전을 포함하지 않는다.

현재는 **테스트 후보**다. 설치된 제품을 교체하지 않았고 티켓은 OPEN으로 유지한다. 다음 순서: 승인 후 공식 서명·공증 ZIP → 설치 승인 후 실제 IMK·앱별·보안 입력 확인. 확인 목록은 [수동 테스트](manual-test-checklist.md)의 빌드 67 절이다. 커밋·푸시·머지·태그는 수행하지 않는다.

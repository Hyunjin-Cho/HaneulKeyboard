# 감사의 글 (Acknowledgements)

> 기준일: 2026-10-10

하늘키보드는 혼자 만든 것이 아닙니다. 앞서 길을 닦아준 수많은 오픈소스와 도구, 그리고 그것을 가능케 한 사람들의 어깨 위에 서 있습니다.

## 하늘키보드 코드와 원본 고지

- 현재 앱 코드: Apache License 2.0. 원문은 `LICENSE`, 원본 프로젝트 이름과 주소는 `NOTICE`에 있습니다.
- 원본: **HaneulKeyboard (하늘키보드)** · Copyright (c) 2026 Hyunjin Cho · https://github.com/Hyunjin-Cho/HaneulKeyboard
- 이전 MIT 배포분의 고지는 소스의 `LICENSES/HaneulKeyboard-MIT-legacy.txt`와 앱/입력기 리소스의 `HaneulKeyboard-MIT-legacy.txt`에 보존합니다. 기존 MIT 배포본의 이용 조건을 소급 변경하지 않습니다.
- 아래 외부 코드·사전·글꼴의 라이선스는 각각 유지합니다. 앱 코드의 라이선스 변경으로 이 자료들을 Apache로 바꾸지 않습니다.
- 적용 근거: `project.yml` 두 타겟의 resources, `scripts/verify_license_resources.py`. 메인 앱과 설치되는 입력기에 LICENSE·NOTICE·감사의 글·과거 MIT 고지를 동봉합니다.

## 직접적으로 도움받은 프로젝트

### 고운바탕 (Gowun Batang)
- 출처: https://github.com/google/fonts/tree/main/ofl/gowunbatang / https://github.com/yangheeryu/Gowun-Batang
- Copyright 2021 The Gowun Batang Project Authors. SIL Open Font License 1.1.
- 5단계 리소그래프 안내의 제목에 수정하지 않은 Bold 원본을 사용합니다. 앱 내부에만 등록하며 시스템에는 설치하지 않습니다.
- 원문 라이선스: `Resources/Onboarding/GowunBatang-OFL.txt`. 반영일: 2026-10-09.
- 원본 TTF SHA256: `dbfcaa646e5831e7478524924f02906f550285a5050699b4e38c9950b3ec4b94`.

### 나눔손글씨 펜 (Nanum Pen Script)
- 출처: https://github.com/google/fonts/tree/main/ofl/nanumpenscript
- Copyright (c) 2010, NHN Corporation. SIL Open Font License 1.1.
- 시작하기의 짧은 손글씨 안내에 원본 폰트를 사용합니다. 글꼴을 수정하지 않았으며 원문 라이선스는 `Resources/Onboarding/NanumPenScript-OFL.txt`에 동봉합니다. 앱 내 등록만 하며 시스템 글꼴로 설치하지 않습니다.
- 반영일: 2026-10-07. 원본 TTF SHA256: `6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43`.

### McBopomofo (OpenVanilla)
- 저장소: https://github.com/openvanilla/McBopomofo
- 라이선스: MIT
- 대만어(주음) 입력기. macOS의 TIS(Text Input Services) 입력기 **등록·설치 메커니즘**을 이해하고 구현하는 데 결정적인 참고가 되었습니다. 사인·노타리된 메인 앱이 입력기 번들을 설치하는 패턴이 특히 큰 도움이 되었습니다.

### 국립국어원 우리말샘
- https://opendict.korean.go.kr
- 라이선스: CC-BY-SA 2.0 KR
- 영타 자동 변환이 "이 글자가 실존하는 한국어 단어인가"를 판정할 때 쓰는 **표제어 67.7만 개**([`Resources/IM/korean_words.txt`](./Resources/IM/korean_words.txt))의 출처입니다. 우리말의 보고를 모두에게 열어준 국립국어원과 우리말샘 참여자들께 감사드립니다.

### New General Service List (NGSL)
- https://www.newgeneralservicelist.com
- 라이선스: CC BY-SA 4.0 — Browne, C., Culligan, B., & Phillips, J. (2013). *The New General Service List*.
- 영타 자동 변환이 "이 입력이 실제 쓰이는 영어 단어인가"를 판정할 때 쓰는 **현대 영어 고빈도 lemma 2,809개**(굴절형 포함 1만여 형태)의 출처입니다. 영어 학습자를 위해 데이터를 공개해준 세 분 연구자께 감사드립니다.

### 미국 인구조사국 (US Census Bureau) — 2010 Census 성씨 데이터
- https://www.census.gov/topics/population/genealogy/data/2010_surnames.html
- 라이선스: Public Domain (미 연방정부 저작물)
- **원천 데이터 규모:** 성씨 약 16.2만 개(2010년 인구 100명 이상). 가공·필터링 후 SSA 이름과 합쳐 앱에 탑재합니다.

### 미국 사회보장국 (SSA) — Baby Names 데이터
- https://www.ssa.gov/oact/babynames/
- 라이선스: Public Domain (미 연방정부 저작물)
- 영타 자동 변환의 인명 인식에 쓰는 **이름(first name) 데이터**(1880년 이후 연도별 출생 신고 집계)의 출처입니다.

### SCOWL / ESDB (English Speller Database) — Kevin Atkinson
- https://wordlist.aspell.net
- 라이선스: MIT-like — Copyright 2000-2026 by Kevin Atkinson (저작권 고지 유지 조건의 퍼미시브 라이선스, 동봉 README 기준)
- **원천 데이터 규모:** size 70 미국식 영어 약 16.7만 단어(현대어와 굴절형 포함). 가공·필터링한 후 broad 영어 사전으로 앱에 탑재합니다. 수십 년간 영어 철자 데이터를 다듬어 공개해 온 Kevin Atkinson과 기여자들(12dicts의 Alan Beale 등)께 감사드립니다.

### 가공 후 앱 탑재 규모

| 탑재 파일 | 규모 | 구성 |
|---|---:|---|
| `english_names.txt` | 28,378개 | Census 성씨와 SSA 이름을 가공·필터링한 목록 |
| `english_modern.txt` | 71,348개 | SCOWL size 70을 가공·필터링한 목록 |
| `english_names_extra.txt` | 수작업 보충 목록 | Census/SSA 출처가 아닌, 유명인을 수작업으로 선별한 목록 |

### GeoNames — 전 세계 지명 데이터
- https://www.geonames.org
- 라이선스: CC BY 4.0
- 영타 자동 변환의 **지명 사전**(북미·유럽 4개국의 주/도 + 인구 5만+ 도시, [`Resources/IM/english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt)에 포함)의 출처입니다. 전 세계 지명을 자유롭게 열어준 GeoNames와 기여자들께 감사드립니다.

### Wikidata (Wikimedia)
- https://www.wikidata.org
- 라이선스: CC0 1.0 (퍼블릭 도메인)
- 영타 자동 변환의 **축구 클럽·선수 사전**(잉글랜드·프랑스·스페인·이탈리아 9개 리그)의 출처입니다. 구조화된 지식을 퍼블릭 도메인으로 공개한 Wikidata 커뮤니티에 감사드립니다.

## 개발에 함께한 도구

### Anthropic — Claude
- https://claude.com/claude-code
- 설계 논의, 디버깅, 문서 작성 등 개발 과정 전반에 함께했습니다.

### OpenAI — Codex · ChatGPT
- https://openai.com/codex/
- 기능 설계와 코드 구현, 기존 기능과의 충돌 검토, 테스트와 문서 정리에 함께했습니다.
- 단청과 종이 질감을 담은 시작하기 안내의 시각 디자인, 이미지 제작과 인물 자세 작업에도 도움을 받았습니다.
- 개발에 사용한 도구이며, 앱이 사용자의 입력을 AI 서비스로 보내는 기능은 아닙니다.

## 참고한 오픈소스 입력기

plist·entitlements 구조와 IME 아키텍처를 비교·학습하는 데 참고했습니다.

- [macSKK](https://github.com/mtgto/macSKK) — Swift, 일본어 SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, 일본어, MIT

## 그리고

이 작은 키보드 하나에도 운영체제, 컴파일러, 언어, 폰트, 수십 년에 걸친 한글 입력 연구, 그리고 셀 수 없이 많은 오픈소스가 녹아 있습니다. 인류가 함께 쌓아 올린 그 모든 지식과 도구에 깊이 감사드립니다.

— Hyunjin Cho

---

# Acknowledgements (English)

> Updated: 2026-10-10

HaneulKeyboard builds on the work of the open-source projects, tools, and people who came before it.

## Application license and original attribution

Current application code is licensed under Apache License 2.0. `NOTICE` identifies **HaneulKeyboard (하늘키보드)**, Copyright (c) 2026 Hyunjin Cho, and the original project at https://github.com/Hyunjin-Cho/HaneulKeyboard. Both the main app and IME bundle LICENSE, NOTICE, this acknowledgements file, and the historical MIT notice (`LICENSES/HaneulKeyboard-MIT-legacy.txt` in source). Prior MIT distributions keep their original terms. Third-party materials below retain their respective licenses.

## Direct help

- **[Gowun Batang](https://github.com/yangheeryu/Gowun-Batang)** — Copyright 2021 The Gowun Batang Project Authors, SIL Open Font License 1.1. Unmodified Bold font for risograph onboarding headings, registered only within the app. Full license: `Resources/Onboarding/GowunBatang-OFL.txt` (2026-10-09).

- **[Nanum Pen Script](https://github.com/google/fonts/tree/main/ofl/nanumpenscript)** — Copyright (c) 2010, NHN Corporation, SIL Open Font License 1.1. The unmodified font is bundled for brief handwritten onboarding cues, with the full license in `Resources/Onboarding/NanumPenScript-OFL.txt` (2026-10-07). Registered for this app process only.

- **[McBopomofo](https://github.com/openvanilla/McBopomofo)** (OpenVanilla, MIT) — A Bopomofo input method for Taiwanese Mandarin. Its approach to **registering and installing a TIS (Text Input Services) input method on macOS** — a signed, notarized host app that installs the IME bundle — was a decisive reference.
- **[Urimalsaem (우리말샘)](https://opendict.korean.go.kr)** (National Institute of Korean Language, CC-BY-SA 2.0 KR) — Source of the 677k Korean headwords used by the wrong-layout auto-correction to verify real Korean words.
- **[New General Service List (NGSL)](https://www.newgeneralservicelist.com)** (Browne, C., Culligan, B., & Phillips, J., CC BY-SA 4.0) — Source of the 2,809 high-frequency modern English lemmas (10k+ word forms) used by the wrong-layout auto-correction to verify real English words.
- **[US Census Bureau — 2010 Census Surnames](https://www.census.gov/topics/population/genealogy/data/2010_surnames.html)** (Public Domain) — The source dataset contains about 162k surnames. After processing and filtering, Census surnames and SSA first names are bundled together in `english_names.txt` (28,378 entries).
- **[US Social Security Administration — Baby Names](https://www.ssa.gov/oact/babynames/)** (Public Domain) — Source of the first-name data (yearly birth registrations since 1880) used for recognizing personal names.
- **[SCOWL / ESDB (English Speller Database)](https://wordlist.aspell.net)** (Kevin Atkinson, MIT-like license — Copyright 2000-2026 by Kevin Atkinson) — The source size-70 American English list contains about 167k words; the processed and filtered `english_modern.txt` bundled with the app contains 71,348 entries. Thanks to Kevin Atkinson and contributors (including Alan Beale of 12dicts) for decades of curating English spelling data.
- **Bundled name data:** `english_names.txt` contains 28,378 processed Census/SSA entries. `english_names_extra.txt` is a hand-curated famous-person supplement and is not sourced from Census or SSA.
- **[GeoNames](https://www.geonames.org)** (CC BY 4.0) — Source of the place-name dictionary (North American & European states/provinces + cities with population 50k+) used by the wrong-layout auto-correction.
- **[Wikidata](https://www.wikidata.org)** (Wikimedia, CC0 1.0 Public Domain) — Source of the football club & player dictionary (9 leagues across England, France, Spain, Italy) used by the wrong-layout auto-correction.
## Development tools

- **Anthropic — [Claude](https://claude.com/claude-code)** — A companion throughout design, debugging, and documentation.
- **OpenAI — [Codex · ChatGPT](https://openai.com/codex/)** — Helped with feature design, code implementation, compatibility reviews, tests, and documentation, as well as the dancheong and paper-textured onboarding artwork and character poses. These are development tools; the app does not send typing to an AI service.

## Studied for reference

- [macSKK](https://github.com/mtgto/macSKK) — Swift, Japanese SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, Japanese, MIT

## And

HaneulKeyboard is built on operating systems, compilers, programming languages, fonts, decades of Hangul input research, and countless open-source projects. Deep gratitude to the people who built and shared these foundations.

— Hyunjin Cho

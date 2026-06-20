# 감사의 글 (Acknowledgements)

하늘키보드는 혼자 만든 것이 아닙니다. 앞서 길을 닦아준 수많은 오픈소스와 도구, 그리고 그것을 가능케 한 사람들의 어깨 위에 서 있습니다.

## 직접적으로 도움받은 프로젝트

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
- 영타 자동 변환의 인명 인식에 쓰는 **성씨 16.2만 개**(2010년 인구 100명 이상)의 출처입니다.

### 미국 사회보장국 (SSA) — Baby Names 데이터
- https://www.ssa.gov/oact/babynames/
- 라이선스: Public Domain (미 연방정부 저작물)
- 영타 자동 변환의 인명 인식에 쓰는 **이름(first name) 데이터**(1880년 이후 연도별 출생 신고 집계)의 출처입니다.

### SCOWL / ESDB (English Speller Database) — Kevin Atkinson
- https://wordlist.aspell.net
- 라이선스: MIT-like — Copyright 2000-2026 by Kevin Atkinson (저작권 고지 유지 조건의 퍼미시브 라이선스, 동봉 README 기준)
- 영타 자동 변환의 broad 영어 사전 보강에 쓰는 **미국식 영어 단어 목록**(size 70, 16.7만 단어 — 현대어와 굴절형 포함)의 출처입니다. 수십 년간 영어 철자 데이터를 다듬어 공개해 온 Kevin Atkinson과 기여자들(12dicts의 Alan Beale 등)께 감사드립니다.

### GeoNames — 전 세계 지명 데이터
- https://www.geonames.org
- 라이선스: CC BY 4.0
- 영타 자동 변환의 **지명 사전**(북미·유럽 4개국의 주/도 + 인구 5만+ 도시, [`Resources/IM/english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt)에 포함)의 출처입니다. 전 세계 지명을 자유롭게 열어준 GeoNames와 기여자들께 감사드립니다.

### Wikidata (Wikimedia)
- https://www.wikidata.org
- 라이선스: CC0 1.0 (퍼블릭 도메인)
- 영타 자동 변환의 **축구 클럽·선수 사전**(잉글랜드·프랑스·스페인·이탈리아 9개 리그)의 출처입니다. 구조화된 지식을 퍼블릭 도메인으로 공개한 Wikidata 커뮤니티에 감사드립니다.

### Claude (Anthropic)
- https://claude.com/claude-code
- 설계 논의, 디버깅, 문서 작성 등 개발 과정 전반에 함께했습니다.

## 참고한 오픈소스 입력기

plist·entitlements 구조와 IME 아키텍처를 비교·학습하는 데 참고했습니다.

- [macSKK](https://github.com/mtgto/macSKK) — Swift, 일본어 SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, 일본어, MIT

## 그리고

이 작은 키보드 하나에도 운영체제, 컴파일러, 언어, 폰트, 수십 년에 걸친 한글 입력 연구, 그리고 셀 수 없이 많은 오픈소스가 녹아 있습니다. 인류가 함께 쌓아 올린 그 모든 지식과 도구에 깊이 감사드립니다.

— Hyunjin Cho

---

# Acknowledgements (English)

HaneulKeyboard builds on the work of the open-source projects, tools, and people who came before it.

## Direct help

- **[McBopomofo](https://github.com/openvanilla/McBopomofo)** (OpenVanilla, MIT) — A Bopomofo input method for Taiwanese Mandarin. Its approach to **registering and installing a TIS (Text Input Services) input method on macOS** — a signed, notarized host app that installs the IME bundle — was a decisive reference.
- **[Urimalsaem (우리말샘)](https://opendict.korean.go.kr)** (National Institute of Korean Language, CC-BY-SA 2.0 KR) — Source of the 677k Korean headwords used by the wrong-layout auto-correction to verify real Korean words.
- **[New General Service List (NGSL)](https://www.newgeneralservicelist.com)** (Browne, C., Culligan, B., & Phillips, J., CC BY-SA 4.0) — Source of the 2,809 high-frequency modern English lemmas (10k+ word forms) used by the wrong-layout auto-correction to verify real English words.
- **[US Census Bureau — 2010 Census Surnames](https://www.census.gov/topics/population/genealogy/data/2010_surnames.html)** (Public Domain) — Source of the 162k surnames used for recognizing personal names.
- **[US Social Security Administration — Baby Names](https://www.ssa.gov/oact/babynames/)** (Public Domain) — Source of the first-name data (yearly birth registrations since 1880) used for recognizing personal names.
- **[SCOWL / ESDB (English Speller Database)](https://wordlist.aspell.net)** (Kevin Atkinson, MIT-like license — Copyright 2000-2026 by Kevin Atkinson) — Source of the size-70 American English word list (167k words, modern vocabulary and inflections) used to broaden the English dictionary for wrong-layout auto-correction. Thanks to Kevin Atkinson and contributors (including Alan Beale of 12dicts) for decades of curating English spelling data.
- **[GeoNames](https://www.geonames.org)** (CC BY 4.0) — Source of the place-name dictionary (North American & European states/provinces + cities with population 50k+) used by the wrong-layout auto-correction.
- **[Wikidata](https://www.wikidata.org)** (Wikimedia, CC0 1.0 Public Domain) — Source of the football club & player dictionary (9 leagues across England, France, Spain, Italy) used by the wrong-layout auto-correction.
- **[Claude](https://claude.com/claude-code)** (Anthropic) — A companion throughout design, debugging, and documentation.

## Studied for reference

- [macSKK](https://github.com/mtgto/macSKK) — Swift, Japanese SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, Japanese, MIT

## And

HaneulKeyboard is built on operating systems, compilers, programming languages, fonts, decades of Hangul input research, and countless open-source projects. Deep gratitude to the people who built and shared these foundations.

— Hyunjin Cho

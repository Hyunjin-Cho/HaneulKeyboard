# 감사의 글 (Acknowledgements)

> 기준일: 2026-11-17 (2026-05-27 초기 공개 때 처음 넣고 2026-10-10에 다시 썼습니다. 2026-11-07에 사전 탑재 방식·고지 원문·McBopomofo 고지를, 2026-11-08에 글꼴을 고운바탕에서 마루 부리로, 2026-11-13에 지명 사전 범위와 보충 목록 설명을 고치고 개발 도구 절을 실제로 함께 개발한 도구(Claude)만 남겼습니다. 2026-11-16에 바뀌는 사전 낱말 수를 확인하는 곳으로 바꿨습니다(#259). 2026-11-17에 영어 절을 한국어 절과 같은 구성으로 맞추고, 머리말 날짜를 바로잡고, 코드 리뷰에 쓴 Codex를 개발 도구에 적었습니다(#263). 같은 날 폴더 정리에 맞춰 소스 파일 경로를 고쳤습니다(#267).)

하늘키보드는 혼자 만든 것이 아닙니다. 앞서 길을 닦아준 수많은 오픈소스와 도구, 그리고 그것을 가능케 한 사람들의 어깨 위에 서 있습니다.

## 하늘키보드 코드와 원본 고지

- 현재 앱 코드: Apache License 2.0. 원문은 `LICENSE`, 원본 프로젝트 이름과 주소는 `NOTICE`에 있습니다.
- 원본: **HaneulKeyboard (하늘키보드)** · Copyright (c) 2026 Hyunjin Cho · https://github.com/Hyunjin-Cho/HaneulKeyboard
- 이전 MIT 배포분의 고지는 소스의 `LICENSES/HaneulKeyboard-MIT-legacy.txt`와 앱/입력기 리소스의 `HaneulKeyboard-MIT-legacy.txt`에 보존합니다. 기존 MIT 배포본의 이용 조건을 소급 변경하지 않습니다.
- 아래 외부 코드·사전·글꼴의 라이선스는 각각 유지합니다. 앱 코드의 라이선스 변경으로 이 자료들을 Apache로 바꾸지 않습니다.
- 적용 근거: `project.yml` 두 타겟의 resources, `scripts/verify_license_resources.py`. 메인 앱과 설치되는 입력기에 LICENSE·NOTICE·감사의 글·과거 MIT 고지를 동봉합니다.

## 직접적으로 도움받은 프로젝트


### 마루 부리 (MaruBuri)
- 출처: 네이버 한글한글 아름답게 https://hangeul.naver.com/font (공식 배포 파일 `maruburi.zip`).
- Copyright © NAVER Corp. & NAVER Cultural Foundation. SIL Open Font License 1.1(네이버 글꼴 라이선스).
- 앱 화면의 모든 글자(제목·설명·버튼)와 리소 그림 속 글자에 수정하지 않은 Regular·SemiBold·Bold OTF 원본을 사용합니다. 앱 내부에만 등록하며 시스템에는 설치하지 않습니다. 글꼴 파일을 따로 팔지 않습니다.
- 원문 라이선스: `Resources/Onboarding/MaruBuri-OFL.txt`. 반영일: 2026-11-08(고운바탕을 대신함).
- 원본 OTF SHA256: Regular `79451e27328ba230b6b39ab41ac039390fce3de41be2a3f745d5eb8b24f35b90`, SemiBold `18dfd1167d44877a5afc1386db5f09c3ea494ab83a5adf0a64953c43c208dd21`, Bold `8226dcc1e975ba48d8b34cc97417e26712a5a5c3d25a8b18844d72c046d6f85b`.

### 나눔손글씨 펜 (Nanum Pen Script)
- 출처: https://github.com/google/fonts/tree/main/ofl/nanumpenscript
- Copyright (c) 2010, NHN Corporation. SIL Open Font License 1.1.
- 시작하기의 짧은 손글씨 안내에 원본 폰트를 사용합니다. 글꼴을 수정하지 않았으며 원문 라이선스는 `Resources/Onboarding/NanumPenScript-OFL.txt`에 동봉합니다. 앱 내 등록만 하며 시스템 글꼴로 설치하지 않습니다.
- 반영일: 2026-10-07. 원본 TTF SHA256: `6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43`.

### McBopomofo (OpenVanilla)
- 저장소: https://github.com/openvanilla/McBopomofo
- 라이선스: MIT
- 대만어(주음) 입력기. macOS의 TIS(Text Input Services) 입력기 **등록·설치 메커니즘**을 이해하고 구현하는 데 결정적인 참고가 되었습니다. 사인·노타리된 메인 앱이 입력기 번들을 설치하는 패턴이 특히 큰 도움이 되었습니다.
- 2026-11-07 오너 결정으로 MIT 고지를 싣습니다. 대조한 사실은 이렇습니다. 입력기 등록 코드(`Sources/Install/IMEInstaller.swift`)에서 TIS 입력 소스 목록을 훑는 머리 4줄이 McBopomofo의 `InputSourceHelper`와 거의 같고, 그 밖은 직접 구현했습니다. 이 사실을 더 크게도 작게도 적지 않습니다.
- McBopomofo의 MIT 라이선스 원문(저작권 줄과 허가 문구):

```text
MIT License

Copyright (c) 2011-2026 Mengjuei Hsieh et al.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 국립국어원 우리말샘
- https://opendict.korean.go.kr
- 라이선스: CC-BY-SA 2.0 KR — https://creativecommons.org/licenses/by-sa/2.0/kr/ (조항 원문: https://creativecommons.org/licenses/by-sa/2.0/kr/legalcode.ko)
- 영타 자동 변환이 "이 글자가 실존하는 한국어 단어인가"를 판정할 때 쓰는 **표제어 67.7만 개**([`Resources/IM/korean_words.txt`](./Resources/IM/korean_words.txt))의 출처입니다. 우리말의 보고를 모두에게 열어준 국립국어원과 우리말샘 참여자들께 감사드립니다.
- 2026-10-18 일반 명사 확장에서는 기존2026-06-03 원자료의 명사·뜻 번호·뜻 수·외국어 표기를 대조했습니다. 영어 대응은 직접 작성·검토했으며 원문 정의·예문을 제품에 복제하지 않았습니다. 항목별 출처와 직접 작성·대조 수준은 [추가 명사 목록](dict_work/2026-10-18-phonetic-reviewed-nouns.tsv)에 기록했습니다(2026-11-07: 공개되지 않는 문서를 가리키던 링크를 이 목록으로 바꿨습니다).

### 국립국어원 한국어 학습용 어휘 목록
- 출처: https://www.korean.go.kr/front/etcData/etcDataView.do?etc_seq=71
- 공공누리 제1유형(출처 표시). 2026-10-18 명사 보강 후보를 찾고 명사 목록에 속하는지 대조할 때 사용했습니다. 이 목록을 영어 번역 출처로 사용하지 않았습니다.


### New General Service List (NGSL)
- https://www.newgeneralservicelist.com
- 라이선스: CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0/ (조항 원문: https://creativecommons.org/licenses/by-sa/4.0/legalcode) — Browne, C., Culligan, B., & Phillips, J. (2013). *The New General Service List*.
- 하늘키보드는 이 목록을 정렬·필터링하고 굴절형을 골라 `english_common.txt` 등으로 가공했습니다(변경 표시). 가공 방식은 `dict_work/SOURCE_FORMATS.md`와 파일 머리말에 있습니다.
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
- 라이선스: MIT-like — Copyright 2000-2026 by Kevin Atkinson (저작권 고지 유지 조건의 퍼미시브 라이선스)
- **원천 데이터 규모:** size 70 미국식 영어 약 16.7만 단어(현대어와 굴절형 포함). 가공·필터링한 후 broad 영어 사전으로 앱에 탑재합니다. 수십 년간 영어 철자 데이터를 다듬어 공개해 온 Kevin Atkinson과 기여자들(12dicts의 Alan Beale 등)께 감사드립니다.
- 2026-11-07: 아래는 SCOWL/ESDB 공개 저장소(https://github.com/en-wl/wordlist)의 `Copyright` 파일에서 `===` 줄 앞부분을 그대로 옮긴 것입니다. 그 파일은 호주식 영어가 아닌 공식 철자 사전에는 `===` 앞 고지로 충분하고, 크기 80보다 큰 생성 목록에는 `===` 뒤의 고지가 더 적용된다고 적고 있습니다(2026-11-17 그 파일 문구대로 고침). 이 앱이 쓴 목록(size 70, 미국식)에 어느 부분이 해당하는지는 이 문서가 판단하지 않습니다.

```text
Copyright 2000-2026 by Kevin Atkinson

Permission to use, copy, modify, distribute, and sell any part of the English
Speller Database (ESDB, previously known as SCOWLv2), or word lists
created from it, is hereby granted without fee, provided that the above
copyright notice appears in all copies and that both the above copyright
notice and this notice appear in supporting documentation.  Kevin Atkinson
makes no representations about the suitability of this database for any
purpose.  It is provided "as is" without express or implied warranty.

ESDB is derived from many sources, most of which are in the Public Domain.
Data from the Corpus of Contemporary American English (COCA) was also used.

All data from COCA comes from 3-gram data that is not freely available;
however, the usage is within the rights given by the NDA that was signed when
purchasing the data.  More information on COCA is available at
https://www.english-corpora.org/coca/.

The primary source of words for ESDB comes from 12dicts and ENABLE2K.  Both
are in the Public Domain, but Alan Beale <biljir@pobox.com> deserves special
credit as he is the author of 12dicts and a major contributor to ENABLE2K.  In
addition, he gave me an incredible amount of feedback and created a number of
special lists in order to help improve the overall quality of ESDB.
```

### 가공 후 앱 탑재 규모

2026-11-07부터 입력기는 아래 사전 파일을 하나씩 읽지 않고, 영어 사전 여섯 개를 합쳐 정렬한 표 `english_bundled.txt` 하나로 찾습니다(`dict_work/dict_manifest.tsv`가 합칠 목록의 정본이고, 낱말 수는 표 머리말의 `count`에 있습니다). 이 표에는 새로 배포하는 낱말이 없고 이미 배포하던 낱말을 합친 것입니다. 표를 만든 원본 중 `english_supplement.txt`·`english_common.txt` 둘은 입력기 번들에 그대로도 들어 있고, 나머지 넷은 표로만 들어갑니다. macOS의 `/usr/share/dict/words`는 이 표에 복사하지 않고, 입력기가 시스템 파일을 그 자리에서 읽습니다.

낱말 수는 사전을 고칠 때마다 바뀌므로 아래 표에 적지 않습니다. 저장소의 각 파일은 `grep -vc '^#' <파일>`로 셀 수 있고, 합친 표의 전체 수는 `english_bundled.txt` 머리말의 `count` 줄에 있습니다(2026-11-16 #259: 옛 숫자가 남아 있어 바꿨습니다).

| 원본 사전 파일(저장소) | 구성 |
|---|---|
| `english_names.txt` | Census 성씨와 SSA 이름을 가공·필터링한 목록 |
| `english_modern.txt` | SCOWL size 70을 가공·필터링한 목록 |
| `english_names_extra.txt` | 수작업 보충 목록. Census/SSA 출처가 아닌, 유명인·이름·제품·기술 약어를 수작업으로 선별한 목록. 2026-11-07 오너 결정으로 약어 7개(`ansi`·`goty`·`emtek`·`totp`·`algo`·`rhel`·`gorm`)가 이 목록으로 내려왔고, 2026-11-13(#225)부터 요일·달·나라·국적·언어 이름이 들어 있습니다 |

### GeoNames — 전 세계 지명 데이터
- https://www.geonames.org
- 라이선스: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- 영타 자동 변환의 **지명 사전**(북미·유럽 7개국 — 미국·캐나다·멕시코·영국·프랑스·스페인·이탈리아 — 의 주/도 + 인구 5만+ 도시, [`Resources/IM/english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt)에 포함)의 출처입니다. 전 세계 지명을 자유롭게 열어준 GeoNames와 기여자들께 감사드립니다.

### Wikidata (Wikimedia)
- https://www.wikidata.org
- 라이선스: CC0 1.0 (퍼블릭 도메인)
- 영타 자동 변환의 **축구 클럽·선수 사전**(잉글랜드·프랑스·스페인·이탈리아 9개 리그)의 출처입니다. 구조화된 지식을 퍼블릭 도메인으로 공개한 Wikidata 커뮤니티에 감사드립니다.
- 2026-10-18 명사 보강에서는 후보의 한국어·영어 명칭/별칭을 보조 대조했습니다. 구조화된 명칭은 CC0이며 설명문·이미지는 복제하지 않았습니다. 항목별 링크와 직접 작성/대조 수준은 [추가 목록](dict_work/2026-10-18-phonetic-reviewed-nouns.tsv)에 기록했습니다.

## 개발에 함께한 도구

### Anthropic — Claude
- https://claude.com/claude-code
- 설계 논의, 디버깅, 문서 작성 등 개발 과정 전반에 함께했습니다.

### OpenAI — Codex
- https://openai.com/codex/
- 코드 리뷰 위주로 사용했습니다.

## 참고한 오픈소스 입력기

plist·entitlements 구조와 IME 아키텍처를 비교·학습하는 데 참고했습니다.

- [macSKK](https://github.com/mtgto/macSKK) — Swift, 일본어 SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, 일본어, MIT

## 그리고

이 작은 키보드 하나에도 운영체제, 컴파일러, 언어, 폰트, 수십 년에 걸친 한글 입력 연구, 그리고 셀 수 없이 많은 오픈소스가 녹아 있습니다. 인류가 함께 쌓아 올린 그 모든 지식과 도구에 깊이 감사드립니다.

— Hyunjin Cho

---

# Acknowledgements (English)

> Updated: 2026-11-17 (first added in the 2026-05-27 initial release and rewritten on 2026-10-10. On 2026-11-07 the dictionary bundling note, license texts and the McBopomofo notice were revised; on 2026-11-08 the fonts changed from Gowun Batang to MaruBuri; on 2026-11-13 the place-name coverage and the supplement list description were corrected, and the development tools section was left with only the tool that actually co-developed the project, Claude. On 2026-11-16 changing entry counts were replaced with where to find them (#259). On 2026-11-17 this English half was rewritten to match the Korean half section by section, the header dates were corrected, and Codex was added to the development tools for code review (#263). The same day, source file paths were updated for the folder reorganization (#267).)

HaneulKeyboard was not made alone. It stands on the shoulders of the countless open-source projects and tools that paved the way, and of the people who made them possible.

## HaneulKeyboard code and original attribution

- Current application code: Apache License 2.0. The full text is in `LICENSE`; the original project name and address are in `NOTICE`.
- Original: **HaneulKeyboard (하늘키보드)** · Copyright (c) 2026 Hyunjin Cho · https://github.com/Hyunjin-Cho/HaneulKeyboard
- The notice for earlier MIT releases is kept in `LICENSES/HaneulKeyboard-MIT-legacy.txt` in the source and in `HaneulKeyboard-MIT-legacy.txt` in the app and IME resources. The terms of earlier MIT releases are not changed retroactively.
- The third-party code, dictionaries and fonts below keep their own licenses. Changing the app code's license does not move them to Apache.
- Where this is applied: the resources of both targets in `project.yml`, and `scripts/verify_license_resources.py`. The main app and the installed IME both bundle LICENSE, NOTICE, this acknowledgements file and the historical MIT notice.

## Projects that helped directly


### MaruBuri
- Source: NAVER Hangeul Hangeul Areumdapge, https://hangeul.naver.com/font (official distribution file `maruburi.zip`).
- Copyright © NAVER Corp. & NAVER Cultural Foundation. SIL Open Font License 1.1 (NAVER font license).
- The unmodified Regular, SemiBold and Bold OTF files are used for all text in the app (titles, descriptions, buttons) and for the lettering inside the risograph artwork. They are registered only within the app and are not installed on the system. The font files are not sold separately.
- Full license: `Resources/Onboarding/MaruBuri-OFL.txt`. Applied 2026-11-08 (replaces Gowun Batang).
- Original OTF SHA256: Regular `79451e27328ba230b6b39ab41ac039390fce3de41be2a3f745d5eb8b24f35b90`, SemiBold `18dfd1167d44877a5afc1386db5f09c3ea494ab83a5adf0a64953c43c208dd21`, Bold `8226dcc1e975ba48d8b34cc97417e26712a5a5c3d25a8b18844d72c046d6f85b`.

### Nanum Pen Script
- Source: https://github.com/google/fonts/tree/main/ofl/nanumpenscript
- Copyright (c) 2010, NHN Corporation. SIL Open Font License 1.1.
- The original font is used for short handwritten cues in the Getting Started guide. The font is not modified, and the full license is bundled at `Resources/Onboarding/NanumPenScript-OFL.txt`. It is registered only within the app and is not installed as a system font.
- Applied 2026-10-07. Original TTF SHA256: `6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43`.

### McBopomofo (OpenVanilla)
- Repository: https://github.com/openvanilla/McBopomofo
- License: MIT
- A Bopomofo (Zhuyin) input method for Taiwanese Mandarin. It was a decisive reference for understanding and implementing how a macOS TIS (Text Input Services) input method is **registered and installed**. The pattern of a signed, notarized main app installing the IME bundle helped especially.
- By the owner's decision on 2026-11-07 its MIT notice is included. What a comparison found: in our IME registration code (`Sources/Install/IMEInstaller.swift`), the first four lines of the loop that walks the TIS input source list are nearly identical to McBopomofo's `InputSourceHelper`; the rest is our own implementation. This is stated neither larger nor smaller than that.
- McBopomofo's MIT license text (copyright line and permission notice):

```text
MIT License

Copyright (c) 2011-2026 Mengjuei Hsieh et al.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Urimalsaem (National Institute of Korean Language)
- https://opendict.korean.go.kr
- License: CC-BY-SA 2.0 KR — https://creativecommons.org/licenses/by-sa/2.0/kr/ (legal code: https://creativecommons.org/licenses/by-sa/2.0/kr/legalcode.ko)
- Source of the **677k headwords** ([`Resources/IM/korean_words.txt`](./Resources/IM/korean_words.txt)) that the wrong-layout auto-conversion uses to decide "is this a real Korean word?". Thanks to the National Institute of Korean Language and the Urimalsaem contributors for opening this treasury of the Korean language to everyone.
- For the 2026-10-18 common-noun expansion, the nouns, sense numbers, sense counts and foreign-language notations in the existing 2026-06-03 source data were cross-checked. The English mappings were written and reviewed by us; definitions and examples are not copied into the product. Per-entry sources and the level of direct authoring or cross-checking are recorded in the [added noun list](dict_work/2026-10-18-phonetic-reviewed-nouns.tsv) (2026-11-07: a link to an unpublished document was replaced with this list).

### NIKL Korean vocabulary list for learners
- Source: https://www.korean.go.kr/front/etcData/etcDataView.do?etc_seq=71
- KOGL Type 1 (attribution). Used on 2026-10-18 to find candidates for the noun expansion and to check whether they belong to the noun list. This list was not used as a source for English translations.


### New General Service List (NGSL)
- https://www.newgeneralservicelist.com
- License: CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0/ (legal code: https://creativecommons.org/licenses/by-sa/4.0/legalcode) — Browne, C., Culligan, B., & Phillips, J. (2013). *The New General Service List*.
- HaneulKeyboard sorted and filtered this list and selected inflected forms to produce `english_common.txt` and related files (changes indicated). The method is in `dict_work/SOURCE_FORMATS.md` and the file headers.
- Source of the **2,809 high-frequency modern English lemmas** (10k+ word forms including inflections) that the wrong-layout auto-conversion uses to decide "is this input a real English word?". Thanks to the three researchers who published this data for English learners.

### US Census Bureau — 2010 Census surnames
- https://www.census.gov/topics/population/genealogy/data/2010_surnames.html
- License: Public Domain (US federal government work)
- **Source size:** about 162k surnames (those held by 100 or more people in 2010). After processing and filtering, they are bundled together with SSA first names.

### US Social Security Administration (SSA) — Baby Names
- https://www.ssa.gov/oact/babynames/
- License: Public Domain (US federal government work)
- Source of the **first-name data** (yearly birth registrations since 1880) used to recognize personal names in the wrong-layout auto-conversion.

### SCOWL / ESDB (English Speller Database) — Kevin Atkinson
- https://wordlist.aspell.net
- License: MIT-like — Copyright 2000-2026 by Kevin Atkinson (a permissive license that requires keeping the copyright notice)
- **Source size:** about 167k words in the size-70 American English list (modern words and inflected forms included). After processing and filtering, it is bundled as the broad English dictionary. Thanks to Kevin Atkinson and the contributors (including Alan Beale of 12dicts) for decades of curating and publishing English spelling data.
- 2026-11-07: The notice below is the part before the `===` line in the `Copyright` file of the public SCOWL/ESDB repository (https://github.com/en-wl/wordlist), copied verbatim. That file says the notice before `===` is sufficient for an official speller dictionary that is not Australian English, and that the notices after `===` also apply to a generated word list larger than 80 (2026-11-17: reworded to follow that file). This document does not decide which part applies to the list this app used (size 70, US spelling).

```text
Copyright 2000-2026 by Kevin Atkinson

Permission to use, copy, modify, distribute, and sell any part of the English
Speller Database (ESDB, previously known as SCOWLv2), or word lists
created from it, is hereby granted without fee, provided that the above
copyright notice appears in all copies and that both the above copyright
notice and this notice appear in supporting documentation.  Kevin Atkinson
makes no representations about the suitability of this database for any
purpose.  It is provided "as is" without express or implied warranty.

ESDB is derived from many sources, most of which are in the Public Domain.
Data from the Corpus of Contemporary American English (COCA) was also used.

All data from COCA comes from 3-gram data that is not freely available;
however, the usage is within the rights given by the NDA that was signed when
purchasing the data.  More information on COCA is available at
https://www.english-corpora.org/coca/.

The primary source of words for ESDB comes from 12dicts and ENABLE2K.  Both
are in the Public Domain, but Alan Beale <biljir@pobox.com> deserves special
credit as he is the author of 12dicts and a major contributor to ENABLE2K.  In
addition, he gave me an incredible amount of feedback and created a number of
special lists in order to help improve the overall quality of ESDB.
```

### Bundled size after processing

Since 2026-11-07 the IME no longer reads the dictionary files below one by one; it looks words up in a single sorted table, `english_bundled.txt`, that merges six English dictionaries (`dict_work/dict_manifest.tsv` is the authoritative list of what is merged, and the word count is in the table header's `count`). The table distributes no new words; it merges words that were already distributed. Of its sources, `english_supplement.txt` and `english_common.txt` are also bundled in the IME as they are, and the other four are bundled only through the table. macOS's `/usr/share/dict/words` is not copied into this table; the IME reads that system file in place.

Entry counts change whenever the dictionaries are edited, so they are not written in the table below. Count a file in the repository with `grep -vc '^#' <file>`; the merged table's total is the `count` line in the `english_bundled.txt` header (2026-11-16, #259: an outdated number had been left here).

| Source dictionary file (repository) | Contents |
|---|---|
| `english_names.txt` | Census surnames and SSA first names, processed and filtered |
| `english_modern.txt` | SCOWL size 70, processed and filtered |
| `english_names_extra.txt` | Hand-curated supplement. Not sourced from Census/SSA: a hand-picked list of well-known people, names, products and technical abbreviations. By owner decision on 2026-11-07 seven abbreviations (`ansi`, `goty`, `emtek`, `totp`, `algo`, `rhel`, `gorm`) moved into this list, and since 2026-11-13 (#225) it also holds the names of weekdays, months, countries, nationalities and languages |

### GeoNames — worldwide place names
- https://www.geonames.org
- License: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- Source of the **place-name dictionary** for the wrong-layout auto-conversion (states/provinces and cities with a population of 50k+ in seven North American and European countries — US, Canada, Mexico, UK, France, Spain, Italy — included in [`Resources/IM/english_sports_geo.txt`](./Resources/IM/english_sports_geo.txt)). Thanks to GeoNames and its contributors for opening the world's place names freely.

### Wikidata (Wikimedia)
- https://www.wikidata.org
- License: CC0 1.0 (public domain)
- Source of the **football club and player dictionary** (9 leagues across England, France, Spain and Italy) for the wrong-layout auto-conversion. Thanks to the Wikidata community for publishing structured knowledge in the public domain.
- For the 2026-10-18 noun expansion, the Korean and English labels and aliases of candidates were used as a secondary cross-check. Structured labels are CC0; descriptions and images were not copied. Per-entry links and the level of direct authoring or cross-checking are recorded in the [added list](dict_work/2026-10-18-phonetic-reviewed-nouns.tsv).

## Tools used in development

### Anthropic — Claude
- https://claude.com/claude-code
- A companion throughout development — design discussions, debugging and documentation.

### OpenAI — Codex
- https://openai.com/codex/
- Used mainly for code review.

## Open-source input methods studied for reference

Used to compare and learn plist and entitlements structure and IME architecture.

- [macSKK](https://github.com/mtgto/macSKK) — Swift, Japanese SKK, GPL-3.0
- [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) — Swift, Japanese, MIT

## And

Even this one small keyboard carries operating systems, compilers, programming languages, fonts, decades of Hangul input research, and countless open-source projects. Deep gratitude for all the knowledge and tools that humanity has built together.

— Hyunjin Cho

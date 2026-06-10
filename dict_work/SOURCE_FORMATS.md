# 영어 사전 소스 파일 형식 명세

> 영어 사전 현대화(ROADMAP 1순위)용 원본 데이터의 정확한 형식 기록.
> `scripts/build_english_wordlists.py`(코더 작성)가 이 명세를 참조해 파서를 맞춘다.
> 원본 저장 위치: `~/Downloads/HaneulDictSources/` (레포 밖 — 가공 결과만 리뷰 후 번들).
> 다운로드 일자: 2026-06-10. SHA-256은 아래 각 절에 기재.

## 공통 주의

- **소스 1~3(NGSL·Census·SSA)은 모든 파일이 CRLF(`\r\n`) 줄바꿈** — 파서에서 `\r` strip 필수.
  **소스 4(SCOWL)는 LF(`\n`)** (tar.gz Unix EOL판으로 받았기 때문). 파서는 양쪽 다 안전하게
  `rstrip('\r\n')` 권장.
- 모든 파일 ASCII (BOM 없음, 비ASCII 문자 없음 확인됨). SCOWL은 diacritic strip 옵션으로 ASCII 보장.

---

## 1. NGSL 1.2 (New General Service List)

- 출처: 공식 사이트 직접 호스팅 `https://www.newgeneralservicelist.com/s/<파일명>`
  (Google Drive 아님 — Squarespace 자체 호스팅이라 CLI 직접 다운로드 가능했음)
- 라이선스: **CC BY-SA 4.0** (공식 페이지 명시: "Browne, C., Culligan, B., and Phillips, J. is
  licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.")
- 인용: Browne, C., Culligan, B., & Phillips, J. (2013). *The New General Service List*.
  http://www.newgeneralservicelist.com
- 규모: **lemma 2,809개** (공식 발표 수치와 일치 확인). 굴절형 포함 시 10,126 형태
  (소문자화 중복 제거 후 10,121).

### 1a. `NGSL_12_stats.csv` — 빈도 통계 (★ 가공의 기준 파일로 추천)

```
Lemma,SFI Rank,SFI,Adjusted Frequency per Million (U)
the,1,87.85,60910
be,2,86.86,48575
```

- SHA-256: `2098bab8955a120a9766c6282a51d7d578c6cb0a7d946600d2ffb73ba25a0b44` (62,566 bytes)
- 헤더 1줄 + 데이터 2,809행 = 총 2,810줄.
- 컬럼: `Lemma`(소문자), `SFI Rank`(1~2809), `SFI`(Standard Frequency Index, float),
  `Adjusted Frequency per Million (U)`(정수).
- **빈도 내림차순 정렬** — top-N 컷이 필요하면 이 파일 한 장으로 충분.

### 1b. `NGSL_12_lemmatized_for_research.csv` — lemma + 전체 굴절형

```
a,an
abandon,abandons,abandoned,abandoning,abandonings
```

- SHA-256: `d814f2a0a3c61479a2c5ad037661719a0cc6e7dbcde31f181b54f12d0f1e11a4` (89,485 bytes)
- 구조: `##`로 시작하는 주석 15줄 → 빈 줄 1 → 데이터 2,809행. 알파벳순 정렬.
- 행 형식: `headword,굴절형1,굴절형2,...` — **행마다 컬럼 수 가변**. 헤더 행 없음.
- 주의: 연구용이라 실존 빈도가 극히 낮은 이론적 굴절형(`abandonings`, `abouts` 등)도 포함.
  broad 사전에 넣을 땐 그대로 써도 무방하나, curated에는 부적합.
- 주의: 동철이의어(homograph)는 별도 처리 없이 한 행 — found(FIND 과거형/설립하다) 등.

### 1c. `NGSL_12_lemmatized_for_teaching.csv` — lemma + 통용 굴절형 (curated 후보)

- SHA-256: `b54e297244988237457e04f823aa8dca68e3d646938dc76d383e099f04cb7666` (73,146 bytes)
- 구조: `##` 주석 12줄 → 빈 줄 1 → 데이터 2,809행. 형식은 1b와 동일(가변 컬럼).
- 1b와 차이: 실제로 쓰이는 굴절형만 수록 (`abandon,abandons,abandoned,abandoning` —
  `abandonings` 없음). 동철이의어는 여러 행에 중복 등장 가능 (found/left/mine 등).

### 1d. `NGSL_12_alphabetized_description.txt` — 단어 목록 + 1.01→1.2 변경 이력

- SHA-256: `8056a5252576ddc5a3c2e96b1422eb2bc7991bdc527ecb2e00181fadff51d9dc` (24,546 bytes)
- 구조: 1~18행 설명문+변경표(탭 구분) → 19행 빈 줄 → **20행부터 한 줄 1단어** 2,809개(알파벳순).
- lemma만 필요하면 이 파일이 가장 단순하나, 빈도가 없으므로 stats.csv 권장.

### 검증 결과 (2026-06-10)

| 단어 | NGSL 수록 | 비고 |
|---|---|---|
| city | ✅ (rank 269) | 사용자 보고 케이스 해결 |
| with | ✅ (rank 18) | |
| and | ✅ (rank 3) | |
| about | ✅ (rank 37) | |
| world | ✅ (rank 156) | |
| **playlist** | ❌ 없음 | 예상대로 — supplement 수동 추가 필요 |
| **internet** | ❌ 없음 | 의외 누락 — supplement 수동 추가 권장 |
| computer/email/online/website/video/music/movie | ✅ | 현대어 커버 양호 |

---

## 2. US Census 2010 성씨 (`census2010/Names_2010Census.csv`)

- 출처: `https://www2.census.gov/topics/genealogy/2010surnames/names.zip` (직링크 정상 동작)
- 라이선스: **Public Domain** (미 연방정부 저작물, 17 U.S.C. §105)
- zip SHA-256: `117c41cb4668727b7627b2845b6df3f83eb2a22a1813f42c0ff4bdcab86de135` (12,874,389 bytes)
- zip 내용: `Names_2010Census.csv`(9.4MB) + `Names_2010Census.xlsx`(11.5MB, 동일 데이터 Excel판
  — zip 안에 보존, CSV만 추출)

```
name,rank,count,prop100k,cum_prop100k,pctwhite,pctblack,pctapi,pctaian,pct2prace,pcthispanic
SMITH,1,2442977,828.19,828.19,70.9,23.11,0.5,0.89,2.19,2.4
```

- 헤더 1줄 + 데이터 162,254행. **마지막 행은 `ALL OTHER NAMES`(rank 0) 집계행 — 반드시 제외**
  → 실제 성씨 **162,253개**.
- `name`: **전부 대문자 A–Z만** (하이픈·공백·아포스트로피 없음 — 정규식 `^[A-Z]+$` 전수 통과).
- `count`: 2010년 인구. **100 이상만 공개** (min=100인 성씨 1,279개 / max=2,442,977 SMITH).
- 인종 비율 컬럼(pct*)에 `(S)`(suppressed) 문자열 존재 — 숫자 파싱 시 주의 (name/rank/count만
  쓰면 무관).
- count 분포 (top-N 컷 설계용):

| 컷 | 그 순위 성씨의 count |
|---|---|
| top 1,000 | ≥ 34,949 |
| top 10,000 | ≥ 3,224 |
| top 30,000 | ≥ 783 |
| top 50,000 | ≥ 419 |
| top 100,000 | ≥ 181 |
| 전체 162,253 | ≥ 100 |

---

## 3. SSA Baby Names (`ssa_names/yob1880.txt` ~ `yob2025.txt`)

- 출처: `https://www.ssa.gov/oact/babynames/names.zip`
  (⚠️ Akamai가 plain curl을 403 차단 — **Referer: `https://www.ssa.gov/oact/babynames/limits.html`
  헤더 + 브라우저 UA를 함께 보내야 통과**. 재현 시 참고.)
- 라이선스: **Public Domain** (미 연방정부 저작물)
- zip SHA-256: `cd78e975ed7bb358e018dd62fbe14ced89295e9581c49172ca4eedcb011b3724` (7,860,026 bytes)
- zip 내용: `yob1880.txt`~`yob2025.txt` 146개 + `NationalReadMe.pdf`(설명서) — txt만 추출.

```
Olivia,F,13544
Charlotte,F,13400
```

- **헤더 없음.** 컬럼: `이름,성별(F/M),해당 연도 출생 수`.
- 파일 내 정렬: **F 블록 전체 → M 블록 전체**, 각 블록 내 count 내림차순.
  (예: yob2025 = F 17,297행 + M 13,930행 = 31,227행)
- 이름: Capitalized(첫 글자만 대문자), **순수 알파벳만**(하이픈·공백 없음, `^[A-Za-z]+$` 전수
  통과), 길이 2~15자.
- **연간 출생 5명 미만 이름은 미수록** (privacy floor — 파일 내 min count=5).
- 같은 이름이 F/M 양쪽에 등장 가능 → 단어 목록 용도로는 이름 기준 합산 필요.
- 다년 집계 통계 (소문자화 dedup):

| 집계 범위 | 고유 이름 수 |
|---|---|
| 전체 1880–2025 | 105,966 |
| 최근 30년 1996–2025 | 80,329 |
| 전체 합산 count ≥ 1,000 | 11,872 |
| 전체 합산 count ≥ 10,000 | 2,808 |

---

## 4. SCOWL / ESDB size-70 미국식 단어 목록 (`SCOWL-wl/words.txt`)

> 사용자 결정(2026-06-10)으로 broad 사전 보강에 추가된 4번째 소스.

- 출처 (공식 커스텀 생성기, GET 파라미터가 곧 재현 레시피):
  `https://app.aspell.net/create?max_size=70&spelling=US&variant_level=0&diacritic=strip&encoding=utf-8&format=tar.gz&download=wordlist`
  - ⚠️ `special`(hacker·roman-numerals) 체크박스는 **파라미터를 아예 안 보내면 제외**됨
    (HTML 폼 규칙). 동봉 README에 `Special: <none>`으로 적용 확인.
- 버전: **ESDB Git Revision `94569af` (2026-05-11)** / App `4364246` (2026-05-29).
  2026년 2월부터 SCOWLv1이 **ESDB(English Speller Database, 구 SCOWLv2)**로 개편 —
  릴리스 번호 대신 git revision으로 식별. 같은 파라미터라도 revision이 다르면 내용이
  달라질 수 있으므로 재다운로드 시 동봉 README의 revision을 함께 기록할 것.
- 라이선스: **MIT-like** (동봉 README에 전문 수록) — `Copyright 2000-2026 by Kevin Atkinson`.
  "Permission to use, copy, modify, distribute, and sell ... provided that the above copyright
  notice appears in all copies ..." — 저작권 고지 유지 조건의 퍼미시브.
  - 데이터 출처 고지: 대부분 Public Domain(12dicts·ENABLE2K 등) + **COCA 3-gram 파생 데이터
    포함**(원본 비공개지만 작성자 NDA 권리 내 사용 — 결과 wordlist 재배포는 위 라이선스로 허용 명시).
- tar.gz SHA-256: `a960df7ac6c3b80421b04c68a606604807beeb5efb724032bb4b5c1baa7cfdc9` (458,919 bytes,
  `scowl_wordlist_70_US.tar.gz`)
- 내용 3파일 (전수 확인 — 전부 텍스트, 실행물 없음): `SCOWL-wl/README`(생성 파라미터+라이선스),
  `SCOWL-wl/README_SCOWL.md`(ESDB 설명), `SCOWL-wl/words.txt`(단어 목록).
- words.txt SHA-256: `930b538f9ca80ca94b28aa621a1323e0518988c7c7c92c39444b6de584c9ee80` (1,625,746 bytes)

```
A
A's
AA
...
zymotic
zymurgy
```

- **헤더 없음, 한 줄 1단어, LF 줄바꿈**, 알파벳순(대문자 블록 우선). 빈 줄·중복 0.
- 문자 구성: **`^[A-Za-z']+$` 전수 통과** — 하이픈·공백·마침표·비ASCII 0개.
  (ESDB 본체는 복합어·trailing-dot 약어도 갖지만 wordlist 출력에는 미포함.)

| 통계 (2026-06-10) | 값 |
|---|---|
| 총 단어 | **167,335** |
| 소문자화 dedup | 164,462 |
| 아포스트로피 포함 (가공 시 제외 대상) | 22,718 (소유격 `'s`형 22,576 + I'm·don't류 축약 142) |
| 대문자 시작 (고유명사·약어) | 28,238 |
| 순수 소문자 `^[a-z]+$` | 127,002 |
| **web2(/usr/share/dict/words) 대비 신규** (소문자 비교, 아포스트로피 제외) | **75,665** (≈ 745KB, 실질 번들 증가분) |
| 〃 (아포스트로피 포함 전체) | 97,850 |

- 신규분의 상당수가 **굴절형**(boosts·reconnected·surfing — web2는 1934년판이라 굴절형 부재)
  → exact-match인 broad(MAIN) 경로에 특히 효과적.
- ⚠️ 신규분 중 2글자 이하 275개는 대부분 약어(ac·bb·cd·cm 등) — 가공 시 길이 필터 검토.

### 현대어 검증 (2026-06-10)

| 단어 | SCOWL 70 | 비고 |
|---|---|---|
| **playlist / internet** | ✅ (+playlists) | NGSL 누락분 해결 — supplement 수동 추가 불필요해짐 |
| selfie / email / blog / online / website / app / podcast / emoji | ✅ 전부 (굴절형 selfies·emails·blogs·apps·podcasts·emojis 포함) | |
| city / with (sanity) | ✅ | |

---

## 가공 시 참고 (제안 — 결정은 리뷰에서)

- **curated(clean-hangul 경로)**: NGSL stats.csv 기준 top-N + teaching 굴절형. 한국어 충돌 스윕
  (우리말샘 veto 파이프라인 재사용) 필수.
- **broad(깨진-hangul 경로)**: NGSL 전체 굴절형(research) + Census top-N 성씨 + SSA 합산 상위
  이름 + **SCOWL 70/US**(아포스트로피 단어 제외·소문자 정규화 — web2 대비 +75,665어, §4).
  깨진 한글 경로는 구조적으로 안전하므로 폭넓게.
- Census는 대문자, SSA는 Capitalized → 양쪽 다 소문자 정규화 필요.
- `Resources/IM/english_names_extra.txt`: 위 두 소스(미국 중심)가 못 덮는 국제 유명인 단어 시드 50개 — 검역(전원 Tier C) 후 머지된 최종본 (초안 파일은 정리됨).

## 부록: exclusions 정본 위치 (2026-06-10)

검역 탈락 결정 기록의 정본은 이 폴더에 보존된다 — `~/Downloads/HaneulDictSources/`는
재다운로드 가능한 원본+재생성 가능한 검역 CSV뿐이므로 통째로 지워도 된다.
- `dict_work/exclusions.txt` — theory(소대교 충돌) + 인명 전부-자모 2,685
- `dict_work/scowl_exclusions_alljamo4.txt` — SCOWL ≤4자모 전부-자모 826 (btw·lol류)
재생성 시: `build_english_wordlists.py --exclude dict_work/exclusions.txt`,
SCOWL diff에는 `comm -23 ... dict_work/scowl_exclusions_alljamo4.txt` (위 §4 레시피).

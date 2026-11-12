#!/usr/bin/env python3
"""북미/유럽 지명(GeoNames CC-BY) + 9리그 축구 클럽·선수(Wikidata CC0) 토큰 추출.
검역(audit) 전 raw 후보 단어를 생성한다. Resources/IM/english_sports_geo.txt의 출처 스크립트.

2026-11-13 (#225, 리뷰 english-dict-F-5): 저장소 밖 `~/Downloads/HaneulDictSources/extract_sports_geo.py`
(2026-06-20, SHA-256 708c321b...8e15005c)를 옮겼다. 추출 규칙은 그대로이고 바꾼 것은 셋이다.
  - 경로를 인자로 받는다(--srcdir). 원본 데이터는 지금처럼 저장소 밖에 둔다.
  - Wikidata 요청의 User-Agent에서 개인 연락처를 뺐다(공개 저장소). 연락처가 필요하면
    실행할 때 환경 변수 HANEUL_DICT_USER_AGENT로 준다.
  - 모듈을 불러오기만 해서는 아무것도 하지 않게 main()으로 감쌌다. --geonames-only는 네트워크 없이
    GeoNames 부분만 다시 만든다(2026-11-13 이 Mac에서 원본 sports_geo_raw.txt에 모두 들어 있는 것을 확인했다).

⚠️ 네트워크: Wikidata SPARQL(query.wikidata.org)에 질의한다(시스템 curl). 시험·빌드에서 돌리지 않는다.

선수 필터(사용자 결정): 토큰이 (정확히 5자 & 두벌식 모음키 yuiophjklbnm 시작)
또는 (6자 이상)일 때만 채택 — 모음 시작/긴 길이로 한국어 충돌을 구조적으로 회피.

뒤 단계(이 스크립트 밖, 절차 정본은 dict_work/SOURCE_FORMATS.md §5):
  scripts/audit_wordlist.sh --candidates <srcdir>/sports_geo_raw.txt --role broad --out <csv>
  → class가 all_jamo(완성 음절 0)인 줄을 뺀 나머지가 english_sports_geo.txt 본문이다.
  → 그 뒤 scripts/build_english_table.py로 번들 표를 다시 만든다.

사용:
  scripts/extract_sports_geo.py                      # 기본 --srcdir ~/Downloads/HaneulDictSources
  scripts/extract_sports_geo.py --geonames-only      # 네트워크 없이 GeoNames 부분만
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse

UA = os.environ.get("HANEUL_DICT_USER_AGENT", "HaneulKeyboard-dict/1.0")
COUNTRIES = {"US", "CA", "MX", "GB", "FR", "ES", "IT"}
LEAGUES = {
    "PL": "Q9448", "Championship": "Q19510", "LeagueOne": "Q19565",
    "Ligue1": "Q13394", "Ligue2": "Q217374",
    "LaLiga": "Q324867", "LaLiga2": "Q35615",
    "SerieA": "Q15804", "SerieB": "Q194052",
}
VOWEL = set("yuiophjklbnm")  # 두벌식에서 모음인 키들
ABBREV = {"esc", "ctrl", "alt", "var", "ufc"}


def sparql(q):
    # macOS Python의 SSL 인증서 이슈 회피 — 시스템 curl로 호출.
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": q, "format": "json"})
    r = subprocess.run(
        ["curl", "-s", "-H", f"User-Agent: {UA}", "-H", "Accept: application/json", url],
        capture_output=True, text=True, timeout=180,
    )
    return json.loads(r.stdout)["results"]["bindings"]


def toks(label):
    out = []
    for t in re.split(r"[ \-]", label.lower()):
        t = re.sub(r"[^a-z]", "", t)
        if t:
            out.append(t)
    return out


def geonames(geo):
    states, cities = set(), set()
    # 1) GeoNames 주/도
    with open(f"{geo}/admin1CodesASCII.txt", encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            if len(c) >= 2 and c[0].split(".")[0] in COUNTRIES:
                states.update(toks(c[1]))
    # 2) GeoNames 도시 (인구 5만+)
    with open(f"{geo}/cities15000.txt", encoding="utf-8") as f:
        for line in f:
            c = line.split("\t")
            if len(c) >= 15 and c[8] in COUNTRIES and c[14].isdigit() and int(c[14]) >= 50000:
                cities.update(toks(c[2]))
    return states, cities


def wikidata():
    clubs, players = set(), set()
    # 3) Wikidata 9리그 클럽
    for name, qid in LEAGUES.items():
        q = f'SELECT DISTINCT ?l WHERE {{ ?c wdt:P31 wd:Q476028; wdt:P118 wd:{qid}; rdfs:label ?l. FILTER(LANG(?l)="en") }}'
        try:
            rows = sparql(q)
            for r in rows:
                clubs.update(toks(r["l"]["value"]))
            print(f"  클럽 {name}: {len(rows)} clubs", file=sys.stderr)
        except Exception as e:
            print(f"  클럽 {name} 실패: {e}", file=sys.stderr)
    # 4) Wikidata 9리그 선수 (필터)
    for name, qid in LEAGUES.items():
        q = f'SELECT DISTINCT ?l WHERE {{ ?c wdt:P31 wd:Q476028; wdt:P118 wd:{qid}. ?p wdt:P54 ?c; wdt:P31 wd:Q5; rdfs:label ?l. FILTER(LANG(?l)="en") }}'
        try:
            rows = sparql(q)
            for r in rows:
                for t in toks(r["l"]["value"]):
                    if (len(t) == 5 and t[0] in VOWEL) or len(t) >= 6:
                        players.add(t)
            print(f"  선수 {name}: {len(rows)} rows", file=sys.stderr)
        except Exception as e:
            print(f"  선수 {name} 실패: {e}", file=sys.stderr)
    return clubs, players


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--srcdir", default=os.path.expanduser("~/Downloads/HaneulDictSources"),
                    help="원본 폴더 (geonames/ 하위 폴더를 읽고 sports_geo_raw.txt를 쓴다)")
    ap.add_argument("--out", help="출력 파일 (기본: <srcdir>/sports_geo_raw.txt)")
    ap.add_argument("--geonames-only", action="store_true", help="네트워크 없이 GeoNames 부분(+약어)만")
    args = ap.parse_args()

    geo = os.path.join(args.srcdir, "geonames")
    out = args.out or os.path.join(args.srcdir, "sports_geo_raw.txt")
    states, cities = geonames(geo)
    clubs, players = (set(), set()) if args.geonames_only else wikidata()

    allwords = states | cities | clubs | players | ABBREV
    with open(out, "w", encoding="utf-8") as w:
        for word in sorted(allwords):
            w.write(word + "\n")

    print("\n=== 추출 완료 ===")
    print(f"  주/도:{len(states)}  도시:{len(cities)}  클럽토큰:{len(clubs)}  선수토큰:{len(players)}  약어:{len(ABBREV)}")
    print(f"  합집합(중복제거): {len(allwords)}")
    print(f"  → {out}")


if __name__ == "__main__":
    main()

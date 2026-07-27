#!/usr/bin/env python3
"""다운로드된 원본(NGSL·US Census 성씨·SSA 이름)을 IME 후보 사전 txt로 가공한다.

원본 다운로드는 별도 담당 — 이 스크립트는 아무것도 다운로드하지 않는다.
  ~/Downloads/HaneulDictSources/
    ├── *NGSL*.(csv|txt|tsv)   — NGSL lemma 2,809개 (CC BY-SA 4.0)
    ├── *Census*.csv           — US Census 2010 성씨 (헤더: name,rank,count,…)
    └── yob*.txt               — SSA 출생 이름 연도별 (형식: name,sex,count)

출력 (기본: 원본 폴더 — repo 밖이라 실수 커밋 불가):
  english_common.candidates.txt — NGSL 가공          → curated+broad 후보
  english_names.candidates.txt  — Census+SSA 가공    → broad 전용 후보

⚠️ 후보(candidates) 단계다 — scripts/audit_wordlist.sh 검역 + 리뷰 게이트를
   통과한 뒤에만 Resources/IM/에 머지한다 (이 스크립트는 Resources/IM/ 불변).

필터 (EnglishDetector.loadWords와 일치):
  - 소문자화, ASCII 알파벳만 — 어퍼스트로피/하이픈 이름(o'brien)은 통째 제외
    (변형하면 실제 타이핑 키 시퀀스와 달라져 검역 의미가 없음)
  - 3자 이상 (loadWords가 어차피 거름)
  - exclusion 파일: 검역에서 탈락한 단어를 영구 반영 — 재생성해도 안전.
    --exclude 반복 지정 + <srcdir>/exclusions.txt 자동 적용.
  - names는 NGSL·english_supplement·web2 기존 등재어 제거(--no-dedupe로 해제)
    — broad에 이미 있는 단어라 행동 변화가 없고 리뷰만 무거워지는 중복 제거.

사용:
  scripts/build_english_wordlists.py --probe     # 형식/통계 확인만
  scripts/build_english_wordlists.py             # 후보 2종 생성
  scripts/build_english_wordlists.py --surnames-top 30000 --firstnames-top 10000
"""
import argparse
import csv
import datetime
import glob
import os
import re
import sys

ALPHA = re.compile(r"^[a-z]{3,}$")
REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SUPPLEMENT = os.path.join(REPO_ROOT, "Resources", "IM", "english_supplement.txt")
WEB2 = "/usr/share/dict/words"


def die(msg):
    sys.exit(f"오류: {msg}")


def norm(word):
    """소문자 + 필터 통과 시 단어, 아니면 None."""
    w = word.strip().lower()
    return w if ALPHA.match(w) else None


# ── 원본 탐색 ──────────────────────────────────────────────────────────────

def find_sources(srcdir, args):
    found = {"ngsl": [], "census": [], "ssa": []}
    if args.ngsl:
        found["ngsl"] = [args.ngsl]
    else:
        for pat in ("*NGSL*", "*ngsl*", "*Ngsl*"):
            for ext in (".csv", ".txt", ".tsv"):
                found["ngsl"] += glob.glob(os.path.join(srcdir, "**", pat + ext), recursive=True)
    if args.census:
        found["census"] = [args.census]
    else:
        for pat in ("*ensus*.csv", "*urname*.csv"):
            found["census"] += glob.glob(os.path.join(srcdir, "**", pat), recursive=True)
    found["ssa"] = (glob.glob(args.ssa_glob, recursive=True) if args.ssa_glob
                    else glob.glob(os.path.join(srcdir, "**", "yob*.txt"), recursive=True))
    for k in found:
        found[k] = sorted(set(found[k]))
    return found


# ── 파서 (표준 공개 형식) ──────────────────────────────────────────────────

def parse_ngsl(path):
    """NGSL: lemma 칼럼이 있는 CSV/TSV(stats.csv 등) 또는 한 줄당 1단어 txt.
    반환: (단어 set, lemma 헤더 감지 여부) — 헤더 감지가 정본 판별 신호."""
    words = set()
    has_header = False
    with open(path, encoding="utf-8-sig", errors="replace") as fp:
        if path.lower().endswith((".csv", ".tsv")):
            delim = "\t" if path.lower().endswith(".tsv") else ","
            rows = list(csv.reader(fp, delimiter=delim))
            if not rows:
                return words, has_header
            header = [c.strip().lower() for c in rows[0]]
            col = next((i for i, c in enumerate(header)
                        if c in ("lemma", "word", "headword", "entry")), None)
            has_header = col is not None
            body = rows[1:] if has_header else rows
            col = col or 0
            for row in body:
                if col < len(row):
                    w = norm(row[col])  # ## 주석/빈 줄은 norm이 거름
                    if w:
                        words.add(w)
        else:
            for line in fp:
                # 빈도 칼럼이 섞인 txt도 허용: 줄에서 첫 알파벳 토큰을 lemma로
                for token in re.split(r"[,\t\s]+", line):
                    w = norm(token)
                    if w:
                        words.add(w)
                        break
    return words, has_header


def pick_ngsl(paths):
    """NGSL 파일 여러 개(stats/teaching/research/description) 중 정본 선택:
    ①lemma류 헤더가 감지된 파일 우선 ②2,809 lemma에 가장 가까운 파싱 결과.
    (description.txt는 산문·변경표가 섞여 오염 위험 — 스코어가 자연 배제.)"""
    scored = []
    for p in paths:
        words, has_header = parse_ngsl(p)
        scored.append((0 if has_header else 1, abs(len(words) - 2809), p, words))
    scored.sort(key=lambda t: (t[0], t[1], t[2]))
    return scored[0][2], scored[0][3], scored


def parse_census(path):
    """US Census 2010 성씨 CSV: name,rank,count,… (census.gov 표준 형식).
    'ALL OTHER NAMES' 집계 행은 알파벳 필터로 자연 탈락."""
    out = []  # (count, name)
    with open(path, encoding="utf-8-sig", errors="replace") as fp:
        rows = csv.reader(fp)
        header = next(rows, None)
        if header is None:
            return out
        cols = [c.strip().lower() for c in header]
        if "name" in cols:
            name_i = cols.index("name")
            count_i = cols.index("count") if "count" in cols else 2
        else:  # 헤더 없는 변형 — 첫 행도 데이터로
            name_i, count_i = 0, 2
            fp.seek(0)
            rows = csv.reader(fp)
        for row in rows:
            if len(row) <= max(name_i, count_i):
                continue
            w = norm(row[name_i])
            if not w:
                continue
            try:
                count = int(row[count_i].replace(",", ""))
            except ValueError:
                continue
            out.append((count, w))
    return out


def parse_ssa(paths):
    """SSA yob*.txt (name,sex,count) 다년 집계 — 이름별 count 합산."""
    totals = {}
    for path in paths:
        with open(path, encoding="utf-8-sig", errors="replace") as fp:
            for row in csv.reader(fp):
                if len(row) < 3:
                    continue
                w = norm(row[0])
                if not w:
                    continue
                try:
                    totals[w] = totals.get(w, 0) + int(row[2])
                except ValueError:
                    continue
    return totals


def load_wordfile(path):
    """기존 단어 파일(supplement/web2/후보) — # 주석·비알파벳 줄 제외."""
    words = set()
    if not os.path.exists(path):
        return words
    with open(path, encoding="utf-8", errors="replace") as fp:
        for line in fp:
            w = norm(line)
            if w:
                words.add(w)
    return words


# ── 출력 ──────────────────────────────────────────────────────────────────

def write_candidates(path, words, header_lines):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as out:
        for line in header_lines:
            out.write("# " + line + "\n")
        for w in sorted(words):
            out.write(w + "\n")
    print(f"  → {path} ({len(words):,}단어)")


# ── main ──────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--srcdir", default=os.path.expanduser("~/Downloads/HaneulDictSources"))
    ap.add_argument("--outdir", default=None, help="출력 폴더 (기본: srcdir)")
    ap.add_argument("--ngsl", help="NGSL 파일 명시 지정")
    ap.add_argument("--census", help="Census 성씨 CSV 명시 지정")
    ap.add_argument("--ssa-glob", help="SSA yob 파일 glob 명시 지정")
    ap.add_argument("--surnames-top", type=int, default=30000, help="성씨 상위 N (기본 30000)")
    ap.add_argument("--firstnames-top", type=int, default=10000, help="이름 상위 N (기본 10000)")
    ap.add_argument("--exclude", action="append", default=[],
                    help="제외 단어 파일 (반복 가능 — 검역 탈락 영구 반영)")
    ap.add_argument("--no-dedupe", action="store_true",
                    help="names에서 NGSL/supplement/web2 기등재어 제거 안 함")
    ap.add_argument("--probe", action="store_true", help="형식 확인·통계만 (출력 안 만듦)")
    args = ap.parse_args()

    srcdir = args.srcdir
    outdir = args.outdir or srcdir
    if not os.path.isdir(srcdir):
        die(f"원본 폴더 없음: {srcdir}\n"
            f"  → 다운로드 담당 작업이 아직 안 끝남. 끝난 뒤 다시 실행하거나 --srcdir로 지정.\n"
            f"  기대 구성: NGSL(csv/txt) + Census 성씨 csv + SSA yob*.txt")

    found = find_sources(srcdir, args)

    # ── probe: 형식 확인만 ──
    if args.probe:
        print(f"probe: {srcdir}")
        for kind, label, expect in (
            ("ngsl", "NGSL lemma 목록", "~2,809 lemma"),
            ("census", "Census 2010 성씨", "헤더 name,rank,count,…"),
            ("ssa", "SSA 출생 이름(yob*.txt)", "name,sex,count — 연도별"),
        ):
            files = found[kind]
            print(f"\n[{label}] {len(files)}개 파일 (기대: {expect})")
            if not files:
                print("  없음 — 다운로드 대기 또는 --ngsl/--census/--ssa-glob로 지정")
                continue
            for f in files[:3]:
                print(f"  {f}")
                with open(f, encoding="utf-8-sig", errors="replace") as fp:
                    for i, line in enumerate(fp):
                        if i >= 2:
                            break
                        print(f"    | {line.rstrip()[:100]}")
            if kind == "ngsl":
                chosen, w, scored = pick_ngsl(files)
                for has_hdr, _, p, ws in scored:
                    mark = "★ 선택" if p == chosen else "  후보"
                    hdr = "헤더 O" if has_hdr == 0 else "헤더 X"
                    print(f"  {mark} {os.path.basename(p)}: {len(ws):,}단어 ({hdr})")
                print(f"  파싱 예: {sorted(w)[:5]}")
                if not 2000 <= len(w) <= 3500:
                    print("  ⚠️ 2,809 lemma와 거리가 있음 — 파일이 NGSL 본체인지 확인, --ngsl로 명시 지정 가능")
            elif kind == "census":
                rows = parse_census(files[0])
                rows.sort(reverse=True)
                print(f"  파싱 결과: {len(rows):,}개 성씨, 상위: {[w for _, w in rows[:5]]}")
            elif kind == "ssa":
                totals = parse_ssa(files[: min(3, len(files))])  # 표본 3개 연도만
                top = sorted(totals.items(), key=lambda kv: -kv[1])[:5]
                print(f"  표본 {min(3, len(files))}개 연도 집계: {len(totals):,}개 이름, 상위: {[w for w, _ in top]}")
        print("\nprobe 완료 — 출력 파일은 만들지 않음.")
        return

    # ── 빌드 ──
    today = datetime.date.today().isoformat()
    exclude_files = list(args.exclude)
    # (review-0712 P3-5) 저장소의 dict_work/exclusions.txt가 제외 목록의 정본이다
    # (SOURCE_FORMATS.md에 그렇게 정해뒀다). 예전엔 외부 원본 폴더의 사본만
    # 자동으로 읽어서, --exclude를 깜빡하면 이미 탈락시킨 후보가 되살아났다.
    # 이제 정본을 항상 적용하고, 없으면 실패한다.
    repo_excl = os.path.join(REPO_ROOT, "dict_work", "exclusions.txt")
    if not os.path.exists(repo_excl):
        die(f"제외 목록 정본이 없음: {repo_excl} (SOURCE_FORMATS.md 참조)")
    if repo_excl not in exclude_files:
        exclude_files.append(repo_excl)
    auto_excl = os.path.join(srcdir, "exclusions.txt")
    if os.path.exists(auto_excl) and auto_excl not in exclude_files:
        exclude_files.append(auto_excl)
    exclusions = set()
    for f in exclude_files:
        if not os.path.exists(f):
            die(f"exclusion 파일 없음: {f}")
        exclusions |= load_wordfile(f)
    print(f"exclusion: {len(exclusions):,}단어 ({', '.join(exclude_files) or '없음'})")

    # 1) english_common.candidates.txt — NGSL
    if not found["ngsl"]:
        die(f"NGSL 파일을 못 찾음 ({srcdir} 안 *NGSL*.csv/txt) — --ngsl로 지정 가능")
    ngsl_path, ngsl, _ = pick_ngsl(found["ngsl"])
    if len(found["ngsl"]) > 1:
        print(f"NGSL 정본 선택: {os.path.basename(ngsl_path)} (헤더 감지+2,809 근접 스코어, --ngsl로 변경 가능)")
    if not 2000 <= len(ngsl) <= 3500:
        print(f"⚠️ NGSL 파싱 {len(ngsl):,}단어 — 기대(~2,809)와 다름. --probe로 형식 확인 권장.")
    common = ngsl - exclusions
    print(f"NGSL: {len(ngsl):,} → exclusion 제외 후 {len(common):,}")
    write_candidates(
        os.path.join(outdir, "english_common.candidates.txt"), common,
        [
            "English common-words CANDIDATE list — NGSL (New General Service List)",
            "Source: NGSL (Browne, C., Culligan, B. & Phillips, J.) — newgeneralservicelist.com",
            "License: Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)",
            f"Generated: {today} scripts/build_english_wordlists.py"
            f" (file: {os.path.basename(ngsl_path)}, exclusions: {len(exclusions)})",
            "Role: curated + broad — clean-Hangul 룰(R5/R2-clean)이 신뢰할 목록",
            "Status: 후보 — scripts/audit_wordlist.sh --role curated 검역 + 리뷰 후",
            "        Resources/IM/english_common.txt로 머지",
        ],
    )

    # 2) english_names.candidates.txt — Census 성씨 + SSA 이름
    if not found["census"] and not found["ssa"]:
        die(f"인명 원본(Census csv / yob*.txt)을 못 찾음 — {srcdir} 확인")
    names = set()
    if found["census"]:
        rows = parse_census(found["census"][0])
        rows.sort(reverse=True)  # count 내림차순
        surnames = [w for _, w in rows[: args.surnames_top]]
        names |= set(surnames)
        print(f"Census 성씨: {len(rows):,} → 상위 {len(surnames):,}")
    else:
        print("주의: Census 성씨 파일 없음 — SSA만으로 진행")
    if found["ssa"]:
        totals = parse_ssa(found["ssa"])
        first = [w for w, _ in sorted(totals.items(), key=lambda kv: -kv[1])[: args.firstnames_top]]
        names |= set(first)
        print(f"SSA 이름: {len(found['ssa'])}개 연도, {len(totals):,} → 상위 {len(first):,}")
    else:
        print("주의: SSA yob*.txt 없음 — Census만으로 진행")

    before = len(names)
    names -= exclusions
    dedupe_note = "dedupe: off"
    if not args.no_dedupe:
        already = ngsl | load_wordfile(SUPPLEMENT) | load_wordfile(WEB2)
        names -= already
        dedupe_note = "dedupe: NGSL+supplement+web2 기등재 제거"
    print(f"인명: {before:,} → exclusion/중복 제거 후 {len(names):,}")
    write_candidates(
        os.path.join(outdir, "english_names.candidates.txt"), names,
        [
            "English names CANDIDATE list — US Census 2010 surnames + SSA baby names",
            "Source: census.gov (Frequently Occurring Surnames 2010), ssa.gov (Baby Names)",
            "License: US Government works — public domain",
            f"Generated: {today} scripts/build_english_wordlists.py"
            f" (surnames-top {args.surnames_top:,}, firstnames-top {args.firstnames_top:,},"
            f" exclusions: {len(exclusions)}, {dedupe_note})",
            "Role: broad 전용 — 깨진-한글 룰(MAIN/R1/R3/R2-broken)만 사용,",
            "      curatedPaths에 절대 등록 금지 (clean 한글 충돌 검증 불가 롱테일)",
            "Status: 후보 — scripts/audit_wordlist.sh --role broad 검역 + 리뷰 후",
            "        Resources/IM/english_names.txt로 머지 (all_jamo 플래그 항목 제외)",
        ],
    )
    print("완료 — 다음 단계: scripts/audit_wordlist.sh로 검역 후 리뷰 게이트.")


if __name__ == "__main__":
    main()

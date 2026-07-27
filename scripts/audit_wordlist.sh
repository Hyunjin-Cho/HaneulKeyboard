#!/bin/bash
# 영어 사전 후보 검역(스윕) — 실제 IME 코드를 컴파일해 "이 단어를 넣으면
# 실제로 뭐가 새로 변환되나"를 답한다 (Tools/WordlistAudit.swift 참조).
#
# 사용법:
#   scripts/audit_wordlist.sh --candidates 후보.txt --role broad|curated \
#       [--out audit.csv] [--base p1,p2] [--curated-base p1] [--korean-dict 경로]
#   scripts/audit_wordlist.sh --reachability 단어목록.txt [--out reach.csv]
#   scripts/audit_wordlist.sh --smoke
#
# 예시:
#   # NGSL 후보를 curated 역할로 검역 (Tier A/B가 리뷰 대상)
#   scripts/audit_wordlist.sh --candidates ~/Downloads/HaneulDictSources/english_common.candidates.txt \
#       --role curated --out /tmp/common_audit.csv
#   # 인명 후보를 broad 역할로 검역 (all_jamo 플래그 = 기본 제외 대상)
#   scripts/audit_wordlist.sh --candidates ~/Downloads/HaneulDictSources/english_names.candidates.txt \
#       --role broad --out /tmp/names_audit.csv
#   # 영어 top-100 기능어의 도달성 표 (and-class 구멍 자동 탐지)
#   scripts/audit_wordlist.sh --reachability /tmp/top100.txt --out /tmp/reach.csv
#
# 기본 베이스 사전 = 현재 effective 구성: web2 + english_supplement.txt
# (+ Resources/IM/에 이미 머지된 english_common/names가 있으면 자동 포함).
set -euo pipefail

cd "$(dirname "$0")/.."

CANDIDATES=""
ROLE=""
OUT=""
REACH_FILE=""
SMOKE=0
KOREAN_DICT="Resources/IM/korean_words.txt"
BASE=""
CURATED_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidates)   CANDIDATES="$2"; shift 2 ;;
    --role)         ROLE="$2"; shift 2 ;;
    --out)          OUT="$2"; shift 2 ;;
    --reachability) REACH_FILE="$2"; shift 2 ;;
    --smoke)        SMOKE=1; shift ;;
    --korean-dict)  KOREAN_DICT="$2"; shift 2 ;;
    --base)         BASE="$2"; shift 2 ;;
    --curated-base) CURATED_BASE="$2"; shift 2 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

# ── 기본 베이스 구성 ──
# (review-0712 P3-5) 목록을 여기 직접 적지 않고 dict_work/dict_manifest.tsv를
# 읽는다. 예전엔 런타임(EnglishDetector)·테스트·이 스크립트가 각자 목록을 들고
# 있어서, english_sports_geo.txt가 런타임에만 있고 검역에서는 빠져도 몰랐다.
MANIFEST="dict_work/dict_manifest.tsv"
if [[ -z "$BASE" ]]; then
  [[ -f "$MANIFEST" ]] || { echo "사전 manifest 없음: $MANIFEST" >&2; exit 2; }
  BASE="/usr/share/dict/words"   # web2 — 시스템 파일이라 manifest 밖
  MANIFEST_CURATED=""
  while IFS=$'\t' read -r name role _min _sample; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    f="Resources/IM/$name.txt"
    [[ -f "$f" ]] || { echo "manifest에 적힌 사전이 없음: $f" >&2; exit 2; }
    BASE="$BASE,$f"
    [[ "$role" == "curated" ]] && MANIFEST_CURATED="${MANIFEST_CURATED:+$MANIFEST_CURATED,}$f"
  done < "$MANIFEST"
  CURATED_BASE="${CURATED_BASE:-$MANIFEST_CURATED}"
elif [[ -z "$CURATED_BASE" ]]; then
  CURATED_BASE="Resources/IM/english_supplement.txt"
fi

# ── 컴파일 (run_ime_tests.sh 패턴 — 실제 IME 소스 그대로) ──
WORK="$(mktemp -d)"
BIN="$WORK/wordlist_audit"
swiftc -O -o "$BIN" \
  IMESources/HangulJamo.swift \
  IMESources/KeyboardLayout2Set.swift \
  IMESources/KoreanComposer.swift \
  IMESources/EnglishDetector.swift \
  IMESources/KoreanDictionary.swift \
  Tools/WordlistAudit.swift

# ── 스모크 테스트: 알려진 단어로 Tier 분류와 자모 플래그를 검증 ──
# 베이스를 web2 단독으로 고정해 향후 사전 머지와 무관하게 안정적으로 동작.
#   goawor(햄잭)  clean 6키 + 미등재 → curated 추가 시 무맥락 R5 신규 = Tier A
#   city(챠쇼)    clean 2음절 + 미등재 → curated 추가 시 무맥락 R5 신규 = Tier A
#   gown(해주)    clean + 우리말샘 등재(veto) → 변화 없음           = Tier C
#   nmn(ㅜㅡㅜ)   완성음절 0 → all_jamo ⚠️ 플래그 (names 제외 메커니즘)
if [[ "$SMOKE" == 1 ]]; then
  SMOKE_CAND="$WORK/smoke_candidates.txt"
  printf "goawor\ncity\ngown\nnmn\n" > "$SMOKE_CAND"
  SMOKE_BASE="/usr/share/dict/words"
  SMOKE_CURATED="Resources/IM/english_supplement.txt"
  "$BIN" scan --candidates "$SMOKE_CAND" --wordlists "$SMOKE_BASE,$SMOKE_CURATED" \
      --curated "$SMOKE_CURATED" --korean-dict "$KOREAN_DICT" > "$WORK/smoke_a.tsv"
  "$BIN" scan --candidates "$SMOKE_CAND" --wordlists "$SMOKE_BASE,$SMOKE_CURATED,$SMOKE_CAND" \
      --curated "$SMOKE_CURATED,$SMOKE_CAND" --korean-dict "$KOREAN_DICT" > "$WORK/smoke_b.tsv"
  "$BIN" merge "$WORK/smoke_a.tsv" "$WORK/smoke_b.tsv" --korean-dict "$KOREAN_DICT" > "$WORK/smoke.csv"

  fail=0
  grep -q '^goawor,햄잭,clean,0,0,1,.*,A,' "$WORK/smoke.csv" || { echo "SMOKE FAIL: goawor가 Tier A 아님"; fail=1; }
  grep -q '^city,챠쇼,clean,0,0,1,.*,A,' "$WORK/smoke.csv" || { echo "SMOKE FAIL: city가 Tier A 아님"; fail=1; }
  grep -q '^gown,해주,clean,1,.*,C,' "$WORK/smoke.csv" || { echo "SMOKE FAIL: gown이 Tier C(veto) 아님"; fail=1; }
  grep '^nmn,' "$WORK/smoke.csv" | grep -q '자모' || { echo "SMOKE FAIL: nmn에 전부-자모 플래그 없음"; fail=1; }
  if [[ "$fail" == 0 ]]; then
    echo "SMOKE PASS: Tier A(goawor, city)/C-veto(gown)/자모 플래그(nmn) 전부 정상"
    exit 0
  fi
  echo "── smoke.csv ──"; cat "$WORK/smoke.csv"
  exit 1
fi

# ── 도달성 모드 ──
if [[ -n "$REACH_FILE" ]]; then
  OUT="${OUT:-/tmp/haneul_reachability.csv}"
  "$BIN" reach --words "$REACH_FILE" --wordlists "$BASE" \
      --curated "$CURATED_BASE" --korean-dict "$KOREAN_DICT" > "$OUT"
  echo "도달성 표: $OUT"
  exit 0
fi

# ── 검역(이중 실행 diff) 모드 ──
[[ -n "$CANDIDATES" ]] || { echo "--candidates 또는 --reachability 또는 --smoke 필요" >&2; exit 2; }
[[ "$ROLE" == "broad" || "$ROLE" == "curated" ]] || { echo "--role broad|curated 필요" >&2; exit 2; }
[[ -f "$CANDIDATES" ]] || { echo "후보 파일 없음: $CANDIDATES" >&2; exit 2; }
OUT="${OUT:-/tmp/haneul_wordlist_audit.csv}"

# 정규화: 소문자·ASCII 알파벳만·3자+·중복 제거 (loadWords 필터와 일치 —
# 대문자 줄이 scan에선 평가되고 사전 로드에선 skip되는 불일치 방지)
NORM="$WORK/candidates.norm.txt"
tr '[:upper:]' '[:lower:]' < "$CANDIDATES" | grep -E '^[a-z]{3,}$' | sort -u > "$NORM" || true
TOTAL_IN=$(grep -cve '^[[:space:]]*$' -e '^#' "$CANDIDATES" || true)
TOTAL_NORM=$(wc -l < "$NORM" | tr -d ' ')
echo "후보 정규화: $TOTAL_IN → $TOTAL_NORM 단어 (소문자/알파벳만/3자+/중복 제거)"
[[ "$TOTAL_NORM" -gt 0 ]] || { echo "정규화 후 후보 0개" >&2; exit 2; }

# pass A: 후보 제외 (현재 베이스 그대로)
"$BIN" scan --candidates "$NORM" --wordlists "$BASE" \
    --curated "$CURATED_BASE" --korean-dict "$KOREAN_DICT" > "$WORK/pass_a.tsv"

# pass B: 후보 포함 (역할에 따라 broad만 또는 broad+curated)
B_WORDLISTS="$BASE,$NORM"
B_CURATED="$CURATED_BASE"
[[ "$ROLE" == "curated" ]] && B_CURATED="$CURATED_BASE,$NORM"
"$BIN" scan --candidates "$NORM" --wordlists "$B_WORDLISTS" \
    --curated "$B_CURATED" --korean-dict "$KOREAN_DICT" > "$WORK/pass_b.tsv"

# merge: diff + Tier + 휴리스틱 note → CSV
"$BIN" merge "$WORK/pass_a.tsv" "$WORK/pass_b.tsv" --korean-dict "$KOREAN_DICT" > "$OUT"

echo "검역 결과: $OUT (role=$ROLE)"
echo "리뷰 안내: Tier A = 전수 리뷰(무맥락 신규 변환) / B = 의심 note 우선 / C = 안전"

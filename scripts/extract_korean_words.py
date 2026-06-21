#!/usr/bin/env python3
"""우리말샘 JSON 덤프에서 한글 표제어만 추출해 IME 번들용 단어 목록을 만든다.

입력: 전체 내려받기 JSON 25개 (channel.item[].wordinfo.word / senseinfo)
출력: Resources/IM/korean_words.txt — 한 줄당 단어 1개, 헤더에 출처/라이선스.

필터 기준 (보수적 — '진짜 한국어 단어' veto 용도):
  - 표제어 정리: 결합 기호 ^(띄어쓰기), -(접사 경계) 제거
  - 전부 완성 한글 음절(가-힣)로만 구성된 것만 (자모 표제어 ㄱ, ㄱㄴㄷ-순 등 제외)
  - 구분(type)이 '일반어'인 것만 (방언/옛말/북한어 제외 — veto는 현대 표준어 기준)
  - 길이 1~6음절 (영타 충돌 단어는 짧음 — 7+ 제외로 9.5만 절감)

데이터 라이선스: 국립국어원 우리말샘, CC-BY-SA 2.0 KR.
"""
import json
import glob
import os
import re
import sys

SRC_DIR = os.path.expanduser("~/Downloads/전체 내려받기_우리말샘_json_20260603")
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "IM", "korean_words.txt")

# 1~6음절: 영타 충돌(veto 대상) 단어는 전부 짧다 — 영어 키 시퀀스가
# 한글 7음절 이상으로 조합되는 일은 사실상 없음. 7+ 제외로 9.5만 개 절감.
HANGUL = re.compile(r"^[가-힣]{1,6}$")

words = set()
files = sorted(glob.glob(os.path.join(SRC_DIR, "*.json")))
if not files:
    sys.exit(f"JSON 파일 없음: {SRC_DIR}")

stats = {"total": 0, "kept": 0}
for path in files:
    with open(path, encoding="utf-8") as fp:
        data = json.load(fp)
    for item in data["channel"]["item"]:
        stats["total"] += 1
        wi = item.get("wordinfo", {})
        word = (wi.get("word") or "").replace("^", "").replace("-", "")
        si = item.get("senseinfo", {})
        wtype = si.get("type", "") if isinstance(si, dict) else ""
        if wtype != "일반어":
            continue
        if not HANGUL.match(word):
            continue
        words.add(word)
        stats["kept"] += 1
    print(f"  {os.path.basename(path)}: 누적 {len(words):,}개", flush=True)

# (H-04) 최소 엔트리 검증 — 우리말샘 일반어/완성한글 1~6음절은 60만+개다.
# 이보다 적으면 입력 손상·부분 다운로드로 보고 운영 파일을 건드리지 않는다.
MIN_WORDS = 500_000
if len(words) < MIN_WORDS:
    sys.exit(f"추출 {len(words):,}개 < 최소 {MIN_WORDS:,}개 — 입력 손상/불완전으로 간주, 쓰기 중단")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
# (H-04) 원자적 쓰기: 임시 파일에 쓰고 fsync 후 rename — 생성이 중단돼도
# 운영 사전이 절반만 쓰인 상태로 남지 않는다. 헤더의 count로 런타임이 로드 시
# 실제 개수와 대조해 부분 손상을 fail-closed로 잡는다.
tmp = OUT + ".tmp"
with open(tmp, "w", encoding="utf-8") as out:
    out.write("# 우리말샘 표제어 (국립국어원, CC-BY-SA 2.0 KR) — 일반어/완성한글만\n")
    out.write("# 출처: https://opendict.korean.go.kr (전체 내려받기 2026-06-03)\n")
    out.write("# 이 데이터 파일은 CC-BY-SA 2.0 KR 라이선스를 따릅니다 (앱 코드는 MIT).\n")
    out.write(f"# count: {len(words)}\n")
    for w in sorted(words):
        out.write(w + "\n")
    out.flush()
    os.fsync(out.fileno())
os.replace(tmp, OUT)

size_mb = os.path.getsize(OUT) / 1024 / 1024
print(f"\n완료: 표제어 {stats['total']:,}개 중 {len(words):,}개 추출 → {OUT} ({size_mb:.1f} MB)")

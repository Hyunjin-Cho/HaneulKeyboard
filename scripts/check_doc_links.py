#!/usr/bin/env python3
"""2026-11-07 (#178): 공개 문서의 깨진 상대 링크를 잡는다.

왜: .gitignore가 docs/feedback/·docs/HANDOFF_*.md 같은 내부 문서를 공개하지 않는데, 공개 문서가 그 경로를 링크로 걸어 두면
GitHub에서 열었을 때 깨진 링크가 된다(리뷰 docs-license-F-3). 링크 대상은 **추적 중인 파일이나 폴더**여야 한다.

무엇을 본다: `git ls-files`의 .md 문서 안 `[글](상대경로)` 링크. http(s)·mailto·`#쪽지`만 있는 링크는 보지 않는다.
2026-11-12 (#228, 리뷰 build-release-docs-F-6): README 배너처럼 HTML 속성(`<img src="…">`·`<a href="…">`)으로 건 경로와
참조식 링크 정의(`[이름]: 경로`)도 본다 — 예전에는 `[글](경로)` 꼴만 봐서 HTML 이미지가 깨져도 통과했다.
무엇을 안 본다: 코드 블록 안의 글, 링크 아닌 백틱 경로 표기, 실제 쪽지(#anchor) 존재 여부.
Resources/IM·LICENSES 아래 데이터·원문 고지는 문서가 아니라서 훑지 않는다.

사용: python3 scripts/check_doc_links.py            # 저장소 루트 기준
      python3 scripts/check_doc_links.py --root DIR  # 다른 트리(대조군 시험용)
scripts/run_ime_tests.sh가 함께 돌린다.
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
HTML_ATTR = re.compile(r"""\b(?:src|href)\s*=\s*(?:"([^"]+)"|'([^']+)')""", re.IGNORECASE)
REFERENCE = re.compile(r'^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?')
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
SKIP_PREFIXES = ("Resources/IM/", "LICENSES/")


def tracked_files(root: Path):
    result = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return [name for name in result.stdout.split("\0") if name]


def broken_links(root: Path, files):
    tracked = set(files)
    folders = set()
    for name in files:
        parent = os.path.dirname(name)
        while parent:
            folders.add(parent)
            parent = os.path.dirname(parent)
    checked = 0
    broken = []
    for name in files:
        if not name.endswith(".md") or name.startswith(SKIP_PREFIXES):
            continue
        try:
            text = (root / name).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        in_fence = False
        for number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            targets = [match.group(1) for match in LINK.finditer(line)]
            targets += [match.group(1) or match.group(2) for match in HTML_ATTR.finditer(line)]
            reference = REFERENCE.match(line)
            if reference:
                targets.append(reference.group(1))
            for original in targets:
                if SCHEME.match(original) or original.startswith("#"):
                    continue
                target = original.split("#")[0].split("?")[0]
                if not target:
                    continue
                checked += 1
                resolved = os.path.normpath(os.path.join(os.path.dirname(name), target))
                if resolved not in tracked and resolved not in folders:
                    broken.append((name, number, original))
    return checked, broken


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    files = tracked_files(args.root)
    if files is None:
        print("SKIP: git 저장소가 아니라 링크를 검사하지 못했다")
        return 0
    checked, broken = broken_links(args.root, files)
    for name, number, target in broken:
        print(f"FAIL {name}:{number} 추적되지 않는 대상을 링크한다 → {target}")
    print(f"doc links: {checked - len(broken)} passed, {len(broken)} failed")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())

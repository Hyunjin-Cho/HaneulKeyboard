#!/usr/bin/env python3
"""2026-10-10: 배포 앱/내장·단독 IME의 고지 원문 누락·오래된 사본을 거부한다.
2026-11-07 (#175): 입력기가 런타임에 읽는 사전도 같은 방식으로 본다. 표가 빠지면 오류 없이 번들 사전 낱말이 변환되지 않는다."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "LICENSE": ROOT / "LICENSE",
    "NOTICE": ROOT / "NOTICE",
    "ACKNOWLEDGEMENTS.md": ROOT / "ACKNOWLEDGEMENTS.md",
    "HaneulKeyboard-MIT-legacy.txt": ROOT / "LICENSES/HaneulKeyboard-MIT-legacy.txt",
}
# 입력기 번들에 있어야 하는 사전. 메인 앱은 영어 사전을 싣지 않는다.
IME_DICTIONARIES = {
    "english_bundled.txt", "english_common.txt", "english_supplement.txt",
    "korean_words.txt", "phonetic_dictionary.json",
}


def verify(app: Path) -> None:
    resources = app / "Contents/Resources"
    for name, source in FILES.items():
        target = resources / name
        if not target.is_file() or target.read_bytes() != source.read_bytes():
            raise SystemExit(f"FAIL: missing/stale notice: {target}")
    helper = app / "Contents/Helpers/HaneulKeyboardIM.app"
    if app.name == "HaneulKeyboard.app" and not helper.is_dir():
        raise SystemExit(f"FAIL: missing embedded IME: {helper}")
    if helper.is_dir():
        verify(helper)
    if app.name == "HaneulKeyboardIM.app":
        for name in sorted(IME_DICTIONARIES):
            target = resources / name
            if not target.is_file() or target.read_bytes() != (ROOT / "Resources/IM" / name).read_bytes():
                raise SystemExit(f"FAIL: missing/stale dictionary: {target}")
    print(f"PASS: current LICENSE + NOTICE + acknowledgements + legacy MIT: {app}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apps", nargs="+", type=Path)
    args = parser.parse_args()
    if b"Apache License" not in FILES["LICENSE"].read_bytes():
        raise SystemExit("FAIL: expected Apache License")
    for app in args.apps:
        verify(app)

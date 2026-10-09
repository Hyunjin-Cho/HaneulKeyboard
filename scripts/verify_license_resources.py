#!/usr/bin/env python3
"""2026-10-10: 배포 앱/내장·단독 IME의 고지 원문 누락·오래된 사본을 거부한다."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "LICENSE": ROOT / "LICENSE",
    "NOTICE": ROOT / "NOTICE",
    "ACKNOWLEDGEMENTS.md": ROOT / "ACKNOWLEDGEMENTS.md",
    "HaneulKeyboard-MIT-legacy.txt": ROOT / "LICENSES/HaneulKeyboard-MIT-legacy.txt",
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
    print(f"PASS: current LICENSE + NOTICE + acknowledgements + legacy MIT: {app}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apps", nargs="+", type=Path)
    args = parser.parse_args()
    if b"Apache License" not in FILES["LICENSE"].read_bytes():
        raise SystemExit("FAIL: expected Apache License")
    for app in args.apps:
        verify(app)

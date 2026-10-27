#!/usr/bin/env python3
"""2026-10-10: 읽기 전용 마운트로 내용/배경/아이콘 배치 검사. Finder/앱을 실행하지 않는다.
Run with the project DMG venv: python scripts/verify_dmg.py IMAGE SOURCE_APP.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from ds_store import DSStore


def verify(image, source):
    root = Path(__file__).resolve().parent.parent
    layout = json.loads((root / "Resources/Installer/layout.json").read_text())
    with tempfile.TemporaryDirectory(prefix="haneul-dmg-verify-") as temporary:
        mount = Path(temporary) / "mount"
        mount.mkdir()
        attached = False
        try:
            subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount), str(image)], check=True, capture_output=True)
            attached = True
            app = mount / source.name
            assert app.is_dir(), "Main app is missing"
            assert (mount / "Applications").is_symlink()
            assert os.readlink(mount / "Applications") == "/Applications"
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            expected = plistlib.loads((source / "Contents/Info.plist").read_bytes())
            assert info == expected, "App metadata changed in DMG"
            # 앱을 실행하지 않고 모든 파일/링크/권한을 원본과 대조한다.
            def files(directory):
                result = {}
                for path in directory.rglob("*"):
                    relative = str(path.relative_to(directory))
                    if path.is_symlink():
                        result[relative] = ("link", os.readlink(path))
                    elif path.is_file():
                        result[relative] = ("file", hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777)
                return result
            assert files(app) == files(source), "App payload changed in DMG"
            background = mount / ".background.tiff"
            assert background.is_file(), "Retina background missing"
            tiff = subprocess.run(["tiffutil", "-info", str(background)], check=True, capture_output=True, text=True)
            tiff_info = tiff.stdout + tiff.stderr
            dimensions = [tuple(map(int, pair)) for pair in re.findall(r"Image Width: (\d+) Image Length: (\d+)", tiff_info)]
            width, height = layout["canvasSize"]
            assert dimensions == [(width, height), (width * 2, height * 2)], "Background must contain matching 1x and 2x representations"
            resolutions = [tuple(map(float, pair)) for pair in re.findall(r"Resolution: ([\d.]+), ([\d.]+)", tiff_info)]
            assert resolutions == [(72, 72), (144, 144)], "Background point size must be identical at both scales"
            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                view = store["."]["icvp"]
                window = store["."]["bwsp"]
                assert view["backgroundType"] == 2, "Finder background is not an image"
                assert "backgroundImageAlias" in view
                assert view["iconSize"] == layout["iconSize"]
                assert view["textSize"] == layout["textSize"]
                assert view["arrangeBy"] == "none"
                assert "pBBk" not in [entry.code.decode() if isinstance(entry.code, bytes) else entry.code for entry in store], "Unsupported background bookmark"
                assert tuple(store[source.name]["Iloc"]) == tuple(layout["appCenter"])
                assert tuple(store["Applications"]["Iloc"]) == tuple(layout["applicationsCenter"])
                for key in ["ShowToolbar", "ShowStatusBar", "ShowPathbar", "ShowSidebar"]:
                    assert window[key] is False, f"Unexpected Finder chrome: {key}"
                bounds = window["WindowBounds"]
                assert [int(value) for value in re.findall(r"\d+", bounds)][-2:] == layout["windowSize"], "Finder window size changed"
            print(json.dumps({"image": str(image), "version": info["CFBundleShortVersionString"] + info.get("HaneulReleaseSuffix", ""),
                "build": info["CFBundleVersion"], "appPayloadIdentical": True, "background": "retina TIFF",
                "backgroundPixels": dimensions, "backgroundDPI": resolutions,
                "appCenter": layout["appCenter"], "applicationsCenter": layout["applicationsCenter"], "windowBounds": bounds}, ensure_ascii=False))
        finally:
            if attached:
                subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: verify_dmg.py IMAGE SOURCE_APP")
    verify(Path(sys.argv[1]).resolve(strict=True), Path(sys.argv[2]).resolve(strict=True))

#!/usr/bin/env python3
"""2026-10-11 리뷰 F-2: 실제 TIS 집계 블록을 fixture로 실행한다(시스템 변경 없음)."""
from pathlib import Path
import os
import subprocess


root = Path(__file__).resolve().parents[1]
source = (root / "scripts/postinstall_probe.sh").read_text()
counters = source[source.index("pass=0; fail=0"):source.index("\nMV=")]
tis = source[source.index('echo "■ 3.'):source.index('echo "■ 4.')]
summary = source[source.index('echo "── 집계:'):]
script = "set -uo pipefail\n" + counters + "\n" + tis + summary

fixtures = [
    ("enabled", "TIS\tfixture.one\tenabled\tselected", 2, 0),
    ("disabled", "TIS\tfixture.one\tdisabled\t-", 1, 1),
    ("absent", "LS\tfixture.app\t/tmp/app", 0, 1),
    ("empty", "", 0, 1),
    ("duplicate", "TIS\tfixture.one\tenabled\t-\nTIS\tfixture.one\tenabled\t-", 2, 1),
    ("mixed duplicate", "TIS\tfixture.one\tenabled\t-\nTIS\tfixture.one\tdisabled\t-", 1, 2),
    ("two enabled", "TIS\tfixture.one\tenabled\t-\nTIS\tfixture.two\tenabled\t-", 3, 0),
]
for name, fixture, passed, failed in fixtures:
    result = subprocess.run(["/bin/bash", "-c", script],
                            env={**os.environ, "OUT": fixture}, capture_output=True, text=True)
    expected = f"── 집계: ✓ {passed} / ✗ {failed}"
    assert expected in result.stdout, (name, result.stdout, result.stderr)
    assert result.returncode == (1 if failed else 0), (name, result.returncode, result.stdout)
    print(f"PASS: {name} — ✓ {passed} / ✗ {failed}, exit {result.returncode}")
cache = source[source.index('echo "■ 7.'):source.index('echo "── 집계:')]
cache_script = "set -uo pipefail\n" + counters + "\n" + cache + summary
cache_fixtures = [
    ("current", "CACHE\tcurrent", 1, 0),
    ("not created", "CACHE\tabsent", 1, 0),
    ("older macOS", "CACHE\tnot-applicable", 1, 0),
    ("stale settings list", "CACHE\tstale", 0, 1),
    ("cache query failure", "CACHE\tunknown", 0, 1),
    ("missing cache observation", "", 0, 1),
]
for name, fixture, passed, failed in cache_fixtures:
    result = subprocess.run(["/bin/bash", "-c", cache_script],
                            env={**os.environ, "OUT": fixture}, capture_output=True, text=True)
    assert f"── 집계: ✓ {passed} / ✗ {failed}" in result.stdout, (name, result.stdout, result.stderr)
    assert result.returncode == (1 if failed else 0), (name, result.returncode, result.stdout)
    print(f"PASS: {name} — ✓ {passed} / ✗ {failed}, exit {result.returncode}")
# 2026-11-12 (#228, 리뷰 install-update-F-2): DMG에서 Finder로 설치한 앱(FinderInfo 속성)은 `codesign --strict`만 실패한다.
# 가짜 codesign(인자에 --strict가 있으면 실패)으로 2번 블록을 돌려, 정상 설치본이 ✗로 세어지지 않는지 고정한다.
import tempfile
signing = source[source.index('echo "■ 2.'):source.index("# 3·4는")]
with tempfile.TemporaryDirectory(prefix="haneul-probe-sign-") as work:
    bin_dir = Path(work, "bin"); bin_dir.mkdir()
    for tool, body in (("codesign", 'for a in "$@"; do [ "$a" = "--strict" ] && exit 1; done; exit 0'),
                       ("spctl", "exit 0"), ("xcrun", "exit 0")):
        path = bin_dir / tool
        path.write_text("#!/bin/bash\n" + body + "\n"); path.chmod(0o755)
    app, ime = Path(work, "HaneulKeyboard.app"), Path(work, "HaneulKeyboardIM.app")
    app.mkdir(); ime.mkdir()
    sign_script = "set -uo pipefail\n" + counters + "\n" + signing + summary
    result = subprocess.run(["/bin/bash", "-c", sign_script], capture_output=True, text=True,
                            env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "APP": str(app), "IME": str(ime)})
    assert "── 집계: ✓ 5 / ✗ 0" in result.stdout, ("finder-installed signature", result.stdout, result.stderr)
    assert result.returncode == 0, ("finder-installed signature", result.returncode)
    print("PASS: Finder 설치본(FinderInfo) 서명 — ✓ 5 / ✗ 0, exit 0")
print(f"Postinstall probe: {len(fixtures) + len(cache_fixtures) + 1} passed, 0 failed")

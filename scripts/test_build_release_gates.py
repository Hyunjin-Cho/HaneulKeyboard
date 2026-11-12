#!/usr/bin/env python3
"""2026-11-12 (#228): build_notarize_install.sh의 'release gates'·'mode flags' 구간을 떼어 실제 bash로 돌린다.
서명·공증·설치는 하지 않는다(가짜 xcrun · 임시 git 저장소만)."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "scripts/build_notarize_install.sh").read_text()


def section(name):
    start = source.index(f"# >>> {name}")
    return source[start:source.index(f"# <<< {name}", start)]


gates, flags = section("release gates"), section("mode flags")
passed = 0


def bash(script, env=None, check_rc=None):
    result = subprocess.run(["/bin/bash", "-c", "set -euo pipefail\n" + script], capture_output=True, text=True,
                            env={**os.environ, **(env or {})})
    return result


# 1) 공개 버전 형식 (리뷰 build-release-docs-F-1)
for version, ok in [("2026.11.04", True), ("2026.11.04_hotfix1", True), ("2026.12.31_hotfix12", True),
                    ("2026.9", False), ("2026.11.4", False), ("2026.02.30", False), ("2026.13.01", False),
                    ("2026.11.04_hotfix", False), ("2026.11.04_hotfix01", False), ("2026.11.04_beta1", False), ("", False)]:
    r = bash(gates + f'\nrelease_version_ok "{version}" && echo YES || echo NO')
    assert r.stdout.strip() == ("YES" if ok else "NO"), (version, r.stdout, r.stderr)
    passed += 1

# 2) 빌드 번호 상승
for new, old, ok in [("112", "111", True), ("111", "111", False), ("50", "111", False), ("0112", "111", True),
                     ("", "111", False), ("abc", "1", False)]:
    r = bash(gates + f'\nrelease_build_increases "{new}" "{old}" && echo YES || echo NO')
    assert r.stdout.strip() == ("YES" if ok else "NO"), (new, old, r.stdout, r.stderr)
    passed += 1

# 3) 직전 공개 릴리스 태그의 빌드 번호 — 임시 저장소(backup/* 태그·접미어 없는 날짜는 섞어도 버전 순으로 마지막 공개 태그)
with tempfile.TemporaryDirectory(prefix="haneul-release-gates-") as work:
    def git(*args):
        subprocess.run(["git", "-C", work, *args], check=True, capture_output=True)
    git("init", "-q")
    git("config", "user.email", "test@example.invalid"); git("config", "user.name", "test")
    for tag, build in [("2026.07", "49"), ("2026.11.04", "112"), ("2026.11.04_hotfix1", "113")]:
        Path(work, "project.yml").write_text(f'settings:\n  base:\n    CURRENT_PROJECT_VERSION: "{build}"\n')
        git("add", "project.yml"); git("commit", "-q", "-m", tag); git("tag", tag)
    Path(work, "project.yml").write_text('    CURRENT_PROJECT_VERSION: "999"\n')
    git("add", "project.yml"); git("commit", "-q", "-m", "backup"); git("tag", "backup/2026-11-07-x")
    r = bash(gates + f'\nprevious_release_build "{work}"')
    assert r.stdout.strip() == "113", (r.stdout, r.stderr)
    passed += 1
    empty = Path(work, "empty"); empty.mkdir()
    subprocess.run(["git", "-C", str(empty), "init", "-q"], check=True)
    r = bash(gates + f'\nprevious_release_build "{empty}"; echo "[$(previous_release_build "{empty}")]"')
    assert r.returncode == 0 and r.stdout.strip().endswith("[]"), (r.stdout, r.stderr)
    passed += 1

    # 4) 공증 실패 안내 (리뷰 build-release-docs-F-3): 비-0 종료여도 출력·제출 ID·로그 명령을 보여 주고 1을 돌려준다
    bin_dir = Path(work, "bin"); bin_dir.mkdir()
    for name, body in [("fail_with_id", 'echo "  id: 1234-abcd"; echo "  status: Invalid"; exit 1'),
                       ("fail_no_id", 'echo "Error: HTTP 401"; exit 69'),
                       ("accepted", 'echo "  id: 5555"; echo "  status: Accepted"; exit 0'),
                       ("invalid_rc0", 'echo "  id: 7777"; echo "  status: Invalid"; exit 0')]:
        tool = bin_dir / "xcrun"
        tool.write_text("#!/bin/bash\n" + body + "\n"); tool.chmod(0o755)
        r = bash(gates + '\nNOTARY_PROFILE=haneul-notary\nnotary_submit /dev/null "App" && echo RC0 || echo RC1',
                 env={"PATH": f"{bin_dir}:{os.environ['PATH']}"})
        out = r.stdout + r.stderr
        if name == "accepted":
            assert "RC0" in r.stdout and "status: Accepted" in out, (name, out)
        else:
            assert "RC1" in r.stdout, (name, out)
            assert "not accepted" in out, (name, out)
            if name == "fail_no_id":
                assert "HTTP 401" in out and "No submission ID" in out, (name, out)
            else:
                assert "notarytool log" in out and ("1234-abcd" in out or "7777" in out), (name, out)
        passed += 1

# 5) PACKAGE_ONLY·ZIP_ONLY 값 (리뷰 build-release-docs-F-2)
for env, rc in [({"PACKAGE_ONLY": "1"}, 0), ({"PACKAGE_ONLY": "0"}, 0), ({"ZIP_ONLY": "1"}, 0), ({}, 0),
                ({"PACKAGE_ONLY": "true"}, 2), ({"PACKAGE_ONLY": "yes"}, 2), ({"ZIP_ONLY": "2"}, 2), ({"PACKAGE_ONLY": " 1"}, 2)]:
    clean = {k: v for k, v in os.environ.items() if k not in ("PACKAGE_ONLY", "ZIP_ONLY")}
    r = subprocess.run(["/bin/bash", "-c", "set -euo pipefail\n" + flags + "\necho OK"], capture_output=True, text=True,
                       env={**clean, **env})
    assert r.returncode == rc, (env, r.returncode, r.stdout, r.stderr)
    passed += 1
mode = source[source.index("PACKAGE_MODE=0"):source.index("\n", source.index('then PACKAGE_MODE=1; fi'))]
for env, expected in [({"PACKAGE_ONLY": "0", "ZIP_ONLY": "1"}, "1"), ({"PACKAGE_ONLY": "1"}, "1"), ({}, "0"), ({"ZIP_ONLY": "0"}, "0")]:
    clean = {k: v for k, v in os.environ.items() if k not in ("PACKAGE_ONLY", "ZIP_ONLY")}
    r = subprocess.run(["/bin/bash", "-c", mode + '\necho "$PACKAGE_MODE"'], capture_output=True, text=True, env={**clean, **env})
    assert r.stdout.strip() == expected, (env, r.stdout, r.stderr)
    passed += 1
assert 'if [[ "$PACKAGE_MODE" == "1" ]]; then' in source and 'if [[ "${PACKAGE_ONLY:-${ZIP_ONLY:-0}}" == "1" ]]' not in source
assert source.count('notary_submit "$') == 2 and "SUBMIT_OUTPUT=$(" not in source and "DMG_SUBMIT=$(" not in source
passed += 2
print(f"Build release gates: {passed} passed, 0 failed")

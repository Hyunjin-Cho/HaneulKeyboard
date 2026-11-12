#!/usr/bin/env python3
"""2026-11-07 (#175): 빌드 없이 잡을 수 있는 번들 사전 사고를 여기서 막는다.

1. 번들 표가 번들 사전 합집합과 정확히 같은가. 오너 결정으로 web2 낱말은 저장소와 앱에 들어가면 안 된다.
2. project.yml의 입력기 리소스와 제외 목록이 dict_work/dict_manifest.tsv와 맞는가.
   표가 번들에서 빠지면 오류 없이 번들 사전 낱말이 변환되지 않는다.
3. scripts/verify_license_resources.py가 표 누락·낡은 사본을 거부하는가(가짜 번들로 확인한다).
   2026-11-07 (#178): 가짜 입력기에도 실제로 컴파일한 작은 실행 파일을 넣는다 — 검증기가 입력기 바이너리의 네트워크 심볼도 보기 때문이다.
scripts/run_ime_tests.sh가 함께 돌린다.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts/verify_license_resources.py"
sys.path.insert(0, str(ROOT / "scripts"))
from build_english_table import TABLE, bundled_words  # noqa: E402
from verify_license_resources import FILES, IME_DICTIONARIES  # noqa: E402
from test_ime_no_network import compile_benign, swiftc  # noqa: E402

failures = 0
checks = 0


def check(condition, label):
    global failures, checks
    checks += 1
    if not condition:
        failures += 1
        print(f"FAIL {label}")


def manifest():
    rows = []
    for line in (ROOT / "dict_work/dict_manifest.tsv").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            fields = line.split("\t")
            rows.append((fields[0].strip(), fields[1].strip()))
    return rows


def check_table():
    lines = TABLE.read_text(encoding="ascii").splitlines()
    body = [line for line in lines if not line.startswith("#")]
    header = [line for line in lines if line.startswith("#")]
    allowed = bundled_words()
    foreign = sorted(set(body) - allowed)
    missing = sorted(allowed - set(body))
    check(not foreign, f"표 ⊆ 번들 사전 합집합: 번들 사전에 없는 낱말 {foreign[:10]}")
    check(not missing, f"번들 사전 합집합 ⊆ 표: 빠진 낱말 {missing[:10]}")
    check(body == sorted(set(body)), "표: 바이트 순 정렬, 중복 없음")
    check(f"# count: {len(body)}" in header, "표: count 머리글")
    check(any("NOT included" in line and "eb2" in line for line in header), "표 머리글: web2가 포함되지 않는다고 적는다")
    check(not (ROOT / "dict_work/web2_snapshot.txt").exists(), "저장소에 web2 사본을 두지 않는다")
    result = subprocess.run([sys.executable, str(ROOT / "scripts/build_english_table.py"), "--check"], capture_output=True, text=True)
    check(result.returncode == 0, "build_english_table.py --check 통과")


def ime_resource_block():
    """입력기 타깃의 `- path: Resources/IM` 항목에 딸린 줄들."""
    text = (ROOT / "project.yml").read_text(encoding="utf-8")
    target = text.split("\n  HaneulKeyboardIM:\n", 1)[1]
    target = target.split("\n    info:\n", 1)[0]
    match = re.search(r"\n( *)- path: Resources/IM\n((?:\1  .*\n|\1    .*\n)*)", target + "\n")
    return match.group(2) if match else None


def check_project():
    block = ime_resource_block()
    check(block is not None, "project.yml: 입력기 타깃에 Resources/IM 항목이 있다")
    if block is None:
        return
    check("buildPhase: resources" in block, "project.yml: Resources/IM이 리소스 단계다")
    excluded = set(re.findall(r"^\s*- (\S+)\s*$", block, re.M))
    rows = manifest()
    broad_only = {f"{name}.txt" for name, role in rows if role == "broad"}
    curated = {f"{name}.txt" for name, role in rows if role == "curated"}
    check(bool(curated), "manifest: curated 사전이 있다")
    check(excluded == broad_only, f"project.yml: 제외 목록이 manifest의 broad 전용과 같다 ({sorted(excluded ^ broad_only)})")
    for name in sorted(IME_DICTIONARIES):
        check(name not in excluded, f"project.yml: 런타임이 읽는 {name}를 제외하지 않는다")
        check((ROOT / "Resources/IM" / name).is_file(), f"Resources/IM에 {name}가 있다")
    check(curated <= IME_DICTIONARIES, "검증 목록: curated 사전을 모두 포함한다")
    # 메인 앱은 영어 사전을 싣지 않는다. 표를 메인 앱에 잘못 넣으면 번들만 커진다.
    app_target = (ROOT / "project.yml").read_text(encoding="utf-8").split("\n  HaneulKeyboardIM:\n", 1)[0]
    check("Resources/IM\n" not in app_target and "english_bundled" not in app_target, "project.yml: 메인 앱에 영어 표를 넣지 않는다")


def fake_ime(root, executable, drop=None, stale=None):
    resources = root / "HaneulKeyboardIM.app/Contents/Resources"
    resources.mkdir(parents=True)
    macos = root / "HaneulKeyboardIM.app/Contents/MacOS"
    macos.mkdir(parents=True)
    shutil.copy2(executable, macos / "HaneulKeyboardIM")
    for name, source in FILES.items():
        (resources / name).write_bytes(source.read_bytes())
    for name in IME_DICTIONARIES:
        if name == drop:
            continue
        data = (ROOT / "Resources/IM" / name).read_bytes()
        (resources / name).write_bytes(b"# stale\n" + data if name == stale else data)
    return root / "HaneulKeyboardIM.app"


def fake_app(root, executable, drop_license=None, **ime):
    app = root / "HaneulKeyboard.app"
    resources = app / "Contents/Resources"
    resources.mkdir(parents=True)
    for name, source in FILES.items():
        (resources / name).write_bytes(source.read_bytes())
    # 2026-11-12 (#228): 메인 앱에는 글꼴 OFL 사본도 실린다(verify_license_resources가 같은 바이트인지 본다).
    for source in sorted((ROOT / "Resources/Onboarding").glob("*-OFL.txt")):
        if source.name != drop_license:
            (resources / source.name).write_bytes(source.read_bytes())
    helpers = app / "Contents/Helpers"
    helpers.mkdir()
    fake_ime(helpers, executable, **ime)
    return app


def verifies(path):
    return subprocess.run([sys.executable, str(VERIFY), str(path)], capture_output=True, text=True).returncode == 0


def check_verifier():
    with tempfile.TemporaryDirectory(prefix="haneul-bundle-check-") as scratch:
        base = Path(scratch)

        def fresh(name):
            path = base / name
            path.mkdir()
            return path

        benign = compile_benign(base)
        networked = swiftc(base, "socket-binary", "import Darwin\nlet fd = socket(AF_INET, SOCK_STREAM, 0)\nprint(fd)\n")

        check(verifies(fake_ime(fresh("ok-ime"), benign)), "검증: 온전한 입력기 통과")
        check(verifies(fake_app(fresh("ok-app"), benign)), "검증: 온전한 앱 + 내장 입력기 통과")
        check(not verifies(fake_app(fresh("no-ofl-app"), benign, drop_license="MaruBuri-OFL.txt")), "검증: 앱에 글꼴 OFL 사본이 없으면 실패")
        check(not verifies(fake_ime(fresh("no-table"), benign, drop="english_bundled.txt")), "검증: 입력기에 표가 없으면 실패")
        check(not verifies(fake_app(fresh("no-table-app"), benign, drop="english_bundled.txt")), "검증: 내장 입력기에 표가 없으면 실패")
        check(not verifies(fake_ime(fresh("stale"), benign, stale="english_bundled.txt")), "검증: 낡은 표면 실패")
        check(not verifies(fake_ime(fresh("no-curated"), benign, drop="english_common.txt")), "검증: curated 사전이 없으면 실패")
        check(not verifies(fake_ime(fresh("networked"), networked)), "검증: 입력기 바이너리가 네트워크 심볼을 쓰면 실패")
        check(not verifies(fake_app(fresh("networked-app"), networked)), "검증: 내장 입력기 바이너리가 네트워크 심볼을 쓰면 실패")
        no_exe = fresh("no-exe")
        shutil.rmtree(fake_ime(no_exe, benign) / "Contents/MacOS")
        check(not verifies(no_exe / "HaneulKeyboardIM.app"), "검증: 입력기 실행 파일이 없으면 실패")


check_table()
check_project()
check_verifier()
print(f"bundle dictionaries: {checks - failures} passed, {failures} failed")
sys.exit(1 if failures else 0)

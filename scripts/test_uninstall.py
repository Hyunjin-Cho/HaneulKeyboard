#!/usr/bin/env python3
"""2026-10-11 B안: thin wrapper의 컴파일/실행 실패 전파. 제품 삭제 검사는 UninstallTests.swift."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
scenarios = ["success", "failure", "cancel", "compiler-failure", "no-compiler", "help", "unknown-option", "inspect"]
with tempfile.TemporaryDirectory(prefix="haneul-removal-wrapper-") as scratch:
    for scenario in scenarios:
        case = Path(scratch) / scenario
        tools = case / "tools"
        tools.mkdir(parents=True)
        journal = case / "calls.jsonl"
        # 실제 개인 설정이나 OS 제거 명령을 실행하지 않는다.
        for name in ["dirname", "uname", "mktemp", "rm"]:
            (tools / name).symlink_to(shutil.which(name))
        compiler = tools / "swiftc"
        if scenario != "no-compiler":
            compiler.write_text("#!" + shutil.which("python3") + "\n" + '''
from pathlib import Path
import json, os, sys
args = sys.argv[1:]
with open(os.environ['HANEUL_WRAPPER_LOG'], 'a') as f: f.write(json.dumps(args) + '\\n')
if os.environ['HANEUL_WRAPPER_CASE'] == 'compiler-failure': sys.exit(2)
out = Path(args[args.index('-o') + 1])
out.write_text("#!/bin/bash\\necho 'fixture-product: $*'\\nexit " + ('1' if os.environ['HANEUL_WRAPPER_CASE'] in ('failure', 'cancel') else '0') + "\\n")
out.chmod(0o700)
''')
            compiler.chmod(0o700)
        args = ["--help"] if scenario == "help" else ["--inspect"] if scenario == "inspect" else ["--unknown"] if scenario == "unknown-option" else []
        result = subprocess.run(["/bin/bash", str(root / "scripts/uninstall.sh"), *args], capture_output=True, text=True,
            env={**os.environ, "PATH": str(tools), "HANEUL_WRAPPER_LOG": str(journal), "HANEUL_WRAPPER_CASE": scenario})
        expected = {"failure": 1, "cancel": 1, "compiler-failure": 2, "no-compiler": 69, "unknown-option": 64}.get(scenario, 0)
        assert result.returncode == expected, (scenario, result.stdout, result.stderr)
        if scenario in ("help", "unknown-option", "no-compiler"):
            assert not journal.exists(), scenario
        else:
            calls = [json.loads(line) for line in journal.read_text().splitlines()]
            assert len(calls) == 1
            for file in ("Shared/RemovalPolicy.swift", "Shared/RemovalObservation.swift", "Shared/RemovalAdminScript.swift", "scripts/RemovalCommand.swift"):
                assert str(root / file) in calls[0], (scenario, file)
            assert ("fixture-product" in result.stdout) == (scenario != "compiler-failure")
            assert not Path(calls[0][calls[0].index("-o") + 1]).exists(), "임시 실행기 정리"
        print(f"PASS: {scenario} — exit {result.returncode}")
print(f"Uninstall wrapper: {len(scenarios)} passed, 0 failed (제품 파일/설정 실패 주입은 Swift 검사)")

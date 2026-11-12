#!/usr/bin/env python3
"""2026-11-12 (#228, 리뷰 build-release-docs-F-5): 글꼴 ↔ OFL 사본 짝 검사의 대조군. 네트워크·빌드 없음."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verify_bundle_resources", HERE / "verify_bundle_resources.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

real = [p.name for p in (HERE.parent / "Resources/Onboarding").iterdir() if p.is_file()]
cases = [
    ("저장소의 실제 폴더", real, 0),
    ("OFL을 지운 사본", [n for n in real if n != "MaruBuri-OFL.txt"], 1),
    ("글꼴 없이 남은 OFL", [n for n in real if not n.startswith("NanumPenScript-Regular")], 1),
    ("새 글꼴만 추가", real + ["Pretendard-Regular.otf"], 1),
    ("새 글꼴 + OFL", real + ["Pretendard-Regular.otf", "Pretendard-OFL.txt"], 0),
    ("대문자 확장자", ["Gowun-Regular.TTF", "Gowun-OFL.txt"], 0),
]
for name, names, expected in cases:
    problems = module.font_license_problems(names)
    assert len(problems) == expected, (name, problems)
    print(f"PASS: {name} — 문제 {len(problems)}")
print(f"Font licenses: {len(cases)} passed, 0 failed")

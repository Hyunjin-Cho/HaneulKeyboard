#!/usr/bin/env python3
"""앱 번들에 실리는 폴더 자원(Resources/Onboarding · Settings · MenuBar)이 코드나 JSON에서 참조되는지 대조한다.

2026-11-07 (#177, 리뷰 app-ui-F-5): project.yml이 이 폴더들을 통째로 리소스로 복사하므로, 코드가 더 안 쓰는 파일이 남아도
빌드는 조용히 통과하고 앱·ZIP·DMG만 무거워진다(실제로 쓰이지 않는 RisoPaper.png 3MB가 한 달 넘게 실렸다).
네트워크·빌드 없이 파일 글만 읽는다. 실행: python3 -I scripts/verify_bundle_resources.py (저장소 어디서든).

참조로 인정하는 것(느슨하게, 지나친 거짓 경보를 피한다):
  1. Sources/·Shared/·IMESources/ 의 Swift 글자(문자열 리터럴)가 파일 이름(확장자·@2x 제외)과 같거나 확장자만 다른 경우.
  2. 보간이 든 리터럴(`SettingsBand_\\(tab.bandName)`)은 보간 앞 글자 + 같은 파일의 다른 리터럴이 파일 이름과 같을 때.
  3. 폴더의 JSON(OnboardingScroll.json · OnboardingPeople.json)에 든 문자열 값의 파일 이름.
참조 없이 싣는 것은 글꼴 라이선스 파일(*-OFL.txt)뿐이다 — 글꼴과 함께 배포해야 한다.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCE_DIRS = ["Resources/Onboarding", "Resources/Settings", "Resources/MenuBar"]
SOURCE_DIRS = ["Sources", "Shared", "IMESources"]
LICENSE_FILES = re.compile(r".+-OFL\.txt$")

LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def stem(name: str) -> str:
    base = name.rsplit(".", 1)[0] if "." in name else name
    return re.sub(r"@\dx$", "", base)


def swift_literals() -> tuple[set[str], list[tuple[str, set[str]]]]:
    plain: set[str] = set()
    interpolated: list[tuple[str, set[str]]] = []  # (보간 앞 글자, 같은 파일의 일반 리터럴)
    for directory in SOURCE_DIRS:
        for path in sorted((ROOT / directory).glob("*.swift")):
            found = LITERAL.findall(path.read_text(encoding="utf-8"))
            file_plain = {text for text in found if "\\(" not in text}
            plain |= file_plain
            for text in found:
                if "\\(" in text:
                    interpolated.append((text.split("\\(", 1)[0], file_plain))
    return plain, interpolated


def json_strings(value) -> set[str]:
    if isinstance(value, str):
        return {value}
    if isinstance(value, list):
        return set().union(*(json_strings(item) for item in value)) if value else set()
    if isinstance(value, dict):
        return set().union(*(json_strings(item) for item in value.values())) if value else set()
    return set()


def main() -> int:
    plain, interpolated = swift_literals()
    plain_stems = {stem(text) for text in plain}
    json_stems: set[str] = set()
    for directory in RESOURCE_DIRS:
        for path in (ROOT / directory).glob("*.json"):
            json_stems |= {stem(Path(text).name) for text in json_strings(json.loads(path.read_text(encoding="utf-8")))}

    unreferenced: list[str] = []
    checked = 0
    for directory in RESOURCE_DIRS:
        folder = ROOT / directory
        if not folder.is_dir():
            print(f"FAIL 자원 폴더가 없어요: {directory}")
            return 1
        for path in sorted(folder.iterdir()):
            if not path.is_file() or path.name.startswith("."):
                continue
            checked += 1
            if LICENSE_FILES.match(path.name):
                continue
            name = stem(path.name)
            if name in plain_stems or name in json_stems:
                continue
            if any(name.startswith(prefix) and name[len(prefix):] in file_plain
                   for prefix, file_plain in interpolated if prefix):
                continue
            unreferenced.append(f"{directory}/{path.name}")

    if unreferenced:
        print("FAIL 코드·JSON 어디에서도 참조되지 않는 번들 자원이 있어요(앱에 실리지만 안 쓰여요):")
        for item in unreferenced:
            print(f"  {item}")
        print("쓰지 않으면 지우고(git 기록에 남아요), 쓰는 것이면 이름을 코드에서 부르는 곳을 확인해 주세요.")
        return 1
    print(f"Resources: {checked} files referenced, 0 unreferenced")
    return 0


if __name__ == "__main__":
    sys.exit(main())

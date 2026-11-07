#!/usr/bin/env python3
"""2026-10-10: 배포 앱/내장·단독 IME의 고지 원문 누락·오래된 사본을 거부한다.
2026-11-07 (#175): 입력기가 런타임에 읽는 사전도 같은 방식으로 본다. 표가 빠지면 오류 없이 번들 사전 낱말이 변환되지 않는다.
2026-11-07 (#178, 리뷰 security-overlap-F-4): 입력기 바이너리가 네트워크 심볼·프레임워크를 가져다 쓰지 않는지 `nm -u`·`otool -L`로 본다.
PRIVACY.md 2번의 '입력기에는 네트워크 코드가 없다'는 약속을 빌드된 결과물에서 기계로 지키는 자리다."""
import argparse
import re
import subprocess
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

# 2026-11-07 (#178): 알려진 네트워크 API가 입력기 실행 파일의 미해결 심볼(`nm -u`)에 있으면 거부한다.
# 이것은 알려진 이름을 지키는 그물이지 증명이 아니다 — dlsym 같은 동적 경로나 이름을 모르는 API는 못 잡는다.
# Foundation 안의 `URL`·`Data(contentsOf:)`(파일 읽기)는 네트워크 심볼이 아니라서 넣지 않았다.
NETWORK_SYMBOL = re.compile(
    r"URLSession|URLRequest|URLConnection|URLProtocol|NSURLDownload|"      # NSURLSession·Swift URLSession 등
    r"CFNetwork|CFHTTP|CFSocket|CFStreamCreatePairWithSocket|CFHost|CFNetService|"
    r"NWConnection|NWListener|NWEndpoint|NWBrowser|NWPathMonitor|\$s7Network|^_nw_|"   # Network.framework
    r"WKWebView|SCNetworkReachability|DNSService|NSNetService|"
    r"getaddrinfo|getnameinfo|gethostby|"
    r"^_(?:socket|connect|bind|listen|accept|sendto|sendmsg|recvfrom|recvmsg)$"        # BSD 소켓
)
# 직접 링크한 프레임워크·라이브러리(`otool -L`). Foundation·AppKit이 안쪽에서 CFNetwork를 끌고 오는 것은 직접 링크가 아니라 여기 안 잡힌다.
NETWORK_LIBRARY = re.compile(r"/(?:Network|CFNetwork|WebKit)\.framework/|libswiftNetwork")


def _run(tool: str, executable: Path) -> list[str]:
    flag = "-u" if tool == "nm" else "-L"
    result = subprocess.run([tool, flag, str(executable)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"FAIL: `{tool} {flag}`를 실행하지 못했다: {executable}: {result.stderr.strip()[:200]}")
    return result.stdout.splitlines()


def network_findings(executable: Path) -> list[str]:
    """실행 파일이 가져다 쓰는 네트워크 심볼·라이브러리 목록. 도구가 실패하거나 심볼을 하나도 못 읽으면 SystemExit(닫힌 실패)."""
    symbols = [line.strip() for line in _run("nm", executable)]
    names = [line for line in symbols if line and not line.endswith(":")]
    if not names:
        raise SystemExit(f"FAIL: 미해결 심볼을 하나도 읽지 못했다(Mach-O가 아니거나 비었다): {executable}")
    found = sorted({line for line in names if NETWORK_SYMBOL.search(line)})
    libraries = sorted({line.strip().split(" (")[0] for line in _run("otool", executable)
                        if NETWORK_LIBRARY.search(line)})
    return found + libraries


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
        executable = app / "Contents/MacOS/HaneulKeyboardIM"
        if not executable.is_file():
            raise SystemExit(f"FAIL: missing IME executable: {executable}")
        found = network_findings(executable)
        if found:
            raise SystemExit(f"FAIL: 입력기 바이너리가 네트워크 심볼·라이브러리를 쓴다: {found[:8]}")
    print(f"PASS: current LICENSE + NOTICE + acknowledgements + legacy MIT: {app}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apps", nargs="+", type=Path)
    args = parser.parse_args()
    if b"Apache License" not in FILES["LICENSE"].read_bytes():
        raise SystemExit("FAIL: expected Apache License")
    for app in args.apps:
        verify(app)

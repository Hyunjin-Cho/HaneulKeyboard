#!/usr/bin/env python3
"""2026-11-07 (#178, 리뷰 security-overlap-F-4): 입력기에 네트워크 코드가 없다는 약속(PRIVACY.md 2번)을 기계로 지킨다.

입력기는 앱 샌드박스도 네트워크 차단도 없는 일반 프로세스라, 막는 것은 '코드가 없다'는 사실뿐이다. 그 사실이 조용히 깨지는 것을 두 곳에서 잡는다.

1. 소스: project.yml의 입력기 타깃이 컴파일하는 소스(IMESources/·Shared/·Sources/BundleTrust.swift)에
   알려진 네트워크 API 이름이 없다. 주석은 보지 않는다.
2. 바이너리: 빌드된 입력기의 `nm -u`·`otool -L`에 네트워크 심볼·프레임워크가 없다 — 이 검사는 scripts/verify_license_resources.py가
   번들 검증 때 한다. 여기서는 그 검사기가 진짜로 잡는지 실제 컴파일한 작은 실행 파일(URLSession·BSD 소켓·Network.framework를 일부러 쓴
   것)로 대조군을 돌린다. 대조군이 통과하면(= 못 잡으면) 이 시험이 실패한다.

둘 다 알려진 이름을 지키는 그물이지 증명이 아니다(샌드박스·dlsym 같은 동적 경로는 못 잡는다). 장기 대책(App Sandbox)은 하지 않기로 했다.
scripts/run_ime_tests.sh가 함께 돌린다.

사용: python3 scripts/test_ime_no_network.py            # 저장소 루트
      python3 scripts/test_ime_no_network.py --root DIR  # 소스 검사만 다른 트리에서(일부러 넣은 줄이 잡히는지 손으로 볼 때)
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import verify_license_resources as verify  # noqa: E402

SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".c", ".cc", ".cpp"}
# 소스 단계의 알려진 네트워크 API 이름. 식별자라서 주석을 걷어낸 글에서 찾는다.
SOURCE_NETWORK = re.compile(
    r"\b(?:URLSession\w*|URLRequest|NSURLRequest|NSMutableURLRequest|URLConnection|NSURLConnection|NSURLSession\w*|URLProtocol|NSURLProtocol|"
    r"NWConnection|NWListener|NWBrowser|NWEndpoint|NWPathMonitor|CFNetwork\w*|CFHTTP\w*|CFSocket\w*|CFHost\w*|CFNetService\w*|"
    r"CFStreamCreatePairWithSocket\w*|getStreamsToHost\w*|NSNetService\w*|NetService\w*|WKWebView|SCNetworkReachability\w*|"
    r"DNSService\w*|getaddrinfo|getnameinfo|gethostby\w*)\b"
    r"|\bimport\s+(?:Network|WebKit|CFNetwork|MultipeerConnectivity|GameKit)\b"
    r"|\bsocket\s*\("
    r"|\bURL\s*\(\s*string\s*:"
    r"|\bhttps?://"
)
# 줄 주석의 `//`는 줄 처음이나 공백 뒤에서만 센다 — 문자열 속 `https://`의 `//`가 뒤를 통째로 지우면 http 주소를 놓친다.
COMMENTS = re.compile(r"/\*.*?\*/|(?:(?<=\s)|^)//[^\n]*", re.S | re.M)

failures = 0
checks = 0


def check(condition, label):
    global failures, checks
    checks += 1
    if not condition:
        failures += 1
        print(f"FAIL {label}")


def ime_source_paths(root: Path):
    """project.yml의 입력기 타깃 sources 중 리소스 단계가 아닌 경로."""
    text = (root / "project.yml").read_text(encoding="utf-8")
    block = text.split("\n  HaneulKeyboardIM:\n", 1)[1].split("\n    info:\n", 1)[0]
    block = block.split("\n    sources:\n", 1)[1]
    paths = []
    for entry in re.split(r"\n      - path: ", "\n" + block)[1:]:
        lines = entry.splitlines()
        if not any("buildPhase: resources" in line for line in lines[1:]):
            paths.append(lines[0].strip())
    return paths


def source_files(root: Path, paths):
    files = []
    for relative in paths:
        target = root / relative
        if target.is_dir():
            files += sorted(p for p in target.rglob("*") if p.is_file() and p.suffix in SOURCE_SUFFIXES)
        elif target.is_file():
            files.append(target)
    return files


def source_findings(text: str):
    return sorted({m.group(0) for m in SOURCE_NETWORK.finditer(COMMENTS.sub("", text))})


def check_sources(root: Path):
    paths = ime_source_paths(root)
    check({"IMESources", "Shared"} <= set(paths), f"project.yml: 입력기 소스에 IMESources·Shared가 있다 ({paths})")
    files = source_files(root, paths)
    check(len(files) > 20, f"입력기 소스 파일을 찾았다 ({len(files)}개)")
    for path in files:
        found = source_findings(path.read_text(encoding="utf-8", errors="replace"))
        check(not found, f"입력기 소스에 네트워크 API가 없다: {path.relative_to(root)} → {found}")


def check_source_controls():
    """검사기가 실제로 잡는지: 일부러 넣은 줄은 잡고, 주석 속 이름과 파일 읽기는 잡지 않는다."""
    for label, code in [
        ("URLSession", "let t = URLSession.shared.dataTask(with: u)"),
        ("NSURLConnection", "let c = NSURLConnection(request: r, delegate: nil)"),
        ("Network 가져오기", "import Network"),
        ("NWConnection", "let c = NWConnection(host: h, port: p, using: .tcp)"),
        ("BSD socket", "let fd = socket(AF_INET, SOCK_STREAM, 0)"),
        ("getaddrinfo", "getaddrinfo(host, nil, nil, &res)"),
        ("URL(string:)", 'let u = URL(string: "x")'),
        ("http 주소", 'let s = "https://example.invalid"'),
        ("CFHTTP", "CFHTTPMessageCreateRequest(nil, m, u, v)"),
    ]:
        check(bool(source_findings(code)), f"대조군(잡혀야 함): {label}")
    for label, code in [
        ("줄 주석 속 이름", "// URLSession은 쓰지 않는다 https://example.invalid"),
        ("블록 주석 속 이름", "/* URLSession\n socket(...) */ let x = 1"),
        ("파일 URL 읽기", "let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)"),
        ("낱말 일부", "let sessionURLSessionless = 1"),
    ]:
        check(not source_findings(code), f"대조군(안 잡혀야 함): {label}")


def swiftc(directory: Path, name: str, code: str) -> Path:
    source = directory / f"{name}.swift"
    source.write_text(code, encoding="utf-8")
    output = directory / name
    result = subprocess.run(
        ["swiftc", "-module-cache-path", str(directory / "module-cache"), "-o", str(output), str(source)],
        capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAIL 대조군 컴파일 실패 {name}: {result.stderr.strip()[:300]}")
        sys.exit(1)
    return output


def compile_benign(directory: Path) -> Path:
    """네트워크를 쓰지 않는 작은 실행 파일. 가짜 번들(scripts/test_bundle_dictionaries.py)도 이 파일을 쓴다."""
    return swiftc(directory, "benign", 'import Foundation\nprint(URL(fileURLWithPath: "/tmp").path)\n')


def check_binaries():
    with tempfile.TemporaryDirectory(prefix="haneul-nonet-") as scratch:
        directory = Path(scratch)
        benign = compile_benign(directory)
        check(verify.network_findings(benign) == [], "바이너리 대조군(안 잡혀야 함): 네트워크 없는 실행 파일")
        controls = {
            "URLSession": ("import Foundation\nlet u = URL(string: \"https://example.invalid\")!\n"
                           "let t = URLSession.shared.dataTask(with: u)\nprint(t)\n", None),
            "BSD socket": ("import Darwin\nlet fd = socket(AF_INET, SOCK_STREAM, 0)\nprint(fd)\n", "_socket"),
            "Network.framework": ("import Network\nlet c = NWConnection(host: \"example.invalid\", port: 80, using: .tcp)\n"
                                  "print(c)\n", None),
        }
        for label, (code, expected) in controls.items():
            executable = swiftc(directory, label.replace(" ", "-").replace(".", ""), code)
            found = verify.network_findings(executable)
            check(bool(found), f"바이너리 대조군(잡혀야 함): {label} → {found[:3]}")
            if expected:
                check(expected in found, f"바이너리 대조군: {label}에서 {expected}를 찾는다 → {found[:5]}")
        # Mach-O가 아닌 파일은 조용히 통과하지 않고 실패해야 한다(닫힌 실패).
        fake = directory / "not-macho"
        fake.write_text("hello\n", encoding="utf-8")
        try:
            verify.network_findings(fake)
            check(False, "Mach-O가 아닌 파일은 실패해야 한다")
        except SystemExit:
            check(True, "Mach-O가 아닌 파일은 실패한다")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT, help="소스 검사에 쓸 트리(기본: 저장소 루트)")
    args = parser.parse_args()
    check_sources(args.root)
    check_source_controls()
    check_binaries()
    print(f"ime no network: {checks - failures} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

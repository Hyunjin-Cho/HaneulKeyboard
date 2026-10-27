#!/usr/bin/env bash
# 2026-10-11 B안: 앱과 같은 Swift 정책·관측 코드를 임시 실행기로 컴파일한다.
# 새 설치 서비스/상주 helper가 아니다. 메인 앱이 안 열릴 때 개발 도구가 있는 환경의 복구용.
# 정확한 정식 IME 두 경로만 대상. 백업·Downloads·개발 산출물·휴지통은 지우지 않는다.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -gt 1 ]] || [[ "$#" -eq 1 && "$1" != "--help" && "$1" != "--inspect" ]]; then
    echo "사용법: bash scripts/uninstall.sh [--inspect | --help]" >&2
    exit 64
fi
if [[ "${1:-}" == "--help" ]]; then
    echo '사용법: bash scripts/uninstall.sh [--inspect | --help]'
    echo '정식 입력기·설정만 정리하며 메인 앱은 Finder에서 직접 제거해 주세요.'
    echo 'Swift/Xcode 명령줄 도구가 필요해요. --inspect는 조회만 해요.'
    exit 0
fi
if ! command -v swiftc >/dev/null 2>&1; then
    echo 'Swift 명령줄 도구를 찾지 못해 아무것도 지우지 않았어요. 설치한 앱의 설정 → 앱 관리 → 전체 제거를 이용해 주세요.' >&2
    exit 69
fi
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" -module-cache-path "$WORK_DIR/module-cache" \
    "$ROOT_DIR/Shared/RemovalPolicy.swift" "$ROOT_DIR/Shared/RemovalObservation.swift" \
    "$ROOT_DIR/Shared/RemovalAdminScript.swift" "$ROOT_DIR/Sources/BundleTrust.swift" \
    "$ROOT_DIR/scripts/RemovalCommand.swift" "$ROOT_DIR/scripts/RemovalCommandMain.swift" \
    -o "$WORK_DIR/uninstall"
"$WORK_DIR/uninstall" "$@"

#!/bin/bash
# 2026-10-07 (#83): 실제 Updater + 가짜 HTTP 응답. 네트워크/설치/실제 앱 설정 변경 없음.
set -euo pipefail
cd "$(dirname "$0")/.."
# 2026-11-13 (#226, 리뷰 install-update-F-5): 시험 설정 도메인을 고정 이름으로 바꿔(`TestPreferenceDomains`) 파일이 쌓이지 않는 대신,
# 같은 Mac에서 두 실행(다른 worktree 포함)이 겹치면 서로의 값을 지운다. 사용자 임시 폴더의 잠금 파일로 차례를 지킨다(최대 10분 기다림).
exec 9>"${TMPDIR:-/tmp}/haneul-updater-tests.lock"
if ! /usr/bin/lockf -s -t 600 9; then
  echo "다른 updater 시험이 10분 안에 끝나지 않아 실행하지 않았어요." >&2
  exit 75
fi
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
# 2026-11-13 (#226, 리뷰 install-update-F-6): 복구 도구를 scripts/uninstall.sh와 같은 파일 목록(그 스크립트에서 읽는다)으로 실제 컴파일하고,
# 지우지 않는 두 경로(--help → 0, 잘못된 옵션 → 64)만 실행한다. 관리자 삭제 스크립트를 함께 쓰므로 컴파일이 깨지면 여기서 드러난다.
cli_sources=()
while IFS= read -r source; do cli_sources+=("$source"); done < <(grep -o '\$ROOT_DIR/[^"]*\.swift' scripts/uninstall.sh | sed 's#\$ROOT_DIR/##')
if [[ "${#cli_sources[@]}" -lt 5 ]]; then echo "FAIL: uninstall.sh에서 복구 도구 파일 목록을 읽지 못함"; exit 1; fi
swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" -module-cache-path "$TEST_DIR/module-cache" "${cli_sources[@]}" -o "$TEST_DIR/uninstall-cli"
cli_help=0; "$TEST_DIR/uninstall-cli" --help > /dev/null || cli_help=$?
cli_bad=0; "$TEST_DIR/uninstall-cli" --unknown > /dev/null || cli_bad=$?
if [[ "$cli_help" -ne 0 || "$cli_bad" -ne 64 ]]; then
  echo "FAIL: 복구 도구 실행 (--help=$cli_help, 잘못된 옵션=$cli_bad)"
  echo "Recovery CLI: 0 passed, 1 failed"
  exit 1
fi
echo "Recovery CLI: 2 passed, 0 failed"
for configuration in Release Debug; do
flags=(-parse-as-library)
if [[ "$configuration" == Debug ]]; then flags+=(-D DEBUG); fi
swiftc "${flags[@]}" -target "$(uname -m)-apple-macos14.0" \
  Shared/RemovalPolicy.swift Shared/RemovalObservation.swift Shared/RemovalAdminScript.swift Sources/RemovalMainAppOperations.swift Sources/ProductOperationGate.swift \
  Sources/Updater.swift Sources/UpdateReplacement.swift Sources/UpdateTransport.swift Sources/BundleTrust.swift Sources/UpdateDecisions.swift Sources/InstallDecisions.swift \
  Sources/IMEInstaller.swift Sources/AppMover.swift Sources/InputSourceSettings.swift Sources/UninstallManager.swift Sources/InputSwitcher.swift Sources/Logging.swift \
  IMESources/OrphanDecision.swift Sources/LoginItem.swift \
  scripts/RemovalCommand.swift Tests/UpdaterTests.swift Tests/UpdateSecurityTests.swift Tests/UpdateReplacementTests.swift Tests/UninstallTests.swift Tests/InputSourceSettingsTests.swift Tests/InstallFlowTests.swift Tests/UpdateInstallTests.swift -o "$TEST_DIR/updater-tests"
echo "$configuration"
"$TEST_DIR/updater-tests"
done

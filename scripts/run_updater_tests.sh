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
for configuration in Release Debug; do
flags=(-parse-as-library)
if [[ "$configuration" == Debug ]]; then flags+=(-D DEBUG); fi
swiftc "${flags[@]}" -target "$(uname -m)-apple-macos14.0" \
  Shared/RemovalPolicy.swift Shared/RemovalObservation.swift Shared/RemovalAdminScript.swift Sources/RemovalMainAppOperations.swift Sources/ProductOperationGate.swift \
  Sources/Updater.swift Sources/UpdateReplacement.swift Sources/UpdateTransport.swift Sources/BundleTrust.swift Sources/UpdateDecisions.swift Sources/InstallDecisions.swift \
  Sources/IMEInstaller.swift Sources/AppMover.swift Sources/InputSourceSettings.swift Sources/UninstallManager.swift Sources/InputSwitcher.swift Sources/Logging.swift \
  IMESources/OrphanDecision.swift Sources/LoginItem.swift \
  scripts/RemovalCommand.swift Tests/UpdaterTests.swift Tests/UpdateSecurityTests.swift Tests/UpdateReplacementTests.swift Tests/UninstallTests.swift Tests/InputSourceSettingsTests.swift Tests/InstallFlowTests.swift -o "$TEST_DIR/updater-tests"
echo "$configuration"
"$TEST_DIR/updater-tests"
done

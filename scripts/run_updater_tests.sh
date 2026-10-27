#!/bin/bash
# 2026-10-07 (#83): 실제 Updater + 가짜 HTTP 응답. 네트워크/설치/실제 앱 설정 변경 없음.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
for configuration in Release Debug; do
flags=(-parse-as-library)
if [[ "$configuration" == Debug ]]; then flags+=(-D DEBUG); fi
swiftc "${flags[@]}" -target "$(uname -m)-apple-macos14.0" \
  Shared/RemovalPolicy.swift Shared/RemovalObservation.swift Shared/RemovalAdminScript.swift Sources/ProductOperationGate.swift \
  Sources/Updater.swift Sources/UpdateReplacement.swift Sources/UpdateTransport.swift Sources/BundleTrust.swift Sources/UpdateDecisions.swift Sources/InstallDecisions.swift \
  Sources/IMEInstaller.swift Sources/InputSourceSettings.swift Sources/UninstallManager.swift Sources/InputSwitcher.swift Sources/Logging.swift \
  scripts/RemovalCommand.swift Tests/UpdaterTests.swift Tests/UpdateSecurityTests.swift Tests/UpdateReplacementTests.swift Tests/UninstallTests.swift Tests/InputSourceSettingsTests.swift -o "$TEST_DIR/updater-tests"
echo "$configuration"
"$TEST_DIR/updater-tests"
done

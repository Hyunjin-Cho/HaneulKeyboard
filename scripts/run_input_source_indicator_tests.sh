#!/bin/bash
# #81 · 2026-10-12: 전환/중복/억제/늦은 타이머 정책 + 제품 패널 offscreen 계약.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" -parse-as-library -o "$TEST_DIR/policy-tests" \
  Sources/InputSourceTransitionPolicy.swift Tests/InputSourceIndicatorTests.swift
"$TEST_DIR/policy-tests"
swiftc -module-cache-path "$TEST_DIR/module-cache" -parse-as-library -o "$TEST_DIR/panel-tests" \
  Sources/InputSwitcher.swift Sources/InputSourceTransitionPolicy.swift \
  Sources/InputSourceTransitionIndicator.swift Tests/InputSourceIndicatorPanelTests.swift
"$TEST_DIR/panel-tests" "${1:-$TEST_DIR/screens}"

#!/bin/bash
# Standalone test runner for the IME composition core (no Xcode project needed).
# The composer layer is Foundation-only by design, so it compiles directly.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN="$(mktemp -d)/haneul_ime_tests"

swiftc -o "$BIN" \
  IMESources/HangulJamo.swift \
  IMESources/KeyboardLayout2Set.swift \
  IMESources/KoreanComposer.swift \
  IMESources/EnglishDetector.swift \
  IMESources/WordFrequencyStore.swift \
  Tests/ComposerTests.swift

"$BIN"

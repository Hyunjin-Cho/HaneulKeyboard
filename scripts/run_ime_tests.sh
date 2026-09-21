#!/bin/bash
# Standalone test runner for the IME composition core (no Xcode project needed).
# The composer layer is Foundation-only by design, so it compiles directly.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN="$(mktemp -d)/haneul_ime_tests"

swiftc -o "$BIN" \
  IMESources/HangulJamo.swift \
  IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift \
  IMESources/KoreanComposer.swift \
  IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift \
  IMESources/KoreanDictionary.swift \
  IMESources/OrphanDecision.swift \
  IMESources/RevertKey.swift \
  IMESources/AutoConvertPolicy.swift \
  IMESources/PersonalDictionary.swift \
  Sources/InstallDecisions.swift \
  Sources/WordSuggestion.swift \
  Sources/UpdateDecisions.swift \
  Tests/ComposerTests.swift

"$BIN"

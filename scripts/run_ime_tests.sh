#!/bin/bash
# Standalone test runner for the IME composition core (no Xcode project needed).
# The composer layer is Foundation-only by design, so it compiles directly.
set -euo pipefail

cd "$(dirname "$0")/.."

# 2026-11-07 (#175): 표가 manifest와 맞는지, 입력기 리소스 설정이 맞는지, 번들 검증이 표 누락을 잡는지 본다.
python3 scripts/test_bundle_dictionaries.py

BIN="$(mktemp -d)/haneul_ime_tests"

swiftc -o "$BIN" \
  IMESources/HangulJamo.swift \
  IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift \
  IMESources/AlphanumericWords.swift \
  IMESources/MeasurementUnits.swift \
  IMESources/PhoneticDictionary.swift IMESources/EnglishParticleSplitter.swift IMESources/KoreanComposer.swift \
  IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift \
  IMESources/KoreanDictionary.swift \
  IMESources/OrphanDecision.swift \
  IMESources/RevertKey.swift \
  IMESources/AutoConvertPolicy.swift \
  IMESources/PersonalDictionary.swift \
  Shared/RemovalPolicy.swift \
  Shared/InputInferencePolicy.swift \
  Sources/InstallDecisions.swift \
  Sources/WordSuggestion.swift \
  Sources/UpdateDecisions.swift \
  Tests/EnglishParticleTests.swift Tests/EnglishRulesTests.swift Tests/PhoneticTests.swift \
  Tests/ComposerTests.swift

"$BIN"

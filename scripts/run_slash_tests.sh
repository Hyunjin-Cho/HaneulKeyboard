#!/bin/bash
# #87 · 2026-10-12: 순수 슬래시 정책 + 실제 조합 코어 연동. OS IMK 실기 검사는 별도.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" -parse-as-library -o "$TEST_DIR/slash-tests" \
  Shared/InputInferencePolicy.swift \
  Shared/SlashEnglishSession.swift \
  IMESources/HangulJamo.swift IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift IMESources/AlphanumericWords.swift IMESources/MeasurementUnits.swift \
  IMESources/PhoneticDictionary.swift IMESources/KoreanComposer.swift IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift IMESources/KoreanDictionary.swift \
  IMESources/PersonalDictionary.swift IMESources/AutoConvertPolicy.swift \
  Tests/SlashEnglishTests.swift
"$TEST_DIR/slash-tests"

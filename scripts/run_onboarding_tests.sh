#!/bin/bash
# 실제 AppKit 텍스트 클라이언트 회귀 검사. macOS에서 실행.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -o "$TEST_DIR/onboarding-tests" \
  Sources/OnboardingPracticeField.swift \
  Sources/OnboardingPracticeProgress.swift \
  IMESources/HangulJamo.swift IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift IMESources/AlphanumericWords.swift IMESources/MeasurementUnits.swift \
  IMESources/PhoneticDictionary.swift IMESources/KoreanComposer.swift IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift IMESources/KoreanDictionary.swift \
  IMESources/PersonalDictionary.swift Tests/OnboardingPracticeTests.swift
"$TEST_DIR/onboarding-tests"

#!/bin/bash
# #14/#24/typo-policy: standalone input-only regression suite; no IME launch/installation.
set -euo pipefail
cd "$(dirname "$0")/.."
INPUT_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haneul-input-inference.XXXXXX")"
trap 'rm -rf "$INPUT_TEST_DIR"' EXIT
swiftc -module-cache-path "$INPUT_TEST_DIR/module-cache" -o "$INPUT_TEST_DIR/tests" \
  IMESources/HangulJamo.swift IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift IMESources/AlphanumericWords.swift \
  IMESources/MeasurementUnits.swift IMESources/PhoneticDictionary.swift \
  IMESources/EnglishParticleSplitter.swift IMESources/KoreanComposer.swift IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift IMESources/KoreanDictionary.swift \
  IMESources/PersonalDictionary.swift IMESources/ExternalEnglishContext.swift \
  Shared/InputInferencePolicy.swift Tests/InputInferenceTests.swift
"$INPUT_TEST_DIR/tests"

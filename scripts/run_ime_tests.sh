#!/bin/bash
# Standalone test runner for the IME composition core (no Xcode project needed).
# The composer layer is Foundation-only by design, so it compiles directly.
set -euo pipefail

cd "$(dirname "$0")/.."

# 2026-11-07 (#175): 표가 manifest와 맞는지, 입력기 리소스 설정이 맞는지, 번들 검증이 표 누락을 잡는지 본다.
python3 scripts/test_bundle_dictionaries.py

# 2026-11-07 (#178): 입력기 소스에 네트워크 API가 없는지(PRIVACY.md 2번의 약속), 번들 검증기가 입력기 바이너리의 네트워크 심볼을
# 실제로 잡는지(일부러 URLSession·소켓·Network.framework를 쓴 작은 실행 파일로 대조), 공개 문서의 상대 링크가 추적 파일을 가리키는지.
python3 scripts/test_ime_no_network.py
python3 scripts/check_doc_links.py

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

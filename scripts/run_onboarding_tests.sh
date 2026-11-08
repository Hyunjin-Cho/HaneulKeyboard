#!/bin/bash
# 실제 AppKit 텍스트 클라이언트 회귀 검사. macOS에서 실행.
# 2026-11-07 (#177): 메인 앱 화면 쪽 판단·자원 검사(Tests/AppUITests.swift)와 번들 자원 대조(verify_bundle_resources.py)를 함께 돌린다.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -o "$TEST_DIR/onboarding-tests" \
  Shared/InputInferencePolicy.swift \
  Sources/OnboardingPracticeField.swift Sources/AppFont.swift \
  Sources/OnboardingPracticeProgress.swift \
  Sources/OnboardingPageNavigation.swift \
  IMESources/HangulJamo.swift IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift IMESources/AlphanumericWords.swift IMESources/MeasurementUnits.swift \
  IMESources/PhoneticDictionary.swift IMESources/EnglishParticleSplitter.swift IMESources/KoreanComposer.swift IMESources/ManualToggle.swift \
  IMESources/EnglishDetector.swift IMESources/KoreanDictionary.swift \
  IMESources/PersonalDictionary.swift Tests/OnboardingPracticeTests.swift
"$TEST_DIR/onboarding-tests"

# 상태 아이콘 메뉴·설정·안내의 문구 판단, defaults 키 고정, 두루마리 JSON 실제 디코드와 참조 PNG 존재(리뷰 app-ui-F-1·6·7·8).
# 제품이 쓰는 같은 소스(OnboardingScrollData.swift 등)를 그대로 컴파일한다.
swiftc -parse-as-library -o "$TEST_DIR/app-ui-tests" \
  Shared/HaneulDefaultsKeys.swift \
  Sources/AppUIDecisions.swift \
  Sources/OnboardingScrollData.swift \
  Tests/AppUITests.swift
"$TEST_DIR/app-ui-tests"

# Resources/{Onboarding,Settings,MenuBar} 안의 모든 파일이 코드나 JSON에서 참조되는지(안 쓰는 자원이 번들에 실리지 않게 — 리뷰 app-ui-F-5).
python3 -I scripts/verify_bundle_resources.py

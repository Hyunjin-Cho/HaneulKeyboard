#!/bin/bash
# 2026-10-07 (#82): repo 루트에서 CSV를 stdout으로 출력. 설치본 IMK 실기와 구분한다.
set -euo pipefail
cd "$(dirname "$0")/.."
UNIT_AUDIT_WORK=$(mktemp -d)
trap 'rm -rf "$UNIT_AUDIT_WORK"' EXIT
swiftc -O -module-cache-path "$UNIT_AUDIT_WORK/cache" -o "$UNIT_AUDIT_WORK/audit" \
  IMESources/HangulJamo.swift IMESources/KeyboardLayout2Set.swift \
  IMESources/Contractions.swift IMESources/AlphanumericWords.swift IMESources/MeasurementUnits.swift \
  IMESources/PhoneticDictionary.swift IMESources/KoreanComposer.swift IMESources/EnglishDetector.swift \
  IMESources/KoreanDictionary.swift IMESources/PersonalDictionary.swift \
  Tools/MeasurementUnitAudit.swift
"$UNIT_AUDIT_WORK/audit"

#!/usr/bin/env bash
# build_notarize_install.sh — single-shot build → notarize → system-install → verify
# for HaneulKeyboard IME targets. Run on the MacBook Air (has Developer ID + notarytool profile).
#
# Usage:
#   scripts/build_notarize_install.sh <Target>
#   e.g. scripts/build_notarize_install.sh Test3IM
#        scripts/build_notarize_install.sh HaneulKeyboardIM
#
# The script will:
#   1. Verify toolchain + credentials are present.
#   2. xcodegen → xcodebuild Release.
#   3. ditto → notarytool submit --wait → stapler.
#   4. sudo install to /Library/Input Methods/ (system-wide).
#   5. Re-register with LaunchServices.
#   6. Restart the IM process.
#   7. Print next steps for TIS picker verification.

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <Target> (e.g. Test3IM, HaneulKeyboardIM, Test1IM, Test2IM)"
    exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE="haneul-notary"
DEVID_CERT_PATTERN="Developer ID Application: Hyunjin Cho"

# Main app vs IME bundle install destinations differ.
# - HaneulKeyboard (GUI menu-bar app): /Applications — required for stable
#   SMAppService.mainApp registration (login-at-start needs a known location).
# - *IM (input method bundles): /Library/Input Methods — where macOS TIS daemon
#   enumerates from.
case "$TARGET" in
    HaneulKeyboard) INSTALL_DIR="/Applications"; IS_MAIN_APP=1 ;;
    *)              INSTALL_DIR="/Library/Input Methods"; IS_MAIN_APP=0 ;;
esac

cd "$PROJECT_ROOT"

echo "════════════════════════════════════════════"
echo "  Build + Notarize + Install: $TARGET"
echo "  Project: $PROJECT_ROOT"
echo "════════════════════════════════════════════"
echo

# ─── 1. Pre-flight checks ───────────────────────────
echo "→ Pre-flight"
command -v xcodegen >/dev/null || { echo "  ✗ xcodegen not installed (brew install xcodegen)"; exit 1; }
command -v xcodebuild >/dev/null || { echo "  ✗ xcodebuild not found"; exit 1; }

if ! security find-identity -p codesigning -v | grep -q "$DEVID_CERT_PATTERN"; then
    echo "  ✗ Developer ID Application cert missing in keychain ($DEVID_CERT_PATTERN)"
    echo "    This script must run on the MacBook Air where the cert is provisioned."
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "  ✗ notarytool keychain profile '$NOTARY_PROFILE' missing."
    echo "    Re-create with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <email> --team-id 6RH6FXY82P"
    exit 1
fi
echo "  ✓ Toolchain + credentials OK"
echo

# ─── 2. xcodegen + build ────────────────────────────
echo "→ xcodegen generate"
xcodegen generate >/dev/null
echo

echo "→ xcodebuild Release ($TARGET)"
xcodebuild -scheme "$TARGET" -configuration Release -quiet build
echo "  ✓ Build succeeded"
echo

# Locate produced .app
RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData/HaneulKeyboard-*/Build/Products/Release -maxdepth 1 -name "$TARGET.app" -type d 2>/dev/null | head -1)
if [[ -z "$RELEASE_APP" ]]; then
    echo "  ✗ Could not locate $TARGET.app in DerivedData"
    exit 1
fi
echo "  → $RELEASE_APP"
echo

# ─── 3. Verify signing ──────────────────────────────
echo "→ Signing summary"
codesign -dvv "$RELEASE_APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|Sealed" | sed 's/^/  /'
echo

# ─── 4. Notarize ────────────────────────────────────
echo "→ Notarize (zip → submit --wait)"
ZIP="/tmp/$TARGET.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$RELEASE_APP" "$ZIP"
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
echo "$SUBMIT_OUTPUT" | sed 's/^/  /'
if ! echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "  ✗ Notarization rejected. Inspect with:"
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | awk '/id:/ {print $2; exit}')
    echo "    xcrun notarytool log $SUBMISSION_ID --keychain-profile \"$NOTARY_PROFILE\""
    exit 1
fi
echo "  ✓ Accepted"
echo

# ─── 5. Staple ──────────────────────────────────────
echo "→ Staple notarization ticket"
xcrun stapler staple "$RELEASE_APP" | sed 's/^/  /'
echo

# ─── 6. Gatekeeper check ────────────────────────────
echo "→ Gatekeeper assessment"
if spctl --assess --verbose "$RELEASE_APP" 2>&1 | sed 's/^/  /'; then
    echo "  ✓ Gatekeeper accepts"
else
    echo "  ✗ Gatekeeper rejects — abort"
    exit 1
fi
echo

# ─── 7. Stop any running instance ───────────────────
echo "→ Stop running $TARGET instance (if any)"
killall "$TARGET" 2>/dev/null && echo "  ✓ Stopped" || echo "  (none running)"
echo

# ─── 8. Install system-wide ─────────────────────────
INSTALL_PATH="$INSTALL_DIR/$TARGET.app"
echo "→ Install to $INSTALL_PATH (sudo)"
if [[ -e "$INSTALL_PATH" ]]; then
    # 백업은 반드시 Input Methods/Applications 폴더 "밖"(/tmp)으로 —
    # 같은 폴더의 .bak은 TIS/Spotlight가 또 하나의 앱으로 집어서
    # 유령 항목을 만든다(2026-06-06). /tmp는 재부팅 시 자동 청소.
    BAK="/tmp/$TARGET.app.bak.$(date +%s)"
    echo "  → backing up existing → $BAK"
    sudo mv "$INSTALL_PATH" "$BAK"
fi
sudo cp -R "$RELEASE_APP" "$INSTALL_PATH"
echo "  ✓ Copied"
echo

echo "→ Re-register with LaunchServices (system domain)"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
sudo "$LSREG" -f -R -trusted -domain system "$INSTALL_PATH"
echo "  ✓ Registered"
echo

# ─── 8.5 Dedup: 비정본 복사본 등록 해제 ──────────────
# 정본(/Library/Input Methods, /Applications) 외의 IME 복사본이
# LaunchServices에 등록돼 있으면 입력 소스 목록에 같은 이름이 줄줄이
# 생긴다(2026-06-06 학습: DerivedData 산출물, 임베드 복사본, user 도메인
# 이중 설치가 원인). 설치 때마다 자동 정리한다. 파일은 건드리지 않고
# 등록(DB)만 뺀다 — DerivedData 산출물은 다음 빌드에 그대로 쓰인다.
echo "→ Dedup: unregister non-canonical copies"
"$LSREG" -u "$RELEASE_APP" >/dev/null 2>&1 || true
"$LSREG" -u "$RELEASE_APP/Contents/Helpers/HaneulKeyboardIM.app" >/dev/null 2>&1 || true
"$LSREG" -u "$INSTALL_PATH/Contents/Helpers/HaneulKeyboardIM.app" >/dev/null 2>&1 || true
"$LSREG" -u "$HOME/Library/Input Methods/HaneulKeyboardIM.app" >/dev/null 2>&1 || true
echo "  ✓ Deduped (canonical registrations only)"
echo

# ─── 9. Launch the app ──────────────────────────────
if [[ "$IS_MAIN_APP" == "1" ]]; then
    echo "→ Launch main app via /usr/bin/open (GUI context for menu-bar icon + SMAppService)"
    open "$INSTALL_PATH"
    sleep 2
    if pgrep -x "$TARGET" >/dev/null; then
        echo "  ✓ Running (pid $(pgrep -x "$TARGET"))"
    else
        echo "  ⚠ Process not running — check Console for crash logs"
    fi
else
    echo "→ Launch $TARGET to register mach service"
    "$INSTALL_PATH/Contents/MacOS/$TARGET" &
    sleep 2
    if pgrep -x "$TARGET" >/dev/null; then
        echo "  ✓ Running (pid $(pgrep -x "$TARGET"))"
    else
        echo "  ⚠ Process not running — check Console for crash logs"
    fi
fi
echo

# ─── 10. TIS verify (optional script) ───────────────
if [[ -f /tmp/tis_verify.swift ]]; then
    echo "→ TIS verification via /tmp/tis_verify.swift"
    swift /tmp/tis_verify.swift "$TARGET" 2>&1 | sed 's/^/  /' || true
    echo
fi

# ─── 11. Next steps ─────────────────────────────────
if [[ "$IS_MAIN_APP" == "1" ]]; then
cat <<EOF

════════════════════════════════════════════
  ✅ Build + notarize + install complete: $TARGET
════════════════════════════════════════════

Next steps (manual):
  1. Look for the HaneulKeyboard icon in the menu bar (top-right).
  2. Open Settings to verify any new UI/behavior under test.
  3. For login-item changes: System Settings → 일반 → 로그인 항목
     should now list "HaneulKeyboard" if default-on registration
     succeeded.

EOF
else
LANG_CAT=""
case "$TARGET" in
    HaneulKeyboardIM) LANG_CAT="한국어 (Korean)" ;;
    Test1IM|Test2IM|Test3IM) LANG_CAT="그리스어 (Greek)" ;;
esac

cat <<EOF

════════════════════════════════════════════
  ✅ Build + notarize + install complete: $TARGET
════════════════════════════════════════════

Next steps (manual):
  1. Open: System Settings → Keyboard → Input Sources → "+"
  2. Find "$LANG_CAT" category (or other if custom target)
  3. Look for the target's display name in the list
  4. If visible → hypothesis confirmed
  5. Report back to the Claude session with the result

EOF
fi

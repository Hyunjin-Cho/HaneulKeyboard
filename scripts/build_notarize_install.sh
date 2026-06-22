#!/usr/bin/env bash
# build_notarize_install.sh — single-shot universal build → notarize → verify → optional install
# for HaneulKeyboard app/IME targets. Run on the Mac Studio (has Developer ID + notarytool profile).
#
# Usage:
#   scripts/build_notarize_install.sh <Target>
#   e.g. scripts/build_notarize_install.sh Test3IM
#        scripts/build_notarize_install.sh HaneulKeyboardIM
#
# The script will:
#   1. Verify toolchain + credentials are present.
#   2. xcodegen → xcodebuild Release universal binary.
#   3. ditto → notarytool submit --wait → stapler.
#   4. codesign/spctl gates on the stapled app and final distribution zip payload.
#   5. optionally sudo install to /Applications or /Library/Input Methods/.
#   6. Re-register with LaunchServices.
#   7. Restart the installed target process.
#   8. Print next steps for picker verification.

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <Target> (e.g. Test3IM, HaneulKeyboardIM, Test1IM, Test2IM)"
    exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE="haneul-notary"
DEVID_CERT_PATTERN="Developer ID Application: Hyunjin Cho"
ZIP_VERIFY_EXTRACT_ROOT=""

cleanup_zip_verify_extract_root() {
    if [[ -n "${ZIP_VERIFY_EXTRACT_ROOT:-}" ]]; then
        rm -rf "$ZIP_VERIFY_EXTRACT_ROOT"
        ZIP_VERIFY_EXTRACT_ROOT=""
    fi
}

trap cleanup_zip_verify_extract_root EXIT

# Main app vs IME bundle install destinations differ.
# - HaneulKeyboard (GUI menu-bar app): /Applications — required for stable
#   SMAppService.mainApp registration (login-at-start needs a known location).
# - *IM (input method bundles): /Library/Input Methods — where macOS TIS daemon
#   enumerates from.
case "$TARGET" in
    HaneulKeyboard) INSTALL_DIR="/Applications"; IS_MAIN_APP=1 ;;
    *)              INSTALL_DIR="/Library/Input Methods"; IS_MAIN_APP=0 ;;
esac

require_path() {
    local path="$1"
    local label="$2"
    if [[ ! -e "$path" ]]; then
        echo "  ✗ Missing $label: $path" >&2
        exit 1
    fi
}

verify_universal_binary() {
    local binary_path="$1"
    local label="$2"
    require_path "$binary_path" "$label"
    local archs
    archs=$(lipo -archs "$binary_path" 2>/dev/null || true)
    if [[ "$archs" != *"arm64"* || "$archs" != *"x86_64"* ]]; then
        echo "  ✗ $label is not universal (found: ${archs:-unknown})" >&2
        exit 1
    fi
    echo "  ✓ $label universal: $archs"
}

verify_codesign_bundle() {
    local app_path="$1"
    local label="$2"
    require_path "$app_path" "$label"
    if codesign --verify --strict --verbose=2 "$app_path" 2>&1 | sed 's/^/  /'; then
        echo "  ✓ $label codesign verified"
    else
        echo "  ✗ $label codesign verification failed" >&2
        exit 1
    fi
}

verify_gatekeeper_bundle() {
    local app_path="$1"
    local label="$2"
    require_path "$app_path" "$label"
    if spctl --assess --type execute --verbose "$app_path" 2>&1 | sed 's/^/  /'; then
        echo "  ✓ $label Gatekeeper accepts"
    else
        echo "  ✗ $label Gatekeeper rejects" >&2
        exit 1
    fi
}

verify_notice_resources() {
    local app_path="$1"
    local label="$2"
    if [[ "$IS_MAIN_APP" != "1" ]]; then
        return 0
    fi
    local resources_dir="$app_path/Contents/Resources"
    require_path "$resources_dir/LICENSE" "$label LICENSE"
    require_path "$resources_dir/ACKNOWLEDGEMENTS.md" "$label ACKNOWLEDGEMENTS.md"
    echo "  ✓ $label includes LICENSE + ACKNOWLEDGEMENTS.md"
}

verify_embedded_helper_bundle() {
    local parent_app="$1"
    local label_prefix="$2"
    local helper_app="$parent_app/Contents/Helpers/HaneulKeyboardIM.app"
    local helper_exec="$helper_app/Contents/MacOS/HaneulKeyboardIM"
    if [[ ! -d "$helper_app" ]]; then
        if [[ "$IS_MAIN_APP" == "1" ]]; then
            echo "  ✗ Missing $label_prefix embedded helper: $helper_app" >&2
            exit 1
        fi
        return 0
    fi
    verify_universal_binary "$helper_exec" "$label_prefix embedded helper executable"
    verify_codesign_bundle "$helper_app" "$label_prefix embedded helper"
}

verify_release_artifacts() {
    local app_path="$1"
    local main_exec="$app_path/Contents/MacOS/$TARGET"
    echo "→ Universal binary gate"
    verify_universal_binary "$main_exec" "$TARGET executable"
    verify_embedded_helper_bundle "$app_path" "$TARGET"
    echo
}

verify_final_zip_payload() {
    local zip_path="$1"
    local label="$2"
    cleanup_zip_verify_extract_root
    ZIP_VERIFY_EXTRACT_ROOT="$(mktemp -d "/tmp/${TARGET}.zipcheck.XXXXXX")"
    echo "→ Verify extracted $label"
    ditto -x -k "$zip_path" "$ZIP_VERIFY_EXTRACT_ROOT"
    local extracted_app="$ZIP_VERIFY_EXTRACT_ROOT/$TARGET.app"
    require_path "$extracted_app" "$label app bundle"
    verify_codesign_bundle "$extracted_app" "$label app"
    verify_gatekeeper_bundle "$extracted_app" "$label app"
    verify_embedded_helper_bundle "$extracted_app" "$label app"
    verify_notice_resources "$extracted_app" "$label app"
    cleanup_zip_verify_extract_root
    echo
}

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
    echo "    This script must run on the Mac Studio where the cert is provisioned."
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
# (H-05) 결정적 산출물 경로 — 고정 -derivedDataPath를 써서 빌드와 설치가
# 정확히 같은 산출물을 가리키게 한다. 예전엔 DerivedData*를 와일드카드로
# 뒤져 `head -1`로 첫 결과를 골라, 옛 산출물(.noindex·다른 프로젝트 해시)이
# 섞이면 "방금 빌드"가 아닌 걸 notarize/install할 수 있었다.
DERIVED="$PROJECT_ROOT/.build/DerivedData"
xcodebuild -scheme "$TARGET" -configuration Release -derivedDataPath "$DERIVED" -quiet build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
echo "  ✓ Build succeeded"
echo

RELEASE_APP="$DERIVED/Build/Products/Release/$TARGET.app"
if [[ ! -d "$RELEASE_APP" ]]; then
    echo "  ✗ Could not locate $TARGET.app at $RELEASE_APP"
    exit 1
fi
echo "  → $RELEASE_APP"
echo

verify_release_artifacts "$RELEASE_APP"

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

echo "→ Codesign gate after staple"
verify_codesign_bundle "$RELEASE_APP" "$TARGET app"
verify_embedded_helper_bundle "$RELEASE_APP" "$TARGET app"
echo

VERSION=$(defaults read "$RELEASE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)
OUT="$PROJECT_ROOT/${TARGET}_${VERSION}.zip"
rm -f "$OUT"
echo "→ Package final distribution zip"
ditto -c -k --keepParent "$RELEASE_APP" "$OUT"
echo "  ✓ Final zip created: $OUT"
echo

verify_final_zip_payload "$OUT" "final distribution zip"

# ─── 6. Gatekeeper check ────────────────────────────
echo "→ Gatekeeper assessment"
verify_gatekeeper_bundle "$RELEASE_APP" "$TARGET app"
echo

# ─── 6.5 ZIP_ONLY: 노타리+staple 검증 끝난 앱을 배포 zip으로만 뽑고 종료 ───
# 설치(sudo)는 건너뛴다 — 자격(notarytool profile)은 있으나 sudo 비번을
# 비대화형으로 넣을 수 없는 환경이나, 배포용 산출물만 필요할 때 쓴다.
# 결과물은 repo 루트의 <Target>_<MARKETING_VERSION>.zip 이다.
if [[ "${ZIP_ONLY:-0}" == "1" ]]; then
    echo "════════════════════════════════════════════"
    echo "  ✅ 노타리+staple 및 검증 완료된 배포 zip 생성 (설치 skip)"
    echo "  → $OUT"
    echo "════════════════════════════════════════════"
    exit 0
fi

# ─── 7. Stop any running instance ───────────────────
echo "→ Stop running $TARGET instance (if any)"
killall "$TARGET" 2>/dev/null && echo "  ✓ Stopped" || echo "  (none running)"
echo

# ─── 8. Install system-wide ─────────────────────────
INSTALL_PATH="$INSTALL_DIR/$TARGET.app"
STAGING_PATH="$INSTALL_DIR/.$TARGET.app.staging.$$"
echo "→ Install to $INSTALL_PATH (sudo)"
BAK=""
if [[ -e "$INSTALL_PATH" ]]; then
    # 백업은 반드시 Input Methods/Applications 폴더 "밖"(/tmp)으로 —
    # 같은 폴더의 .bak은 TIS/Spotlight가 또 하나의 앱으로 집어서
    # 유령 항목을 만든다(2026-06-06). /tmp는 재부팅 시 자동 청소.
    BAK="/tmp/$TARGET.app.bak.$(date +%s)"
    echo "  → backing up existing → $BAK"
    sudo mv "$INSTALL_PATH" "$BAK"
fi
# (M-06) 정본 경로에 직접 복사하지 않는다. 같은 부모의 staging에 완전히
# 복사하고 검증한 뒤 rename해야, cp 실패 시 반쪽 앱이 정본으로 남지 않는다.
rollback_install() {
    local rc=$?
    trap - ERR
    echo "  ⚠ 설치 실패(rc=$rc) — partial 설치 제거" >&2
    sudo rm -rf "$STAGING_PATH" "$INSTALL_PATH" 2>/dev/null || true
    if [[ -n "$BAK" && -e "$BAK" ]]; then
        echo "  → 백업 복원: $BAK → $INSTALL_PATH" >&2
        sudo mv "$BAK" "$INSTALL_PATH" 2>/dev/null || true
    fi
    return "$rc"
}
trap rollback_install ERR

sudo rm -rf "$STAGING_PATH"
sudo cp -R "$RELEASE_APP" "$STAGING_PATH"
(
    verify_codesign_bundle "$STAGING_PATH" "$TARGET staged app"
    verify_embedded_helper_bundle "$STAGING_PATH" "$TARGET staged app"
    verify_notice_resources "$STAGING_PATH" "$TARGET staged app"
)
sudo mv "$STAGING_PATH" "$INSTALL_PATH"
echo "  ✓ Staged, verified, and atomically installed"
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

# 설치와 등록이 모두 끝났으므로 이후 오류는 설치 rollback 대상이 아니다.
trap - ERR
if [[ -n "$BAK" ]]; then
    sudo rm -rf "$BAK"
    BAK=""
fi

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

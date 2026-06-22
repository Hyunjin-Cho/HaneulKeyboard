#!/usr/bin/env bash
# uninstall.sh — full removal of HaneulKeyboard footprint.
# Use this when the main app won't open or you can't get to its Settings.
#
# Usage:
#   bash scripts/uninstall.sh
#
# Removes:
#   - Running HaneulKeyboardIM process
#   - ~/Library/Input Methods/HaneulKeyboardIM.app (+ any *.bak.* siblings)
#   - LaunchServices registrations for our bundle ID
#   - UserDefaults under com.hyunjincho.haneulkeyboard,
#     com.hyunjincho.inputmethod.haneul, and NSGlobalDomain haneul.*
#
# Does NOT remove (macOS requires user GUI action):
#   - The enabled input source entry in System Settings → Keyboard → Input Sources
#   - The main app bundle itself (HaneulKeyboard.app on Desktop / wherever you put it)
#
# Both of those are clearly reported at the end.

set -u

BUNDLE_ID="com.hyunjincho.inputmethod.haneul"
IME_NAME="HaneulKeyboardIM"
MAIN_APP_DOMAIN="com.hyunjincho.haneulkeyboard"
IME_DEFAULTS_DOMAIN="com.hyunjincho.inputmethod.haneul"
INPUT_METHODS_DIR="$HOME/Library/Input Methods"
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

echo "════════════════════════════════════════════"
echo "  HaneulKeyboard — full uninstall"
echo "════════════════════════════════════════════"
echo

echo "→ 1. Stop running IME process"
if pgrep -x "$IME_NAME" >/dev/null 2>&1; then
    killall "$IME_NAME" 2>/dev/null && echo "  ✓ killed" || echo "  ⚠ kill failed (may need re-run)"
else
    echo "  (not running)"
fi
echo

echo "→ 2. Remove ~/Library/Input Methods/HaneulKeyboardIM.app (and any .bak siblings)"
found=0
for item in "$INPUT_METHODS_DIR/$IME_NAME.app" "$INPUT_METHODS_DIR/$IME_NAME.app".bak.*; do
    if [ -e "$item" ]; then
        rm -rf "$item" && echo "  ✓ removed $(basename "$item")" && found=$((found+1))
    fi
done
[ "$found" -eq 0 ] && echo "  (nothing to remove)"
echo

echo "→ 2b. Remove system-domain IME (/Library/Input Methods) if present (admin)"
SYS_IME="/Library/Input Methods/$IME_NAME.app"
if [ -e "$SYS_IME" ]; then
    echo "  시스템 도메인 설치 발견 — 관리자 권한으로 삭제합니다 (비밀번호 입력)."
    if sudo rm -rf "$SYS_IME"; then
        echo "  ✓ removed (system)"
        [ -x "$LSREG" ] && "$LSREG" -u "$SYS_IME" 2>/dev/null
    else
        echo "  ⚠ 삭제 실패 — 수동 제거 필요: sudo rm -rf \"$SYS_IME\""
    fi
else
    echo "  (시스템 도메인 설치 없음)"
fi
echo

echo "→ 3. Unregister bundle from LaunchServices"
if [ -x "$LSREG" ]; then
    # Unregister by path (idempotent — succeeds even if path is gone)
    "$LSREG" -u "$INPUT_METHODS_DIR/$IME_NAME.app" 2>/dev/null
    echo "  ✓ unregistered"
else
    echo "  ⚠ lsregister not found at expected path"
fi
echo

echo "→ 4. Clear UserDefaults"
defaults delete "$MAIN_APP_DOMAIN" 2>/dev/null && echo "  ✓ cleared $MAIN_APP_DOMAIN" || echo "  (no $MAIN_APP_DOMAIN domain found)"
defaults delete "$IME_DEFAULTS_DOMAIN" 2>/dev/null && echo "  ✓ cleared $IME_DEFAULTS_DOMAIN" || echo "  (no $IME_DEFAULTS_DOMAIN domain found)"
# Stray haneul.* keys in NSGlobalDomain
for key in $(defaults read NSGlobalDomain 2>/dev/null | grep -oE '"haneul\.[a-zA-Z]+"' | tr -d '"'); do
    defaults delete NSGlobalDomain "$key" 2>/dev/null && echo "  ✓ cleared NSGlobalDomain → $key"
done
echo

echo "════════════════════════════════════════════"
echo "  Done. Two manual steps remain:"
echo "════════════════════════════════════════════"
echo
echo "  a) System Settings → Keyboard → Input Sources →"
echo "     select \"하늘키보드 (두벌식)\" → click \"-\" to remove."
echo "     (macOS does not let scripts modify enabled input sources.)"
echo
echo "  b) Move HaneulKeyboard.app itself to the Trash."
echo "     (Whatever folder you launched it from — usually ~/Desktop.)"
echo

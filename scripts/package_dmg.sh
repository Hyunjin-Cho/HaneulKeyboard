#!/usr/bin/env bash
# 2026-10-10: 검증한 앱을 Finder 드래그 설치 DMG로 포장한다. 공증/게시/설치는 하지 않는다.
# Usage: bash scripts/package_dmg.sh APP OUTPUT_DMG [saekdong]
# Preview: HANEUL_DMG_PREVIEW=1 ... (파일명에 -preview- 필수, 설치용으로 배포 금지)
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
DMGBUILD="${DMGBUILD:-$PROJECT_ROOT/.tools/dmg/bin/dmgbuild}"
DMGBUILD_PY="${DMGBUILD_PY:-${DMGBUILD%/*}/python}"
check_tools() {
    for tool in swiftc tiffutil hdiutil python3; do
        command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
    done
    if [[ ! -x "$DMGBUILD" || ! -x "$DMGBUILD_PY" ]]; then
        echo "DMG tools are missing. Setup in this repository:" >&2
        echo "  python3 -m venv .tools/dmg" >&2
        echo "  .tools/dmg/bin/python -m pip install -r scripts/requirements-dmg.txt" >&2
        exit 1
    fi
    "$DMGBUILD_PY" -c 'import dmgbuild; assert tuple(map(int, dmgbuild.__version__.split("."))) >= (1, 6, 7), "dmgbuild >= 1.6.7 required"; print("dmgbuild " + dmgbuild.__version__)'
}
check_tools
if [[ "${1:-}" == "--check-tools" ]]; then exit 0; fi
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then echo "Usage: $0 APP OUTPUT_DMG [variant]" >&2; exit 2; fi
APP="$1"
OUTPUT="$2"
VARIANT="${3:-$(python3 -c 'import json; print(json.load(open("Resources/Installer/layout.json"))["defaultVariant"])')}"
python3 - "$VARIANT" <<'PY'
import json, sys
assert sys.argv[1] in json.load(open("Resources/Installer/layout.json"))["variants"], "Unknown DMG variant"
PY
[[ -d "$APP" && ! -e "$OUTPUT" ]] || { echo "App missing or output already exists; nothing overwritten." >&2; exit 1; }
VERSION=$(python3 - "$APP" <<'PY'
import plistlib, re, sys
from pathlib import Path
info = plistlib.loads((Path(sys.argv[1])/"Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.hyunjincho.haneulkeyboard", "Only the main app can be packaged"
version = info["CFBundleShortVersionString"]
suffix = info.get("HaneulReleaseSuffix", "")
assert isinstance(version, str) and re.fullmatch(r"[0-9]{4}\.[0-9]{1,2}(?:\.[0-9]{1,2})?", version)
assert suffix in ("", "_hotfix")
if suffix:
    from datetime import datetime
    assert re.fullmatch(r"[0-9]{4}\.[0-9]{2}\.[0-9]{2}", version)
    datetime.strptime(version, "%Y.%m.%d")
print(version + suffix)
PY
)
if [[ "${HANEUL_DMG_PREVIEW:-0}" == "1" ]]; then
    [[ "$(basename "$OUTPUT")" == *-preview-*.dmg ]] || { echo "Preview filename must include -preview-." >&2; exit 1; }
    VOLUME="하늘키보드 ${VERSION} 미리보기 ${VARIANT}"
else
    [[ "$(basename "$OUTPUT")" == "HaneulKeyboard_${VERSION}.dmg" ]] || { echo "DMG filename must match the public version." >&2; exit 1; }
    codesign --verify --deep --strict "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute "$APP"
    VOLUME="하늘키보드 ${VERSION}"
fi
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/haneul-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$(dirname "$OUTPUT")"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PROJECT_ROOT/.build/ModuleCache}"
swiftc -parse-as-library scripts/dmg_background.swift -o "$STAGE/artwork"
"$STAGE/artwork" "$STAGE" "$VARIANT"
tiffutil -cathidpicheck "$STAGE/${VARIANT}.png" "$STAGE/${VARIANT}@2x.png" -out "$STAGE/background.tiff"
"$DMGBUILD" -s scripts/dmg_settings.py -D app="$APP" -D background="$STAGE/background.tiff" \
    -D layout="$PROJECT_ROOT/Resources/Installer/layout.json" -D icon="$PROJECT_ROOT/Resources/AppIcon.icns" \
    "$VOLUME" "$STAGE/installer.dmg"
mv -n "$STAGE/installer.dmg" "$OUTPUT"
[[ ! -e "$STAGE/installer.dmg" ]] || { echo "Output appeared during packaging; nothing overwritten." >&2; exit 1; }
echo "DMG created (container signing/notarization is the release script's next step): $OUTPUT"

"""2026-10-09. Embed local assets into the standalone conversation fragment."""
import base64
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
repo = root.parents[1]
logo = repo / ".tmp/onboarding-icon/AppIcon.iconset/icon_128x128@2x.png"
if not logo.exists():
    logo.parent.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "iconset", "-o", str(logo.parent),
                    str(repo / "Resources/AppIcon.icns")], check=True)
assets = {
    "logo": "data:image/png;base64," + base64.b64encode(logo.read_bytes()).decode(),
    "menuIcon": '<img aria-hidden="true" class="hk-menu-icon" src="data:image/png;base64,' + base64.b64encode((repo / "Resources/MenuBar/HaneulRoofTemplate@2x.png").read_bytes()).decode() + '">',
    "inputIcon": "data:image/png;base64," + base64.b64encode((repo / "Resources/IM/HaneulInputTemplate@2x.png").read_bytes()).decode(),
    "data": json.loads((root / "preview-data.json").read_text()),
}
markup = (root / "onboarding-template.html").read_text()
markup = markup.replace("__HK_ASSETS__", json.dumps(assets, ensure_ascii=False).replace("</", "<\\/"))
markup = markup.replace("__HK_BEHAVIOR__", (root / "preview-behavior.js").read_text())
if len(markup.encode()) >= 1_000_000:
    raise ValueError("Preview exceeds the inline size limit")
(root / "haneul-onboarding.html").write_text(markup)
print(f"Updated haneul-onboarding.html ({len(markup.encode()):,} bytes)")

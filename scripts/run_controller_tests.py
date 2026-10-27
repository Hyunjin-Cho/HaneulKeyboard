#!/usr/bin/env python3
"""2026-10-20: run controller session tests without registering or driving an IME."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    repo = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="haneul-controller-tests-") as scratch:
        work = Path(scratch)
        bundle = work / "ControllerTests.app/Contents"
        binary = bundle / "MacOS/ControllerTests"
        binary.parent.mkdir(parents=True)
        resources = bundle / "Resources"
        resources.mkdir()
        (bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": binary.name,
            "CFBundleIdentifier": "local.haneul.controller-session-tests",
            "CFBundlePackageType": "APPL",
            "LSBackgroundOnly": True,
        }))
        for source in (repo / "Resources/IM").iterdir():
            if source.is_file() and source.suffix in (".json", ".txt"):
                shutil.copyfile(source, resources / source.name)

        # Only the framework-owned session constructor is replaced. All product
        # callback/handle bodies remain intact; settings use a memory-only store.
        original = (repo / "IMESources/HaneulInputController.swift").read_text()
        declaration = "final class HaneulInputController: IMKInputController {"
        assert original.count(declaration) == 1, "Update fixture for the new controller declaration"
        fixture = original.replace(declaration, """final class HaneulInputController: NSObject {
    var probeComposer: KoreanComposer { composer }
    var probeSlashActive: Bool { slashEnglish.isActive }""", 1)
        for name in ("recognizedEvents", "activateServer", "deactivateServer"):
            fixture = fixture.replace("    override func " + name, "    func " + name)
        fixture = fixture.replace("        super.deactivateServer(sender)",
                                  "        // No OS session superclass in this fixture.")
        fixture = (fixture.replace("UserDefaults.standard", "probeDefaults")
                   .replace("from: .standard", "from: probeDefaults")
                   .replace("in: .standard", "in: probeDefaults"))
        controller = work / "FixtureController.swift"
        controller.write_text(fixture)
        sources = [
            p for p in sorted((repo / "IMESources").glob("*.swift"))
            if p.name not in ("main.swift", "OrphanWatcher.swift", "HaneulInputController.swift")
        ]
        sources += [
            repo / "Shared/SlashEnglishSession.swift",
            repo / "Shared/InputInferencePolicy.swift",
            controller,
            repo / "Tests/InputControllerSessionTests.swift",
        ]
        cache = os.environ.get("SWIFT_MODULECACHE_PATH", str(work / "module-cache"))
        subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", cache,
                        *map(str, sources), "-o", str(binary)], cwd=repo, check=True)
        result = subprocess.run([str(binary)], cwd=repo, capture_output=True, text=True)
        if result.stderr:
            print(result.stderr, end="")
        try:
            report = json.loads(result.stdout)
        except json.JSONDecodeError:
            print(result.stdout, end="")
            return result.returncode or 1
        print(f"Controller sessions: {report['checks']} checks, "
              f"{len(report['failures'])} failed, {report['scenarioCount']} scenarios")
        for failure in report["failures"]:
            print("FAIL:", failure)
        print(report["limits"])
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())

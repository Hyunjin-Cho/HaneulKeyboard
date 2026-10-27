#!/usr/bin/env python3
"""Standalone vocabulary tests using real IME sources, without shared-cache writes.

2026-10-17. Run from any directory. --core-root may point at a recorded source
snapshot to separate wordlist effects from concurrent input-core changes.
"""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--core-root", type=Path, default=ROOT)
parser.add_argument("--evidence-dir", type=Path)
args = parser.parse_args()
core = args.core_root.resolve()
sources = [core / "IMESources" / (name + ".swift") for name in (
    "HangulJamo", "KeyboardLayout2Set", "Contractions", "AlphanumericWords",
    "MeasurementUnits", "PhoneticDictionary", "KoreanComposer", "ManualToggle",
    "EnglishDetector", "KoreanDictionary", "PersonalDictionary",
)]
policy = core / "Shared/InputInferencePolicy.swift"
if policy.exists():
    sources.append(policy)
# Older --core-root snapshots predate particle splitting and have no dependency.
particles = core / "IMESources/EnglishParticleSplitter.swift"
if particles.exists():
    sources.append(particles)
sources.append(ROOT / "Tests/VocabularyExtensionTests.swift")
resources = list((ROOT / "Resources/IM").glob("english*.txt")) + [
    ROOT / "Resources/IM/korean_words.txt", ROOT / "dict_work/dict_manifest.tsv",
    ROOT / "dict_work/2026-10-14-nature-camera-coverage.txt",
    ROOT / "dict_work/2026-10-06-nature-film-coverage.txt",
]
tracked = sources + resources

def hashes():
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in tracked}

before = hashes()
with tempfile.TemporaryDirectory(prefix="haneul-vocabulary-tests-") as temporary:
    temporary = Path(temporary)
    binary = temporary / "vocabulary-tests"
    command = ["swiftc", "-module-cache-path", str(temporary / "module-cache"),
               "-o", str(binary)] + [str(path) for path in sources]
    subprocess.run(command, cwd=ROOT, check=True)
    result = subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True)
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
after = hashes()
unchanged = before == after
if args.evidence_dir:
    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    (args.evidence_dir / "vocabulary-tests.json").write_text(json.dumps({
        "date": date.today().isoformat(), "core_root": str(core), "command": command,
        "stdout": result.stdout, "stderr": result.stderr,
        "exit_code": result.returncode, "sources_unchanged": unchanged,
        "source_and_resource_sha256": before,
    }, ensure_ascii=False, indent=2) + "\n")
if not unchanged:
    raise SystemExit("Sources/resources changed during tests; rerun after concurrent edits finish.")
raise SystemExit(result.returncode)

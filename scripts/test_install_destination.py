#!/usr/bin/env python3
"""Installer destination safety fixtures; never changes a system installation."""

import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("destination", Path(__file__).with_name("verify_install_destination.py"))
destination = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(destination)
PRODUCT = "com.hyunjincho.haneulkeyboard"


class DestinationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="haneul-install-destination-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.existing = self.bundle("existing.app")
        self.incoming = self.bundle("incoming.app")
        self.calls = []

    def bundle(self, name, identifier=PRODUCT):
        bundle = self.root / name
        (bundle / "Contents").mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
        (bundle / "original-sentinel").write_text("preserve me")
        return bundle

    def signer(self, arguments, **kwargs):
        self.calls.append(arguments)
        return subprocess.CompletedProcess(arguments, 0, "", "TeamIdentifier=ABCDEFGHIJ\n")

    def verify(self):
        with patch.object(destination.subprocess, "run", side_effect=self.signer):
            destination.verify_destination(self.existing, self.incoming, PRODUCT)

    def assert_preserved(self):
        self.assertEqual((self.existing / "original-sentinel").read_text(), "preserve me")

    def test_same_product_requires_apple_anchor_for_both_bundles(self):
        self.verify()
        self.assertEqual(len(self.calls), 3)
        for call in self.calls[1:]:
            self.assertIn("--all-architectures", call)
            self.assertIn('-R=anchor apple generic and certificate leaf[subject.OU] = "ABCDEFGHIJ"', call)
        self.assert_preserved()

    def test_clean_install_needs_no_existing_signature(self):
        self.existing = self.root / "absent.app"
        self.verify()
        self.assertEqual(self.calls, [])

    def test_other_product_is_rejected_before_signing_checks(self):
        self.existing = self.bundle("other.app", "com.example.other-product")
        with self.assertRaises(ValueError): self.verify()
        self.assertEqual(self.calls, [])
        self.assert_preserved()

    def test_unknown_incoming_product_is_rejected(self):
        self.incoming = self.bundle("wrong-incoming.app", "com.example.other-product")
        with self.assertRaises(ValueError): self.verify()
        self.assert_preserved()

    def test_wrong_team_or_damaged_existing_signature_is_rejected(self):
        good = self.signer
        def invalid(arguments, **kwargs):
            result = good(arguments, **kwargs)
            return subprocess.CompletedProcess(arguments, 1, "", "bad Team") if arguments[-1] == str(self.existing) else result
        self.signer = invalid
        with self.assertRaises(ValueError): self.verify()
        self.assert_preserved()

    def test_untrusted_incoming_team_is_rejected(self):
        self.signer = lambda args, **kwargs: subprocess.CompletedProcess(
            args, 0 if "-d" in args else 1, "", "TeamIdentifier=ABCDEFGHIJ\n")
        with self.assertRaises(ValueError): self.verify()
        self.assert_preserved()

    def test_missing_team_is_rejected(self):
        self.signer = lambda args, **kwargs: subprocess.CompletedProcess(args, 0, "", "TeamIdentifier=not set\n")
        with self.assertRaises(ValueError): self.verify()
        self.assert_preserved()

    def test_symlink_and_broken_symlink_are_rejected(self):
        for target in [self.existing, self.root / "missing.app"]:
            link = self.root / ("valid-link.app" if target == self.existing else "broken-link.app")
            link.symlink_to(target)
            with self.assertRaises(ValueError):
                destination.verify_destination(link, self.incoming, PRODUCT)
        self.assert_preserved()

    def test_regular_file_is_rejected(self):
        path = self.root / "file.app"; path.write_text("preserve me")
        with self.assertRaises(ValueError): destination.verify_destination(path, self.incoming, PRODUCT)
        self.assertEqual(path.read_text(), "preserve me")

    def test_linked_contents_or_plist_is_rejected(self):
        for name in ["Contents", "Contents/Info.plist"]:
            app = self.root / (name.replace("/", "-") + ".app")
            app.mkdir()
            if "/" in name: (app / "Contents").mkdir()
            (app / name).symlink_to(self.existing / name)
            with self.assertRaises(ValueError): destination.verify_destination(app, self.incoming, PRODUCT)
        self.assert_preserved()

    def test_linked_parent_is_rejected(self):
        parent = self.root / "linked-applications"; parent.symlink_to(self.root)
        for name in ["existing.app", "absent.app"]:
            with self.assertRaises(ValueError): destination.verify_destination(parent / name, self.incoming, PRODUCT)
        self.assert_preserved()

    def test_unreadable_or_invalid_plist_is_rejected(self):
        info = self.existing / "Contents/Info.plist"; info.write_text("not a plist")
        with self.assertRaises(plistlib.InvalidFileException): self.verify()
        self.assert_preserved()

    def run_install_block(self, *, wrong_product=False, fail_rename=False, bad_signature=False):
        # Execute the product's real staging/backup/rollback/cleanup block. Only
        # administrator elevation and cryptographic fixtures are replaced.
        repo = Path(__file__).resolve().parent.parent
        source = (repo / "scripts/build_notarize_install.sh").read_text()
        start = source.index('INSTALL_PATH="$INSTALL_DIR/$TARGET.app"')
        end = source.index('echo "→ Re-register with LaunchServices', start)
        cleanup_start = source.index('trap - ERR', end)
        cleanup_end = source.index('\nfi', cleanup_start) + len('\nfi')
        block = source[start:end] + source[cleanup_start:cleanup_end] + '\n'
        backup = self.root / "backup.app"
        block = block.replace('BAK="/tmp/$TARGET.app.bak.$$"', 'BAK="$FIXTURE_BACKUP"')
        self.assertIn('BAK="$FIXTURE_BACKUP"', block)
        applications = self.root / "Applications"; applications.mkdir()
        existing = applications / "HaneulKeyboard.app"
        self.existing.rename(existing); self.existing = existing
        if wrong_product:
            (existing / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.example.other-product"}))
        (self.incoming / "original-sentinel").write_text("incoming")
        driver = self.root / "signing-fixture.py"
        driver.write_text('''import os,runpy,subprocess,sys
from unittest.mock import patch
target=sys.argv.pop(1)
def signing(args,**kwargs):
    bad=os.environ.get("FIXTURE_BAD_SIGNATURE")=="1" and args[-1]==os.environ["FIXTURE_EXISTING"]
    return subprocess.CompletedProcess(args,1 if bad else 0,"","TeamIdentifier=ABCDEFGHIJ\\n")
with patch("subprocess.run",side_effect=signing): runpy.run_path(target,run_name="__main__")
''')
        fixture_bin = self.root / "bin"; fixture_bin.mkdir()
        python_wrapper = fixture_bin / "python3"
        python_wrapper.write_text('#!/bin/bash\nexec "$FIXTURE_PYTHON" "$FIXTURE_DRIVER" "$@"\n')
        python_wrapper.chmod(0o755)
        preamble = '''set -euo pipefail
sudo() {
    if [[ "$1" == mv && "$2" == "$STAGING_PATH" && "$FIXTURE_FAIL_RENAME" == 1 ]]; then return 1; fi
    command "$@"
}
verify_codesign_bundle() { :; }
verify_embedded_helper_bundle() { :; }
verify_notice_resources() { :; }
'''
        environment = {**os.environ, "TARGET": "HaneulKeyboard", "IS_MAIN_APP": "1",
            "PATH": str(fixture_bin) + os.pathsep + os.environ["PATH"],
            "INSTALL_DIR": str(applications), "RELEASE_APP": str(self.incoming), "PROJECT_ROOT": str(repo),
            "FIXTURE_PYTHON": sys.executable, "FIXTURE_DRIVER": str(driver), "FIXTURE_BACKUP": str(backup),
            "FIXTURE_EXISTING": str(existing), "FIXTURE_FAIL_RENAME": str(int(fail_rename)),
            "FIXTURE_BAD_SIGNATURE": str(int(bad_signature))}
        result = subprocess.run(["bash", "-c", preamble + block], env=environment, capture_output=True, text=True)
        self.assertFalse(backup.exists(), result.stderr)
        self.assertFalse(list(applications.glob(".*.staging.*")), result.stderr)
        return result

    def test_installer_block_preserves_unrelated_product(self):
        result = self.run_install_block(wrong_product=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_preserved()

    def test_installer_block_preserves_untrusted_existing_product(self):
        result = self.run_install_block(bad_signature=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_preserved()

    def test_installer_block_replaces_trusted_same_product(self):
        result = self.run_install_block()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.existing / "original-sentinel").read_text(), "incoming")

    def test_installer_block_restores_original_when_rename_fails(self):
        result = self.run_install_block(fail_rename=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assert_preserved()


if __name__ == "__main__":
    unittest.main()

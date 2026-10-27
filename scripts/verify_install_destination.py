#!/usr/bin/env python3
"""Reject unrelated or untrusted existing apps before the developer installer moves them."""

import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys


def bundle_id(bundle):
    contents = bundle / "Contents"
    info = contents / "Info.plist"
    if not stat.S_ISDIR(contents.lstat().st_mode) or not stat.S_ISREG(info.lstat().st_mode):
        raise ValueError("bundle metadata must be real directories and a regular plist")
    with info.open("rb") as source:
        return plistlib.load(source).get("CFBundleIdentifier")


def signing_team(bundle):
    result = subprocess.run(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)],
                            capture_output=True, text=True)
    team = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", result.stderr, re.MULTILINE)
    if result.returncode or not team:
        raise ValueError("cannot establish the incoming app's signing Team")
    return team.group(1)


def verify_signature(bundle, team):
    requirement = f'anchor apple generic and certificate leaf[subject.OU] = "{team}"'
    # The '=' selects an inline requirement; plain -R treats its value as a file.
    result = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures",
                             "-R=" + requirement, str(bundle)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("app is not Apple-trusted and signed by the incoming Team")


def verify_destination(destination, incoming, expected_id):
    try:
        existing = destination.lstat()
    except FileNotFoundError:
        # A dangling parent link must not be mistaken for a clean install.
        if destination.parent.is_symlink():
            raise ValueError("installation parent must not be a symbolic link")
        return
    if destination.parent.is_symlink() or not stat.S_ISDIR(existing.st_mode):
        raise ValueError("existing destination must be a real app directory, not a link or file")
    if bundle_id(destination) != expected_id or bundle_id(incoming) != expected_id:
        raise ValueError("existing and incoming bundle IDs must match the expected product")
    team = signing_team(incoming)
    verify_signature(incoming, team)
    verify_signature(destination, team)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: verify_install_destination.py EXISTING INCOMING EXPECTED_BUNDLE_ID")
    try:
        verify_destination(Path(os.path.abspath(sys.argv[1])), Path(os.path.abspath(sys.argv[2])), sys.argv[3])
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Refusing to replace existing destination; original preserved: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

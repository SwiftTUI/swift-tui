#!/usr/bin/env python3
"""Transfer one exact-revision native test build between jobs in the same run."""
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
RECEIPT = BUILD / "ci-test-bundle.json"


def identity():
    return {
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "toolchain": subprocess.check_output(["swiftly", "run", "swift", "--version"], cwd=ROOT, text=True).strip(),
        "platform": platform.system(),
        "arch": platform.machine(),
        "workspace": str(ROOT),
        "build": "native-debug-warnings-as-errors-module-trace-v1",
    }


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: ci_test_bundle.py pack|verify")
    mode = sys.argv[1]
    if mode == "pack":
        if os.environ.get("SWIFTTUI_WARNINGS_AS_ERRORS") != "1":
            raise SystemExit("CI bundle must be built with warnings as errors")
        RECEIPT.write_text(json.dumps(identity(), indent=2) + "\n")
        # Preserve permissions and symlinks (upload-artifact alone does not).
        # There is no cross-revision restore or fallback to a stale binary.
        with tarfile.open(ROOT / "ci-test-bundle.tar.gz", "w:gz", compresslevel=1) as archive:
            archive.add(BUILD, arcname=".build")
    elif mode == "verify":
        actual = json.loads(RECEIPT.read_text())
        expected = identity()
        if actual != expected:
            raise SystemExit(f"test bundle identity mismatch: {actual!r} != {expected!r}")
        if subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).strip():
            raise SystemExit("--prebuilt requires an unchanged checkout")
        added_sources = subprocess.check_output(
            ["git", "ls-files", "--others", "--exclude-standard", "--",
             "Sources", "Platforms", "Tests", "Vendor", "Package.swift"], cwd=ROOT, text=True)
        if added_sources.strip():
            raise SystemExit("--prebuilt cannot include unbuilt source files")
        print("Verified test bundle for", expected["revision"])
    else:
        raise SystemExit("usage: ci_test_bundle.py pack|verify")


if __name__ == "__main__":
    main()

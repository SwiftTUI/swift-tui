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
USAGE = "usage: ci_test_bundle.py pack|verify [--kind debug|release]"

# One build identity per bundle kind. The kind is part of the receipt, so a
# debug bundle can never satisfy a release lane's verify, or the reverse.
#   debug    the Repo Gate and macOS Gate bundle (Scripts/build_ci_test_bundle.sh).
#   release  the Release Soundness Lane bundle
#            (Scripts/build_ci_release_test_bundle.sh).
BUILD_IDENTITIES = {
    "debug": "native-debug-warnings-as-errors-module-trace-v1",
    "release": "native-release-testable-per-file-tests-v1",
}


def identity(kind="debug"):
    return {
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "toolchain": subprocess.check_output(["swiftly", "run", "swift", "--version"], cwd=ROOT, text=True).strip(),
        "platform": platform.system(),
        "arch": platform.machine(),
        "workspace": str(ROOT),
        "build": BUILD_IDENTITIES[kind],
    }


def verify_checkout():
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).strip()
    if changed:
        raise SystemExit(f"test bundle requires an unchanged checkout; changed files:\n{changed}")
    added_sources = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "--",
         "Sources", "Platforms", "Tests", "Vendor", "Package.swift"], cwd=ROOT, text=True)
    if added_sources.strip():
        raise SystemExit(f"test bundle cannot include unbuilt source files:\n{added_sources.strip()}")


def parse_arguments(arguments):
    if len(arguments) == 1:
        mode, kind = arguments[0], "debug"
    elif len(arguments) == 3 and arguments[1] == "--kind":
        mode, kind = arguments[0], arguments[2]
    else:
        raise SystemExit(USAGE)
    if mode not in ("pack", "verify") or kind not in BUILD_IDENTITIES:
        raise SystemExit(USAGE)
    return mode, kind


def main():
    mode, kind = parse_arguments(sys.argv[1:])
    if mode == "pack":
        # The release lane has never built with warnings as errors; the debug
        # gates always do, and their bundle must not be publishable without it.
        if kind == "debug" and os.environ.get("SWIFTTUI_WARNINGS_AS_ERRORS") != "1":
            raise SystemExit("CI bundle must be built with warnings as errors")
        verify_checkout()
        RECEIPT.write_text(json.dumps(identity(kind), indent=2) + "\n")
        # Preserve permissions and symlinks (upload-artifact alone does not).
        # There is no cross-revision restore or fallback to a stale binary.
        with tarfile.open(ROOT / "ci-test-bundle.tar.gz", "w:gz", compresslevel=1) as archive:
            archive.add(BUILD, arcname=".build")
    else:
        actual = json.loads(RECEIPT.read_text())
        expected = identity(kind)
        if actual != expected:
            raise SystemExit(f"test bundle identity mismatch: {actual!r} != {expected!r}")
        verify_checkout()
        print("Verified", kind, "test bundle for", expected["revision"])


if __name__ == "__main__":
    main()

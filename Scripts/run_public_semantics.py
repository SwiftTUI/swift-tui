#!/usr/bin/env python3
"""Run the versioned public SwiftUI/SwiftTUI semantic comparison on macOS."""
import argparse
import copy
import difflib
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXPECTED = ROOT / "Scripts/data/public-semantic-v1.json"


def behavioral_diff(expected, observations):
    failures = []
    known = set(expected["fixtures"])
    for engine, actual in observations.items():
        if set(actual) != known:
            failures.append(f"{engine}: fixture census differs: {sorted(set(actual) ^ known)}")
        for name, contract in expected["fixtures"].items():
            if contract["status"] == "unsupported":
                continue
            wanted = contract["events"][engine]
            got = actual.get(name, [])
            if wanted != got:
                failures.append("\n".join(difflib.unified_diff(
                    wanted, got, fromfile=f"expected/{engine}/{name}", tofile=f"actual/{engine}/{name}", lineterm="")))
            if contract["status"] == "parity" and contract["events"]["swiftui"] != contract["events"]["swifttui"]:
                failures.append(f"{name}: parity declaration has unequal expected events")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/public-semantics")
    parser.add_argument("--expected", type=Path, default=DEFAULT_EXPECTED)
    parser.add_argument("--compare-only", type=Path, help="Recheck a saved result without executing either adapter")
    args = parser.parse_args()
    expected = json.loads(args.expected.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    if args.compare_only:
        result = json.loads(args.compare_only.read_text())
    elif sys.platform != "darwin":
        result = {"fixtureVersion": expected["version"], "status": "unsupported", "reason": "Apple SwiftUI/AppKit adapter requires native macOS",
                  "fixtures": {name: "unsupported: native macOS required" for name in expected["fixtures"]}}
        (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        for name in result["fixtures"]:
            print(f"SKIP {name}: {result['reason']}")
        return 0
    else:
        def capture(command):
            return subprocess.check_output(command, cwd=ROOT, text=True).strip()

        def run(command, log, timeout):
            with (args.output / log).open("w") as stream:
                subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=timeout)
            return (args.output / log).read_text(errors="replace")

        fixture = ROOT / "Tests/SwiftTUITests/PublicSemanticFixture.swift"
        executable = args.output.resolve() / "swiftui-oracle"
        run(["swiftly", "run", "swiftc", "-parse-as-library", "-D", "PUBLIC_SEMANTIC_ORACLE",
             "Tools/PublicSemanticOracle.swift", str(fixture), "-o", str(executable)], "swiftui-build.log", 120)
        apple_text = run([str(executable)], "swiftui.log", 30)
        apple = json.loads(apple_text.splitlines()[-1])
        tui_text = run(["swiftly", "run", "swift", "test", "--build-system", "native", "--no-parallel",
                        "--filter", "SwiftTUITests.PublicSemanticDifferentialTests"], "swifttui.log", 900)
        records = [line.removeprefix("[public-semantics] ") for line in tui_text.splitlines() if line.startswith("[public-semantics] ")]
        if len(records) != 1:
            raise RuntimeError(f"Expected exactly one SwiftTUI observation record, got {len(records)}")
        result = {"fixtureVersion": expected["version"], "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
                  "frameworkRevision": capture(["git", "rev-parse", "HEAD"]),
                  "frameworkDirty": bool(capture(["git", "status", "--porcelain"])),
                  "workingTreeDiffSHA256": hashlib.sha256(capture(["git", "diff", "HEAD"]).encode()).hexdigest(),
                  "environment": {"macOS": platform.mac_ver()[0], "architecture": platform.machine(),
                                  "sdk": capture(["xcrun", "--show-sdk-version"]), "xcode": capture(["xcodebuild", "-version"]),
                                  "swift": capture(["swiftly", "run", "swift", "--version"])},
                  "observations": {"swiftui": apple, "swifttui": json.loads(records[0])}}
    if result.get("fixtureVersion") != expected["version"]:
        raise RuntimeError("Fixture version mismatch; compare only matching contracts")
    if set(result.get("observations", {})) != {"swiftui", "swifttui"}:
        raise RuntimeError("Both executed engine observations are required for a comparison")
    failures = behavioral_diff(expected, result["observations"])
    # Demonstrate that an altered event is rejected; never update the oracle.
    altered = copy.deepcopy(expected)
    altered["fixtures"]["state-batching"]["events"]["swiftui"].append("deliberately-wrong-event")
    negative_control = bool(behavioral_diff(altered, result["observations"]))
    if not negative_control:
        failures.append("Deliberately changed expected event did not fail")
    result["negativeControlRejected"] = negative_control
    result["status"] = "failed" if failures else "passed"
    result["declarations"] = {name: {"status": contract["status"], "reason": contract["reason"]} for name, contract in expected["fixtures"].items()}
    (args.output / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    (args.output / "behavior.diff").write_text("\n".join(failures) + ("\n" if failures else ""))
    for name, contract in expected["fixtures"].items():
        print(f"{contract['status'].upper()} {name}: {contract['reason']}")
    print(f"Comparison {result['status']}; negative control rejected={negative_control}; artifacts={args.output}")
    if failures:
        print("\n".join(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

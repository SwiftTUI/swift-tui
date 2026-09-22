#!/usr/bin/env python3
"""Advisory SwiftPM source census. No source-size failure threshold."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def census(root, manifest, ownership, revision):
    files, excluded = [], []
    for target in sorted(manifest["targets"], key=lambda item: item["name"]):
        for source in sorted(target.get("sources", [])):
            path = (Path(target["path"]) / source).as_posix()
            data = (root / path).read_bytes()
            text = data.decode("utf-8")
            reason = None
            if path.startswith("Vendor/") or target["name"].startswith("SwiftTUIVendor"):
                reason = "vendor"
            elif re.search(r"^// (?:This file is )?(?:auto[- ]?)?generated\b", "\n".join(text.splitlines()[:8]), re.I | re.M):
                reason = "generated header"
            if reason:
                excluded.append({"path": path, "target": target["name"], "reason": reason})
                continue
            row = {"path": path, "target": target["name"], "kind": target["type"],
                   "lines": len(data.splitlines()), "sha256": hashlib.sha256(data).hexdigest()}
            if target["type"] == "test" and re.search(r"@Test\b", text):
                row["classification"] = ownership.get("files", {}).get(path, {"category": "unclassified", "reason": "No reviewed ownership entry"})
            files.append(row)
    return {"format": 1, "sourceRevision": revision, "manifestTargets": sorted(t["name"] for t in manifest["targets"]),
            "files": files, "excluded": excluded}


def compare(base, head):
    old = {(r["path"], r["target"]): r for r in base["files"]}
    new = {(r["path"], r["target"]): r for r in head["files"]}
    changes = []
    for key in sorted(old.keys() & new.keys()):
        if old[key] != new[key]:
            changes.append({"change": "modified", "before": old[key], "after": new[key]})
    removed = [old[k] for k in sorted(old.keys() - new.keys())]
    added = [new[k] for k in sorted(new.keys() - old.keys())]
    # Unique same-path matches preserve target moves, even with content edits.
    # Unique identical-content matches preserve renames. Ambiguous duplicates
    # stay added/deleted rather than inventing a correspondence.
    for field in ("path", "sha256"):
        for previous in removed[:]:
            matches = [r for r in added if r[field] == previous[field]]
            if len(matches) == 1 and sum(r[field] == previous[field] for r in removed) == 1:
                current = matches[0]
                changes.append({"change": "target-move" if previous["path"] == current["path"] else "rename",
                                "before": previous, "after": current})
                removed.remove(previous)
                added.remove(current)
    changes += [{"change": "deleted", "before": r} for r in removed]
    changes += [{"change": "added", "after": r} for r in added]
    return sorted(changes, key=lambda r: (r.get("after", r.get("before"))["path"], r["change"]))


def render(data, changes=None):
    production = [r for r in data["files"] if r["kind"] != "test"]
    suites = [r for r in data["files"] if "classification" in r]
    unknown = [r for r in suites if r["classification"]["category"] == "unclassified"]
    lines = ["# Source structure observations", "", f"Format 1; source revision `{data['sourceRevision']}`.", "",
             f"{len(production)} production source files; {len(suites)} test source files containing `@Test`; {len(unknown)} unclassified; {len(data['excluded'])} excluded.", "",
             "Physical lines include comments and blank lines. Counts are advisory, not limits.", "",
             "## Largest production files", "", "| Path | SwiftPM target | Lines |", "| --- | --- | ---: |"]
    for row in sorted(production, key=lambda r: (-r["lines"], r["path"]))[:30]:
        lines.append(f"| `{row['path']}` | {row['target']} | {row['lines']} |")
    lines += ["", "## Suite ownership", "", "| Category | Files |", "| --- | ---: |"]
    for category in sorted({r["classification"]["category"] for r in suites}):
        lines.append(f"| {category} | {sum(r['classification']['category'] == category for r in suites)} |")
    lines += ["", "## Unclassified test sources", ""]
    lines += [f"- `{r['path']}` ({r['target']})" for r in unknown] or ["None in this census."]
    if changes is not None:
        lines += ["", "## Baseline changes", "", "| Change | Before | After |", "| --- | --- | --- |"]
        for change in changes:
            def label(row):
                return f"`{row['path']}` ({row['target']}, {row['lines']} lines)" if row else "—"
            lines.append(f"| {change['change']} | {label(change.get('before'))} | {label(change.get('after'))} |")
        if not changes:
            lines.append("| none | — | — |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/source-structure.json")
    parser.add_argument("--compare", type=Path, help="Compare with a saved base census; writes .diff.json")
    args = parser.parse_args()
    manifest = json.loads(subprocess.check_output(["swiftly", "run", "swift", "package", "describe", "--type", "json"], cwd=ROOT))
    ownership = json.loads((ROOT / "Scripts/data/test-ownership.json").read_text())
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    data = census(ROOT, manifest, ownership, revision)
    changes = compare(json.loads(args.compare.read_text()), data) if args.compare else None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    args.output.with_suffix(".md").write_text(render(data, changes))
    if changes is not None:
        args.output.with_suffix(".diff.json").write_text(json.dumps(changes, indent=2, sort_keys=True) + "\n")
    print(f"Source observations: {args.output.with_suffix('.md')}")


if __name__ == "__main__":
    main()

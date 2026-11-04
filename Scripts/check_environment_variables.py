"""Require production Swift code to reference framework environment keys by name."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
registry = root / "Sources/SwiftTUIPrimitives/Support/SwiftTUIEnvironmentVariable.swift"
literal = re.compile(r'"SWIFTTUI_[A-Z0-9_]+"')
violations = []
for directory in ("Sources", "Platforms"):
    for source in (root / directory).rglob("*.swift"):
        if source == registry or "Tests" in source.parts:
            continue
        for number, line in enumerate(source.read_text().splitlines(), 1):
            if not line.lstrip().startswith("//") and literal.search(line):
                violations.append(f"{source.relative_to(root)}:{number}: use SwiftTUIEnvironmentVariable")
if violations:
    sys.exit("\n".join(violations))

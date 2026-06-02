#!/usr/bin/env sh

# Verify the Foundation-free engine layers never load Foundation through ANY
# transitive dependency.
#
# The `no-foundation-in-library-products` pre-commit hook greps a fixed set of
# source directories for `import Foundation`. That is fast but blind to
# Foundation arriving through a dependency whose directory nobody remembered to
# add to the list. This check instead follows real package resolution: it builds
# the layers with the Swift compiler's `-emit-loaded-module-trace`, which makes
# each module emit a `<Module>.trace.json` listing every `.swiftmodule` it
# actually loaded transitively. We then assert no Foundation module appears.
#
# Scope: SwiftTUICore and SwiftTUIViews — the layers that are Foundation-free
# through their *entire* transitive graph. Checking them also covers the vendored
# EmbeddedFonts / SwiftFiglet modules they depend on. The `SwiftTUI` convenience
# product is intentionally NOT checked here: it re-exports the terminal/WebHost
# runner products, which legitimately use Foundation, so it is Foundation-free
# only at the source level (the no-foundation hook covers that).
#
# `_DarwinFoundation1/2/3` are stdlib Darwin overlays present even in pure-stdlib
# code; they are deliberately not treated as Foundation here.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

if ! command -v python3 >/dev/null 2>&1; then
  >&2 echo "check_foundation_free_layers requires python3 to parse module traces."
  exit 1
fi

layers="SwiftTUICore SwiftTUIViews"
scratch=".build/foundation-audit"

rm -rf "$scratch"
mkdir -p "$scratch"

target_args=""
for layer in $layers; do
  target_args="$target_args --target $layer"
done

echo "[check_foundation_free_layers] Building ($layers) with -emit-loaded-module-trace..." >&2
# shellcheck disable=SC2086
if ! swiftly run swift build --scratch-path "$scratch" $target_args \
  -Xswiftc -emit-loaded-module-trace >"$scratch/build.log" 2>&1; then
  >&2 echo "[check_foundation_free_layers] build failed:"
  >&2 tail -40 "$scratch/build.log"
  exit 1
fi

violations=$(
  python3 - "$scratch" $layers <<'PY'
import glob
import json
import os
import re
import sys

scratch = os.path.abspath(sys.argv[1])
layers = sys.argv[2:]

# Exact module names that mean "Foundation reached this module". The
# `_DarwinFoundation*` stdlib overlays are intentionally excluded.
forbidden = re.compile(
    r"^(Foundation|FoundationEssentials|FoundationInternationalization"
    r"|FoundationNetworking|FoundationXML|CoreFoundation)$"
)


def last_record(path):
    # `-emit-loaded-module-trace` appends one JSON object per compile (JSONL);
    # the final record reflects the most recent compilation of current sources.
    record = None
    for line in open(path):
        line = line.strip()
        if line:
            record = json.loads(line)
    return record


def trace_for(module):
    matches = glob.glob(
        os.path.join(scratch, "**", f"{module}.build", f"{module}.trace.json"),
        recursive=True,
    )
    return matches[0] if matches else None


def loaded_modules(record):
    # Yields (module_name, swiftmodule_path) for every loaded .swiftmodule.
    # SDK/toolchain modules appear as a `Foo.swiftmodule/<arch>.swiftinterface`
    # directory; SwiftPM-built local modules appear as a single `Foo.swiftmodule`
    # file (no trailing slash) — so accept either a `/` or end-of-string after it.
    for entry in record.get("swiftmodules", []):
        path = entry if isinstance(entry, str) else entry.get("name", "")
        match = re.search(r"/([^/]+)\.swiftmodule(?:/|$)", path)
        if match:
            yield match.group(1), path


failures = []
# Walk the entire LOCAL module closure reachable from the Foundation-free layers.
# A module is "local" (first-party, vendored, or an SPM dependency we build) when
# its .swiftmodule lives under our scratch build dir; toolchain/SDK modules do
# not. Each module's own trace reveals a Foundation import that its interface may
# not expose to its dependents, so every local module must be inspected directly.
to_visit = list(layers)
visited = set()
while to_visit:
    module = to_visit.pop()
    if module in visited:
        continue
    visited.add(module)

    trace = trace_for(module)
    if trace is None:
        if module in layers:
            failures.append(f"{module}: no loaded-module trace emitted (build issue)")
        continue

    record = last_record(trace) or {}
    found = set()
    for name, path in loaded_modules(record):
        if forbidden.match(name):
            found.add(name)
        elif scratch in os.path.abspath(path) and name not in visited:
            to_visit.append(name)
    if found:
        failures.append(f"{module}: imports {', '.join(sorted(found))}")

for failure in sorted(failures):
    print(failure)
PY
)

if [ -n "$violations" ]; then
  >&2 echo "Foundation reached a Foundation-free engine layer through its transitive"
  >&2 echo "module graph:"
  >&2 echo ""
  >&2 printf '  %s\n' "$violations"
  >&2 echo ""
  >&2 echo "SwiftTUICore and SwiftTUIViews (and the vendored modules they depend on)"
  >&2 echo "must stay Foundation-free through the entire dependency graph. Find the"
  >&2 echo "dependency that imports Foundation and remove or replace it."
  exit 1
fi

echo "[check_foundation_free_layers] ok — $layers load no Foundation transitively." >&2

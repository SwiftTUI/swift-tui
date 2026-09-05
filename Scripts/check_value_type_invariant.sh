#!/usr/bin/env sh

# Negative-compile lane for the value-type authoring invariant
# (plan 2026-08-29-001 Stage 1).
#
# `View`, `ViewModifier`, `DynamicProperty`, the four style protocols,
# `Scene`, and `App` each declare a defaulted static witness whose
# `Self: AnyObject` overload is `@available(*, unavailable)`. A class
# conformer therefore fails to compile with the protocol's own message. That
# enforcement is a compiler behavior, not a test the package can assert from
# inside itself — a conforming class does not compile, so it cannot live in
# `Tests/`. This lane typechecks two out-of-tree fixtures against the modules
# the debug build already produced:
#
#   Scripts/data/value-type-invariant/rejected.swift  must FAIL, with one
#       unavailable-witness diagnostic per authoring protocol, and with no
#       error of any other kind (an unrelated failure — a renamed
#       configuration type, say — would otherwise mask a diagnostic that has
#       silently stopped firing).
#   Scripts/data/value-type-invariant/accepted.swift  must typecheck CLEAN:
#       structs, enums, generics, a downstream conditional conformance, and
#       views holding class-typed FIELDS all stay legal.
#
# The fixtures import the public products only, so they typecheck as a
# downstream consumer would — which also pins that the witness stays
# satisfiable from outside the package.
#
# Usage:
#   Scripts/check_value_type_invariant.sh [--modules-dir <dir>]
#
# <dir> defaults to the HOST build's module directory, asked of SwiftPM
# (`swift build --show-bin-path`) rather than assumed to be `.build/debug`.
# That symlink points at whichever triple was built last, so a preceding
# wasm32-wasi cross-compile leaves it aimed at wasm modules and the typecheck
# fails with "module 'SwiftTUIRuntime' was created for incompatible target".
# Run `swift build` first (the repo gate's core lane already has, so this
# costs one typecheck per fixture).

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

modules_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --modules-dir)
    shift
    if [ "$#" -eq 0 ] || [ -z "$1" ]; then
      >&2 echo "--modules-dir requires a directory."
      exit 2
    fi
    modules_dir=$1
    ;;
  *)
    >&2 echo "usage: $0 [--modules-dir <dir>]"
    exit 2
    ;;
  esac
  shift
done

if [ -z "$modules_dir" ]; then
  host_bin_path=$(swiftly run swift build --show-bin-path 2>/dev/null || true)
  if [ -n "$host_bin_path" ] && [ -d "$host_bin_path/Modules" ]; then
    modules_dir="$host_bin_path/Modules"
  else
    modules_dir=".build/debug/Modules"
  fi
fi

fixture_dir="Scripts/data/value-type-invariant"
rejected="$fixture_dir/rejected.swift"
accepted="$fixture_dir/accepted.swift"

# Every protocol the invariant covers, in declaration order. Each must produce
# its own diagnostic in the rejected fixture.
protocols="View ViewModifier DynamicProperty ButtonStyle PickerStyle TextFieldStyle TabViewStyle LabelStyle LabeledContentStyle GroupBoxStyle Scene App"

for module in SwiftTUIViews SwiftTUIRuntime SwiftTUIGraph; do
  if [ ! -e "$modules_dir/$module.swiftmodule" ]; then
    >&2 echo "[check_value_type_invariant] no $module.swiftmodule under $modules_dir"
    >&2 echo "Build first (swift build), or pass --modules-dir <dir>."
    exit 1
  fi
done

# Runs one typecheck, setting `typecheck_output` and `typecheck_status`.
# Both are needed from a single compile — running the fixture twice would
# double the lane's cost for nothing.
typecheck() {
  set +e
  typecheck_output=$(swiftly run swiftc -typecheck -swift-version 6 -I "$modules_dir" "$1" 2>&1)
  typecheck_status=$?
  set -e
}

failures=0

fail() {
  >&2 echo "$1"
  failures=1
}

# --- The rejected fixture must not compile ---------------------------------
typecheck "$rejected"
rejected_output=$typecheck_output

if [ "$typecheck_status" -eq 0 ]; then
  fail "$rejected typechecked, but every declaration in it is a class conforming to an authoring protocol and must be rejected. The value-type invariant is no longer enforced."
fi

for protocol_name in $protocols; do
  if ! printf '%s\n' "$rejected_output" |
    grep -q "was used to satisfy a requirement of protocol '$protocol_name'"; then
    fail "No unavailable-witness diagnostic for protocol '$protocol_name' in $rejected. Either its witness is missing, or the compiler stopped rejecting an unavailable witness."
  fi
done

# Any error that is NOT the invariant's own is a broken fixture masking the
# check above.
unexpected=$(
  printf '%s\n' "$rejected_output" |
    grep -E "^${fixture_dir}/[^:]*:[0-9]+:[0-9]+: error: " |
    grep -v "was used to satisfy a requirement of protocol" |
    grep -v "does not conform to protocol" ||
    true
)

if [ -n "$unexpected" ]; then
  fail "$rejected failed for reasons unrelated to the value-type invariant:"
  >&2 printf '  %s\n' "$unexpected"
fi

# --- The accepted fixture must compile clean -------------------------------
typecheck "$accepted"

if [ "$typecheck_status" -ne 0 ]; then
  fail "$accepted must typecheck clean — the invariant constrains authoring CONTAINERS only. Errors:"
  >&2 printf '%s\n' "$typecheck_output" | grep -E "error: " >&2 || true
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "[check_value_type_invariant] ok — class conformers rejected for: $protocols" >&2

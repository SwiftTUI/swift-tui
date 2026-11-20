#!/usr/bin/env sh

# Overload-selection lane for `View.transition(_:)` (STUI-1543).
#
# `View` has two `transition(_:)` methods: the original one takes an
# `AnyTransition`, and the generic one takes any `Transition`. Every call
# spelling that existed before the generic method must keep selecting the
# `AnyTransition` method, with no ambiguity. Which overload a call selects is
# a type-checker decision, not something a test inside the package can
# observe at run time, so this lane typechecks two out-of-tree fixtures
# against the modules the debug build already produced:
#
#   Scripts/data/transition-overloads/accepted.swift  must typecheck CLEAN.
#       It binds the result of each spelling and compares its type with a
#       reference that only one overload can produce. An ambiguity, or a
#       spelling that moved to the other overload, is a compile error.
#   Scripts/data/transition-overloads/rejected.swift  must FAIL, with an
#       error on every line marked `expect-error` and on no other line. Each
#       marked line compares results of the two different overloads, so the
#       file proves the comparison in the accepted fixture can fail.
#
# The fixtures import the public product only and are typechecked with the
# upcoming features the SwiftTUI library repositories enable, as a downstream
# consumer would compile them.
#
# Usage:
#   Scripts/check_transition_overloads.sh [--modules-dir <dir>]
#
# <dir> defaults to the HOST build's module directory, asked of SwiftPM
# (`swift build --show-bin-path`), as Scripts/check_value_type_invariant.sh
# does. Run `swift build` first (the repo gate's core lane already has).

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
  host_bin_path=$(swiftly run swift build --build-system native --show-bin-path 2>/dev/null || true)
  if [ -n "$host_bin_path" ] && [ -d "$host_bin_path/Modules" ]; then
    modules_dir="$host_bin_path/Modules"
  else
    modules_dir=".build/debug/Modules"
  fi
fi

fixture_dir="Scripts/data/transition-overloads"
accepted="$fixture_dir/accepted.swift"
rejected="$fixture_dir/rejected.swift"

if [ ! -e "$modules_dir/SwiftTUIViews.swiftmodule" ]; then
  >&2 echo "[check_transition_overloads] no SwiftTUIViews.swiftmodule under $modules_dir"
  >&2 echo "Build first (swift build), or pass --modules-dir <dir>."
  exit 1
fi

# Runs one typecheck, setting `typecheck_output` and `typecheck_status`.
typecheck() {
  set +e
  typecheck_output=$(
    swiftly run swiftc -typecheck -swift-version 6 -strict-memory-safety \
      -enable-upcoming-feature ExistentialAny \
      -enable-upcoming-feature ImmutableWeakCaptures \
      -enable-upcoming-feature InternalImportsByDefault \
      -enable-upcoming-feature MemberImportVisibility \
      -enable-upcoming-feature NonisolatedNonsendingByDefault \
      -I "$modules_dir" "$1" 2>&1
  )
  typecheck_status=$?
  set -e
}

failures=0

fail() {
  >&2 echo "$1"
  failures=1
}

# --- The accepted fixture must compile clean -------------------------------
typecheck "$accepted"

if [ "$typecheck_status" -ne 0 ]; then
  fail "$accepted must typecheck clean: every existing spelling selects the AnyTransition overload and every new spelling the generic one. Errors:"
  >&2 printf '%s\n' "$typecheck_output" | grep -E "error: " >&2 || true
fi

# --- The rejected fixture must fail on exactly its marked lines ------------
typecheck "$rejected"

if [ "$typecheck_status" -eq 0 ]; then
  fail "$rejected typechecked, but each marked line compares results of the two different transition(_:) overloads. The fixture no longer tells the overloads apart."
fi

expected_lines=$(grep -n '// expect-error' "$rejected" | cut -d: -f1 | sort -n -u)
actual_lines=$(
  printf '%s\n' "$typecheck_output" |
    grep -E "^${rejected}:[0-9]+:[0-9]+: error: " |
    cut -d: -f2 | sort -n -u || true
)

if [ -z "$expected_lines" ]; then
  fail "$rejected has no line marked expect-error; the negative fixture is empty."
fi

if [ "$expected_lines" != "$actual_lines" ]; then
  fail "$rejected must fail on exactly the lines marked expect-error."
  >&2 echo "  expected error lines: $(printf '%s' "$expected_lines" | tr '\n' ' ')"
  >&2 echo "  actual error lines:   $(printf '%s' "$actual_lines" | tr '\n' ' ')"
  >&2 printf '%s\n' "$typecheck_output" | grep -E "error: " >&2 || true
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

expected_count=$(printf '%s\n' "$expected_lines" | wc -l | tr -d ' ')
echo "[check_transition_overloads] ok — existing spellings select the AnyTransition overload; $expected_count cross-overload comparisons rejected" >&2

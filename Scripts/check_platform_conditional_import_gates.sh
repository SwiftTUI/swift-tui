#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() {
  printf '[check_platform_conditional_import_gates] %s\n' "$1" >&2
  exit 1
}

# Windows plan, Stage 6 items 1/3 (the Stage 5 build-history trap, measured
# live at Stage 6): a module whose dependency EDGES are platform-conditional
# can still be built — empty — on an excluded platform whenever any target
# (a test target is enough) depends on it unconditionally. The stale
# .swiftmodule in the shared build directory then flips every
# `#if canImport(<module>)` gate in the package, compiling code the platform
# cannot support. Gates on conditionally-edged siblings must therefore be
# platform mirrors of the manifest allowlist (`#if os(macOS) || os(iOS) ||
# os(Linux) || os(Android)`), never `canImport`.
#
# This check derives the conditionally-edged dependency names from
# Package.swift and rejects `canImport(<name>)` in non-test sources.
# `canImport` on SDK modules (Darwin, Glibc, WASILibc, ucrt, CoreFoundation)
# and on unconditionally-edged in-package modules stays legal.

# ---- derive the conditionally-edged dependency names ------------------------
# Dependency entries carry the shape:
#     .target(
#       name: "X",
#       condition: .when(platforms: [...])
#     ),
# (or .product with package:). Remember the most recent `name:` and emit it
# when a `condition: .when` follows within the same entry.
conditional_modules=$(
  awk '
    /name: "/ {
      line = $0
      sub(/.*name: "/, "", line)
      sub(/".*/, "", line)
      last_name = line
      distance = 0
      next
    }
    /condition: \.when/ && last_name != "" && distance <= 2 { print last_name; last_name = "" }
    { distance += 1 }
  ' Package.swift | sort -u
)

if [ -z "$conditional_modules" ]; then
  fail "derived ZERO conditionally-edged modules from Package.swift — the awk scan no longer matches the manifest shape; fix the parser rather than letting the check pass vacuously"
fi

# ---- scan non-test sources for canImport gates on those modules -------------
violations=""
for module in $conditional_modules; do
  hits=$(
    grep -rn "canImport(${module})" Sources/ Platforms/ Vendor/ \
      --include='*.swift' 2>/dev/null |
      grep -v '/Tests/' || true
  )
  if [ -n "$hits" ]; then
    violations="${violations}${hits}"$'\n'
  fi
done

if [ -n "$violations" ]; then
  printf '[check_platform_conditional_import_gates] canImport gate(s) on conditionally-edged modules:\n%s' "$violations" >&2
  fail "replace each with the platform mirror of the manifest allowlist: #if os(macOS) || os(iOS) || os(Linux) || os(Android)"
fi

count=$(printf '%s\n' "$conditional_modules" | wc -l | tr -d ' ')
printf '[check_platform_conditional_import_gates] ok — no canImport gates on the %s conditionally-edged modules (%s).\n' \
  "$count" "$(printf '%s' "$conditional_modules" | tr '\n' ' ')"

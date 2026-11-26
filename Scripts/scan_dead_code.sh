#!/usr/bin/env sh

set -eu

# Dead-code scan with Periphery (https://github.com/peripheryapp/periphery).
#
# Periphery reads the compiler's index store, so it sees only what a build
# compiled. This script builds two stores in their own scratch paths, then
# runs `periphery scan` with the options in `.periphery.yml`:
#
#   .build-periphery        the macOS debug build, with tests
#   .build-periphery-wasm   the wasm32-wasi cross-compile of SwiftTUIWASI
#
# The second store lets the scan see WASI-only code and its callers. The
# baseline store is the Darwin build, so run this on macOS.
#
# Code compiled only for Windows, Linux or Android stays invisible, and so
# does a release-only (`#if DEBUG ... #else`) branch. A declaration or an
# `import` that is used only there is reported as unused. Do not delete it. Put
#
#   // periphery:ignore - <where it is used>
#
# on the line above it (above its doc comment, if it has one). Before removing
# anything from a file that has platform branches, build for every platform.
# Use the same comment for a declaration that is unused on purpose, such as a
# field that mirrors a runtime layout or a protocol requirement that exists to
# bind its conformers. For a parameter a platform stub must accept, use
# `// periphery:ignore:parameters <name>,<name>`. Periphery reports an ignore
# comment that is no longer needed.
#
# Usage: Scripts/scan_dead_code.sh [--clean] [periphery scan options...]
#
#   --clean   delete both scratch paths first, so neither store holds a unit
#             from an earlier build
#
# Every other argument goes to `periphery scan`, for example
# `--format json --write-results findings.json`.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
cd "$repo_root"

host_scratch=.build-periphery
wasi_scratch=.build-periphery-wasm
swift_version=$(cat .swift-version)
wasm_sdk_id="${WASM_SDK_ID:-swift-${swift_version}-RELEASE_wasm}"

if [ "${1:-}" = "--clean" ]; then
  shift
  rm -rf "$host_scratch" "$wasi_scratch"
fi

for tool in periphery swiftly; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    >&2 printf 'scan_dead_code: %s is not on PATH' "$tool"
    if [ "$tool" = periphery ]; then
      >&2 printf ' (brew install periphery)'
    fi
    >&2 printf '\n'
    exit 1
  fi
done

printf '==> Build the macOS index store (%s)\n' "$host_scratch"
swiftly run swift build --build-tests --scratch-path "$host_scratch"

printf '==> Build the WASI index store (%s)\n' "$wasi_scratch"
swiftly run swift build --swift-sdk "$wasm_sdk_id" --target SwiftTUIWASI \
  --scratch-path "$wasi_scratch"

# `.periphery.yml` names these paths. A SwiftPM build engine that lays the
# store out differently must fail here, not scan an empty index.
for store in "$host_scratch/out" "$wasi_scratch/out"; do
  if [ ! -d "$store/v5/units" ]; then
    >&2 printf 'scan_dead_code: no index store at %s; update index_store_path in .periphery.yml\n' \
      "$store"
    exit 1
  fi
done

manifest=$(mktemp "${TMPDIR:-/tmp}/swifttui-periphery-manifest.XXXXXX")
trap 'rm -f "$manifest"' EXIT HUP INT TERM
swiftly run swift package describe --type json >"$manifest"

printf '==> Scan\n'
periphery scan --json-package-manifest-path "$manifest" "$@"

#!/usr/bin/env sh

set -eu

# Builds and runs package tests under a sanitizer in a separate scratch path,
# so the ordinary debug build cache survives, and fails on any sanitizer
# report (campaign two, lineage F4; plan docs/plans/2026-10-23-001 in
# swift-tui-org).
#
# Usage:
#   Scripts/run_sanitizer_lane.sh --sanitize thread|address|undefined \
#       [--filter REGEX] [--jobs N] [--log PATH] [--scratch-path PATH]
#
# The lane is serialized (--no-parallel): sanitizer reports from concurrent
# tests interleave and lose their stacks. Reports are summarized at the end
# by their first frame so a baseline can be compared run to run.
#
# Exit tests (`#expect(processExitsWith:)`) re-spawn the test host. On Darwin
# a sanitizer runtime must be loaded at launch: SwiftPM preloads it for the
# host, but the preload does not survive into the host's environment, so the
# child loaded the runtime too late and aborted ("Interceptors are not
# working"). Swift Testing turns `XCTestBundleInjectPath` into the child's
# `DYLD_INSERT_LIBRARIES` (its XCTest app-hosting path), so the lane hands it
# this sanitizer's runtime.

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

sanitizer=""
filter=""
jobs=""
log=""
scratch=""

usage() {
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --sanitize) sanitizer="$2"; shift 2 ;;
  --sanitize=*) sanitizer="${1#*=}"; shift ;;
  --filter) filter="$2"; shift 2 ;;
  --filter=*) filter="${1#*=}"; shift ;;
  --jobs) jobs="$2"; shift 2 ;;
  --jobs=*) jobs="${1#*=}"; shift ;;
  --log) log="$2"; shift 2 ;;
  --log=*) log="${1#*=}"; shift ;;
  --scratch-path) scratch="$2"; shift 2 ;;
  --scratch-path=*) scratch="${1#*=}"; shift ;;
  -h | --help) usage; exit 0 ;;
  *) >&2 echo "Unknown argument: $1"; usage >&2; exit 1 ;;
  esac
done

case "$sanitizer" in
thread | address | undefined) ;;
*) >&2 echo "--sanitize must be thread, address or undefined"; exit 1 ;;
esac

scratch="${scratch:-$repo_root/.build/sanitizer-$sanitizer}"
log="${log:-$scratch/sanitizer-$sanitizer.log}"
mkdir -p "$(dirname "$log")"

# Report every finding instead of aborting at the first, and keep the test
# process alive so the summary below sees the whole run. LeakSanitizer is not
# available on macOS and is noisy under Swift runtime allocations on Linux.
export TSAN_OPTIONS="${TSAN_OPTIONS:-halt_on_error=0 second_deadlock_stack=1 history_size=4}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0 halt_on_error=0}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1 halt_on_error=0}"
export SWIFTTUI_SANITIZER_LANE="$sanitizer"

# The sanitizer runtime next to the toolchain's clang resources, for the
# exit-test child spawn (see the header).
sanitizer_runtime_path() {
  resources=$(swiftly run swift -print-target-info 2>/dev/null \
    | sed -n 's/^ *"runtimeResourcePath": *"\(.*\)",*$/\1/p' | head -n 1)
  [ -n "$resources" ] || return 0
  case "$1" in
  address) short=asan ;;
  thread) short=tsan ;;
  undefined) short=ubsan ;;
  esac
  for candidate in "${resources%/swift}"/clang/*/lib/darwin/libclang_rt.${short}_osx_dynamic.dylib; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
}

case "$(uname -s)" in
Darwin)
  runtime=$(sanitizer_runtime_path "$sanitizer")
  if [ -n "$runtime" ]; then
    export XCTestBundleInjectPath="$runtime"
    echo "[sanitizer-lane] exit-test children preload: $runtime"
  else
    >&2 echo "[sanitizer-lane] warning: no $sanitizer runtime dylib found; exit-test children will abort"
  fi
  ;;
esac

set -- swiftly run swift test --build-system native --sanitize "$sanitizer" --scratch-path "$scratch" --no-parallel
if [ -n "$jobs" ]; then set -- "$@" --jobs "$jobs"; fi
if [ -n "$filter" ]; then set -- "$@" --filter "$filter"; fi

echo "[sanitizer-lane] $*"
echo "[sanitizer-lane] log: $log"
status=0
"$@" >"$log" 2>&1 || status=$?

reports=$(grep -c -E "WARNING: ThreadSanitizer|ERROR: AddressSanitizer|runtime error:" "$log" || true)
tests_line=$(grep -E "Test run with [0-9]+ tests" "$log" | tail -1 || true)
echo "[sanitizer-lane] swift test exit: $status"
echo "[sanitizer-lane] $tests_line"
echo "[sanitizer-lane] sanitizer reports: $reports"
if [ "$reports" -gt 0 ]; then
  echo "[sanitizer-lane] report kinds and first frames:"
  grep -E -A4 "WARNING: ThreadSanitizer|ERROR: AddressSanitizer|runtime error:" "$log" \
    | grep -E "WARNING: ThreadSanitizer|ERROR: AddressSanitizer|runtime error:|#0 " \
    | sed -E 's/ \(0x[0-9a-f]+\)//; s/^ *//' | sort | uniq -c | sort -rn | head -40
fi

if [ "$status" -ne 0 ] || [ "$reports" -gt 0 ]; then
  exit 1
fi

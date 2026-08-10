#!/usr/bin/env sh

set -eu

# Liveness assertion for serialized test execution.
#
# The runtime lane claims to run serially (`--no-parallel`; the mitigation for
# KNOWN-TEST-FLAKES.md entry 14). Twice before, a serialization switch was
# inert while its step stayed green: a bare `--num-workers 1` died on argument
# validation, and `--parallel --num-workers 1` validated but left swift-testing
# at peak 1645 tests in flight. A green step cannot distinguish "serialized"
# from "flag ignored", so this script measures the execution shape instead:
# it parses a `swift test` log, tracks tests started minus tests completed,
# and fails when the peak in-flight count exceeds a small bound. A genuinely
# serial lane measures ~1-3; a parallel lane measures hundreds.
#
# It also fails when the log contains NO recognizable test-start events, so a
# format drift in the test runner's output breaks this check loudly instead of
# silently turning it into a fourth piece of inert tooling.
#
# Usage:
#   check_serialized_execution.sh <log-file> [max-peak]
#   check_serialized_execution.sh --self-test
#
# The bound defaults to 8 and can be set via SWIFTTUI_SERIALIZED_PEAK_MAX or
# the second argument.

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

# Prints "peak started finished" for a swift test log. Recognizes both
# swift-testing lines (`◇ Test x() started.` / `✔ Test x() passed after ...`,
# matched on words so the glyphs and their encoding never matter) and XCTest
# lines (`Test Case '...' started.` / `... passed (0.1 seconds)`). Suite and
# run-level lines are excluded, and so are parameterized `Test case ...`
# lines: swift-testing announces each case at start but emits no per-case
# completion (measured: 103 case starts, 0 case completions in one lane log),
# so counting them inflates a perfectly serial lane to peak ~100. Only
# top-level test events count; a serial lane measures peak 1, a parallel lane
# measures peak ~1600.
measure_log() {
  awk '
    /Test run /                                { next }
    / Suite /                                  { next }
    / Test case /                              { next }
    /^Test Suite /                             { next }
    /^Test Case .* started\.?$/                { start_event(); next }
    /^Test Case .* (passed|failed) \(/         { finish_event(); next }
    / Test .* started\.$/                      { start_event(); next }
    / Test .* (passed|failed) after /          { finish_event(); next }
    / Test .* skipped/                         { finish_event(); next }
    function start_event() {
      started += 1
      in_flight += 1
      if (in_flight > peak) peak = in_flight
    }
    function finish_event() {
      finished += 1
      if (in_flight > 0) in_flight -= 1
    }
    END { printf "%d %d %d\n", peak, started, finished }
  ' "$1"
}

check_log() {
  log_file=$1
  max_peak=$2

  if [ ! -f "$log_file" ]; then
    >&2 echo "error: no such log file: $log_file"
    return 1
  fi

  measured=$(measure_log "$log_file")
  peak=${measured%% *}
  rest=${measured#* }
  started=${rest%% *}
  finished=${rest#* }

  echo "serialized-execution: peak=$peak started=$started finished=$finished max=$max_peak ($log_file)"

  if [ "$started" -eq 0 ]; then
    >&2 echo "error: no test-start events parsed from $log_file."
    >&2 echo "Either the lane ran no tests or the runner's output format drifted;"
    >&2 echo "both must fail here rather than silently passing (inert-tooling trap,"
    >&2 echo "docs/KNOWN-TEST-FLAKES.md entry 14)."
    return 1
  fi

  if [ "$peak" -gt "$max_peak" ]; then
    >&2 echo "error: peak in-flight tests $peak exceeds $max_peak: this lane ran PARALLEL."
    >&2 echo "The serialization flag is inert or was dropped. Only \`--no-parallel\`"
    >&2 echo "serializes swift-testing (docs/KNOWN-TEST-FLAKES.md entry 14)."
    return 1
  fi

  return 0
}

self_test() {
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-serialized-selftest.XXXXXX")
  trap 'rm -rf "$work_dir"' EXIT
  failures=0

  fail() {
    >&2 echo "error: $1"
    failures=$((failures + 1))
  }

  # Serial swift-testing log: each test completes before the next starts.
  # Includes a parameterized test whose cases are announced at start with NO
  # per-case completion lines — the real swift-testing output shape. Counting
  # those would inflate a serial lane to peak ~100, which is exactly how this
  # checker's first draft misread a genuinely serial lane.
  cat >"$work_dir/serial.log" <<'EOF'
Building for debugging...
Build complete! (1.23s)
◇ Test run started.
◇ Suite SwiftTUITests started.
◇ Test parserHandlesEmptyInput() started.
✔ Test parserHandlesEmptyInput() passed after 0.001 seconds.
◇ Test "braille cell rounds" started.
◇ Test case passing 1 argument metrics → CellPixelMetrics(width: 8, height: 16) to "braille cell rounds" started.
◇ Test case passing 1 argument metrics → CellPixelMetrics(width: 10, height: 20) to "braille cell rounds" started.
◇ Test case passing 1 argument metrics → CellPixelMetrics(width: 12, height: 24) to "braille cell rounds" started.
✔ Test "braille cell rounds" passed after 0.002 seconds with 1 known issue.
◇ Test inputModifierOrder() started.
✘ Test inputModifierOrder() failed after 0.003 seconds with 1 issue.
◇ Test slowPathSkipped() started.
⏭ Test slowPathSkipped() skipped.
✔ Suite SwiftTUITests passed after 0.010 seconds.
✔ Test run with 4 tests passed after 0.010 seconds.
EOF
  if ! sh "$0" "$work_dir/serial.log" >/dev/null 2>&1; then
    fail "serial swift-testing log with parameterized cases should pass"
  fi

  # Parallel swift-testing log: many starts before any completion.
  {
    echo "◇ Test run started."
    i=0
    while [ "$i" -lt 40 ]; do
      echo "◇ Test parallelCase$i() started."
      i=$((i + 1))
    done
    i=0
    while [ "$i" -lt 40 ]; do
      echo "✔ Test parallelCase$i() passed after 0.5 seconds."
      i=$((i + 1))
    done
    echo "✔ Test run with 40 tests passed after 0.6 seconds."
  } >"$work_dir/parallel.log"
  if sh "$0" "$work_dir/parallel.log" >/dev/null 2>&1; then
    fail "parallel swift-testing log should fail"
  fi

  # Serial XCTest log.
  cat >"$work_dir/xctest.log" <<'EOF'
Test Suite 'All tests' started at 2026-08-10 12:00:00.000.
Test Case 'FooTests.testBar' started.
Test Case 'FooTests.testBar' passed (0.001 seconds).
Test Case 'FooTests.testBaz' started.
Test Case 'FooTests.testBaz' failed (0.002 seconds).
Test Suite 'All tests' passed at 2026-08-10 12:00:01.000.
EOF
  if ! sh "$0" "$work_dir/xctest.log" >/dev/null 2>&1; then
    fail "serial XCTest log should pass"
  fi

  # A log with no test events at all (build output only, or a format drift)
  # must fail: a checker that passes on an unparseable log is itself inert.
  cat >"$work_dir/empty.log" <<'EOF'
Building for debugging...
Build complete! (1.23s)
EOF
  if sh "$0" "$work_dir/empty.log" >/dev/null 2>&1; then
    fail "log with no test events should fail"
  fi

  # A missing file must fail.
  if sh "$0" "$work_dir/does-not-exist.log" >/dev/null 2>&1; then
    fail "missing log file should fail"
  fi

  if [ "$failures" -gt 0 ]; then
    >&2 echo "self-test: $failures failure(s)"
    exit 1
  fi
  echo "self-test: all cases passed"
}

case "${1:-}" in
--self-test)
  self_test
  ;;
"")
  >&2 echo "usage: $0 <log-file> [max-peak] | --self-test"
  exit 2
  ;;
*)
  check_log "$1" "${2:-${SWIFTTUI_SERIALIZED_PEAK_MAX:-8}}"
  ;;
esac

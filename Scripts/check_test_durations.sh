#!/usr/bin/env sh

set -eu

# Per-test duration ratchet for the serialized runtime shards
# (swift-tui-org plan 2026-08-25-001, Stage 2b).
#
# Every hot-path test is expected to finish in <= 10 s; the churn loops that
# used to take 12-55 s read their iteration count from
# `stressIterations(full:hotPath:)` (Tests/Support/StressIterations.swift) and
# run the full count only under SWIFTTUI_STRESS_FULL=1 (the nightly and tag
# lanes). This script parses a `swift test` log and reports every test whose
# `passed/failed after N seconds` line exceeds the WARN bound, and fails the
# step when one exceeds the FAIL bound.
#
# Two bounds, not one: the amd64 runner class varies by 2x between runs
# (KNOWN-TEST-FLAKES.md entry 12), so a single 10 s hard bound would turn the
# ratchet itself into a flake source. The hard bound therefore sits at 2x the
# target; the target is reported so a creeping test is visible on every run.
#
# Only meaningful on a --no-parallel log: under parallel execution a test's
# reported duration includes contention from its neighbours.
#
# Usage:
#   check_test_durations.sh <log-file> [fail-seconds] [warn-seconds]
#   check_test_durations.sh --self-test
#
# Defaults: FAIL 20 (SWIFTTUI_TEST_DURATION_FAIL_SECONDS),
#           WARN 10 (SWIFTTUI_TEST_DURATION_WARN_SECONDS).

# Prints "<seconds>\t<test name>" for every completed top-level test in the
# log, both swift-testing (`Test x() passed after 1.2 seconds`) and XCTest
# (`Test Case '-[M.C t]' passed (1.2 seconds)`). Suite and run-level lines
# are excluded; parameterized `Test case` lines never carry a duration.
list_durations() {
  awk '
    /Test run /      { next }
    / Suite /        { next }
    / Test case /    { next }
    /^Test Suite /   { next }
    /^Test Case .* (passed|failed) \([0-9.]+ seconds\)/ {
      name = $0
      sub(/^Test Case /, "", name)
      sub(/ (passed|failed) \(.*$/, "", name)
      seconds = $0
      sub(/^.* \(/, "", seconds)
      sub(/ seconds\).*$/, "", seconds)
      printf "%s\t%s\n", seconds, name
      next
    }
    / Test .* (passed|failed) after [0-9.]+ seconds/ {
      name = $0
      sub(/^.* Test /, "", name)
      sub(/ (passed|failed) after .*$/, "", name)
      seconds = $0
      sub(/^.* after /, "", seconds)
      sub(/ seconds.*$/, "", seconds)
      # A parameterized test reports ONE duration for all of its cases
      # (`... with 50 test cases`) and no per-case completion lines, so the
      # bound applies to the per-case average: 50 distinct scenarios at 0.6 s
      # each are scenario coverage, not a slow test.
      cases = 1
      if (match(name, / with [0-9]+ test cases?$/)) {
        cases = substr(name, RSTART + 6)
        sub(/ test cases?$/, "", cases)
        cases += 0
        if (cases < 1) cases = 1
      }
      printf "%.3f\t%s\n", seconds / cases, name
      next
    }
  ' "$1"
}

check_log() {
  log_file=$1
  fail_bound=$2
  warn_bound=$3

  if [ ! -f "$log_file" ]; then
    >&2 echo "error: no such log file: $log_file"
    return 1
  fi

  durations=$(list_durations "$log_file")
  completed=$(printf '%s\n' "$durations" | awk 'NF { n += 1 } END { print n + 0 }')

  if [ "$completed" -eq 0 ]; then
    >&2 echo "error: no test-completion events parsed from $log_file."
    >&2 echo "Either the lane ran no tests or the runner's output format drifted;"
    >&2 echo "both must fail here rather than silently passing (inert-tooling trap)."
    return 1
  fi

  over_warn=$(printf '%s\n' "$durations" | awk -F '\t' -v bound="$warn_bound" 'NF && ($1 + 0) > bound' | sort -rn)
  over_fail=$(printf '%s\n' "$durations" | awk -F '\t' -v bound="$fail_bound" 'NF && ($1 + 0) > bound' | sort -rn)
  slowest=$(printf '%s\n' "$durations" | sort -rn | head -n 1)

  echo "test-durations: completed=$completed slowest=[$slowest] warn>${warn_bound}s fail>${fail_bound}s ($log_file)"

  if [ -n "$over_warn" ]; then
    echo "tests over the ${warn_bound}s hot-path target:"
    printf '%s\n' "$over_warn" | awk -F '\t' '{ printf "  %8.3f s  %s\n", $1, $2 }'
  fi

  if [ -n "$over_fail" ]; then
    >&2 echo "error: $(printf '%s\n' "$over_fail" | awk 'NF' | wc -l | tr -d ' ') test(s) exceed the ${fail_bound}s hard bound."
    >&2 echo "Read the loop's iteration count from stressIterations(full:hotPath:) or move"
    >&2 echo "the suite to the timing lane (Scripts/data/runtime-shards.txt); see plan"
    >&2 echo "2026-08-25-001 Stage 2b."
    return 1
  fi

  return 0
}

self_test() {
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-durations-selftest.XXXXXX")
  trap 'rm -rf "$work_dir"' EXIT
  failures=0

  fail() {
    >&2 echo "error: $1"
    failures=$((failures + 1))
  }

  cat >"$work_dir/fast.log" <<'LOG'
Building for debugging...
Build complete! (1.23s)
◇ Test run started.
◇ Suite SwiftTUITests started.
◇ Test quick() started.
✔ Test quick() passed after 0.001 seconds.
◇ Test "named test" started.
◇ Test case passing 1 argument x → 1 to "named test" started.
✔ Test "named test" passed after 4.500 seconds.
◇ Test failing() started.
✘ Test failing() failed after 0.003 seconds with 1 issue.
✔ Suite SwiftTUITests passed after 40.010 seconds.
✔ Test run with 3 tests passed after 40.010 seconds.
LOG
  if ! sh "$0" "$work_dir/fast.log" 20 10 >/dev/null 2>&1; then
    fail "log with every test under the bounds should pass"
  fi

  cat >"$work_dir/warn.log" <<'LOG'
◇ Test run started.
◇ Test slowish() started.
✔ Test slowish() passed after 12.5 seconds.
✔ Test run with 1 test passed after 12.5 seconds.
LOG
  if ! sh "$0" "$work_dir/warn.log" 20 10 >"$work_dir/warn.out" 2>&1; then
    fail "log with a test between warn and fail bounds should pass"
  fi
  if ! grep -q "slowish" "$work_dir/warn.out"; then
    fail "warn-bound test should be listed in the output"
  fi

  cat >"$work_dir/fail.log" <<'LOG'
◇ Test run started.
◇ Test "mixed deferred runtime surfaces survive repeated teardown and recreation" started.
✔ Test "mixed deferred runtime surfaces survive repeated teardown and recreation" passed after 54.558 seconds.
✔ Test run with 1 test passed after 54.558 seconds.
LOG
  if sh "$0" "$work_dir/fail.log" 20 10 >/dev/null 2>&1; then
    fail "log with a test over the fail bound should fail"
  fi

  cat >"$work_dir/xctest.log" <<'LOG'
Test Suite 'All tests' started at 2026-08-10 12:00:00.000.
Test Case '-[FooTests testBar]' started.
Test Case '-[FooTests testBar]' passed (0.001 seconds).
Test Case '-[FooTests testSlow]' started.
Test Case '-[FooTests testSlow]' passed (25.0 seconds).
Test Suite 'All tests' passed at 2026-08-10 12:00:25.000.
LOG
  if sh "$0" "$work_dir/xctest.log" 20 10 >/dev/null 2>&1; then
    fail "XCTest log with a test over the fail bound should fail"
  fi

  # A parameterized test's aggregate duration is normalized per case.
  cat >"$work_dir/parameterized.log" <<'LOG'
◇ Test run started.
◇ Test "directed stress expansion case" started.
✔ Test "directed stress expansion case" with 50 test cases passed after 30.008 seconds.
✔ Test run with 1 test passed after 30.008 seconds.
LOG
  if ! sh "$0" "$work_dir/parameterized.log" 20 10 >/dev/null 2>&1; then
    fail "parameterized test duration should be normalized by its case count"
  fi

  # A suite-level duration must never be mistaken for a test duration.
  cat >"$work_dir/suite-only.log" <<'LOG'
◇ Test run started.
◇ Test tiny() started.
✔ Test tiny() passed after 0.001 seconds.
✔ Suite "SwiftTUI framework stress behavior" passed after 249.027 seconds.
✔ Test run with 1 test passed after 249.027 seconds.
LOG
  if ! sh "$0" "$work_dir/suite-only.log" 20 10 >/dev/null 2>&1; then
    fail "suite/run durations must not count as test durations"
  fi

  cat >"$work_dir/empty.log" <<'LOG'
Building for debugging...
Build complete! (1.23s)
LOG
  if sh "$0" "$work_dir/empty.log" 20 10 >/dev/null 2>&1; then
    fail "log with no test completions should fail"
  fi

  if sh "$0" "$work_dir/does-not-exist.log" 20 10 >/dev/null 2>&1; then
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
  >&2 echo "usage: $0 <log-file> [fail-seconds] [warn-seconds] | --self-test"
  exit 2
  ;;
*)
  check_log "$1" \
    "${2:-${SWIFTTUI_TEST_DURATION_FAIL_SECONDS:-20}}" \
    "${3:-${SWIFTTUI_TEST_DURATION_WARN_SECONDS:-10}}"
  ;;
esac

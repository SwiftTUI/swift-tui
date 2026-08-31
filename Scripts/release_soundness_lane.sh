#!/usr/bin/env sh

# F05: release-configuration soundness lane.
#
# Before this lane, zero `swift test -c release` executions existed in any
# gate (24 debug steps): the sampled release soundness probe never ran in CI,
# and the deliberate release-only behavioral divergences (raster
# `.trustSoundDamage`, delta-checkpoint trust, release-checked isolation
# traps) shipped unobserved. This lane runs the pipeline, runtime, stress,
# and reconciliation suites in release with the probe forced on for every
# frame and violation tracing enabled, so the release-only arms actually
# execute and any violation is printed into the CI log.
#
# Not part of the push/PR gate: nightly-if-changed, every release tag, and
# dispatch via .github/workflows/release-soundness.yml.
#
# Execution shape (since 2026-08-31). The SwiftTUITests surface runs
# SERIALIZED, in the same shards as the repo gate (Scripts/data/runtime-shards.txt
# through Scripts/lib/runtime_shards.sh), each launch under the gate's silence
# watchdog (Scripts/lib/step_watchdog.sh) and followed by the
# serialized-execution assertion. Until then this lane was the only place in
# the org that ran the run-loop suites in ONE parallel `swift test` — about
# 1,600 tests in flight on a four-vCPU runner — and it had not been green
# since 2026-08-04. That shape failed in two ways no other gate could show,
# because no other gate has it:
#   * the real-time animator pins (KeyframeAnimator, PhaseAnimator,
#     ContentTransition) starved on the one main-actor executor every test
#     shares: an 800 ms animation observed as [start, end] with no frame
#     between, a phase never leaving rest inside a 32 s scaled wait;
#   * the whole process froze one to ten seconds into the run — none of the
#     ~1,600 in-flight tests progressed for 65 minutes (flake register entry
#     14's shape at extreme parallelism) — and cost the 90-minute job cap with
#     no dump.
# swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md entry 20 has the record.
#
# Modes:
#   (default)          every part below in order: build once, then core, and
#                      each shard in the manifest's order.
#   --part core        SwiftTUICoreTests in one parallel launch (the gate's
#                      core lane runs its non-runtime targets the same way),
#                      then each of the manifest's isolated SwiftTUITests
#                      suites in its own serialized launch, minus the ones the
#                      --flaky-only step owns.
#   --part <shard>     one serialized SwiftTUITests shard (A, B, C, ...),
#                      minus the isolated suites and the load-flaky run-loop
#                      suites documented in
#                      swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
#   --flaky-only       ONLY those load-flaky suites, serialized. Run from a
#                      continue-on-error step: a SIGSEGV here is flake #1
#                      (swift-tui#12) signal, and in release the checked
#                      isolation traps can convert it into an attributable
#                      preconditionIsolated failure.
#   --race-checks      stress + reconciliation subset rebuilt with
#                      -enable-actor-data-race-checks, serialized.
#   --dry-run          print every swift invocation instead of running it
#                      (composes with any mode above).
#
# Every mode builds once (`swift build -c release --build-tests`) and runs
# its launches with `--skip-build`. That keeps the 15-25 minute release build
# outside the per-launch watchdog: its whole-module compile of the test
# targets prints nothing for ten minutes or more while very busy, which is
# exactly the shape the watchdog would otherwise have to be widened to
# tolerate — and a widened watchdog is one that no longer fires inside the
# job cap for the stall it exists to catch.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

SWIFT="swift"
if command -v swiftly >/dev/null 2>&1; then
  SWIFT="swiftly run swift"
fi

SWIFTTUI_SOUNDNESS_PROBE=1 && export SWIFTTUI_SOUNDNESS_PROBE
SWIFTTUI_SOUNDNESS_PROBE_SAMPLE=1 && export SWIFTTUI_SOUNDNESS_PROBE_SAMPLE
SWIFTTUI_SOUNDNESS_PROBE_TRACE=1 && export SWIFTTUI_SOUNDNESS_PROBE_TRACE
# The collection probes (realization + list-layout derivation) are DEBUG-default
# and release-opt-in; the windowing suites assert through them, so this lane
# arms them the same way it forces the soundness probe on.
SWIFTTUI_COLLECTION_PROBES=1 && export SWIFTTUI_COLLECTION_PROBES

# Per-launch silence watchdog, the same knobs and defaults as the repo gate
# (Scripts/test_all.sh; the header of Scripts/lib/step_watchdog.sh explains
# each). Worst-case kill of a silent launch = idle bound + busy grace + kill
# grace = 910 s at these defaults; the workflow sets the deadline to its job
# cap so a watchdog that could not fire inside it refuses to start. The build
# is deliberately not under it (see the header).
step_timeout_seconds=${SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS:-600}
step_timeout_kill_grace_seconds=${SWIFTTUI_TEST_TIMEOUT_KILL_GRACE_SECONDS:-10}
step_absolute_timeout_seconds=${SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS:-2400}
step_output_probe_ticks=${SWIFTTUI_TEST_STEP_OUTPUT_PROBE_TICKS:-25}
step_busy_grace_seconds=${SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS:-300}
step_busy_min_cpu_percent=${SWIFTTUI_TEST_STEP_BUSY_MIN_CPU_PERCENT:-25}
step_watchdog_deadline_seconds=${SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS:-0}
. "$repo_root/Scripts/lib/step_watchdog.sh"
validate_timeout_configuration

runtime_shard_manifest=$repo_root/Scripts/data/runtime-shards.txt
. "$repo_root/Scripts/lib/runtime_shards.sh"

# The load-flaky run-loop suites (flake #1's usual homes) plus the
# high-contention async suites the debug gate also isolates. Both sets run
# only in --flaky-only, the signal-only step; the parts skip them.
FLAKY_SUITES="InteractiveRuntimeTests PortalPrimitiveTests ActorIsolationSurfaceTests"
ISOLATED_ASYNC_SUITES="AsyncLifecycleGenerationTests AsyncFrameTailRenderingTests TaskReadsUnbodiedStateTests"

usage_error() {
  >&2 echo "$1"
  >&2 echo "usage: Scripts/release_soundness_lane.sh [--dry-run] [--part core|<shard> | --flaky-only | --race-checks]"
  exit 2
}

mode=""
part=""
dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run)
    dry_run=1
    ;;
  --part)
    [ "$#" -ge 2 ] || usage_error "--part requires a value (core or a shard id)"
    [ -z "$mode" ] || usage_error "only one mode may be given"
    mode=--part
    part=$2
    shift
    ;;
  --part=*)
    [ -z "$mode" ] || usage_error "only one mode may be given"
    mode=--part
    part=${1#--part=}
    ;;
  --flaky-only | --race-checks)
    [ -z "$mode" ] || usage_error "only one mode may be given"
    mode=$1
    ;;
  *)
    usage_error "unknown argument: $1"
    ;;
  esac
  shift
done

case "$mode" in
"") mode_slug=default ;;
--flaky-only) mode_slug=flaky-only ;;
--race-checks) mode_slug=race-checks ;;
--part)
  if [ "$part" != core ] && [ -z "$(manifest_shard_regex "$part")" ]; then
    usage_error "unknown part: $part (expected core or one of: $(manifest_shard_ids | tr '\n' ' '))"
  fi
  mode_slug=part-$part
  ;;
esac
mode_label=${mode:-default}
if [ "$mode" = --part ]; then
  mode_label="--part $part"
fi

soundness_trace_root=${SWIFTTUI_SOUNDNESS_TRACE_ROOT:-"$repo_root/.build/soundness-trace/release-$mode_slug"}
lane_log_root=${SWIFTTUI_RELEASE_LANE_LOG_ROOT:-"$repo_root/.build/release-soundness-logs/$mode_slug"}
if [ "$dry_run" -eq 0 ]; then
  for root in "$soundness_trace_root" "$lane_log_root"; do
    if [ -d "$root" ]; then
      find "$root" -type f -name '*.log' -delete
    fi
    mkdir -p "$root"
  done
fi
release_test_index=0
last_launch_log=""

# `swift test -c release` compiles with testability on (its
# `--enable-testable-imports` default), which every `@testable import` in the
# test targets needs; `swift build` has no such switch and in release leaves it
# off, so the build carries `-enable-testing` itself. The lane has therefore
# always run release-with-testability; only the spelling moved.
release_build() {
  echo "==> $SWIFT build -c release --build-tests -Xswiftc -enable-testing $*"
  if [ "$dry_run" -eq 1 ]; then
    return 0
  fi
  # shellcheck disable=SC2086
  $SWIFT build -c release --build-tests -Xswiftc -enable-testing "$@"
}

# One `swift test` launch under the watchdog. The trace file is created up
# front, as the gate does, so a launch that records no violation still leaves
# a file for the merged scan's artifact to carry.
release_test() {
  release_test_index=$((release_test_index + 1))
  SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE=$soundness_trace_root/invocation-$release_test_index.log
  export SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE
  last_launch_log=$lane_log_root/invocation-$release_test_index.log
  status_file=$lane_log_root/invocation-$release_test_index.status
  timeout_file=$lane_log_root/invocation-$release_test_index.timeout
  echo "==> $SWIFT test -c release --skip-build $*"
  if [ "$dry_run" -eq 1 ]; then
    return 0
  fi
  : >"$SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE"
  # shellcheck disable=SC2086
  if run_logged_command "$last_launch_log" "$status_file" "$timeout_file" \
    $SWIFT test -c release --skip-build "$@"; then
    rm -f "$status_file" "$timeout_file"
    return 0
  fi
  exit_code=$(read_step_exit_code "$status_file")
  if [ -f "$timeout_file" ]; then
    >&2 echo "TIMEOUT: swift test $* ($(cat "$timeout_file"))"
  else
    >&2 echo "FAIL: swift test $* (exit $exit_code)"
  fi
  rm -f "$status_file" "$timeout_file"
  exit 1
}

# A serialized launch, and the assertion that it WAS serialized. `--no-parallel`
# is the only spelling that serializes swift-testing: bare `--num-workers 1`
# failed SwiftPM argument validation (this lane's flaky arm died 130 ms in from
# 2026-07-03 to 2026-07-07 while its continue-on-error step reported green), and
# `--parallel --num-workers 1` validated but bounds only XCTest worker
# processes — swift-testing kept its own in-process concurrency, measured at
# peak 1645 tests in flight (flake register entry 14). A green launch cannot
# tell "serialized" from "flag ignored", so the shape is measured from the log.
release_test_serialized() {
  release_test "$@" --no-parallel
  if [ "$dry_run" -eq 1 ]; then
    return 0
  fi
  Scripts/check_serialized_execution.sh "$last_launch_log"
}

is_flaky_only_suite() {
  for candidate in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES; do
    if [ "$candidate" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

run_part_core() {
  release_test --filter SwiftTUICoreTests
  # The manifest's isolated suites, each in its own serialized launch, as the
  # gate's core lane runs them. PerTickPresentCadenceTests deliberately
  # suppresses trace emission across awaits while it proves the
  # completed-frame disposal arm: that process-global window must stay out of
  # any broad process so unrelated violations cannot be hidden. The
  # --flaky-only step owns the rest of the isolated set.
  for suite in $(manifest_isolated_suites); do
    if is_flaky_only_suite "$suite"; then
      continue
    fi
    release_test_serialized --filter "SwiftTUITests.$suite"
  done
}

# Regex characters must not be glob-expanded while the manifest lines are
# re-split into arguments, hence the `set -f` bracket.
run_part_shard() {
  shard=$1
  set -f
  # shellcheck disable=SC2046
  set -- $(runtime_shard_test_args "$shard")
  set +f
  for suite in $FLAKY_SUITES; do
    set -- "$@" --skip "SwiftTUITests.$suite"
  done
  release_test_serialized "$@"
}

case "$mode" in
--flaky-only)
  release_build
  # Flake #1's prescribed dynamic pursuit (swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md): all
  # statically identified corruptor candidates are resolved (release-checked
  # or deleted outright), so if the corruption ever recurs the lead is heap
  # misuse, not an isolation race. glibc allocator guards make that trap
  # near the corruption site instead of surfacing as anonymous torn bytes:
  # MALLOC_CHECK_=3 aborts on detected heap misuse, MALLOC_PERTURB_ poisons
  # freed memory. Inert on macOS (glibc-only), active on the Linux soak.
  # Exported after the build so the compiler does not run under them.
  MALLOC_CHECK_=3 && export MALLOC_CHECK_
  MALLOC_PERTURB_=165 && export MALLOC_PERTURB_
  for suite in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES; do
    release_test_serialized --filter "SwiftTUITests.$suite"
  done
  ;;
--race-checks)
  # The flag rides on the build only: `--skip-build` runs the binaries that
  # build produced, and SwiftPM keys the build signature on the flag, so a
  # plain release build in the same tree is recompiled rather than reused.
  release_build -Xswiftc -enable-actor-data-race-checks
  release_test_serialized \
    --filter 'SwiftTUITests.(FrameworkStressTests|BoundedReconciliationTests|DirtyTrackingCoherenceTests|RetainedSubtreeReuseTests|RuntimeRenderPipelineTests|PipelineContractTests)'
  ;;
--part)
  release_build
  if [ "$part" = core ]; then
    run_part_core
  else
    run_part_shard "$part"
  fi
  ;;
"")
  release_build
  run_part_core
  for shard in $(manifest_shard_ids); do
    run_part_shard "$shard"
  done
  ;;
esac

if [ "$dry_run" -eq 0 ]; then
  Scripts/scan_soundness_traces.sh \
    "$soundness_trace_root" \
    Scripts/soundness_quarantine.txt
fi

echo "release soundness lane ($mode_label) passed"

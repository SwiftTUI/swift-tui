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
# Not part of the push/PR gate: scheduled + dispatch via
# .github/workflows/release-soundness.yml.
#
# Modes:
#   (default)        core + runtime suites, minus the load-flaky run-loop
#                    suites documented in docs/KNOWN-TEST-FLAKES.md
#   --flaky-only     ONLY those load-flaky suites, serialized. Run from a
#                    continue-on-error step: a SIGSEGV here is flake #1
#                    (swift-tui#12) signal, and in release the checked
#                    isolation traps can convert it into an attributable
#                    preconditionIsolated failure.
#   --race-checks    stress + reconciliation subset rebuilt with
#                    -enable-actor-data-race-checks

set -eu

cd "$(dirname "$0")/.."

SWIFT="swift"
if command -v swiftly >/dev/null 2>&1; then
  SWIFT="swiftly run swift"
fi

SWIFTTUI_SOUNDNESS_PROBE=1 && export SWIFTTUI_SOUNDNESS_PROBE
SWIFTTUI_SOUNDNESS_PROBE_SAMPLE=1 && export SWIFTTUI_SOUNDNESS_PROBE_SAMPLE
SWIFTTUI_SOUNDNESS_PROBE_TRACE=1 && export SWIFTTUI_SOUNDNESS_PROBE_TRACE

mode="${1:-}"
case "$mode" in
"") mode_slug=default ;;
--flaky-only) mode_slug=flaky-only ;;
--race-checks) mode_slug=race-checks ;;
*)
  echo "unknown mode: $mode (expected --flaky-only, --race-checks, or none)" >&2
  exit 2
  ;;
esac

soundness_trace_root=${SWIFTTUI_SOUNDNESS_TRACE_ROOT:-".build/soundness-trace/release-$mode_slug"}
if [ -d "$soundness_trace_root" ]; then
  find "$soundness_trace_root" -type f -name '*.log' -delete
fi
mkdir -p "$soundness_trace_root"
release_test_index=0

# The load-flaky run-loop suites (flake #1's usual homes) plus the
# high-contention async suites the debug gate also isolates.
FLAKY_SUITES="InteractiveRuntimeTests PortalPrimitiveTests ActorIsolationSurfaceTests"
ISOLATED_ASYNC_SUITES="AsyncLifecycleGenerationTests AsyncFrameTailRenderingTests TaskReadsUnbodiedStateTests"
# This suite deliberately suppresses trace emission across awaits while it
# proves the completed-frame disposal arm. Keep that process-global window out
# of the broad release process so unrelated violations cannot be hidden.
TRACE_SUPPRESSION_SUITES="PerTickPresentCadenceTests"

release_test() {
  release_test_index=$((release_test_index + 1))
  SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE=$soundness_trace_root/invocation-$release_test_index.log
  export SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE
  echo "==> $SWIFT test -c release $*"
  # shellcheck disable=SC2086
  $SWIFT test -c release "$@"
}

case "$mode" in
  --flaky-only)
    # Flake #1's prescribed dynamic pursuit (docs/KNOWN-TEST-FLAKES.md): all
    # statically identified corruptor candidates are resolved (release-checked
    # or deleted outright), so if the corruption ever recurs the lead is heap
    # misuse, not an isolation race. glibc allocator guards make that trap
    # near the corruption site instead of surfacing as anonymous torn bytes:
    # MALLOC_CHECK_=3 aborts on detected heap misuse, MALLOC_PERTURB_ poisons
    # freed memory. Inert on macOS (glibc-only), active on the Linux soak.
    MALLOC_CHECK_=3 && export MALLOC_CHECK_
    MALLOC_PERTURB_=165 && export MALLOC_PERTURB_
    # `--num-workers` requires `--parallel` (SwiftPM rejects it bare — this
    # arm was dying on that arg error 130 ms in from 2026-07-03 to
    # 2026-07-07 while the continue-on-error step reported green; one
    # parallel worker = the intended serialized run).
    for suite in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES; do
      release_test --filter "SwiftTUITests.$suite" --parallel --num-workers 1
    done
    ;;
  --race-checks)
    release_test \
      -Xswiftc -enable-actor-data-race-checks \
      --filter 'SwiftTUITests.(FrameworkStressTests|BoundedReconciliationTests|DirtyTrackingCoherenceTests|RetainedSubtreeReuseTests|RuntimeRenderPipelineTests|PipelineContractTests)'
    ;;
  "")
    release_test --filter SwiftTUICoreTests
    skip_args=""
    for suite in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES $TRACE_SUPPRESSION_SUITES; do
      skip_args="$skip_args --skip SwiftTUITests.$suite"
    done
    # shellcheck disable=SC2086
    release_test --filter SwiftTUITests $skip_args
    for suite in $TRACE_SUPPRESSION_SUITES; do
      release_test --filter "SwiftTUITests.$suite" --parallel --num-workers 1
    done
    ;;
  *)
    echo "unknown mode: $mode (expected --flaky-only, --race-checks, or none)" >&2
    exit 2
    ;;
esac

Scripts/scan_soundness_traces.sh \
  "$soundness_trace_root" \
  Scripts/soundness_quarantine.txt

echo "release soundness lane (${mode:-default}) passed"

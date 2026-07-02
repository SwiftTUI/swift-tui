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

# The load-flaky run-loop suites (flake #1's usual homes) plus the
# high-contention async suites the debug gate also isolates.
FLAKY_SUITES="InteractiveRuntimeTests PortalPrimitiveTests ActorIsolationSurfaceTests"
ISOLATED_ASYNC_SUITES="AsyncLifecycleGenerationTests AsyncFrameTailRenderingTests TaskReadsUnbodiedStateTests"

release_test() {
  echo "==> $SWIFT test -c release $*"
  # shellcheck disable=SC2086
  $SWIFT test -c release "$@"
}

mode="${1:-}"

case "$mode" in
  --flaky-only)
    for suite in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES; do
      release_test --filter "SwiftTUITests.$suite" --num-workers 1
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
    for suite in $FLAKY_SUITES $ISOLATED_ASYNC_SUITES; do
      skip_args="$skip_args --skip SwiftTUITests.$suite"
    done
    # shellcheck disable=SC2086
    release_test --filter SwiftTUITests $skip_args
    ;;
  *)
    echo "unknown mode: $mode (expected --flaky-only, --race-checks, or none)" >&2
    exit 2
    ;;
esac

echo "release soundness lane (${mode:-default}) passed"

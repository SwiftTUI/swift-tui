#!/bin/sh
set -eu

mkdir -p .perf/runs

output_file="${TMPDIR:-/tmp}/termui-perf-smoke-$$.log"
rm -f "$output_file"

swiftly run swift run --package-path Tools/TermUIPerf -c release termui-perf run \
  --scenario gallery-animation-click \
  --modes sync,async \
  --iterations 1 \
  --configuration release | tee "$output_file"

run_dirs="$(awk '/\/.perf\/runs\// || /^\.perf\/runs\// { print }' "$output_file")"
base_run="$(printf '%s\n' "$run_dirs" | sed -n '1p')"
candidate_run="$(printf '%s\n' "$run_dirs" | sed -n '2p')"

if [ -n "$base_run" ] && [ -n "$candidate_run" ]; then
  swiftly run swift run --package-path Tools/TermUIPerf -c release termui-perf compare \
    "$base_run" \
    "$candidate_run" | tee .perf/runs/latest-compare.txt
else
  echo "warning: expected two run directories for sync/async comparison" >&2
fi

# ---------------------------------------------------------------------------
# Scroll family — advisory only.
#
# Pre-0.9.0 there is no CI-blocking perf gate, and a shared GitHub runner is
# nowhere near quiet enough to gate scroll latency on anyway. This lane exists
# so artifacts accumulate: a per-scenario run directory with frames.tsv,
# presents.tsv and summary.json, uploaded and kept. Nothing here fails the job.
#
# Failures are still REPORTED, loudly and into an uploaded file. Suppressing a
# lane's exit status is how a broken invocation stays green for weeks — this
# repo has already paid for that once, with a `continue-on-error` that hid an
# argument error rather than a perf result. A scenario that cannot even start
# must be visible in the artifact.
#
# The collection probes are armed so the accumulated artifacts carry
# `realized_rows` / `list_layout_derivations` beside their milliseconds.
# ---------------------------------------------------------------------------
scroll_status_file=".perf/runs/scroll-advisory-status.txt"
: > "$scroll_status_file"

for scenario in \
  scroll-notch-latency \
  scroll-cadence-60hz \
  scroll-fling-momentum \
  scroll-jump \
  scroll-document-mixed
do
  if SWIFTTUI_COLLECTION_PROBES=1 swiftly run swift run \
    --package-path Tools/TermUIPerf -c release termui-perf run \
    --scenario "$scenario" \
    --iterations 1 \
    --artifacts-root ".perf/runs/scroll-advisory/$scenario" \
    --configuration release
  then
    echo "ok: $scenario" >> "$scroll_status_file"
  else
    status=$?
    echo "warning: advisory scroll scenario '$scenario' exited $status" >&2
    echo "FAILED($status): $scenario" >> "$scroll_status_file"
  fi
done

echo "--- advisory scroll lane ---"
cat "$scroll_status_file"

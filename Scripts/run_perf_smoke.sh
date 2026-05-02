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

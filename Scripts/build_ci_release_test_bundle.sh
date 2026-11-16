#!/usr/bin/env bash
# Build the Release Soundness Lane's test bundle once per workflow run, and
# keep a memory record of that build.
#
# The build itself is Scripts/release_soundness_lane.sh --build-only, so its
# flags stay spelled in one file. This wrapper adds the record, because a
# compiler process the kernel kills leaves no diagnostic of its own. Until
# SwiftTUITests was compiled per file, its one whole-module process was
# killed that way, and SwiftDriver reported only that its `-primary.d` output
# was missing. The record states what the processes and the runner were doing:
# the largest compiler resident set, the container's peak memory, the
# runner's lowest available memory and swap, and the count of processes in
# this container that an out-of-memory killer ended (STUI-1539;
# swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md entry 26).
#
# The record never changes the verdict. The build's own exit status is this
# script's exit status.
set -euo pipefail
cd "$(dirname "$0")/.."

record_root=${SWIFTTUI_RELEASE_BUILD_RECORD_ROOT:-.build/ci-release-build}
sample_interval_seconds=${SWIFTTUI_RELEASE_BUILD_SAMPLE_SECONDS:-10}
samples=$record_root/memory-samples.tsv
summary=$record_root/memory-summary.txt
mkdir -p "$record_root"
: >"$samples"

# cgroup v2 counts every process of this container that any out-of-memory
# killer ended, the host's included. Absent (cgroup v1, macOS) reads as unknown.
oom_kill_count() {
  if [ -r /sys/fs/cgroup/memory.events ]; then
    awk '$1 == "oom_kill" { print $2; found = 1 } END { if (!found) print "unknown" }' \
      /sys/fs/cgroup/memory.events
  else
    echo unknown
  fi
}

meminfo_kib() {
  awk -v key="$1:" '$1 == key { print $2; found = 1 } END { if (!found) print 0 }' /proc/meminfo
}

# One row: epoch, MemAvailable, SwapFree, then the resident set and module of
# the largest swift-frontend process (0 and `-` when none runs).
record_sample() {
  largest=$(ps -eo rss=,args= --sort=-rss 2>/dev/null |
    awk '$2 ~ /swift-frontend$/ {
      module = "-"
      for (i = 3; i < NF; i++) if ($i == "-module-name") module = $(i + 1)
      print $1 "\t" module
      exit
    }')
  if [ -z "$largest" ]; then
    largest=$(printf '0\t-')
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$(meminfo_kib MemAvailable)" "$(meminfo_kib SwapFree)" \
    "$largest" >>"$samples"
}

sample_memory() {
  while :; do
    sleep "$sample_interval_seconds"
    record_sample
  done
}

# The first row is taken before the build starts, so a build that ends inside
# one interval still leaves the runner's starting state on record.
sampler_pid=""
oom_kills_before=$(oom_kill_count)
if [ -r /proc/meminfo ]; then
  record_sample
  sample_memory &
  sampler_pid=$!
fi

status=0
sh ./Scripts/release_soundness_lane.sh --build-only || status=$?

if [ -n "$sampler_pid" ]; then
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
fi
oom_kills_after=$(oom_kill_count)

{
  echo "release test bundle build: exit $status"
  if [ -s "$samples" ]; then
    awk -F '\t' \
      -v total="$(meminfo_kib MemTotal)" -v swap="$(meminfo_kib SwapTotal)" '
      NR == 1 || $2 < least_available { least_available = $2 }
      NR == 1 || $3 < least_swap { least_swap = $3 }
      NR == 1 || $4 > peak { peak = $4; peak_module = $5 }
      END {
        printf "runner memory: %.1f GiB, swap %.1f GiB\n", total / 1048576, swap / 1048576
        printf "largest compiler resident set: %.1f GiB (%s)\n", peak / 1048576, peak_module
        printf "lowest available memory: %.1f GiB\n", least_available / 1048576
        printf "lowest free swap: %.1f GiB\n", least_swap / 1048576
        printf "samples: %d\n", NR
      }' "$samples"
  else
    echo "no memory samples (no /proc/meminfo on this host)"
  fi
  # Cumulative for the container, so earlier steps of the job are included.
  if [ -r /sys/fs/cgroup/memory.peak ]; then
    awk '{ printf "container peak memory: %.1f GiB\n", $1 / 1073741824 }' /sys/fs/cgroup/memory.peak
  fi
  if [ "$oom_kills_before" = unknown ] || [ "$oom_kills_after" = unknown ]; then
    echo "out-of-memory kills in this container: unknown (no cgroup v2 memory.events)"
  else
    echo "out-of-memory kills in this container: $((oom_kills_after - oom_kills_before))"
  fi
} | tee "$summary"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Release test bundle build"
    echo
    echo '```'
    cat "$summary"
    echo '```'
  } >>"$GITHUB_STEP_SUMMARY"
fi

exit "$status"

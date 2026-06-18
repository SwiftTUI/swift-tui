#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

iterations=${STUI_ASYNC_FLAKE_ITERATIONS:-2}
load_workers=${STUI_ASYNC_FLAKE_LOAD_WORKERS:-0}
output_root=${STUI_ASYNC_FLAKE_OUTPUT_ROOT:-/tmp}
allow_failures=0

usage() {
  cat <<'EOF'
Usage: Scripts/repeat_async_flake_registry.sh [options]

Runs the current async/runtime flake registry repeatedly and stores logs under
/tmp by default.

Options:
  --iterations N       Number of repetitions per candidate (default: 2)
  --load-workers N     Busy-loop CPU workers while tests run (default: 0)
  --output-root PATH   Directory that receives the retained run folder
  --allow-failures     Exit 0 after writing counts even when candidates fail
  -h, --help           Show this help

Environment:
  STUI_ASYNC_FLAKE_ITERATIONS
  STUI_ASYNC_FLAKE_LOAD_WORKERS
  STUI_ASYNC_FLAKE_OUTPUT_ROOT
  SWIFTTUI_TEST_TIMEOUT_SCALE
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --iterations)
    iterations=$2
    shift 2
    ;;
  --iterations=*)
    iterations=${1#--iterations=}
    shift
    ;;
  --load-workers)
    load_workers=$2
    shift 2
    ;;
  --load-workers=*)
    load_workers=${1#--load-workers=}
    shift
    ;;
  --output-root)
    output_root=$2
    shift 2
    ;;
  --output-root=*)
    output_root=${1#--output-root=}
    shift
    ;;
  --allow-failures)
    allow_failures=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $1"
    >&2 echo ""
    usage >&2
    exit 1
    ;;
  esac
done

case "$iterations" in
'' | *[!0-9]*)
  >&2 echo "--iterations must be a positive integer"
  exit 1
  ;;
esac

case "$load_workers" in
'' | *[!0-9]*)
  >&2 echo "--load-workers must be a non-negative integer"
  exit 1
  ;;
esac

if [ "$iterations" -lt 1 ]; then
  >&2 echo "--iterations must be at least 1"
  exit 1
fi

if ! command -v swiftly >/dev/null 2>&1; then
  >&2 echo "Missing required command: swiftly"
  exit 1
fi

timestamp=$(date '+%Y%m%d-%H%M%S')
run_root="$output_root/swift-tui-async-flake-registry-$timestamp-$$"
mkdir -p "$run_root"

results_file="$run_root/results.tsv"
summary_file="$run_root/summary.tsv"

printf 'candidate\tcategory\titeration\tstatus\texit_code\tlog_file\towner\tremediation\tcommand\n' \
  >"$results_file"

load_pids=""

stop_load() {
  for pid in $load_pids; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}

cleanup() {
  stop_load
}

trap cleanup EXIT INT TERM

start_load() {
  i=0
  while [ "$i" -lt "$load_workers" ]; do
    (
      while :; do
        :
      done
    ) >/dev/null 2>&1 &
    load_pids="$load_pids $!"
    i=$((i + 1))
  done
}

should_skip_candidate() {
  candidate=$1
  return 1
}

run_candidate() {
  candidate=$1
  category=$2
  owner=$3
  remediation=$4
  command=$5

  iteration=1
  while [ "$iteration" -le "$iterations" ]; do
    log_file="$run_root/${candidate}-${iteration}.log"
    if should_skip_candidate "$candidate"; then
      printf '%s\t%s\t%s\tSKIP\t-\t%s\t%s\t%s\t%s\n' \
        "$candidate" "$category" "$iteration" "$log_file" "$owner" "$remediation" "$command" \
        >>"$results_file"
    elif (
      cd "$repo_root"
      sh -c "$command"
    ) >"$log_file" 2>&1; then
      printf '%s\t%s\t%s\tPASS\t0\t%s\t%s\t%s\t%s\n' \
        "$candidate" "$category" "$iteration" "$log_file" "$owner" "$remediation" "$command" \
        >>"$results_file"
    else
      exit_code=$?
      printf '%s\t%s\t%s\tFAIL\t%s\t%s\t%s\t%s\t%s\n' \
        "$candidate" "$category" "$iteration" "$exit_code" "$log_file" "$owner" "$remediation" \
        "$command" >>"$results_file"
    fi
    iteration=$((iteration + 1))
  done
}

if [ "$load_workers" -gt 0 ]; then
  start_load
fi

run_candidate \
  "InteractiveRuntimeTests.toastAutoDismissRerendersWithoutAdditionalInput" \
  "async/runtime-adjacent" \
  "runtime test support" \
  "Scripts/repeat_async_flake_registry.sh" \
  "swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput"

run_candidate \
  "AsyncFrameTailRenderingTests" \
  "async renderer/runtime" \
  "runtime test support" \
  "Scripts/repeat_async_flake_registry.sh" \
  "swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests"

run_candidate \
  "RenderDiffTests" \
  "process/presentation integration and wall-clock sensitivity" \
  "terminal embedding test support" \
  "Scripts/repeat_async_flake_registry.sh" \
  "swiftly run swift test --filter SwiftTUITerminalTests.RenderDiffTests"

unsorted_summary_file="$run_root/summary.unsorted.tsv"
awk -F '\t' '
  NR == 1 { next }
  {
    total[$1] += 1
    category[$1] = $2
    if ($4 == "PASS") pass[$1] += 1
    if ($4 == "FAIL") fail[$1] += 1
    if ($4 == "SKIP") skip[$1] += 1
  }
  END {
    print "candidate\tcategory\tpass\tfail\tskip\ttotal"
    for (candidate in total) {
      printf "%s\t%s\t%d\t%d\t%d\t%d\n",
        candidate, category[candidate], pass[candidate] + 0,
        fail[candidate] + 0, skip[candidate] + 0, total[candidate]
    }
  }
' "$results_file" >"$unsorted_summary_file"

{
  head -n 1 "$unsorted_summary_file"
  tail -n +2 "$unsorted_summary_file" | sort
} >"$summary_file"
rm -f "$unsorted_summary_file"

cat "$summary_file"
echo "Results: $results_file"
echo "Logs: $run_root"

if awk -F '\t' 'NR > 1 && $4 == "FAIL" { found = 1 } END { exit found ? 0 : 1 }' \
  "$results_file"; then
  [ "$allow_failures" -eq 1 ] && exit 0
  exit 1
fi

exit 0

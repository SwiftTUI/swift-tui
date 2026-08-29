#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

runner_name=${SWIFTTUI_TEST_RUNNER_NAME:-test-all}
# The per-step watchdog measures *silence*, not wall clock. A fixed wall-clock
# cap cannot tell a lane that parked from one that is merely running 5x slower
# under contention, so it kills both — which is how the largest lane
# (`Run SwiftTUI runtime tests`, ~221 s solo) turned red on loaded runners while
# passing everywhere else. Silence separates the two: a live lane keeps emitting
# per-test output, a parked one emits nothing. See KNOWN-TEST-FLAKES.md entry 9.
step_timeout_seconds=${SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS:-1200}
step_timeout_kill_grace_seconds=${SWIFTTUI_TEST_TIMEOUT_KILL_GRACE_SECONDS:-10}
# Backstop for the one case silence cannot catch: a step that livelocks *while*
# printing. Defaults to 4x the idle bound; 0 disables it.
step_absolute_timeout_seconds=${SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS:-$((step_timeout_seconds * 4))}
# How often the watchdog samples the step's log size and clock. Sampling every
# tick would stat a multi-megabyte log five times a second for no added
# resolution.
step_output_probe_ticks=${SWIFTTUI_TEST_STEP_OUTPUT_PROBE_TICKS:-25}
# Total quiet-but-busy time the watchdog forgives across one step. Silence alone
# does not mean parked: `swift test` writes to a pipe, so libc block-buffers it
# and a healthy binary is quiet until its buffer fills (measured at 274 s on a
# CI runner). A wedge consumes no CPU, so it still dies at the first idle bound.
#
# Spelled in SECONDS on purpose. This was a count of forgiven windows, each
# costing another whole idle bound, so the real worst case was
# `(1 + count) * bound` — 4800 s at this file's defaults, past every job cap the
# gate runs under. Worst-case kill is now just `bound + grace + kill grace`.
step_busy_grace_seconds=${SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS:-$((step_timeout_seconds / 2))}
# Average CPU across the silent window that counts as "working". A bare
# "consumed any CPU at all" test is tripped by a parked tree's signal and timer
# wakeups; the shapes this has to separate measured 0% and 107%.
step_busy_min_cpu_percent=${SWIFTTUI_TEST_STEP_BUSY_MIN_CPU_PERCENT:-25}
# This job's own wall-clock cap, when it has one (CI sets it from the workflow's
# `timeout-minutes`). The watchdog refuses to start if it could not fire inside
# it, because a job that dies at its cap leaves no TIMEOUT line and no dump.
step_watchdog_deadline_seconds=${SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS:-0}

if [ -n "${SWIFTTUI_TEST_STEP_BUSY_EXTENSIONS:-}" ]; then
  >&2 echo "SWIFTTUI_TEST_STEP_BUSY_EXTENSIONS was replaced by"
  >&2 echo "SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS, which is a budget in seconds rather"
  >&2 echo "than a count of idle windows. Setting the old name has no effect; unset it"
  >&2 echo "and set the new one so the worst-case kill time stays visible."
  exit 1
fi
soundness_trace_root=$repo_root/.build/soundness-trace
soundness_quarantine_file=$repo_root/Scripts/soundness_quarantine.txt
soundness_trace_invocation_index=0
# Lane selection (plan 2026-08-25-001 Stage 1a). `all` is the local gate and
# the historical single-job shape; `policy`, `core`, and `runtime:<shard>` are
# the CI jobs that together cover exactly the same surface. The runtime
# shards are defined in ONE file so the shard launches, the isolated-suite
# skip list, and the coverage check cannot drift apart.
runtime_shard_manifest=$repo_root/Scripts/data/runtime-shards.txt
lane=all
runtime_shard=""
# Every Swift lane builds with `-emit-loaded-module-trace` so the Foundation
# audit reads the core lane's own build (Stage 1c) instead of compiling
# Core+Views a second time. The flag rides on EVERY swift build/test
# invocation of every lane, including the runtime shards that never read the
# traces: SwiftPM treats compiler flags as part of the build signature, so a
# flagged build followed by one unflagged `swift test` — or two lanes run
# back to back on one machine with different flags — recompiles the whole
# module graph, the exact cost the trace reuse exists to remove.
emit_module_trace=0

write_full_log_report() {
  body_log=$1
  results_report=$2
  full_log_path=$3
  command_text=$4
  exit_code=$5

  generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  marker_file=$(mktemp "/tmp/swift-tui-$runner_name-markers.XXXXXX")

  awk '
    /^==> / {
      title = substr($0, 5)
      if (!(title in seen)) {
        seen[title] = 1
        print title "|" NR
      }
    }
  ' "$body_log" >"$marker_file"

  result_count=$(awk 'END { print NR + 0 }' "$results_report" 2>/dev/null || echo 0)
  failure_count=$(awk -F '|' '$2 == "FAIL" || $2 == "TIMEOUT" { count += 1 } END { print count + 0 }' \
    "$results_report" 2>/dev/null || echo 0)
  line_offset=$((6 + result_count + failure_count + 2))

  {
    echo "swift-tui test log"
    echo "Generated: $generated_at"
    echo "Command: $command_text"
    echo "Exit status: $exit_code"
    echo ""
    echo "Sub-suite summary:"

    while IFS='|' read -r title status step_exit step_failures rerun_command log_file detail; do
      body_line=$(awk -F '|' -v title="$title" '$1 == title { print $2; exit }' "$marker_file")
      if [ -n "$body_line" ]; then
        report_line=$((line_offset + body_line))
      else
        report_line="?"
      fi

      printf '  %-4s  exit=%-3s  failures=%-3s  log=line %-5s  %s' \
        "$status" "$step_exit" "$step_failures" "$report_line" "$title"
      if [ "$status" = "SKIP" ] && [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      if [ "$status" = "TIMEOUT" ] && [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'

      if [ "$status" = "FAIL" ] || [ "$status" = "TIMEOUT" ]; then
        printf '        rerun: %s\n' "$rerun_command"
      fi
    done <"$results_report"

    echo ""
    echo "Raw run log:"
    cat "$body_log"
  } >"$full_log_path"

  rm -f "$marker_file"
}

if [ "${SWIFTTUI_TEST_ALL_CAPTURED:-0}" != "1" ]; then
  timestamp=$(date '+%Y%m%d-%H%M%S')
  full_log_path="/tmp/swift-tui-$runner_name-$timestamp-$$.log"
  body_log=$(mktemp "/tmp/swift-tui-$runner_name-body.XXXXXX")
  status_file=$(mktemp "/tmp/swift-tui-$runner_name-status.XXXXXX")
  results_report=$(mktemp "/tmp/swift-tui-$runner_name-results.XXXXXX")
  if [ -n "${SWIFTTUI_TEST_COMMAND_TEXT:-}" ]; then
    command_text=$SWIFTTUI_TEST_COMMAND_TEXT
  else
    command_text="sh $0"

    for argument; do
      command_text="$command_text $argument"
    done
  fi

  cleanup_capture() {
    rm -f "$body_log" "$status_file" "$results_report"
  }

  trap cleanup_capture EXIT

  : >"$full_log_path"
  : >"$results_report"

  export SWIFTTUI_TEST_ALL_CAPTURED=1
  export SWIFTTUI_TEST_ALL_FINAL_LOG=$full_log_path
  export SWIFTTUI_TEST_ALL_RESULTS_REPORT=$results_report

  (
    set +e
    sh "$0" "$@"
    child_status=$?
    printf '%s\n' "$child_status" >"$status_file"
  ) 2>&1 | tee "$body_log"

  if [ -f "$status_file" ]; then
    captured_status=$(cat "$status_file")
  else
    captured_status=1
  fi

  write_full_log_report \
    "$body_log" \
    "$results_report" \
    "$full_log_path" \
    "$command_text" \
    "$captured_status"

  exit "$captured_status"
fi

skip_bun_install=0
clean_builds=0
host_os=$(uname -s)
is_linux=0
step_index=0

for name in \
  PARALLEL_RECORD_RENDERED_FIXTURES \
  SWIFTTUI_REGENERATE_CONFORMANCE_FIXTURES \
  SWIFTTUI_RECORD_RENDERED_TEXT_FIXTURES \
  SWIFTTUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT; do
  eval "is_set=\${$name+x}"
  if [ -n "$is_set" ]; then
    >&2 echo "$name must not be set when running the repo gate."
    >&2 echo "Use the fixture recorder named in swift-tui-org/docs/swift-tui/DEVELOPMENT.md."
    exit 1
  fi
done

tmp_root=${TMPDIR:-/tmp}
log_root=$(mktemp -d "$tmp_root/swift-tui-test-all.XXXXXX")
results_file=$log_root/results.txt
any_failed=0

: >"$results_file"

cleanup() {
  if [ -n "${SWIFTTUI_TEST_ALL_RESULTS_REPORT:-}" ] && [ -f "$results_file" ]; then
    cp "$results_file" "$SWIFTTUI_TEST_ALL_RESULTS_REPORT" || true
  fi
  rm -rf "$log_root"
}

trap cleanup EXIT

if [ "$host_os" = "Linux" ]; then
  is_linux=1
  export DISABLE_EXPLICIT_PLATFORMS=1
fi

# Compiler warnings fail the gate. The Package.swift setting behind this is
# opt-in rather than unconditional because `.treatAllWarnings(as: .error)` is
# NOT stripped for `path:` dependencies, so an unconditional setting would turn
# swift-tui warnings into hard failures inside overlay and Xcode local-package
# builds that consume this repo. See the comment on `warningsAsErrors` in
# Package.swift. The gate is where the policy is meant to bind, so it is turned
# on here for every SwiftPM step below.
export SWIFTTUI_WARNINGS_AS_ERRORS=1

usage() {
  cat <<'EOF'
Usage: Scripts/test_all.sh [--clean] [--skip-bun-install] [--lane <lane>]

Runs the exhaustive checked-in repo verification surface:
  - checked-in policy hooks
  - stable-doc source-path guardrails
  - explicit layout work-stack guardrails
  - per-step watchdog self-test
  - serialized-execution check for the runtime lane (plus its self-test)
  - per-test duration ratchet for the runtime shards (plus its self-test;
    SWIFTTUI_STRESS_FULL=1 runs the full churn-loop counts and skips it)
  - frame-tail tree-walker recursion guardrails (plus their self-test)
  - public DocC catalog and website build guardrails
  - root Package.swift test-target coverage guardrails
  - rendered-text fixture matrix guardrails
  - public-API baseline freshness check
  - focused root SwiftPM framework tests, with high-contention async runtime
    suites isolated from the broad SwiftTUI runtime step
  - focused SwiftTUIArguments tests
  - focused SwiftTUICLI tests
  - focused SwiftTUITerminal / PTY primitive tests
  - focused SwiftTUIWASI / SwiftTUIWASISurfaceBridge tests
  - focused SwiftTUIWebHost tests
  - focused SwiftTUIAndroidHost tests
  - Tools/TermUIPerf tests

The script also checks required environment dependencies up front:
  - Swift 6.3.x via `swiftly`
  - Bun availability
  - Bun workspace dependencies via `bun install --frozen-lockfile` at the repo root

On Linux, the script also:
  - exports `DISABLE_EXPLICIT_PLATFORMS=1` for repo package resolution

Pass --skip-bun-install to reuse the existing Bun install state.

Pass --lane to run one CI lane of the surface instead of all of it:
  all              every step below, in one process (the default; `bun run test`)
  policy           the toolchain-free policy phase, guardrails, and self-tests
  core             build once; every non-runtime test target in one parallel
                   launch; the isolated SwiftTUITests suites; entry-point
                   launch fixtures and tests
  runtime:<shard>  one serialized SwiftTUITests shard from
                   Scripts/data/runtime-shards.txt, plus its
                   serialized-execution check
The three CI lanes partition the `all` surface exactly; the soundness-trace
scan runs in `all` and, for CI, once over the merged traces of every lane
(.github/workflows/run-tests-linux.yml).

Pass --clean to delete every SwiftPM `.build` directory before any step
runs. The satellite packages reached via `--package-path` rebuild the repo's
module graph inside their own `.build`, and SwiftPM's incremental tracking
across that package boundary can leave a stale object linked against a
since-changed symbol. --clean trades a from-scratch rebuild for a run that
cannot be tripped by that staleness.

Each step is bounded by SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS, defaulting to 1200
seconds. This bounds SILENCE, not total runtime: the watchdog fires when a step
has produced no output for that long, so a lane running slowly under contention
is not killed like one that parked, while a genuinely wedged lane still dies.
Set it to 0 to disable the per-step watchdog for local diagnosis.
A step that is quiet but whose process tree still averages at least
SWIFTTUI_TEST_STEP_BUSY_MIN_CPU_PERCENT (default 25) of a core is treated as
working — the block-buffered-writer case — for up to
SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS (default: half the idle bound) in total.
The worst-case kill time is therefore the sum of those two plus
SWIFTTUI_TEST_TIMEOUT_KILL_GRACE_SECONDS, and setting
SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS to the job's own cap makes the
runner refuse to start if that sum could not fire inside it.
SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS (default: 4x the idle bound, 0 to
disable) is the backstop for a step that livelocks while still printing.
After a timeout, the runner sends SIGTERM to the step's process tree, waits
SWIFTTUI_TEST_TIMEOUT_KILL_GRACE_SECONDS seconds, then sends SIGKILL before
printing the captured log and failing the gate.

For the curated repo gate, use Scripts/test_gate.sh. That runner keeps the same
post-split non-example surface and writes a shorter test-gate log name.

Set SWIFTTUI_SKIP_PUBLIC_API_BASELINE=1 when the public API baseline is covered by
the separate CI workflow. Set SWIFTTUI_SKIP_TERMUIPERF=1 when Tools/TermUIPerf is
covered by its path-filtered or scheduled workflow.
EOF
}

record_result() {
  title=$1
  status=$2
  exit_code=$3
  failure_count=$4
  rerun_command=$5
  log_file=$6
  detail=$7

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$title" "$status" "$exit_code" "$failure_count" "$rerun_command" "$log_file" "$detail" \
    >>"$results_file"
}

. "$repo_root/Scripts/lib/step_watchdog.sh"

swift_command_text() {
  if [ "$is_linux" -eq 1 ]; then
    printf 'DISABLE_EXPLICIT_PLATFORMS=1 '
  fi

  printf 'swiftly run swift'

  for argument; do
    printf ' %s' "$argument"
  done

  if [ "$emit_module_trace" -eq 1 ] && [ "$#" -gt 0 ]; then
    case "$1" in
    build | test)
      printf ' -Xswiftc -emit-loaded-module-trace'
      ;;
    esac
  fi
}

soundness_trace_slug() {
  printf '%s' "$1" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//'
}

derive_failure_count() {
  log_file=$1

  if [ ! -f "$log_file" ]; then
    echo "?"
    return
  fi

  count=$(
    awk '
      function first_number(text) {
        if (match(text, /[0-9]+/)) {
          return substr(text, RSTART, RLENGTH)
        }
        return ""
      }

      {
        line = tolower($0)

        if (match(line, /[0-9]+[[:space:]]+tests?[[:space:]]+failed/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /with[[:space:]]+[0-9]+[[:space:]]+(failure|failures|issue|issues)/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /[0-9]+[[:space:]]+(failure|failures)/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /[0-9]+[[:space:]]+fail/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /(fail|failed):[[:space:]]+[0-9]+/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
      }

      END {
        if (candidate != "" && candidate != "0") {
          print candidate
        }
      }
    ' "$log_file"
  )

  if [ -n "$count" ]; then
    echo "$count"
  else
    echo "?"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --skip-bun-install)
    skip_bun_install=1
    ;;
  --clean)
    clean_builds=1
    ;;
  --lane)
    shift
    if [ "$#" -eq 0 ]; then
      >&2 echo "--lane requires a value (all, policy, core, runtime:<shard>)."
      exit 1
    fi
    lane=$1
    ;;
  --lane=*)
    lane=${1#--lane=}
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $1"
    >&2 echo ""
    usage
    exit 1
    ;;
  esac
  shift
done

case "$lane" in
all | policy | core) ;;
runtime:?*)
  runtime_shard=${lane#runtime:}
  lane=runtime
  ;;
*)
  >&2 echo "Unknown lane: $lane (expected all, policy, core, or runtime:<shard>)."
  exit 1
  ;;
esac

if [ "$lane" != policy ]; then
  emit_module_trace=1
fi

lane_runs_policy() { [ "$lane" = all ] || [ "$lane" = policy ]; }
lane_runs_core() { [ "$lane" = all ] || [ "$lane" = core ]; }
lane_runs_runtime() { [ "$lane" = all ] || [ "$lane" = runtime ]; }
lane_needs_swift() { [ "$lane" != policy ]; }

# --- Runtime shard manifest (Scripts/data/runtime-shards.txt) ---------------
# Rows are `<shard-id>|<regex>` (ordered, first match wins) or
# `isolated|<SuiteType>`. Regexes may contain `|`, so split on the FIRST bar
# only. Comments and blank lines are ignored.
manifest_rows() {
  if [ ! -f "$runtime_shard_manifest" ]; then
    >&2 echo "Missing runtime shard manifest: $runtime_shard_manifest"
    exit 1
  fi
  grep -v '^[[:space:]]*#' "$runtime_shard_manifest" | grep -v '^[[:space:]]*$'
}

manifest_shard_ids() {
  manifest_rows | awk '{ id = $0; sub(/\|.*/, "", id); if (id != "isolated") print id }'
}

manifest_shard_regex() {
  manifest_rows | awk -v id="$1" '
    { row_id = $0; sub(/\|.*/, "", row_id) }
    row_id == id { print substr($0, length(row_id) + 2); exit }
  '
}

manifest_isolated_suites() {
  manifest_rows | awk '{ id = $0; sub(/\|.*/, "", id); if (id == "isolated") print substr($0, length(id) + 2) }'
}

if [ "$lane" = runtime ]; then
  if [ -z "$(manifest_shard_regex "$runtime_shard")" ]; then
    >&2 echo "Unknown runtime shard: $runtime_shard (manifest: $runtime_shard_manifest)."
    >&2 echo "Known shards: $(manifest_shard_ids | tr '\n' ' ')"
    exit 1
  fi
fi

# Prints, one per line, the `swift test` selection arguments for one shard:
# `--filter <its regex>`, `--skip <regex>` for every shard listed above it in
# the manifest (first match wins, so an earlier shard's suites are never
# re-run here), and `--skip <suite>` for every isolated suite.
runtime_shard_test_args() {
  shard=$1
  printf '%s\n' --filter "$(manifest_shard_regex "$shard")"
  for earlier_shard in $(manifest_shard_ids); do
    if [ "$earlier_shard" = "$shard" ]; then
      break
    fi
    printf '%s\n' --skip "$(manifest_shard_regex "$earlier_shard")"
  done
  for isolated_suite in $(manifest_isolated_suites); do
    printf '%s\n' --skip "$isolated_suite"
  done
}

run_swift() {
  # Opt-in test-run modifiers, composed onto any `swift test` invocation. Both
  # default off, so the gate's behaviour is unchanged unless an operator sets
  # them deliberately (e.g. to bisect a load-sensitive flake such as the
  # run-loop SIGSEGV in swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md):
  #   SWIFTTUI_SWIFT_TEST_SKIP_REGEX — skip tests matching a regex.
  #   SWIFTTUI_SWIFT_TEST_SERIALIZED — run tests serially (--no-parallel) so a
  #     timing-dependent interleaving is reproducible/bisectable rather than
  #     racing across parallel workers.
  if [ "$#" -gt 0 ] && [ "$1" = "test" ]; then
    soundness_trace_invocation_index=$((soundness_trace_invocation_index + 1))
    trace_slug=${soundness_trace_step_slug:-swift-test}
    trace_file=$soundness_trace_root/$trace_slug-$soundness_trace_invocation_index.log
    mkdir -p "$soundness_trace_root"
    : >"$trace_file"
    SWIFTTUI_SOUNDNESS_PROBE_TRACE=1 && export SWIFTTUI_SOUNDNESS_PROBE_TRACE
    SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE=$trace_file
    export SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE

    if [ -n "${SWIFTTUI_SWIFT_TEST_SKIP_REGEX:-}" ]; then
      set -- "$@" --skip "$SWIFTTUI_SWIFT_TEST_SKIP_REGEX"
    fi
    if [ -n "${SWIFTTUI_SWIFT_TEST_SERIALIZED:-}" ]; then
      # `--no-parallel` is the ONLY spelling that serializes swift-testing.
      # Two prior spellings were inert, each in a different way:
      #   * bare `--num-workers 1` — SwiftPM rejects it without `--parallel`,
      #     so the step died on argument validation in about a second (made
      #     the release-soundness soak inert for four days; KNOWN-TEST-FLAKES.md
      #     entry 1, "soak integrity note").
      #   * `--parallel --num-workers 1` — validates, and does not serialize:
      #     `--num-workers` bounds XCTest worker processes, while swift-testing
      #     keeps its own in-process concurrency (measured peak 1645 tests in
      #     flight with the pair vs 3 with `--no-parallel`; entry 14).
      # `swift test --help` advertising no-parallel as the default is wrong in
      # practice: the empirical default is parallel.
      set -- "$@" --no-parallel
    fi
  fi

  if [ "$emit_module_trace" -eq 1 ] && [ "$#" -gt 0 ]; then
    case "$1" in
    build | test)
      set -- "$@" -Xswiftc -emit-loaded-module-trace
      ;;
    esac
  fi

  swiftly run swift "$@"
}

# The broad runtime lane runs serialized — `--no-parallel`, the only spelling
# that actually serializes swift-testing (see the SWIFTTUI_SWIFT_TEST_SERIALIZED
# comment above; the `--parallel --num-workers 1` pair this lane shipped with
# first was measured at peak 1645 tests in flight, i.e. still parallel).
# Serialization does NOT change the lane's stall rate (2/10 serialized vs
# 5/17 parallel pooled — the wedge needs only a single test's internal
# run-loop concurrency). What it buys, for ~5-10% wall clock: a single-test
# stall signature at a consistent lane offset instead of ~113 in-flight
# tests, and an execution shape the following gate step can assert. The
# root cause is open and recorded as KNOWN-TEST-FLAKES.md entry 14.
run_swift_runtime_tests_without_isolated_async_suites() {
  set -- "$@" --no-parallel
  for isolated_suite in $(manifest_isolated_suites); do
    set -- "$@" --skip "$isolated_suite"
  done
  run_swift test "$@"
}

# Same lane, one shard of it (CI `runtime:<shard>` lane). Regex characters
# must not be glob-expanded while the manifest lines are re-split into
# arguments, hence the `set -f` bracket.
run_swift_runtime_shard_tests() {
  set -f
  # shellcheck disable=SC2046
  set -- $(runtime_shard_test_args "$runtime_shard")
  set +f
  run_swift test --no-parallel "$@"
}

runtime_shard_command_text() {
  set -f
  # shellcheck disable=SC2046
  set -- $(runtime_shard_test_args "$runtime_shard")
  set +f
  text="$(swift_command_text test --no-parallel)"
  for argument; do
    case "$argument" in
    --filter | --skip)
      text="$text $argument"
      ;;
    *)
      text="$text '$argument'"
      ;;
    esac
  done
  printf '%s' "$text"
}

# The core lane's single parallel launch of every test target except the
# serialized SwiftTUITests lane (its shards run in the runtime jobs) and
# EntryPointLaunchTests (which needs the fixture executables built first and
# keeps its own launch below). swift-testing matches the regexes against the
# fully qualified name `Module.Suite/test()`, so the anchored module prefix
# cannot bleed into SwiftTUIWASITests or SwiftTUIWebHostTests.
# The socket, PTY, and process-launching targets stay out of the merged
# launch: on the first CI run of the merged shape (swift-tui run 32844751713)
# WebHostLoopbackWireTests lost its 5 s WebSocket reads and a
# SwiftTUITerminalTests session-lifecycle race lost its wakeup with 2,389
# tests in flight on a 4-vCPU runner — contention, not defects (both pass in
# their own launch, as they always did). They keep their own launches below;
# the cost is four ~8 s discovery passes.
run_non_runtime_test_targets() {
  run_swift test \
    --skip '^SwiftTUITests\.' \
    --skip '^EntryPointLaunchTests\.' \
    --skip '^SwiftTUICLITests\.' \
    --skip '^SwiftTUITerminalTests\.' \
    --skip '^SwiftTUIPTYPrimitivesTests\.' \
    --skip '^SwiftTUIWebHostTests\.'
}

# The per-tick cadence suite re-runs under the WASI-shaped mode profiles so
# the browser regime (stack-lean resolve, chunked depth-capped resolve) keeps
# native coverage: the 0.1.9 frame-coalescing incident only reproduced with
# those profiles active. `SWIFTTUI_RESOLVE_DEPTH_LIMIT=6` is the WASI
# stack-lean default depth cap (DeferredResolveDriver.stackLeanDefaultDepthLimit).
run_per_tick_cadence_lean_lane() {
  SWIFTTUI_STACK_LEAN_PROFILE=1 run_swift test \
    --filter SwiftTUITests.PerTickPresentCadenceTests
}

run_per_tick_cadence_depth_limit_lane() {
  SWIFTTUI_RESOLVE_DEPTH_LIMIT=6 run_swift test \
    --filter SwiftTUITests.PerTickPresentCadenceTests
}

# The lean + retained-reuse lane (bounded-depth-reuse program): the same
# cadence suite plus the reuse-gate pin under the opt-in
# `SWIFTTUI_LEAN_RETAINED_REUSE=1`, so the browser regime that re-enables
# retained reuse under the stack-lean profile keeps native coverage. The
# reuse-gate pin also runs (with inverted expectations) in the default and
# bare-lean lanes — it is environment-adaptive.
run_per_tick_cadence_lean_reuse_lane() {
  SWIFTTUI_STACK_LEAN_PROFILE=1 SWIFTTUI_LEAN_RETAINED_REUSE=1 run_swift test \
    --filter "SwiftTUITests.PerTickPresentCadenceTests|LeanRetainedReuseGateTests"
}

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
  fi
}

# The three layers whose stored-struct growth leaves downstream SwiftPM
# products stale (plan 2026-08-25-003 P4): a consumer object compiled against
# the old layout of a Graph/Core struct segfaults instead of recompiling.
layer_sources_fingerprint() {
  find Sources/SwiftTUIPrimitives Sources/SwiftTUIGraph Sources/SwiftTUICore \
    -name '*.swift' -type f -print 2>/dev/null \
    | LC_ALL=C sort \
    | xargs cat 2>/dev/null \
    | cksum \
    | cut -d ' ' -f 1-2
}

layer_fingerprint_stamp=$repo_root/.build/.swifttui-gate-layer-fingerprint
layer_sources_changed_since_last_gate=0

# Records this gate's Primitives/Graph/Core source fingerprint and remembers
# whether it differs from the previous gate's, so a signal-11 crash can be
# attributed to stale downstream products rather than diagnosed from scratch.
stamp_layer_sources_fingerprint() {
  current_fingerprint=$(cd "$repo_root" && layer_sources_fingerprint)
  if [ -f "$layer_fingerprint_stamp" ] \
    && [ "$(cat "$layer_fingerprint_stamp")" != "$current_fingerprint" ]; then
    layer_sources_changed_since_last_gate=1
  fi
  mkdir -p "$(dirname "$layer_fingerprint_stamp")"
  printf '%s' "$current_fingerprint" >"$layer_fingerprint_stamp"
}

print_stale_build_products_hint_if_applicable() {
  hint_exit_code=$1
  hint_log_file=$2
  [ "$layer_sources_changed_since_last_gate" -eq 1 ] || return 0
  if [ "$hint_exit_code" = 139 ] \
    || grep -q -E 'signal code 11|SIGSEGV|Segmentation fault|Illegal instruction|signal code 4' \
      "$hint_log_file" 2>/dev/null; then
    >&2 echo ""
    >&2 echo "HINT: a Primitives/Graph/Core source changed since the last gate and this step"
    >&2 echo "      crashed by signal. Stale downstream SwiftPM products are the usual cause"
    >&2 echo "      (a consumer compiled against a struct's previous layout). Purge them with:"
    >&2 echo "        Scripts/purge_downstream_build_products.sh SwiftTUIGraph"
    >&2 echo "      (or SwiftTUIPrimitives / SwiftTUICore for the layer that changed), then rerun."
  fi
}

run_step() {
  title=$1
  workdir=$2
  rerun_command=$3
  shift 3
  step_index=$((step_index + 1))
  log_file=$log_root/step-$step_index.log
  status_file=$log_root/step-$step_index.status
  timeout_file=$log_root/step-$step_index.timeout

  echo ""
  echo "==> $title"

  if (
    cd "$workdir" &&
      run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"
  ); then
    rm -f "$status_file" "$timeout_file"
    echo "PASS: $title"
    record_result "$title" "PASS" "0" "-" "$rerun_command" "$log_file" ""
  else
    exit_code=$(read_step_exit_code "$status_file")
    if [ -f "$timeout_file" ]; then
      detail=$(cat "$timeout_file")
      failure_count="-"
      status=TIMEOUT
      >&2 echo "TIMEOUT: $title ($detail)"
    else
      detail=""
      failure_count=$(derive_failure_count "$log_file")
      status=FAIL
      >&2 echo "FAIL: $title"
      print_stale_build_products_hint_if_applicable "$exit_code" "$log_file"
    fi
    rm -f "$status_file" "$timeout_file"
    any_failed=1
    record_result "$title" "$status" "$exit_code" "$failure_count" "$rerun_command" "$log_file" "$detail"
    if [ "$status" = "TIMEOUT" ]; then
      >&2 echo ""
      >&2 echo "Aborting after timeout to avoid spending more CI minutes on a stuck gate."
      print_failure_logs
      print_summary >&2
      exit 1
    fi
  fi
}

run_function_step() {
  title=$1
  rerun_command=$2
  shift 2
  step_index=$((step_index + 1))
  log_file=$log_root/step-$step_index.log
  status_file=$log_root/step-$step_index.status
  timeout_file=$log_root/step-$step_index.timeout
  soundness_trace_step_slug=$step_index-$(soundness_trace_slug "$title")

  echo ""
  echo "==> $title"

  if run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"; then
    rm -f "$status_file" "$timeout_file"
    echo "PASS: $title"
    record_result "$title" "PASS" "0" "-" "$rerun_command" "$log_file" ""
  else
    exit_code=$(read_step_exit_code "$status_file")
    if [ -f "$timeout_file" ]; then
      detail=$(cat "$timeout_file")
      failure_count="-"
      status=TIMEOUT
      >&2 echo "TIMEOUT: $title ($detail)"
    else
      detail=""
      failure_count=$(derive_failure_count "$log_file")
      status=FAIL
      >&2 echo "FAIL: $title"
      print_stale_build_products_hint_if_applicable "$exit_code" "$log_file"
    fi
    rm -f "$status_file" "$timeout_file"
    any_failed=1
    record_result "$title" "$status" "$exit_code" "$failure_count" "$rerun_command" "$log_file" "$detail"
    if [ "$status" = "TIMEOUT" ]; then
      >&2 echo ""
      >&2 echo "Aborting after timeout to avoid spending more CI minutes on a stuck gate."
      print_failure_logs
      print_summary >&2
      exit 1
    fi
  fi
}

. "$repo_root/Scripts/lib/repo_policy_checks.sh"

skip_step() {
  title=$1
  reason=$2

  echo ""
  echo "==> $title"
  echo "SKIP: $title ($reason)"
  record_result "$title" "SKIP" "-" "-" "-" "" "$reason"
}

check_swift_environment() {
  version_output=$(run_swift --version 2>&1)
  echo "$version_output"

  case "$version_output" in
  *"Swift version 6.3"* | *"Apple Swift version 6.3"*)
    return 0
    ;;
  *)
    >&2 echo ""
    >&2 echo "Expected Swift 6.3.x for this repository."
    >&2 echo "Use 'swiftly run swift ...' for repo-local package builds and tests."
    return 1
    ;;
  esac
}

check_bun_environment() {
  bun --version
}

check_fixture_recording_environment_disabled() {
  for name in \
    PARALLEL_RECORD_RENDERED_FIXTURES \
    SWIFTTUI_REGENERATE_CONFORMANCE_FIXTURES \
    SWIFTTUI_RECORD_RENDERED_TEXT_FIXTURES \
    SWIFTTUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT; do
    eval "is_set=\${$name+x}"
    if [ -n "$is_set" ]; then
      >&2 echo "$name must not be set when running the repo gate."
      >&2 echo "Use the fixture recorder named in swift-tui-org/docs/swift-tui/DEVELOPMENT.md."
      return 1
    fi
  done
}

clean_swift_build_directories() {
  build_dirs=$(find "$repo_root" -type d -name .build -prune 2>/dev/null)

  if [ -z "$build_dirs" ]; then
    echo "No SwiftPM .build directories found; nothing to clean."
    return 0
  fi

  echo "$build_dirs" | while IFS= read -r build_dir; do
    [ -n "$build_dir" ] || continue
    echo "Removing $build_dir"
    rm -rf "$build_dir"
  done
}

print_failure_logs() {
  while IFS='|' read -r title status exit_code failure_count rerun_command log_file detail; do
    [ "$status" = "FAIL" ] || [ "$status" = "TIMEOUT" ] || continue

    >&2 echo ""
    >&2 echo "===== $title (exit $exit_code) ====="
    if [ -f "$log_file" ]; then
      cat "$log_file" >&2
    else
      >&2 echo "Missing captured log: $log_file"
    fi
  done <"$results_file"
}

print_summary() {
  echo ""
  echo "Repo test summary:"

  while IFS='|' read -r title status exit_code failure_count rerun_command log_file detail; do
    case "$status" in
    PASS)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' \
        "$status" "$exit_code" "$failure_count" "$title"
      ;;
    FAIL)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' \
        "$status" "$exit_code" "$failure_count" "$title"
      printf '        rerun: %s\n' "$rerun_command"
      ;;
    TIMEOUT)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s' \
        "$status" "$exit_code" "$failure_count" "$title"
      if [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'
      printf '        rerun: %s\n' "$rerun_command"
      ;;
    SKIP)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s' \
        "$status" "$exit_code" "$failure_count" "$title"
      if [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'
      ;;
    esac
  done <"$results_file"

  if [ -n "${SWIFTTUI_TEST_ALL_FINAL_LOG:-}" ]; then
    echo "Full log: $SWIFTTUI_TEST_ALL_FINAL_LOG"
  fi

  if [ "$any_failed" -eq 0 ]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi
}

if lane_needs_swift; then
  require_command swiftly
fi
if lane_runs_policy; then
  require_command bun
fi
validate_timeout_configuration
if [ -d "$soundness_trace_root" ]; then
  find "$soundness_trace_root" -type f -name '*.log' -delete
fi
mkdir -p "$soundness_trace_root"

if [ "$is_linux" -eq 1 ]; then
  echo "Linux host detected; exporting DISABLE_EXPLICIT_PLATFORMS=1 for repo package resolution."
fi

echo "Lane: $lane${runtime_shard:+:$runtime_shard}"

if lane_needs_swift; then
  swift_version_command=$(swift_command_text --version)

  run_function_step \
    "Check Swift toolchain" \
    "$swift_version_command" \
    check_swift_environment
fi

if lane_runs_policy; then
  run_function_step \
    "Check Bun availability" \
    "bun --version" \
    check_bun_environment
fi

run_function_step \
  "Check fixture recording is disabled" \
  "env | rg '^(PARALLEL_RECORD_RENDERED_FIXTURES|SWIFTTUI_REGENERATE_CONFORMANCE_FIXTURES|SWIFTTUI_RECORD_RENDERED_TEXT_FIXTURES|SWIFTTUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT)='" \
  check_fixture_recording_environment_disabled

if lane_needs_swift; then
  stamp_layer_sources_fingerprint
fi

if [ "$clean_builds" -eq 1 ]; then
  run_function_step \
    "Clean SwiftPM build directories" \
    "find . -type d -name .build -prune -exec rm -rf {} +" \
    clean_swift_build_directories
fi

# --- Policy lane: no Swift toolchain required ------------------------------
if lane_runs_policy; then
  if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
    run_step \
      "Install Bun workspace dependencies" \
      "$repo_root" \
      "bun install --frozen-lockfile" \
      bun install --frozen-lockfile
  fi

  run_repo_policy_phase "$repo_root" test-all

  run_step \
    "Run layout work-stack guardrails" \
    "$repo_root" \
    "Scripts/check_layout_work_stack_guardrails.sh" \
    Scripts/check_layout_work_stack_guardrails.sh

  run_step \
    "Self-test step watchdog" \
    "$repo_root" \
    "Scripts/check_step_watchdog.sh" \
    Scripts/check_step_watchdog.sh

  run_step \
    "Self-test apt-get retry wrapper" \
    "$repo_root" \
    "Scripts/check_apt_get_retry.sh" \
    Scripts/check_apt_get_retry.sh

  run_step \
    "Self-test serialized-execution check" \
    "$repo_root" \
    "Scripts/check_serialized_execution.sh --self-test" \
    Scripts/check_serialized_execution.sh --self-test

  run_step \
    "Self-test test-duration ratchet" \
    "$repo_root" \
    "Scripts/check_test_durations.sh --self-test" \
    Scripts/check_test_durations.sh --self-test

  run_step \
    "Run tree-walker recursion guardrails" \
    "$repo_root" \
    "Scripts/check_tree_walker_recursion.sh" \
    Scripts/check_tree_walker_recursion.sh

  run_step \
    "Self-test tree-walker recursion guardrails" \
    "$repo_root" \
    "Scripts/check_tree_walker_recursion.sh --self-test" \
    Scripts/check_tree_walker_recursion.sh --self-test
fi

# --- Core lane: compile once, then every non-runtime suite -----------------
# The whole package and every test bundle are built in ONE step, with
# `-emit-loaded-module-trace` (see `emit_module_trace`), so the Foundation
# audit reads the traces of this build instead of compiling Core+Views a second
# time into its own scratch, and every later `swift test` launch in the lane
# is an incremental no-op build.
if lane_runs_core; then
  run_function_step \
    "Build package and test bundles" \
    "$(swift_command_text build --build-tests)" \
    run_swift build --build-tests

  run_step \
    "Check Foundation-free layers (transitive)" \
    "$repo_root" \
    "Scripts/check_foundation_free_layers.sh --trace-dir .build/debug" \
    Scripts/check_foundation_free_layers.sh --trace-dir .build/debug

  run_step \
    "Check the value-type authoring invariant (negative compile)" \
    "$repo_root" \
    "Scripts/check_value_type_invariant.sh" \
    Scripts/check_value_type_invariant.sh
fi

if [ "$lane" = all ]; then
  run_function_step \
    "Run SwiftTUIGraph tests" \
    "$(swift_command_text test --filter SwiftTUIGraphTests)" \
    run_swift test --filter SwiftTUIGraphTests

  run_function_step \
    "Run SwiftTUICore tests" \
    "$(swift_command_text test --filter SwiftTUICoreTests)" \
    run_swift test --filter SwiftTUICoreTests

  run_function_step \
    "Run SwiftTUIViews tests" \
    "$(swift_command_text test --filter SwiftTUIViewsTests)" \
    run_swift test --filter SwiftTUIViewsTests

  run_function_step \
    "Run SwiftTUIProfiling tests" \
    "$(swift_command_text test --filter SwiftTUIProfilingTests)" \
    run_swift test --filter SwiftTUIProfilingTests
elif [ "$lane" = core ]; then
  run_function_step \
    "Run non-runtime test targets" \
    "$(swift_command_text test --skip '^SwiftTUITests\.' --skip '^EntryPointLaunchTests\.' --skip '^SwiftTUICLITests\.' --skip '^SwiftTUITerminalTests\.' --skip '^SwiftTUIPTYPrimitivesTests\.' --skip '^SwiftTUIWebHostTests\.')" \
    run_non_runtime_test_targets

  run_function_step \
    "Run SwiftTUICLI tests" \
    "$(swift_command_text test --filter SwiftTUICLITests)" \
    run_swift test --filter SwiftTUICLITests

  run_function_step \
    "Run SwiftTUITerminal tests" \
    "$(swift_command_text test --filter SwiftTUITerminalTests)" \
    run_swift test --filter SwiftTUITerminalTests

  run_function_step \
    "Run SwiftTUIPTYPrimitives tests" \
    "$(swift_command_text test --filter SwiftTUIPTYPrimitivesTests)" \
    run_swift test --filter SwiftTUIPTYPrimitivesTests

  run_function_step \
    "Run SwiftTUIWebHost tests" \
    "$(swift_command_text test --filter SwiftTUIWebHostTests)" \
    run_swift test --filter SwiftTUIWebHostTests
fi

if lane_runs_core; then
  run_function_step \
    "Run SwiftTUI async lifecycle tests" \
    "$(swift_command_text test --filter SwiftTUITests.AsyncLifecycleGenerationTests)" \
    run_swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests

  run_function_step \
    "Run SwiftTUI async frame-tail tests" \
    "$(swift_command_text test --filter SwiftTUITests.AsyncFrameTailRenderingTests)" \
    run_swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests

  run_function_step \
    "Run SwiftTUI task-state observation tests" \
    "$(swift_command_text test --filter SwiftTUITests.TaskReadsUnbodiedStateTests)" \
    run_swift test --filter SwiftTUITests.TaskReadsUnbodiedStateTests

  run_function_step \
    "Run SwiftTUI per-tick present cadence tests" \
    "$(swift_command_text test --filter SwiftTUITests.PerTickPresentCadenceTests)" \
    run_swift test --filter SwiftTUITests.PerTickPresentCadenceTests

  run_function_step \
    "Run SwiftTUI per-tick present cadence tests (stack-lean profile)" \
    "SWIFTTUI_STACK_LEAN_PROFILE=1 $(swift_command_text test --filter SwiftTUITests.PerTickPresentCadenceTests)" \
    run_per_tick_cadence_lean_lane

  run_function_step \
    "Run SwiftTUI per-tick present cadence tests (chunked resolve driver)" \
    "SWIFTTUI_RESOLVE_DEPTH_LIMIT=6 $(swift_command_text test --filter SwiftTUITests.PerTickPresentCadenceTests)" \
    run_per_tick_cadence_depth_limit_lane

  run_function_step \
    "Run SwiftTUI per-tick present cadence tests (stack-lean + retained reuse)" \
    "SWIFTTUI_STACK_LEAN_PROFILE=1 SWIFTTUI_LEAN_RETAINED_REUSE=1 $(swift_command_text test --filter 'SwiftTUITests.PerTickPresentCadenceTests|LeanRetainedReuseGateTests')" \
    run_per_tick_cadence_lean_reuse_lane

  # Isolated like the other held-tail suites: the draft-window test parks a
  # frame-tail worker thread on the raster gate, and inside the parallel lane
  # that thread hold starves scheduling-sensitive siblings (observed: stress
  # cancellation 020's yield-budget settle losing its producer thread in the
  # Linux container lane).
  run_function_step \
    "Run SwiftTUI observation draft-window tests" \
    "$(swift_command_text test --filter SwiftTUITests.ObservationDraftWindowRuntimeTests)" \
    run_swift test --filter SwiftTUITests.ObservationDraftWindowRuntimeTests
fi

# --- Runtime lane: the serialized SwiftTUITests surface --------------------
# Two checks follow every runtime launch, against that launch's own log:
#   * serialized execution — the launch claims `--no-parallel`; verify the
#     claim rather than trusting the flag (two earlier serialization spellings
#     were inert while their steps stayed green, KNOWN-TEST-FLAKES.md entry
#     14). The check also fails when the log holds NO test-start events, which
#     is what a shard whose manifest regex matches nothing looks like.
#   * per-test durations — the hot-path budget (plan 2026-08-25-001 Stage 2b):
#     every test <= 10 s target, > 20 s fails; churn loops read their counts
#     from stressIterations(full:hotPath:). Under SWIFTTUI_STRESS_FULL=1 the
#     full counts run by design, so the ratchet is skipped rather than made
#     to fail the nightly lane it exists to complement.
check_runtime_lane_log() {
  launch_label=$1
  runtime_lane_log=$log_root/step-$step_index.log

  run_step \
    "Check runtime lane executed serially$launch_label" \
    "$repo_root" \
    "Scripts/check_serialized_execution.sh <runtime-lane-log>" \
    Scripts/check_serialized_execution.sh "$runtime_lane_log"

  if [ "${SWIFTTUI_STRESS_FULL:-0}" = "1" ]; then
    skip_step \
      "Check runtime lane test durations$launch_label" \
      "SWIFTTUI_STRESS_FULL=1 runs the full iteration counts"
  else
    run_step \
      "Check runtime lane test durations$launch_label" \
      "$repo_root" \
      "Scripts/check_test_durations.sh <runtime-lane-log>" \
      Scripts/check_test_durations.sh "$runtime_lane_log"
  fi
}

# `all` runs the SAME shard launches CI runs, in the same order (Stage 2d),
# so the local gate and the CI aggregator scan identically partitioned
# traces against one ledger (Scripts/soundness_quarantine.txt). Measured
# 2026-08-25: the three-shard `all` run reproduces the single-process
# ledger to the unit (registration-publication 1199, teardown-coherence-leak
# 499; 64 and 174 after the 2026-08-28 burn-down; 0 and 67 after the first
# 2026-08-29 pass, which unquarantined the first kind; 0 and 0 after the
# second, which emptied the ledger) — the counts are
# per-test, not per-process, so the partition does not
# move them; keeping the shapes identical removes the question rather than
# answering it every time. SWIFTTUI_RUNTIME_LANE_SHAPE=single restores the
# historical one-process launch for diagnosis (reproducing an entry-14 stall
# at its lane offset, bisecting a cross-suite interaction).
if [ "$lane" = all ] && [ "${SWIFTTUI_RUNTIME_LANE_SHAPE:-shards}" = single ]; then
  run_function_step \
    "Run SwiftTUI runtime tests" \
    "$(swift_command_text test --filter SwiftTUITests --no-parallel --skip AsyncLifecycleGenerationTests --skip AsyncFrameTailRenderingTests --skip TaskReadsUnbodiedStateTests --skip PerTickPresentCadenceTests --skip ObservationDraftWindowRuntimeTests)" \
    run_swift_runtime_tests_without_isolated_async_suites --filter SwiftTUITests
  check_runtime_lane_log ""
elif [ "$lane" = all ]; then
  for runtime_shard in $(manifest_shard_ids); do
    run_function_step \
      "Run SwiftTUI runtime tests (shard $runtime_shard)" \
      "$(runtime_shard_command_text)" \
      run_swift_runtime_shard_tests
    check_runtime_lane_log " (shard $runtime_shard)"
  done
  runtime_shard=""
elif [ "$lane" = runtime ]; then
  run_function_step \
    "Run SwiftTUI runtime tests (shard $runtime_shard)" \
    "$(runtime_shard_command_text)" \
    run_swift_runtime_shard_tests
  check_runtime_lane_log " (shard $runtime_shard)"
fi

if [ "$lane" = all ]; then
  run_function_step \
    "Run SwiftTUIAnimatedImage tests" \
    "$(swift_command_text test --filter SwiftTUIAnimatedImageTests)" \
    run_swift test --filter SwiftTUIAnimatedImageTests

  run_function_step \
    "Run SwiftTUIArguments tests" \
    "$(swift_command_text test --filter SwiftTUIArgumentsTests)" \
    run_swift test --filter SwiftTUIArgumentsTests

  run_function_step \
    "Run SwiftTUICLI tests" \
    "$(swift_command_text test --filter SwiftTUICLITests)" \
    run_swift test --filter SwiftTUICLITests

  run_function_step \
    "Run SwiftTUITerminal tests" \
    "$(swift_command_text test --filter SwiftTUITerminalTests)" \
    run_swift test --filter SwiftTUITerminalTests

  run_function_step \
    "Run SwiftTUIPTYPrimitives tests" \
    "$(swift_command_text test --filter SwiftTUIPTYPrimitivesTests)" \
    run_swift test --filter SwiftTUIPTYPrimitivesTests

  run_function_step \
    "Run SwiftTUIWASISurfaceBridge tests" \
    "$(swift_command_text test --filter SwiftTUIWASISurfaceBridgeTests)" \
    run_swift test --filter SwiftTUIWASISurfaceBridgeTests

  run_function_step \
    "Run SwiftTUIWASI tests" \
    "$(swift_command_text test --filter SwiftTUIWASITests)" \
    run_swift test --filter SwiftTUIWASITests

  run_function_step \
    "Run SwiftTUIWebHost tests" \
    "$(swift_command_text test --filter SwiftTUIWebHostTests)" \
    run_swift test --filter SwiftTUIWebHostTests

  run_function_step \
    "Run SwiftTUIAndroidHost tests" \
    "$(swift_command_text test --filter SwiftTUIAndroidHostTests)" \
    run_swift test --filter SwiftTUIAndroidHostTests
fi

# The fixtures are deliberately not build-order dependencies of the test
# target (an executable dependency's `main` hijacks the release test runner's
# entry point — see Package.swift), so build them explicitly before the suite
# that launches them from disk. After the lane's full build this is an
# incremental no-op; the explicit step keeps the ordering guarantee visible.
build_entry_point_launch_fixtures() {
  for fixture in \
    EntryPointFixtureAtMain \
    EntryPointFixtureBare \
    EntryPointFixtureCLIBare \
    EntryPointFixtureWebHostCLIBare \
    EntryPointFixtureCLIAsyncVerbDispatch \
    EntryPointFixtureWebHostCLIAsyncVerbDispatch \
    EntryPointFixtureVerbDispatch \
    EntryPointFixtureVerbDispatchNoOptions; do
    run_swift build --target "$fixture"
  done
}

if lane_runs_core; then
  run_function_step \
    "Build entry-point launch fixtures" \
    "$(swift_command_text build --target 'EntryPointFixture{AtMain,Bare,CLIBare,WebHostCLIBare,CLIAsyncVerbDispatch,WebHostCLIAsyncVerbDispatch,VerbDispatch,VerbDispatchNoOptions}')" \
    build_entry_point_launch_fixtures

  run_function_step \
    "Run entry-point launch tests" \
    "$(swift_command_text test --filter EntryPointLaunchTests)" \
    run_swift test --filter EntryPointLaunchTests
fi

# Absorbed Vendor test targets (sources under Vendor/<pkg>/, targets first-class
# inside swift-tui's Package.swift since the Vendor sub-packages were absorbed).
# The core lane covers them in its single non-runtime launch.
if [ "$lane" = all ]; then
  run_function_step \
    "Run vendored UnixSignals tests" \
    "$(swift_command_text test --filter SwiftTUIVendorUnixSignalsTests)" \
    run_swift test --filter SwiftTUIVendorUnixSignalsTests

  run_function_step \
    "Run vendored SwiftFiglet tests" \
    "$(swift_command_text test --filter SwiftTUIVendorFigletTests)" \
    run_swift test --filter SwiftTUIVendorFigletTests

  run_function_step \
    "Run vendored GIF tests" \
    "$(swift_command_text test --filter SwiftTUIVendorGIFTests)" \
    run_swift test --filter SwiftTUIVendorGIFTests

  run_function_step \
    "Run vendored JPEG tests" \
    "$(swift_command_text test --filter SwiftTUIVendorJPEGTests)" \
    run_swift test --filter SwiftTUIVendorJPEGTests

  run_function_step \
    "Run vendored PNG tests" \
    "$(swift_command_text test --filter SwiftTUIVendorPNGTests)" \
    run_swift test --filter SwiftTUIVendorPNGTests
fi

if lane_runs_core; then
  if [ "${SWIFTTUI_SKIP_TERMUIPERF:-0}" = "1" ]; then
    skip_step \
      "Run Tools/TermUIPerf tests" \
      "covered by the separate TermUIPerf workflow"
  else
    run_function_step \
      "Run Tools/TermUIPerf tests" \
      "$(swift_command_text test --package-path Tools/TermUIPerf)" \
      run_swift test --package-path Tools/TermUIPerf
  fi
fi

# The quarantine ledger counts are whole-surface counts. The `all` lane scans
# here; the CI lanes upload their traces and the aggregator job scans the
# merged set once (.github/workflows/run-tests-linux.yml), which is the same
# number as long as every suite runs exactly once across the lanes — the
# invariant Scripts/check_root_test_target_coverage.sh enforces.
if [ "$lane" = all ]; then
  run_function_step \
    "Scan soundness traces" \
    "Scripts/scan_soundness_traces.sh .build/soundness-trace Scripts/soundness_quarantine.txt" \
    Scripts/scan_soundness_traces.sh "$soundness_trace_root" "$soundness_quarantine_file"
fi

if [ "$any_failed" -eq 0 ]; then
  print_summary
  exit 0
fi

>&2 echo ""
>&2 echo "Failure logs:"
print_failure_logs
print_summary >&2

exit 1

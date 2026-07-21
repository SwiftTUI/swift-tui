#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

runner_name=${STUI_TEST_RUNNER_NAME:-test-all}
step_timeout_seconds=${STUI_TEST_STEP_TIMEOUT_SECONDS:-1200}
step_timeout_kill_grace_seconds=${STUI_TEST_TIMEOUT_KILL_GRACE_SECONDS:-10}

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

if [ "${STUI_TEST_ALL_CAPTURED:-0}" != "1" ]; then
  timestamp=$(date '+%Y%m%d-%H%M%S')
  full_log_path="/tmp/swift-tui-$runner_name-$timestamp-$$.log"
  body_log=$(mktemp "/tmp/swift-tui-$runner_name-body.XXXXXX")
  status_file=$(mktemp "/tmp/swift-tui-$runner_name-status.XXXXXX")
  results_report=$(mktemp "/tmp/swift-tui-$runner_name-results.XXXXXX")
  if [ -n "${STUI_TEST_COMMAND_TEXT:-}" ]; then
    command_text=$STUI_TEST_COMMAND_TEXT
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

  export STUI_TEST_ALL_CAPTURED=1
  export STUI_TEST_ALL_FINAL_LOG=$full_log_path
  export STUI_TEST_ALL_RESULTS_REPORT=$results_report

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
  STUI_RECORD_RENDERED_TEXT_FIXTURES \
  STUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT; do
  eval "is_set=\${$name+x}"
  if [ -n "$is_set" ]; then
    >&2 echo "$name must not be set when running the repo gate."
    >&2 echo "Use Scripts/record_rendered_text_fixtures.sh to update rendered fixtures."
    exit 1
  fi
done

tmp_root=${TMPDIR:-/tmp}
log_root=$(mktemp -d "$tmp_root/swift-tui-test-all.XXXXXX")
results_file=$log_root/results.txt
any_failed=0

: >"$results_file"

cleanup() {
  if [ -n "${STUI_TEST_ALL_RESULTS_REPORT:-}" ] && [ -f "$results_file" ]; then
    cp "$results_file" "$STUI_TEST_ALL_RESULTS_REPORT" || true
  fi
  rm -rf "$log_root"
}

trap cleanup EXIT

if [ "$host_os" = "Linux" ]; then
  is_linux=1
  export DISABLE_EXPLICIT_PLATFORMS=1
fi

usage() {
  cat <<'EOF'
Usage: Scripts/test_all.sh [--clean] [--skip-bun-install]

Runs the exhaustive checked-in repo verification surface:
  - checked-in policy hooks
  - stable-doc source-path guardrails
  - explicit layout work-stack guardrails
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

Pass --clean to delete every SwiftPM `.build` directory before any step
runs. The satellite packages reached via `--package-path` rebuild the repo's
module graph inside their own `.build`, and SwiftPM's incremental tracking
across that package boundary can leave a stale object linked against a
since-changed symbol. --clean trades a from-scratch rebuild for a run that
cannot be tripped by that staleness.

Each step is bounded by STUI_TEST_STEP_TIMEOUT_SECONDS, defaulting to 1200
seconds. Set it to 0 to disable the per-step watchdog for local diagnosis.
After a timeout, the runner sends SIGTERM to the step's process tree, waits
STUI_TEST_TIMEOUT_KILL_GRACE_SECONDS seconds, then sends SIGKILL before
printing the captured log and failing the gate.

For the curated repo gate, use Scripts/test_gate.sh. That runner keeps the same
post-split non-example surface and writes a shorter test-gate log name.

Set STUI_SKIP_PUBLIC_API_BASELINE=1 when the public API baseline is covered by
the separate CI workflow. Set STUI_SKIP_TERMUIPERF=1 when Tools/TermUIPerf is
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

read_step_exit_code() {
  status_file=$1

  if [ -f "$status_file" ]; then
    cat "$status_file"
  else
    echo 1
  fi
}

is_non_negative_integer() {
  case "$1" in
  "" | *[!0-9]*)
    return 1
    ;;
  *)
    return 0
    ;;
  esac
}

validate_timeout_configuration() {
  if ! is_non_negative_integer "$step_timeout_seconds"; then
    >&2 echo "STUI_TEST_STEP_TIMEOUT_SECONDS must be a non-negative integer."
    exit 1
  fi

  if ! is_non_negative_integer "$step_timeout_kill_grace_seconds"; then
    >&2 echo "STUI_TEST_TIMEOUT_KILL_GRACE_SECONDS must be a non-negative integer."
    exit 1
  fi
}

process_children() {
  pid=$1

  if command -v pgrep >/dev/null 2>&1; then
    pgrep -P "$pid" 2>/dev/null || true
    return
  fi

  ps -e -o pid= -o ppid= 2>/dev/null | awk -v parent="$pid" '$2 == parent { print $1 }'
}

send_signal() {
  signal=$1
  pid=$2

  case "$signal" in
  TERM)
    kill -TERM "$pid" 2>/dev/null || true
    ;;
  KILL)
    kill -KILL "$pid" 2>/dev/null || true
    ;;
  esac
}

kill_process_tree() {
  pid=$1
  signal=$2

  for child in $(process_children "$pid"); do
    kill_process_tree "$child" "$signal"
  done

  send_signal "$signal" "$pid"
}

descendant_pids() {
  pid=$1

  for child in $(process_children "$pid"); do
    printf '%s\n' "$child"
    descendant_pids "$child"
  done
}

# Pre-kill hang diagnostics (STUI_HANG_DIAGNOSTICS=1): when the step watchdog
# fires, capture per-thread kernel wait channels and full thread backtraces of
# the test-runner processes BEFORE terminating them, so a wedged step leaves
# evidence of WHAT it was blocked on instead of just "timed out". Linux-only
# by construction (wchan/gdb); inert unless explicitly enabled.
dump_hang_diagnostics() {
  root_pid=$1

  [ "${STUI_HANG_DIAGNOSTICS:-0}" = "1" ] || return 0

  pid_list=$root_pid
  for pid in $(descendant_pids "$root_pid"); do
    pid_list="$pid_list,$pid"
  done

  >&2 echo "HANG-DIAGNOSTICS: capturing state of process tree rooted at $root_pid"
  >&2 ps -o pid,stat,pcpu,etimes,comm -p "$pid_list" 2>/dev/null || true

  gdb_command=""
  if command -v gdb >/dev/null 2>&1; then
    gdb_command="gdb"
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      # ptrace of a non-child needs privilege when yama/ptrace_scope=1.
      gdb_command="sudo -n gdb"
    fi
  fi

  dumped=0
  for pid in $root_pid $(descendant_pids "$root_pid"); do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo '?')
    case "$comm" in
    *swift* | *xctest* | *Packag*) ;;
    *) continue ;;
    esac

    thread_count=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
    >&2 echo "HANG-DIAGNOSTICS: pid $pid ($comm) threads=$thread_count"
    >&2 echo "--- per-thread state/wchan: pid $pid ---"
    >&2 ps -L -o tid,stat,pcpu,wchan:32,comm -p "$pid" 2>/dev/null || true

    if [ "$dumped" -lt 3 ] && [ -n "$gdb_command" ]; then
      >&2 echo "--- gdb thread backtraces: pid $pid ($comm) ---"
      $gdb_command --batch -p "$pid" \
        -ex "set pagination off" \
        -ex "set print thread-events off" \
        -ex "thread apply all bt 24" 2>&1 |
        sed 's/^/[gdb] /' >&2 || true
      dumped=$((dumped + 1))
    fi
  done
}

run_logged_command() {
  log_file=$1
  status_file=$2
  timeout_file=$3
  watchdog_cancel_file=$timeout_file.cancel
  shift 3

  rm -f "$status_file" "$timeout_file" "$watchdog_cancel_file"

  (
    set +e

    if [ "$step_timeout_seconds" -eq 0 ]; then
      "$@"
      command_status=$?
      printf '%s\n' "$command_status" >"$status_file"
      exit 0
    fi

    "$@" &
    command_pid=$!

    (
      elapsed_ticks=0
      timeout_ticks=$((step_timeout_seconds * 5))
      while [ "$elapsed_ticks" -lt "$timeout_ticks" ]; do
        if [ -f "$watchdog_cancel_file" ]; then
          exit 0
        fi
        sleep 0.2
        elapsed_ticks=$((elapsed_ticks + 1))
      done

      if [ -f "$watchdog_cancel_file" ]; then
        exit 0
      fi

      if kill -0 "$command_pid" 2>/dev/null; then
        detail="timed out after ${step_timeout_seconds}s"
        printf '%s\n' "$detail" >"$timeout_file"
        printf '%s\n' 124 >"$status_file"
        >&2 echo "TIMEOUT: command $detail; terminating process tree rooted at pid $command_pid."
        dump_hang_diagnostics "$command_pid"
        kill_process_tree "$command_pid" TERM
        sleep "$step_timeout_kill_grace_seconds"
        if kill -0 "$command_pid" 2>/dev/null; then
          >&2 echo "TIMEOUT: command still running after ${step_timeout_kill_grace_seconds}s; sending SIGKILL."
          kill_process_tree "$command_pid" KILL
        fi
      fi
    ) &
    watchdog_pid=$!

    wait "$command_pid"
    command_status=$?
    if [ -f "$timeout_file" ]; then
      wait "$watchdog_pid" 2>/dev/null || true
    else
      printf '%s\n' cancel >"$watchdog_cancel_file"
      wait "$watchdog_pid" 2>/dev/null || true
    fi
    rm -f "$watchdog_cancel_file"

    if [ ! -f "$status_file" ]; then
      printf '%s\n' "$command_status" >"$status_file"
    fi

    exit 0
  ) 2>&1 | tee "$log_file"

  command_status=$(read_step_exit_code "$status_file")
  [ "$command_status" -eq 0 ]
}

swift_command_text() {
  if [ "$is_linux" -eq 1 ]; then
    printf 'DISABLE_EXPLICIT_PLATFORMS=1 '
  fi

  printf 'swiftly run swift'

  for argument; do
    printf ' %s' "$argument"
  done
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

for argument in "$@"; do
  case "$argument" in
  --skip-bun-install)
    skip_bun_install=1
    ;;
  --clean)
    clean_builds=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $argument"
    >&2 echo ""
    usage
    exit 1
    ;;
  esac
done

run_swift() {
  # Opt-in test-run modifiers, composed onto any `swift test` invocation. Both
  # default off, so the gate's behaviour is unchanged unless an operator sets
  # them deliberately (e.g. to bisect a load-sensitive flake such as the
  # run-loop SIGSEGV in docs/KNOWN-TEST-FLAKES.md):
  #   STUI_SWIFT_TEST_SKIP_REGEX — skip tests matching a regex.
  #   STUI_SWIFT_TEST_SERIALIZED — run tests serially (--num-workers 1) so a
  #     timing-dependent interleaving is reproducible/bisectable rather than
  #     racing across parallel workers.
  if [ "$#" -gt 0 ] && [ "$1" = "test" ]; then
    if [ -n "${STUI_SWIFT_TEST_SKIP_REGEX:-}" ]; then
      set -- "$@" --skip "$STUI_SWIFT_TEST_SKIP_REGEX"
    fi
    if [ -n "${STUI_SWIFT_TEST_SERIALIZED:-}" ]; then
      set -- "$@" --num-workers 1
    fi
  fi

  swiftly run swift "$@"
}

run_swift_runtime_tests_without_isolated_async_suites() {
  run_swift test "$@" \
    --skip AsyncLifecycleGenerationTests \
    --skip AsyncFrameTailRenderingTests \
    --skip TaskReadsUnbodiedStateTests \
    --skip PerTickPresentCadenceTests
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

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
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
    STUI_RECORD_RENDERED_TEXT_FIXTURES \
    STUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT; do
    eval "is_set=\${$name+x}"
    if [ -n "$is_set" ]; then
      >&2 echo "$name must not be set when running the repo gate."
      >&2 echo "Use Scripts/record_rendered_text_fixtures.sh to update rendered fixtures."
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

  if [ -n "${STUI_TEST_ALL_FINAL_LOG:-}" ]; then
    echo "Full log: $STUI_TEST_ALL_FINAL_LOG"
  fi

  if [ "$any_failed" -eq 0 ]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi
}

require_command swiftly
require_command bun
validate_timeout_configuration

if [ "$is_linux" -eq 1 ]; then
  echo "Linux host detected; exporting DISABLE_EXPLICIT_PLATFORMS=1 for repo package resolution."
fi

swift_version_command=$(swift_command_text --version)

run_function_step \
  "Check Swift toolchain" \
  "$swift_version_command" \
  check_swift_environment

run_function_step \
  "Check Bun availability" \
  "bun --version" \
  check_bun_environment

run_function_step \
  "Check rendered fixture recording is disabled" \
  "env | rg '^(PARALLEL_RECORD_RENDERED_FIXTURES|STUI_RECORD_RENDERED_TEXT_FIXTURES|STUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT)='" \
  check_fixture_recording_environment_disabled

if [ "$clean_builds" -eq 1 ]; then
  run_function_step \
    "Clean SwiftPM build directories" \
    "find . -type d -name .build -prune -exec rm -rf {} +" \
    clean_swift_build_directories
fi

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
  "Check Foundation-free layers (transitive)" \
  "$repo_root" \
  "Scripts/check_foundation_free_layers.sh" \
  Scripts/check_foundation_free_layers.sh

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
  "Run SwiftTUI runtime tests" \
  "$(swift_command_text test --filter SwiftTUITests --skip AsyncLifecycleGenerationTests --skip AsyncFrameTailRenderingTests --skip TaskReadsUnbodiedStateTests --skip PerTickPresentCadenceTests)" \
  run_swift_runtime_tests_without_isolated_async_suites --filter SwiftTUITests

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
  "Run SwiftTUITerminalWorkspace tests" \
  "$(swift_command_text test --filter SwiftTUITerminalWorkspaceTests)" \
  run_swift test --filter SwiftTUITerminalWorkspaceTests

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

# The fixtures are deliberately not build-order dependencies of the test
# target (an executable dependency's `main` hijacks the release test runner's
# entry point — see Package.swift), so build them explicitly before the suite
# that launches them from disk.
build_entry_point_launch_fixtures() {
  for fixture in \
    EntryPointFixtureAtMain \
    EntryPointFixtureBare \
    EntryPointFixtureCLIBare \
    EntryPointFixtureWebHostCLIBare; do
    run_swift build --target "$fixture"
  done
}

run_function_step \
  "Build entry-point launch fixtures" \
  "$(swift_command_text build --target 'EntryPointFixture{AtMain,Bare,CLIBare,WebHostCLIBare}')" \
  build_entry_point_launch_fixtures

run_function_step \
  "Run entry-point launch tests" \
  "$(swift_command_text test --filter EntryPointLaunchTests)" \
  run_swift test --filter EntryPointLaunchTests

# Absorbed Vendor test targets (sources under Vendor/<pkg>/, targets first-class
# inside swift-tui's Package.swift since the Vendor sub-packages were absorbed).
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

if [ "${STUI_SKIP_TERMUIPERF:-0}" = "1" ]; then
  skip_step \
    "Run Tools/TermUIPerf tests" \
    "covered by the separate TermUIPerf workflow"
else
  run_function_step \
    "Run Tools/TermUIPerf tests" \
    "$(swift_command_text test --package-path Tools/TermUIPerf)" \
    run_swift test --package-path Tools/TermUIPerf
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

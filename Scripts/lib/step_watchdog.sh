#!/usr/bin/env sh

# The per-step watchdog, and the process-tree kill and hang-diagnostic helpers
# it drives. Sourced by Scripts/test_all.sh and exercised directly by
# Scripts/check_step_watchdog.sh, so the gate's timeout behaviour is verified
# deterministically in seconds instead of only on a loaded CI runner.
#
# Callers must set, before sourcing:
#   step_timeout_seconds                 idle bound (0 disables the watchdog)
#   step_timeout_kill_grace_seconds      SIGTERM -> SIGKILL grace
#   step_absolute_timeout_seconds        livelock backstop (0 disables)
#   step_output_probe_ticks              log-size sample interval, in 0.2s ticks

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
    >&2 echo "SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS must be a non-negative integer."
    exit 1
  fi

  if ! is_non_negative_integer "$step_timeout_kill_grace_seconds"; then
    >&2 echo "SWIFTTUI_TEST_TIMEOUT_KILL_GRACE_SECONDS must be a non-negative integer."
    exit 1
  fi

  if ! is_non_negative_integer "$step_absolute_timeout_seconds"; then
    >&2 echo "SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS must be a non-negative integer."
    exit 1
  fi

  if ! is_non_negative_integer "$step_output_probe_ticks" ||
    [ "$step_output_probe_ticks" -eq 0 ]; then
    >&2 echo "SWIFTTUI_TEST_STEP_OUTPUT_PROBE_TICKS must be a positive integer."
    exit 1
  fi
}

# Byte count of the step's log, without reading the file: the watchdog only
# needs to know whether it grew.
log_byte_count() {
  if [ ! -f "$1" ]; then
    printf '0'
    return
  fi
  ls -ln "$1" 2>/dev/null | awk 'NR == 1 { print $5; found = 1 } END { if (!found) print 0 }'
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

# Signals a process and every descendant.
#
# Deliberately NOT recursive. POSIX sh has no locals, so the previous recursive
# form (`pid=$1; for child …; do kill_process_tree "$child" …; done;
# send_signal "$signal" "$pid"`) let each recursive call overwrite its caller's
# `pid`. By the time the outermost call reached its own `send_signal`, `$pid`
# named the deepest descendant — so the root was signalled *never* whenever it
# had a child. Every `swift test` step has children (swiftly -> swift-test ->
# xctest), which meant the watchdog reported TIMEOUT and then left the whole
# tree running: the gate's "stop burning CI minutes" abort was inert.
#
# The root is signalled FIRST so a supervisor cannot spawn a replacement child
# in the window between enumerating descendants and signalling it; the
# descendants are then reaped. `descendant_pids` runs inside a command
# substitution, so its own global assignments cannot leak back here.
kill_process_tree() {
  kill_tree_root_pid=$1
  kill_tree_signal=$2

  kill_tree_descendants=$(descendant_pids "$kill_tree_root_pid")

  send_signal "$kill_tree_signal" "$kill_tree_root_pid"

  for kill_tree_target in $kill_tree_descendants; do
    send_signal "$kill_tree_signal" "$kill_tree_target"
  done
}

descendant_pids() {
  pid=$1

  for child in $(process_children "$pid"); do
    printf '%s\n' "$child"
    descendant_pids "$child"
  done
}

# Pre-kill hang diagnostics (SWIFTTUI_HANG_DIAGNOSTICS=1): when the step watchdog
# fires, capture per-thread kernel wait channels and full thread backtraces of
# the test-runner processes BEFORE terminating them, so a wedged step leaves
# evidence of WHAT it was blocked on instead of just "timed out". Linux-only
# by construction (wchan/gdb); inert unless explicitly enabled.
dump_hang_diagnostics() {
  root_pid=$1

  [ "${SWIFTTUI_HANG_DIAGNOSTICS:-0}" = "1" ] || return 0

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
      idle_ticks=0
      idle_timeout_ticks=$((step_timeout_seconds * 5))
      absolute_timeout_ticks=$((step_absolute_timeout_seconds * 5))
      last_output_bytes=$(log_byte_count "$log_file")
      detail=""

      while [ -z "$detail" ]; do
        if [ -f "$watchdog_cancel_file" ]; then
          exit 0
        fi
        sleep 0.2
        elapsed_ticks=$((elapsed_ticks + 1))
        idle_ticks=$((idle_ticks + 1))

        if [ $((elapsed_ticks % step_output_probe_ticks)) -eq 0 ]; then
          current_output_bytes=$(log_byte_count "$log_file")
          if [ "$current_output_bytes" != "$last_output_bytes" ]; then
            last_output_bytes=$current_output_bytes
            idle_ticks=0
          fi
        fi

        if [ "$idle_ticks" -ge "$idle_timeout_ticks" ]; then
          detail="produced no output for ${step_timeout_seconds}s"
        elif [ "$absolute_timeout_ticks" -gt 0 ] &&
          [ "$elapsed_ticks" -ge "$absolute_timeout_ticks" ]; then
          detail="exceeded the ${step_absolute_timeout_seconds}s absolute cap while still producing output"
        fi
      done

      if [ -f "$watchdog_cancel_file" ]; then
        exit 0
      fi

      if kill -0 "$command_pid" 2>/dev/null; then
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

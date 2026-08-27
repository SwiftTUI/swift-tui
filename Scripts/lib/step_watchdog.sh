#!/usr/bin/env sh

# The per-step watchdog, and the process-tree kill and hang-diagnostic helpers
# it drives. Sourced by Scripts/test_all.sh and exercised directly by
# Scripts/check_step_watchdog.sh, so the gate's timeout behaviour is verified
# deterministically in seconds instead of only on a loaded CI runner.
#
# swift-tui-examples keeps a copy of this file under the same path, differing
# only in the environment-variable prefix and this header; the coordination
# root's //:step_watchdog_sync gate compares the two. It bounds SILENCE rather
# than wall clock, and only when the step's process tree is also idle: a step
# that
# keeps printing is left alone however long it runs; a step that goes quiet
# for the idle bound is dumped (gdb thread backtraces when
# SWIFTTUI_HANG_DIAGNOSTICS=1 on Linux) and killed. That is the guard the
# 2026-08-25 mrkdwn journey hang needed: the wedge sat in Foundation calls
# before any PTY pair was opened, so only something watching the test process
# from OUTSIDE could see it. Before this, a hang cost the workflow cap (60-75
# minutes) and left no evidence.
#
# Callers must set, before sourcing:
#   step_timeout_seconds                 idle bound (0 disables the watchdog)
#   step_timeout_kill_grace_seconds      SIGTERM -> SIGKILL grace
#   step_absolute_timeout_seconds        livelock backstop (0 disables)
#   step_output_probe_ticks              log-size sample interval, in 0.2s ticks
#   step_busy_extensions                 idle windows forgiven while the tree is
#                                        burning CPU (0 disables; default 3)

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

  if ! is_non_negative_integer "$step_busy_extensions"; then
    >&2 echo "SWIFTTUI_TEST_STEP_BUSY_EXTENSIONS must be a non-negative integer."
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

# CPU time consumed by a process tree, in hundredths of a second.
#
# Silence is not evidence about a process. `swift test`'s stdout is a pipe, so
# libc block-buffers it, and a perfectly healthy test binary stays quiet for
# however long its ~4 KB buffer takes to fill: the 2026-08-26 gallery seam step
# delivered 453 test lines across 14 distinct seconds, in bursts of up to 103
# lines, and the watchdog read the gap between two bursts as a hang. CPU time
# is the signal that separates the two cases the gate actually cares about —
# the mrkdwn lost-continuation wedge sat at 0% CPU parked in `sigsuspend`,
# while the gallery "hang" was measured at 107%.
#
# `/proc` where it exists (10 ms resolution, Linux CI); `ps` elsewhere (10 ms
# on Darwin). Returns 0 when neither can answer, which makes an unreadable tree
# look idle — the conservative direction, since it preserves the old
# kill-on-silence behaviour rather than suppressing it.
process_tree_cpu_centiseconds() {
  root_pid=$1
  total=0

  for pid in $root_pid $(descendant_pids "$root_pid"); do
    if [ -r "/proc/$pid/stat" ]; then
      # utime and stime are fields 14 and 15 *after* the parenthesised comm,
      # which can itself contain spaces — so split on the last ')' first.
      ticks=$(sed 's/^.*) //' "/proc/$pid/stat" 2>/dev/null |
        awk '{ print $12 + $13 }' 2>/dev/null)
      case "$ticks" in
      "" | *[!0-9]*) ticks=0 ;;
      esac
      total=$((total + ticks))
    else
      # `[[dd-]hh:]mm:ss[.cc]` -> centiseconds.
      centiseconds=$(ps -o time= -p "$pid" 2>/dev/null | awk '
        { gsub(/^[ \t]+/, "", $0)
          n = split($0, parts, /[:-]/)
          seconds = 0
          for (i = 1; i <= n; i++) { seconds = seconds * 60 + parts[i] }
          printf "%d", seconds * 100 }' 2>/dev/null)
      case "$centiseconds" in
      "" | *[!0-9]*) centiseconds=0 ;;
      esac
      total=$((total + centiseconds))
    fi
  done

  printf '%s' "$total"
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

  # Deepest process first. `swiftly` and `swift-test` are supervisors that are
  # always parked in sigsuspend/waitpid; the wedged test binary is the leaf, and
  # it is the only one whose backtrace answers anything. On 2026-08-26 the
  # gallery hang spent this budget on those two supervisors and the run ended
  # before the leaf was reached, leaving a spinning test process undumped.
  ordered_pids=$root_pid
  for pid in $(descendant_pids "$root_pid"); do
    ordered_pids="$pid $ordered_pids"
  done

  dumped=0
  for pid in $ordered_pids; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo '?')
    # `/proc/<pid>/comm` truncates at 15 bytes, so a test bundle can lose the
    # very substring being matched: "gallery-demoPackageTests.xctest" arrives as
    # "gallery-demoPac", which contains no "Packag" and no "xctest". That is why
    # every gallery hang through 2026-08-26 went undumped while mrkdwn's
    # ("mrkdwnPackageTe") did not. argv[0] is not truncated, so match on both.
    argv0=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | head -1)
    case "$comm $argv0" in
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

    # The step runs as an asynchronous job, and POSIX sh hands an asynchronous
    # job /dev/null as its standard input unless one is explicitly
    # redirected. Hand the step the gate's own stdin instead, saved on fd 3
    # before the implicit redirection applies, so a watched step sees exactly
    # what the unwatched gate passed on (some example tests drive a run loop
    # from the process's input; a watchdog must not change what they read).
    exec 3<&0
    "$@" <&3 &
    command_pid=$!
    exec 3<&-

    (
      elapsed_ticks=0
      idle_ticks=0
      idle_timeout_ticks=$((step_timeout_seconds * 5))
      absolute_timeout_ticks=$((step_absolute_timeout_seconds * 5))
      last_output_bytes=$(log_byte_count "$log_file")
      # CPU consumed as of the start of the current idle window, so the check
      # below asks "did this tree do any work *while it was quiet*" rather than
      # "has it ever done any work".
      window_start_cpu=$(process_tree_cpu_centiseconds "$command_pid")
      busy_extensions_used=0
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
            window_start_cpu=$(process_tree_cpu_centiseconds "$command_pid")
          fi
        fi

        if [ "$idle_ticks" -ge "$idle_timeout_ticks" ]; then
          current_cpu=$(process_tree_cpu_centiseconds "$command_pid")
          if [ "$step_busy_extensions" -gt 0 ] &&
            [ "$busy_extensions_used" -lt "$step_busy_extensions" ] &&
            [ "$current_cpu" -gt "$window_start_cpu" ]; then
            # Quiet, but working: a buffered writer, not a wedge. Forgive the
            # window and say so, and spend one of a fixed per-step budget so a
            # genuine livelock still dies here rather than at the absolute cap.
            # The budget is deliberately NOT refunded when output resumes: this
            # very message grows the log, and refunding on log growth would let
            # the watchdog extend itself forever.
            busy_extensions_used=$((busy_extensions_used + 1))
            idle_ticks=0
            window_start_cpu=$current_cpu
            >&2 echo "NOTE: no output for ${step_timeout_seconds}s, but the process tree consumed CPU; treating that as progress (${busy_extensions_used}/${step_busy_extensions})."
          elif [ "$current_cpu" -gt "$window_start_cpu" ]; then
            detail="produced no output for ${step_timeout_seconds}s and exhausted its ${step_busy_extensions} busy extensions while still consuming CPU"
          else
            detail="produced no output for ${step_timeout_seconds}s"
          fi
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

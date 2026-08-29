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
#   step_output_probe_ticks              sample interval, in 0.2s ticks
#   step_busy_grace_seconds              total quiet-but-busy time forgiven
#                                        across the step (0 forgives nothing)
#   step_busy_min_cpu_percent            average tree CPU that counts as busy
#   step_watchdog_deadline_seconds       the job's own wall-clock cap, so a
#                                        watchdog that could never fire inside
#                                        it is rejected (0 skips the check)
#
# WORST-CASE KILL TIME is deliberately additive, and stated in one place:
#
#     step_timeout_seconds + step_busy_grace_seconds + step_timeout_kill_grace_seconds
#
# It used to be multiplicative — `step_busy_extensions` was a COUNT of forgiven
# windows, each costing another whole idle bound — and nobody ever did the
# multiplication. At the macOS gate's 1200 s bound with the default 3
# extensions the earliest possible kill was 4800 s against a 4500 s job cap, so
# the watchdog could not fire at all: every wedge burned the entire budget and
# produced no dump, which is exactly what the first macOS hang investigation
# had to work with. The same arithmetic left it inert on all five Linux gate
# lanes. Seconds compose by addition, which is why the budget is spelled in
# seconds now, and `step_watchdog_deadline_seconds` makes the gate refuse to
# start rather than let the mistake recur silently.
#
# The bounds are also measured against a real clock rather than counted in
# ticks. A tick is `sleep 0.2` plus a fork, so on a loaded runner — the only
# place a hang matters — 1200 nominal seconds of ticks ran closer to 1700 real
# ones, and the stated bound understated the true one by ~40%.

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

  if ! is_non_negative_integer "$step_busy_grace_seconds"; then
    >&2 echo "SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS must be a non-negative integer."
    exit 1
  fi

  if ! is_non_negative_integer "$step_busy_min_cpu_percent" ||
    [ "$step_busy_min_cpu_percent" -eq 0 ]; then
    >&2 echo "SWIFTTUI_TEST_STEP_BUSY_MIN_CPU_PERCENT must be a positive integer."
    >&2 echo "It is an average-utilisation floor, not a switch; forgive nothing by"
    >&2 echo "setting SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS=0 instead."
    exit 1
  fi

  if ! is_non_negative_integer "$step_watchdog_deadline_seconds"; then
    >&2 echo "SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS must be a non-negative integer."
    exit 1
  fi

  if [ "$step_timeout_seconds" -eq 0 ]; then
    return 0
  fi

  # The probe interval is the watchdog's whole resolution: nothing is evaluated
  # between two samples, so a probe slower than the bound it is meant to enforce
  # silently widens that bound.
  if [ "$step_output_probe_ticks" -gt $((step_timeout_seconds * 5)) ]; then
    >&2 echo "SWIFTTUI_TEST_STEP_OUTPUT_PROBE_TICKS ($step_output_probe_ticks ticks,"
    >&2 echo "$((step_output_probe_ticks / 5))s) is coarser than the ${step_timeout_seconds}s idle bound"
    >&2 echo "it samples, so the bound cannot be enforced to its stated value."
    exit 1
  fi

  # A watchdog that cannot fire inside the job's own cap is not a watchdog: the
  # job dies at the cap first, with no TIMEOUT line, no hang dump, and no
  # evidence of which step wedged. That was true of every gate lane before
  # 2026-08-29 and it is invisible unless something checks the arithmetic, so
  # this checks it — at startup, before any step has run.
  if [ "$step_watchdog_deadline_seconds" -eq 0 ]; then
    return 0
  fi

  worst_case_kill_seconds=$((step_timeout_seconds + step_busy_grace_seconds +
    step_timeout_kill_grace_seconds))
  if [ "$worst_case_kill_seconds" -ge "$step_watchdog_deadline_seconds" ]; then
    >&2 echo "The step watchdog cannot fire inside this job's ${step_watchdog_deadline_seconds}s cap."
    >&2 echo "Worst-case kill = ${step_timeout_seconds}s idle + ${step_busy_grace_seconds}s busy grace +"
    >&2 echo "${step_timeout_kill_grace_seconds}s kill grace = ${worst_case_kill_seconds}s."
    >&2 echo "Lower SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS or SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS,"
    >&2 echo "or raise the job's cap and SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS with it."
    exit 1
  fi

  if [ "$step_absolute_timeout_seconds" -gt 0 ] &&
    [ $((step_absolute_timeout_seconds + step_timeout_kill_grace_seconds)) -ge \
      "$step_watchdog_deadline_seconds" ]; then
    >&2 echo "The absolute backstop (${step_absolute_timeout_seconds}s + ${step_timeout_kill_grace_seconds}s kill grace) cannot fire"
    >&2 echo "inside this job's ${step_watchdog_deadline_seconds}s cap, so a step that livelocks while"
    >&2 echo "printing would still cost the whole job with no diagnostic."
    >&2 echo "Lower SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS."
    exit 1
  fi

  >&2 echo "step watchdog: kills a silent step after at most ${worst_case_kill_seconds}s (job cap ${step_watchdog_deadline_seconds}s);" \
    "a quiet step is forgiven only while its process tree averages >= ${step_busy_min_cpu_percent}% CPU, for ${step_busy_grace_seconds}s in total."
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

# Seconds since the epoch. The watchdog's bounds are real seconds, not counted
# ticks: see the header.
current_epoch_seconds() {
  date +%s
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
# Only a RATE computed from this is meaningful, never a bare difference. This
# is a tree-wide cumulative total, so two samples differ by a centisecond for
# reasons that say nothing about progress: a parked process still wakes for
# signal delivery and timer ticks, and any process that JOINS the tree between
# samples adds its own CPU to the total. Comparing the two totals with `-gt`
# — which is what the busy check did until 2026-08-29 — therefore called a tree
# "busy" on 10 ms of CPU across a 20-minute window, i.e. 0.0008% utilisation,
# and read a parked wedge as a spin.
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
      ticks_since_probe=0
      start_epoch=$(current_epoch_seconds)
      # Start of the current silence window: reset when the log grows, and
      # again whenever a window is forgiven as busy. `window_start_cpu` is
      # sampled at the same instants, so the check below asks "did this tree do
      # work *while it was quiet*" rather than "has it ever done any work".
      window_start_epoch=$start_epoch
      last_output_bytes=$(log_byte_count "$log_file")
      window_start_cpu=$(process_tree_cpu_centiseconds "$command_pid")
      # Silence this window may accrue before the watchdog re-decides. It is
      # the idle bound after real output, and after a forgiven window it is
      # whatever busy grace is left, capped at the idle bound — so a grace
      # SHORTER than the bound still buys exactly that much extra silence
      # instead of buying nothing. Charging a whole bound per grant would make
      # any grace below one bound silently dead, which is the same class of
      # mistake as the window COUNT this budget replaced.
      window_bound=$step_timeout_seconds
      busy_grace_used=0
      detail=""

      while [ -z "$detail" ]; do
        if [ -f "$watchdog_cancel_file" ]; then
          exit 0
        fi
        sleep 0.2
        ticks_since_probe=$((ticks_since_probe + 1))
        if [ "$ticks_since_probe" -lt "$step_output_probe_ticks" ]; then
          continue
        fi
        ticks_since_probe=0

        # Everything below is timed from the clock, not from the tick count. A
        # tick is `sleep 0.2` plus the fork to run it, so tick-counted "seconds"
        # stretch under exactly the load that makes a hang likely.
        now=$(current_epoch_seconds)
        current_output_bytes=$(log_byte_count "$log_file")
        if [ "$current_output_bytes" != "$last_output_bytes" ]; then
          last_output_bytes=$current_output_bytes
          window_start_epoch=$now
          window_start_cpu=$(process_tree_cpu_centiseconds "$command_pid")
          window_bound=$step_timeout_seconds
        fi

        window_seconds=$((now - window_start_epoch))
        elapsed_seconds=$((now - start_epoch))

        if [ "$window_seconds" -ge "$window_bound" ]; then
          current_cpu=$(process_tree_cpu_centiseconds "$command_pid")
          # Centiseconds of CPU per second of window IS percent utilisation, so
          # this is an average-utilisation floor over the whole silent window —
          # scale-free, and the same test whether the window is 20 seconds or
          # 20 minutes. The two shapes it has to separate were measured 0% (the
          # mrkdwn wedge, parked in sigsuspend) and 107% (the gallery step,
          # block-buffering its output while working).
          window_cpu_centiseconds=$((current_cpu - window_start_cpu))
          required_cpu_centiseconds=$((window_seconds * step_busy_min_cpu_percent))
          window_cpu_percent=$((window_cpu_centiseconds / window_seconds))
          tree_is_busy=0
          if [ "$window_cpu_centiseconds" -ge "$required_cpu_centiseconds" ]; then
            tree_is_busy=1
          fi

          busy_grace_remaining=$((step_busy_grace_seconds - busy_grace_used))
          if [ "$tree_is_busy" -eq 1 ] && [ "$busy_grace_remaining" -gt 0 ]; then
            # Quiet, but working: a buffered writer, not a wedge. Grant another
            # window from a fixed per-step budget, so a genuine livelock still
            # dies here rather than at the absolute cap. The grant is charged
            # UP FRONT and never refunded when output resumes — this very NOTE
            # grows the log, and refunding on log growth would let the watchdog
            # extend itself forever. Charging seconds rather than counting
            # windows is what keeps the worst case additive: the whole budget
            # can never buy more than `step_busy_grace_seconds` of extra
            # silence, whatever the idle bound is.
            window_bound=$step_timeout_seconds
            if [ "$busy_grace_remaining" -lt "$window_bound" ]; then
              window_bound=$busy_grace_remaining
            fi
            busy_grace_used=$((busy_grace_used + window_bound))
            window_start_epoch=$now
            window_start_cpu=$current_cpu
            >&2 echo "NOTE: no output for ${window_seconds}s, but the process tree averaged ${window_cpu_percent}% CPU (>= ${step_busy_min_cpu_percent}%); treating that as progress and allowing ${window_bound}s more (${busy_grace_used}s of ${step_busy_grace_seconds}s busy grace spent)."
          elif [ "$tree_is_busy" -eq 1 ]; then
            detail="produced no output for ${window_seconds}s and exhausted its ${step_busy_grace_seconds}s busy-grace budget while still consuming CPU (${window_cpu_percent}%)"
          else
            detail="produced no output for ${window_seconds}s while its process tree averaged ${window_cpu_percent}% CPU (below the ${step_busy_min_cpu_percent}% busy floor)"
          fi
        elif [ "$step_absolute_timeout_seconds" -gt 0 ] &&
          [ "$elapsed_seconds" -ge "$step_absolute_timeout_seconds" ]; then
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

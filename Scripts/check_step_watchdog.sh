#!/usr/bin/env sh

set -eu

# Self-test for the repo gate's per-step watchdog (Scripts/lib/step_watchdog.sh).
#
# The watchdog bounds SILENCE, not total runtime. That distinction is the whole
# fix for KNOWN-TEST-FLAKES.md entry 9: the previous fixed wall-clock cap killed
# `Run SwiftTUI runtime tests` on loaded runners because a lane running 5x slower
# under contention is indistinguishable, to a wall clock, from a lane that
# parked. A regression here does not fail loudly — it silently reintroduces a
# gate flake that only reproduces on a busy CI runner, which is exactly the kind
# of thing nobody can debug after the fact.
#
# So the behaviour is pinned here instead, driving the real `run_logged_command`
# with synthetic steps and sub-second bounds. The whole file runs in a few
# seconds on an idle machine.

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-watchdog-selftest.XXXXXX")
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

failures=0

fail() {
  >&2 echo "error: $1"
  failures=$((failures + 1))
}

# Drives one synthetic step through the real watchdog.
#
# Bounds are expressed in whole seconds because that is the watchdog's own unit.
# `probe_ticks=1` samples the log every 0.2 s so a 2 s idle bound still gets ten
# samples — the production default of 25 ticks (5 s) would be coarser than the
# whole test.
case_deadline_seconds=${SWIFTTUI_WATCHDOG_SELFTEST_DEADLINE_SECONDS:-40}

run_case() {
  case_name=$1
  idle_seconds=$2
  absolute_seconds=$3
  shift 3

  step_timeout_seconds=$idle_seconds
  step_timeout_kill_grace_seconds=1
  step_absolute_timeout_seconds=$absolute_seconds
  step_output_probe_ticks=1
  # Per-case overrides; the busy cases raise the grace to exercise it, and one
  # raises the CPU floor above what its step can reach.
  step_busy_grace_seconds=${case_busy_grace_seconds:-0}
  step_busy_min_cpu_percent=${case_busy_min_cpu_percent:-25}
  step_watchdog_deadline_seconds=0

  log_file=$work_dir/$case_name.log
  status_file=$work_dir/$case_name.status
  timeout_file=$work_dir/$case_name.timeout
  rm -f "$log_file" "$status_file" "$timeout_file"
  case_wedged=0

  # The case runs in the background behind this script's own deadline. A
  # watchdog bug that fails to kill its step makes `run_logged_command` block in
  # `wait` forever, and a self-test that hangs the gate is worse than the flake
  # it is guarding against — so a wedge has to be reported, not waited on.
  (
    set +e
    run_logged_command "$log_file" "$status_file" "$timeout_file" "$@"
    exit 0
  ) >/dev/null 2>&1 &
  case_pid=$!

  case_waited_ticks=0
  while kill -0 "$case_pid" 2>/dev/null; do
    sleep 0.2
    case_waited_ticks=$((case_waited_ticks + 1))
    if [ "$case_waited_ticks" -ge $((case_deadline_seconds * 5)) ]; then
      case_wedged=1
      kill_process_tree "$case_pid" KILL
      break
    fi
  done
  wait "$case_pid" 2>/dev/null || true

  case_exit=$(read_step_exit_code "$status_file")
  case_detail=""
  if [ -f "$timeout_file" ]; then
    case_detail=$(cat "$timeout_file")
  fi
}

# A step that burns CPU without printing anything — the block-buffered writer
# shape. `swift test` writes to a pipe, so libc holds its output until a ~4 KB
# buffer fills; the 2026-08-26 gallery seam step in swift-tui-examples delivered
# 453 test lines in 14 bursts and its watchdog read the gap between two of them
# as a hang. Bounded by wall clock rather than iteration count so the case costs
# the same everywhere.
busy_silent_step() {
  busy_seconds=$1
  busy_end=$(($(date +%s) + busy_seconds))
  while [ "$(date +%s)" -lt "$busy_end" ]; do
    busy_i=0
    while [ "$busy_i" -lt 2000 ]; do
      busy_i=$((busy_i + 1))
    done
  done
}

# A step that runs well past the idle bound but never goes quiet for it: the
# entry-9 case. Emits every 0.4 s for ~4 s against a 2 s idle bound.
chatty_slow_step() {
  i=0
  while [ "$i" -lt 10 ]; do
    echo "progress $i"
    sleep 0.4
    i=$((i + 1))
  done
}

# A step that starts, then parks forever. This one MUST be killed.
parks_after_output_step() {
  echo "starting"
  sleep 600
}

# A step that never emits anything at all. Also killed.
silent_step() {
  sleep 600
}

# A step that never finishes but keeps printing: silence cannot catch it, so
# only the absolute backstop can.
livelock_step() {
  while :; do
    echo "still going"
    sleep 0.2
  done
}

. "$repo_root/Scripts/lib/step_watchdog.sh"

# Drives `validate_timeout_configuration` with one configuration, in a subshell
# because it reports a bad configuration by exiting. Returns success when the
# configuration is accepted.
config_is_accepted() {
  (
    step_timeout_seconds=$1
    step_busy_grace_seconds=$2
    step_absolute_timeout_seconds=$3
    step_timeout_kill_grace_seconds=$4
    step_watchdog_deadline_seconds=$5
    step_output_probe_ticks=25
    step_busy_min_cpu_percent=25
    validate_timeout_configuration
  ) >/dev/null 2>&1
}

echo "1/11 a slow but talking step survives an idle bound it far exceeds"
run_case chatty_slow 2 0 chatty_slow_step
if [ "$case_exit" != "0" ]; then
  fail "a step that kept emitting output was killed (exit=$case_exit, detail='$case_detail'). \
This is the entry-9 regression: the watchdog is measuring wall clock again."
fi

echo "2/11 a step that parks after emitting output is killed"
run_case parks_after_output 2 0 parks_after_output_step
if [ "$case_wedged" = "1" ]; then
  fail "the watchdog reported a timeout but never actually killed the step, so the \
runner blocked in wait. kill_process_tree is signalling the wrong pid."
fi
if [ "$case_exit" != "124" ]; then
  fail "a parked step was not killed (exit=$case_exit); a wedged gate would run unbounded."
fi
case "$case_detail" in
*"no output"*) ;;
*) fail "parked step reported an unexpected timeout detail: '$case_detail'" ;;
esac

echo "3/11 a step that never emits anything is killed"
run_case silent 2 0 silent_step
if [ "$case_wedged" = "1" ]; then
  fail "a silent step outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a silent step was not killed (exit=$case_exit)."
fi

echo "4/11 the absolute backstop kills a step that livelocks while printing"
run_case livelock 60 3 livelock_step
if [ "$case_wedged" = "1" ]; then
  fail "a livelocking step outlived the watchdog's kill. A step that respawns \
children must still die: this is the case that proved kill_process_tree never \
signalled the root of a tree with children."
fi
if [ "$case_exit" != "124" ]; then
  fail "a livelocking step outran the absolute backstop (exit=$case_exit)."
fi
case "$case_detail" in
*"absolute cap"*) ;;
*) fail "livelock step reported an unexpected timeout detail: '$case_detail'" ;;
esac

echo "5/11 a disabled watchdog (0) never kills anything"
run_case disabled 0 0 chatty_slow_step
if [ "$case_exit" != "0" ]; then
  fail "a step ran with the watchdog disabled but still failed (exit=$case_exit)."
fi

echo "6/11 a silent step that is still burning CPU survives the idle bound"
case_busy_grace_seconds=6
run_case busy_silent_survives 2 0 busy_silent_step 5
case_busy_grace_seconds=0
if [ "$case_wedged" = "1" ]; then
  fail "the busy-but-silent case never finished; the watchdog left it running."
fi
if [ "$case_exit" != "0" ]; then
  fail "a silent step that was consuming CPU throughout was killed (exit=$case_exit, \
detail='$case_detail'). Silence is not evidence: a block-buffered writer is quiet \
until its buffer fills, and killing it turns a healthy lane red with a hang dump \
that shows a working thread."
fi

echo "7/11 a silent, busy step still dies once its busy grace runs out"
case_busy_grace_seconds=2
run_case busy_silent_exhausts 2 0 busy_silent_step 600
case_busy_grace_seconds=0
if [ "$case_wedged" = "1" ]; then
  fail "a livelocking silent step outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a silent step that burned CPU forever was never killed (exit=$case_exit); the \
busy grace is unbounded, so a real livelock would only die at the absolute cap."
fi
case "$case_detail" in
*"busy-grace budget"*) ;;
*) fail "exhausted-grace step reported an unexpected detail: '$case_detail'" ;;
esac

echo "8/11 a busy-grace budget does not save a parked step"
case_busy_grace_seconds=6
run_case parked_with_budget 2 0 parks_after_output_step
case_busy_grace_seconds=0
if [ "$case_wedged" = "1" ]; then
  fail "a parked step outlived the watchdog's kill when grace was available."
fi
if [ "$case_exit" != "124" ]; then
  fail "a parked step survived because grace was available (exit=$case_exit). The \
grace must require CPU to have advanced; a wedge consumes none."
fi
case "$case_detail" in
*"busy-grace budget"*)
  fail "a parked step was charged busy grace: '$case_detail'. It consumed no CPU."
  ;;
*"no output"*) ;;
*) fail "parked step with budget reported an unexpected detail: '$case_detail'" ;;
esac

# A busy grace SHORTER than the idle bound must still buy exactly that much
# extra silence. It bought nothing in the first cut of this change: a grant
# was charged a whole idle bound, so `grace < bound` failed the affordability
# test on the very first window and the block-buffered-writer protection was
# silently dead on every lane whose grace was under its bound — the macOS gate
# included. A budget that reads as 900 s and means 0 s is the same defect as
# the window COUNT it replaced.
echo "9/11 a busy grace shorter than the idle bound still buys silence"
case_busy_grace_seconds=2
run_case busy_partial_grace 4 0 busy_silent_step 5
case_busy_grace_seconds=0
if [ "$case_wedged" = "1" ]; then
  fail "the partial-grace case never finished; the watchdog left it running."
fi
if [ "$case_exit" != "0" ]; then
  fail "a busy step with 2s of grace against a 4s bound was killed at 4s (exit=$case_exit, \
detail='$case_detail'). A grant is being charged a whole idle bound instead of the \
silence it actually hands out, so any grace below one bound forgives nothing at all."
fi

# The busy test is an average-utilisation FLOOR, not "did the total go up".
# Until 2026-08-29 it was `current_cpu -gt window_start_cpu` — one centisecond,
# tree-wide, over a window up to 20 minutes long — so a parked tree's signal and
# timer wakeups, or any process merely joining the tree, read as work and the
# gate spent its whole grace on a wedge. Pinned here without depending on how
# much CPU a shell loop happens to burn on the machine running this: the step is
# genuinely busy at roughly one core, and the floor is set far above it.
echo "10/11 a step below the busy CPU floor is killed even with grace available"
case_busy_grace_seconds=6
case_busy_min_cpu_percent=400
run_case busy_below_floor 2 0 busy_silent_step 600
case_busy_grace_seconds=0
case_busy_min_cpu_percent=25
if [ "$case_wedged" = "1" ]; then
  fail "a step below the busy floor outlived the watchdog's kill."
fi
if [ "$case_exit" != "124" ]; then
  fail "a step burning ~1 core survived a 400% busy floor (exit=$case_exit). The busy \
test is comparing cumulative CPU totals again instead of an average rate, which is what \
made a parked wedge read as a spin."
fi
case "$case_detail" in
*"busy-grace budget"*)
  fail "a step below the busy floor was charged busy grace: '$case_detail'."
  ;;
*"busy floor"*) ;;
*) fail "below-floor step reported an unexpected detail: '$case_detail'" ;;
esac

# A watchdog whose earliest possible kill lands past the job's own cap is not a
# watchdog: the job dies at the cap first, with no TIMEOUT line and no hang
# dump. That was the shipped macOS configuration until 2026-08-29 — a 1200 s
# bound with three forgiven windows could not fire inside 4500 s — and nothing
# reported it, because the arithmetic is only wrong when you multiply it out.
echo "11/11 a watchdog that cannot fire inside the job's cap is rejected"
if config_is_accepted 1200 3600 4800 10 4500; then
  fail "the historical macOS configuration (1200 s bound, 3600 s of grace, 4800 s \
absolute) was accepted against a 4500 s job cap. Its earliest kill is 4810 s, so every \
wedge burns the whole job and leaves no diagnostic."
fi
if config_is_accepted 600 300 2400 10 1800; then
  fail "an absolute backstop of 2400 s was accepted against a 1800 s job cap; a step \
that livelocks while printing would still cost the whole job."
fi
if ! config_is_accepted 1200 900 3300 10 4500; then
  fail "the shipped macOS configuration was rejected; its worst case is 2110 s against \
a 4500 s cap."
fi
if ! config_is_accepted 1200 3600 4800 10 0; then
  fail "a deadline of 0 must skip the check entirely, so local runs and any caller \
without a job cap are unaffected."
fi

if [ "$failures" -ne 0 ]; then
  >&2 echo ""
  >&2 echo "Step-watchdog self-test FAILED with $failures problem(s)."
  exit 1
fi

echo "Step-watchdog self-test passed."

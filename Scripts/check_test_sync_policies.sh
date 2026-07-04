#!/usr/bin/env sh

# Ratchets timeout-driven test synchronisation toward zero.
#
# Tests must synchronise on directly-awaitable signals (AsyncEvent,
# MainActorConditionSignal, AsyncStream, an explicit `await` on a readiness
# callback) — not by polling a predicate under a timeout, sleeping a fixed
# wall-clock interval, or bridging async work through a blocking semaphore.
# Those patterns are simultaneously the flakiest and the slowest tests on a
# loaded CI runner.
#
# This is a one-way ratchet, not a hard ban: the recorded baseline counts the
# anti-pattern occurrences that still exist. New code may not push the count
# above the baseline. Converting a test lowers the count; lower the baseline
# to lock the improvement in.
#
# Matched primitives: waitUntil(, valueWithTimeout(, DispatchSemaphore,
# Task.sleep, .sleep(for:, usleep(, nanosleep(, Thread.sleep. The fixed-sleep
# forms (usleep/nanosleep/Thread.sleep) were added 2026-05-30 after a flake
# audit found they slipped past the original regex set.
#
# Baseline composition (15): 6 DispatchSemaphore barriers
# (TerminalPresentationTests x4, AsyncFrameTailRenderingTests x1,
# TerminalHostPresentationBatchingTests x1) + 4 fixed sleeps
# (InteractiveRuntimeTests x2 usleep, AnimationRepeatForeverGrowthTests x1
# usleep, RenderDiffTests x1 Thread.sleep) + 3 process/loop watchdogs
# (EntryPointLaunchTests x1 Task.sleep, GeometryReaderSurfaceTests x1
# Task.sleep, PresentationPortalForceQueueTests x1 Task.sleep — bounds the
# scripted-input frame-condition waits so a wrong predicate fails the test
# with diagnostics instead of hanging the suite) + 2 autonomous-workload
# ticks (GeometryReaderSurfaceTests x1 Task.sleep,
# TaskReadsUnbodiedStateTests x1 Task.sleep).
#
# NOTE: the EntryPointLaunchTests occurrence is a *process watchdog backstop*,
# not timeout-driven synchronisation. `runFixture` reads a launched fixture's
# PTY output event-by-event and stops the moment the expected marker appears;
# the real wait is the event-driven read loop. The `Task.sleep` only arms a
# SIGKILL that fires if a wedged or never-rendering fixture would otherwise hang
# the suite forever — there is no signal to await because the failure mode is
# the absence of one. It cannot be converted to AsyncEvent/MainActorCondition-
# Signal/AsyncStream and is grandfathered like the fixed-sleep latency
# injections above.
#
# NOTE: the two GeometryReaderSurfaceTests occurrences (added 2026-06-07 with the
# autonomous-task GeometryReader coverage) are the same two grandfathered shapes,
# not the test's synchronisation. That test already synchronises on a
# `MainActorConditionSignal` (notified from the mock host's `present()`) and an
# `AsyncStream`-based quit reader awaiting `conditionSignal.wait(until:)`:
#   - The 20 ms `Task.sleep` inside `GeometryReaderAutonomousTaskProbe.body`'s
#     `.task` is the *tick interval of the autonomous workload under test* — a
#     self-driving SwiftUI `.task` that periodically mutates state. It is the
#     producer the test observes, not a waiter; converting it would delete the
#     behaviour being verified. Same category as the fixed-sleep latency
#     injections above.
#   - The multi-second `Task.sleep` in `GeometryReaderAutonomousTaskQuitInputReader`
#     is a *loop watchdog backstop*: the real wait is the adjacent
#     `conditionSignal.wait(until: shouldQuit)`; the sleep only arms a synthetic
#     ctrl-D quit if the run loop never pumps a frame, so a wedged loop fails
#     instead of hanging the suite. Same un-awaitable "absence of a signal"
#     failure mode as the EntryPointLaunchTests watchdog above.
#
# NOTE: the TaskReadsUnbodiedStateTests occurrence (added with the @State /
# `.task` stale-read coverage) is the same autonomous-workload-tick shape as the
# 20 ms GeometryReader probe above: the 5 ms `Task.sleep` inside `HeldProbe`'s
# `.task` is the frame-pacing interval of the self-driving game loop *under
# test* (it mirrors the gallery "Logo Breaker" physics loop), not a waiter. The
# test's real synchronisation is the signal-based `ScriptedAutonomousWakeInput-
# Reader` (it awaits `terminal.frameSignal` conditions), so the sleep cannot be
# converted without deleting the workload being verified.
#
# NOTE: all 4 fixed sleeps are deliberate *presentation-latency injections*
# inside mock present()/presentObserver methods — they simulate a slow terminal
# present so a test can exercise frame batching/diffing (e.g.
# runLoopBatchesQueuedScrollBursts needs present to be slow so scroll events
# queue and coalesce). They are NOT timeout-driven synchronisation; the real
# waits in those tests are already signal-based (MainActorConditionSignal). Do
# not "convert" them to signals — that would defeat the latency they inject.
# They are grandfathered into the baseline so the ratchet still blocks *new*
# fixed sleeps. The lasting fix is to route latency injection through a named
# Tests/Support helper the regex can exclude (then drop the baseline to 6); the
# DispatchSemaphore barriers are the genuine sync anti-pattern to ratchet down.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

baseline_file="Scripts/data/test-sync-policy-baseline.txt"
baseline=$(tr -d '[:space:]' < "$baseline_file")

# Count lines containing a timeout-driven synchronisation primitive across
# every test directory. Tests/Support is excluded: it is the sanctioned home
# of the shared helpers, including the legacy `waitUntil` that callers are
# being migrated off of.
count=$(
  rg -c \
    --glob '*.swift' \
    --glob '!Tests/Support/**' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --regexp 'waitUntil\(' \
    --regexp 'valueWithTimeout\(' \
    --regexp 'DispatchSemaphore' \
    --regexp 'Task\.sleep' \
    --regexp '\.sleep\(for:' \
    --regexp '\busleep\(' \
    --regexp '\bnanosleep\(' \
    --regexp 'Thread\.sleep' \
    Tests Platforms/*/Tests 2>/dev/null \
    | awk -F: '{ sum += $2 } END { print sum + 0 }'
)

if [ "$count" -gt "$baseline" ]; then
  >&2 echo "Timeout-driven test synchronisation increased: $count occurrences, baseline $baseline."
  >&2 echo ""
  >&2 echo "Tests must await a direct signal, not poll a timeout. Use:"
  >&2 echo "  - AsyncEvent              — a one-shot 'it happened' signal"
  >&2 echo "  - MainActorConditionSignal — await a MainActor state predicate"
  >&2 echo "  - AsyncStream             — pull observations as they are produced"
  >&2 echo "  - an explicit onReady/completion callback the test can await"
  >&2 echo ""
  >&2 echo "All three live in Tests/Support (SwiftTUITestSupport)."
  >&2 echo ""
  >&2 echo "Offending occurrences:"
  rg -n \
    --glob '*.swift' \
    --glob '!Tests/Support/**' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --regexp 'waitUntil\(' \
    --regexp 'valueWithTimeout\(' \
    --regexp 'DispatchSemaphore' \
    --regexp 'Task\.sleep' \
    --regexp '\.sleep\(for:' \
    --regexp '\busleep\(' \
    --regexp '\bnanosleep\(' \
    --regexp 'Thread\.sleep' \
    Tests Platforms/*/Tests >&2 2>/dev/null || true
  exit 1
fi

if [ "$count" -lt "$baseline" ]; then
  echo "[check_test_sync_policies] timeout-driven synchronisation dropped to $count (baseline $baseline)."
  echo "[check_test_sync_policies] lower the baseline in $baseline_file to $count to lock this in."
  exit 0
fi

echo "[check_test_sync_policies] ok ($count occurrences, at baseline)"

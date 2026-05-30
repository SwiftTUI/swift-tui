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
# Baseline composition (10): 6 DispatchSemaphore barriers
# (TerminalPresentationTests x4, AsyncFrameTailRenderingTests x1,
# TerminalHostPresentationBatchingTests x1) + 4 fixed sleeps
# (InteractiveRuntimeTests x2 usleep, AnimationRepeatForeverGrowthTests x1
# usleep, RenderDiffTests x1 Thread.sleep).
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

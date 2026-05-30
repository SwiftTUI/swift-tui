# Known Test Flakes

The single register of **known, pre-existing flaky tests** in this repository:
tests that can fail spuriously under load or timing without any real
regression. When a `bun run test` / `swift test` failure matches an entry here,
it is almost certainly the known flake — not your change.

> **Triage rule.** Match the *signature* (test name + failing assertion + crash
> site) against an entry below before attributing a failure to a flake. Do
> **not** mask a genuine regression as "the flake": if the signature differs, or
> the failure reproduces deterministically in isolation, treat it as real.

The repo gate is otherwise deterministic by design (see
[Why the gate is otherwise deterministic](#why-the-gate-is-otherwise-deterministic)),
so a failure that is *not* listed here should be assumed real until proven
otherwise.

---

## Active flakes

### 1. Run-loop `SIGSEGV` / `SIGBUS` memory corruption — `SwiftTUI/swift-tui#12`

**Signature.** A crash (`SIGSEGV` or `SIGBUS`) on `com.apple.main-thread` inside
run-loop / async-render code — observed sites include
`FrameTailRenderer.setRenderSuspensionHooks`, copying `DefaultRenderer`, and
`SendableLayoutWorkerProxy.layoutSubviews`. It is **memory corruption**: torn
pointers whose bytes are rendered text (em-dash `0xe28094…`, ASCII), i.e. a
concurrent writer corrupting main-thread-owned memory.

**Where it surfaces.** Whichever run-loop-building suite happens to be running
when the corruption lands — most often `InteractiveRuntimeTests`,
`PortalPrimitiveTests`, or `ActorIsolationSurfaceTests`. The toast test's
`duration: 0.01` (10 ms auto-dismiss) is the most reliable trigger under load.

**Characteristics.**
- **Load/timing-sensitive** and **not reproducible on demand** — crashed 10/10
  in isolation under one load condition, then 0/30 isolated + 0/4 parallel +
  0/20 under deliberate CPU load once the machine was idle.
- **Invisible to both AddressSanitizer and ThreadSanitizer** (both pass clean),
  which rules out simple heap use-after-free and TSan-visible races and points
  at unsafe-pointer / detached-task corruption.
- **Predates** the H1 off-screen-elision work (reproduces on `375dbbb5`); it is
  orthogonal to the render-pipeline optimizations.

**How to confirm it's this, not your change.** Check the crash site/signature
matches the above. Re-run; if it does not reproduce deterministically, it is
the flake. A real fix needs a forced-repro harness (widen the race window via
injected delays) — see issue #12 for the investigation and suspect seams.

**Status.** Open (`#12`). Fix deferred (user decision, 2026-05-29).

### 2. `OffscreenFrameElisionRuntimeTests` — off-screen deadline tick (real-time deadline race)

**Test.** `OffscreenFrameElisionRuntimeTests` →
`offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders`
("off-screen deadline tick elides but reschedules; on-screen invalidation
renders"), in `Tests/SwiftTUITests/OffscreenFrameElisionRuntimeTests.swift`.

**Signature.** Under heavy parallel test load it fails at one of three
assertions (which one varies run-to-run):
- the in-flight `repeatForever` animation reads `activeAnimationCount == 0`
  (the animation appears to have died), and/or the loop did not reschedule its
  next deadline (`hasPendingFrame` is false); **or**
- after the on-screen invalidation, `elidedFrameCount` advanced by an extra
  frame (`elidedFrameCount != elidedBeforeInvalidation`).

**Root cause.** A real-time-clock race, **not** a logic regression. The test
drives real `.now()`-based animation deadlines; `renderPendingFramesAsync`
consumes ready frames at the real `.now()`. Under CPU contention, real time
advances between the test's scheduler operations, so the rescheduled ~100 ms
animation deadline becomes ready and is drained alongside the on-screen
invalidation (producing the extra elision), or the controller's per-frame state
is read at an unlucky instant.

**Proven pre-existing.** This fails identically on **`main` with zero retained
reuse** (`canReuse` always returns `false` pre-enabler — verified failing 3/3
runs under full-gate load on `3aaa8282`), on the H2 enabler-only commit, and
with the H2 scoped-reuse fix. It **passes in isolation** on all three. The H2
investigation initially mis-attributed this to retained reuse / an animation
"gap"; that was an isolation-vs-load artifact. There is no reuse mechanism to
"fix" here.

**How to confirm it's this, not your change.** Run the test in isolation
(`swift test --filter offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders`)
— it passes. The failure only appears under the parallel load of the full gate.

**Status.** Open. Fix direction: harden the test to be load-deterministic —
drive it on a controlled/injected clock instead of `.now()`, or assert on the
frame's *causes* (`[.deadline]` vs. `.invalidation`) rather than on
`elidedFrameCount`, so a concurrently-ready deadline cannot perturb the count.

---

## Triage checklist

When `bun run test` reports a failure:

1. **Identify the failing test + assertion** (the gate prints a `rerun:` command
   per failed step).
2. **Match against an entry above** — same test, same assertion family, same
   crash site? If yes, it is the known flake.
3. **Re-run in isolation** with the printed `--filter`. Both active flakes
   **pass in isolation**; a deterministic isolated failure means it is *not*
   these flakes and is real.
4. **Never** wave off an unmatched signature as "probably the flake." Add a new
   entry here only after confirming load/timing-sensitivity (passes isolated,
   fails under load) and ruling out a real defect.

---

## Why the gate is otherwise deterministic

So that a *new* flake stands out, the suite deliberately avoids the usual
sources of test flake:

- **Poll-free synchronisation.** Runtime/animation tests use the condition-based
  primitives in `Tests/Support` instead of `sleep`/polling — see
  `SwiftTUITestSupport.docc` ("Poll-free synchronisation primitives for
  deterministic, flake-resistant tests") and `Synchronising-Without-Polling.md`.
- **No wall-clock budget assertions in the gate.** The one wall-clock
  blunder-detector (`RenderPipelineStructureTests.composedRenderTimeBudget`) is
  opt-in behind `STUI_RUN_WALLCLOCK_PERF` and **skipped** by the repo gate; do
  not tighten its 2× multiplier. Timing-sensitive coverage instead uses
  hang-detection against the CI job timeout (e.g.
  `FrameSchedulerIntentCoalescingTests` waits on a far-future deadline) or
  deterministic state-machine tests (e.g. `InputBatchingResponsivenessTests`
  does not try to reproduce the wall-clock-timing bug it guards).
- **Real-perf measurement lives outside the gate** in `Tools/TermUIPerf`, run on
  schedule / manual dispatch, never as a pass/fail wall-clock assertion.

The repo gate has **no automatic test retries** — `Scripts/test_all.sh` only
prints a `rerun:` command for a failed step. A green gate therefore means the
flakes above did not fire on that run, not that flakiness was retried away.

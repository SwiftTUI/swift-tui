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

**Repro instrument (2026-05-30).** A production-default-`nil` worker seam,
`FrameTailRenderHooks.beforeOverlayApply` (`FrameTailModels.swift`), fires on the
frame-tail worker immediately before the off-main overlay write, so a test can
park the worker inside that window and race a concurrent main-actor read. Wired +
ordering-guarded by `Tests/SwiftTUITests/FrameTailOverlayApplyHookTests.swift`. To
serialize a repro run, set `STUI_SWIFT_TEST_SERIALIZED=1` (gate seam → `--num-workers
1`). **Sharpened hypothesis:** the `Boxed` copy-on-write path the seam brackets is
likely *safe* under value semantics (worker copies-on-write its own box; the shared
`_BoxStorage` is `Mutex`-guarded with atomic refcount). The **stronger corruptor
candidate** is the unsynchronized `assumeIsolated` dictionary writes
(`ForEachIndexedChildSource.cache`, `LayoutProxyBox.cachedStates`) reached off-main
when the layout-offload eligibility scan misses a live source/handle — target that
path next. Full analysis: org-root `docs/reports/2026-05-30-flake-bcd-investigation.md`.

**Status.** Open (`#12`). Fix deferred (user decision, 2026-05-29); repro
instrument landed 2026-05-30, crashing experiment not yet run.

---

## Fixed flakes

### 2. `OffscreenFrameElisionRuntimeTests` — off-screen deadline tick (real-time deadline race) — FIXED 2026-05-30

**Test.** `OffscreenFrameElisionRuntimeTests` →
`offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders`, in
`Tests/SwiftTUITests/OffscreenFrameElisionRuntimeTests.swift`.

**Was.** Under heavy parallel test load it failed at one of three assertions
(which one varied run-to-run): the in-flight `repeatForever` read
`activeAnimationCount == 0`; the loop appeared not to reschedule
(`hasPendingFrame` false); or `elidedFrameCount` advanced an extra frame after
the on-screen invalidation. The async drain consumed frames at the real
`.now()` (`scheduler.consumeReadyFrame(at: .now())`), so the off-screen
`repeatForever`'s self-rescheduled animation deadline (`now + minimumLeadTime`
under load) drifted into "ready" between the test's scheduler operations and was
drained as an unexpected extra frame, perturbing the test's exact
`elidedFrameCount` equality. Proven pre-existing: failed identically on `main`
with zero retained reuse (3/3 under full-gate load on `3aaa8282`), independent of
the H2 work; passed in isolation.

**Fix.** Two parts:
1. **Injectable frame-readiness clock.** `RunLoop.frameReadinessClock` (default
   real `.now()`) now supplies the instant both frame drivers compare against
   pending scheduler deadlines (`consumeReadyFrame(at:)`). Production behaviour
   is unchanged; a runtime test can pin it to drive virtual time. Only *frame
   readiness* routes through it — real-time waiting (the event-pump sleeps) still
   uses the wall clock.
2. **Pinned-instant test.** The test freezes the clock to a single `frozenNow`
   captured before any frame is consumed. Every deadline the off-screen
   animation auto-reschedules lands at the real future (`> frozenNow`), so it is
   invisible to the drain — only the test's explicit deadline/invalidation
   requests drive frames, making the elision/present counts deterministic. The
   one real-clock assertion (`hasPendingFrame(at: .now() + 100 ms)`) became
   `nextWakeInstant(after: frozenNow) != nil` — the load-independent statement of
   the same "loop isn't frozen" invariant.

**Verification.** 11/11 suite green in isolation; **25/25 green under 18-core CPU
saturation** (the original failed 3/3 under full-gate load). Deterministic by
construction — no timing window remains.

---

## Triage checklist

When `bun run test` reports a failure:

1. **Identify the failing test + assertion** (the gate prints a `rerun:` command
   per failed step).
2. **Match against an entry above** — same test, same assertion family, same
   crash site? If yes, it is the known flake.
3. **Re-run in isolation** with the printed `--filter`. The active flake (#1) is
   load/timing-sensitive and does not reproduce deterministically in isolation;
   a deterministic isolated failure therefore means it is *not* the flake and is
   real.
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
- **Injectable frame-readiness clock.** A runtime test that drives animation
  deadlines can pin `RunLoop.frameReadinessClock` to a frozen instant, so the
  loop decides frame readiness against virtual time instead of the wall clock.
  Self-rescheduled animation deadlines then land in the real future relative to
  the frozen instant and stay invisible to the drain, so CPU contention cannot
  perturb frame counts (see fixed flake #2).
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

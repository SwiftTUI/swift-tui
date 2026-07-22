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
1`). The `Boxed` copy-on-write path the seam brackets was judged *safe* under value
semantics (worker copies-on-write its own box; the shared `_BoxStorage` is
`Mutex`-guarded with atomic refcount).

**Identified off-main-reach paths now EXHAUSTED (2026-05-30).** Both static paths by
which a live `@MainActor` `ForEachIndexedChildSource` (its mutable `cache` dictionary
is the torn-byte corruptor candidate) could reach the off-main frame-tail worker are
**closed**:

- *Current-frame offload* — the eligibility scan forces a full
  `indexedChildSourceWorkerSnapshot` conversion (a live source has
  `canRunOnWorker == false`) before anything goes off-main, so the worker only ever
  sees the value-type snapshot.
- *Retained-reuse* — verified by a 6-agent adversarial trace (workflow `w1u1xkuj0`).
  The one-shot/sync commit path **does** retain a live, un-converted source (the
  snapshot conversion is gated `mode == .abortable`, which one-shot skips:
  `injectAnimations` → reconcile → `commitOneShotFrame` → `storeCommittedFrame` →
  `RetainedFrameIndex` stores the whole `ResolvedNode`), and a later frame's off-main
  worker **does** read that retained source (`RetainedInvalidationSummary.init` →
  `source.identityRoot`, on the `swift-tui.frame-tail-renderer` queue). **But every
  reachable off-main accessor reads immutable `let` storage** (`identityRoot`,
  `measurementSignature`) under `MainActor.assumeIsolated` — a benign read (or a clean
  isolation trap), never a torn write. The sole mutator (`cache[index] = …` in
  `child(at:)`) is invoked only on the *current* node's source, which off-main is
  always the value-type snapshot — never the retained live source.
  `computeSupportsRetainedReuse` further returns `false` for any source-bearing node,
  so `isEquivalentFor*` is never even invoked on a source subtree. The mutable
  `LayoutProxyBox.cachedStates` is likewise unreachable (retained reuse returns cached
  values; it never calls `measureContainer`). This vector therefore **cannot produce
  #12's corruption signature** — the crash-repro build was cancelled rather than built.

**Consequence.** With both identified paths closed and the `Boxed` COW path judged
value-semantics-safe, **#12's corruption mechanism is currently unidentified**. Static
analysis has exhausted the named candidates; the honest next move (if/when #12 is
re-prioritized) is *dynamic* — reproduce the SEGV under load with the `assumeIsolated`
sites + eligibility scan annotated/under TSan — not another static repro harness.

**Instrumentation update (2026-06-26).** A first increment of that "annotate the
`assumeIsolated` sites" move has landed for one named suspect. The non-`Sendable`
custom-layout proxy `LayoutProxyBox` now routes every entry point through
`preconditionMainActor()` (an explicit `MainActor.preconditionIsolated`) **before**
the `assumeIsolated` (`CustomLayoutErasure.swift`). So if that vector is ever reached
off the frame-tail worker — contradicting the static "unreachable" judgment above —
it crashes **deterministically with an attributable message naming the cause**,
instead of a silent torn write that reads as anonymous corruption. It converts one
suspect seam from "judged safe by static analysis" into "self-reporting if the
analysis was wrong"; the remaining `assumeIsolated` sites are still un-instrumented.
(Rationale: org-root `docs/proposals/2026-06-26-001-architecture-fragility-improvements-proposal.md`, opportunity #3.)

**Release-checked seams update (2026-07-02).** The 2026-06-26 note above is
superseded: every previously suspected seam is now **release-checked**, not just
the one.

- *Observation bridge* — `withObservationTracking`'s `onChange` hop routes
  through `withCheckedMainActorAccess("ObservationBridge.recordChange")`
  (`SwiftTUIViews/Environment/Observation.swift`), landed `39b7d739`.
- *`LayoutProxyBox`* — the local `preconditionMainActor()` described above was
  refactored into the shared release-checked helper
  `withCheckedMainActorAccess` (`SwiftTUICore/Support/CheckedMainActorAccess.swift`)
  covering all five entry points (`247e4dc3`), after the deterministic
  off-main trap landed in `78417f02`. **Deleted 2026-07-06 (F11):** `Layout`
  now requires `Sendable` (and `Cache: Sendable`), every custom layout runs
  through the `Mutex`-backed `LayoutWorkerProxy`, and `LayoutProxyBox` — the
  unsynchronized `cachedStates` dictionary this seam guarded — no longer
  exists. The suspect surface is gone by construction, not just checked.
- *`FrameScheduler`* — redesigned lock-based and `Sendable`
  (`OSAllocatedUnfairLock` around all coalescing state, `Pipeline/Scheduler.swift`),
  landed `39b7d739` with `FrameSchedulerConcurrencyTests`. This closed the
  "raced `consumeReadyFrame`" mechanism the commit named as the suspected #1
  class.
- The sibling bridges (`IndexedChildSources` ×4, `LayoutDependentContent` ×2,
  the `.assumedMainActor` host frame bridge in `HostedRasterSurface`) are
  likewise checked (`247e4dc3`, `a2eec874`). The only bare `assumeIsolated`
  hops left in core targets are three deliberately-exempt pure read-recording
  scans in `Environment.swift` plus the Android-only `directWake`
  (`RunLoop.swift`) and the Android `@_cdecl` ABI entry points.

**New triage rule (2026-07-02).** Because every suspect seam now carries a
release-mode `preconditionIsolated` check:

- a crash that presents as a **`preconditionIsolated` trap with an attributable
  accessor name** = the old mechanism, finally located — file it against the
  named seam;
- a **raw `SIGSEGV`/`SIGBUS`** now *falsifies* the `assumeIsolated`-race
  hypothesis class for the checked seams — treat it as evidence of non-race
  heap corruption and pursue dynamically (e.g. `libgmalloc`, plus the release
  lane below), not with further static seam audits.

The scheduled **Release Soundness Lane**
(`.github/workflows/release-soundness.yml`, `Scripts/release_soundness_lane.sh`,
added 2026-07-02) runs the flaky trio (`InteractiveRuntimeTests`,
`PortalPrimitiveTests`, `ActorIsolationSurfaceTests`) serialized in release
configuration as a `continue-on-error` step — the standing soak where the
release-checked traps get their chance to convert this flake into an
attributable failure.

*Separate, real-but-benign finding.* The one-shot commit path stores a live
`@MainActor` source into retained state with no snapshot conversion
(`commitOneShotFrame` → `storeCommittedFrame`). It is harmless today (off-main reuse
only reads immutable storage) but is a latent soundness gap: if retained reuse ever
began calling `child(at:)` off-main it would become the corruptor. Optional
defense-in-depth: snapshot-convert in the one-shot commit path before
`storeCommittedFrame` (weigh against the full-tree recursion cost on every one-shot
commit). Full analysis: org-root `docs/reports/2026-05-30-flake-bcd-investigation.md`.

**Status (2026-07-07): DORMANT — watching via the daily soak.** Zero occurrences
since the seams were release-checked (2026-07-02): recent CI failure logs
contain no `SIGSEGV`/`SIGBUS` signatures (all recent gate reds were the known
MainActor-freeze timeout or genuine test failures), and multiple heavy local
load-testing sessions since have not sighted it. Two of the three historical
crash sites no longer exist: `SendableLayoutWorkerProxy` and the
`LayoutProxyBox` corruptor candidate were **deleted outright by F11
(2026-07-06)** — the strongest suspect surface is gone by construction.

**Soak integrity note (2026-07-07).** The lane's flaky-trio step was
**inert from 2026-07-03 to 2026-07-07**: `--num-workers` without `--parallel`
is rejected by SwiftPM, the script died 130 ms in, and the
`continue-on-error` step reported green anyway — so "the soak has been quiet"
was vacuous for that window. Fixed (`--parallel --num-workers 1`); the
serialized flaky-trio soak is genuinely running from 2026-07-08 onward, and
the dormancy evidence above deliberately does not lean on the inert window.
Lesson: a signal-only (`continue-on-error`) step needs its own liveness
check — an instant arg-error failure is indistinguishable from a quiet pass
at the workflow-status level.

**Forced-repro retired (2026-07-07).** The parked-worker `beforeOverlayApply`
repro stays unlanded *by decision*, not backlog: its weaker target (the `Boxed`
COW path) was judged value-semantics-safe and the hook seam is already landed +
ordering-guarded; its stronger target needed a layout-stage parking seam and
that target was deleted with F11. A new repro would need a new corruption
hypothesis, and none exists — the register's own conclusion stands: the pursuit
is dynamic. To that end the soak's flaky arm now runs under glibc allocator
guards (`MALLOC_CHECK_=3`, `MALLOC_PERTURB_` — `release_soundness_lane.sh
--flaky-only`), so heap misuse traps near its source instead of surfacing as
anonymous torn bytes.

**Tracking.** The historical `SwiftTUI/swift-tui#12` reference predates the
public repository (no such issue exists there); **this register entry is the
tracker of record**. Re-open criteria:

- a **`preconditionIsolated` trap naming an accessor** = the old race class,
  finally located — file against the named seam;
- a **raw `SIGSEGV`/`SIGBUS`** (or an allocator-guard abort) = non-race heap
  corruption — the guard's trap site is the lead; escalate locally on macOS
  with `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` on the flaky trio.

### 6. `FrameworkStressGestureScrollTests` — stress gesture scroll 025 nested takeover over-pans on Linux CI

**Signature.** "stress gesture scroll 025 nested takeover pans the leaf
scroll view" fails at `FrameworkStressGestureScrollTests.swift` with
`Expectation failed: (inner.value.y → 5) == 3` — the leaf scroll pane ends
two rows past the expected pan target after the nested takeover hand-off.

**Where it surfaces.** The `Linux repo gate (amd64)` lane only. Firings:
the `0.1.5` release-window Repo Gate (2026-07-13, rerun green), then
2026-07-18 at `6bce1644`/`8560d337` (pre-noon runs, before that day's fix
batch), at `feb28468` (alongside two other slow-runner timeouts: a
tap-composition test running 289 s so the inter-tap window decomposed a
double into two singles, and a 300 s starvation-cap timeout), and at the
`0.1.7` release commit `70feb5cf` (run 29655794779). The same day's
`c6ccba5e` run escalated to the whole runtime-test lane timing out at
1200 s. The identical `5` vs `3` overshoot in every assertion-level firing
suggests a load-dependent extra-tick class (two additional momentum/settle
ticks landing before the assertion) rather than randomness.

**Why this is not treated as a product regression.** Every firing tree was
green on the macOS full gate, and the arm64-native Linux container gate
(`mise run linux-gate`, worktree mode) passed in 337 s at `c6ccba5e` — the
exact tree whose amd64 lane had just timed out wholesale. The lane was red
at commits both before and after the 2026-07-18 changes with the same
signature, and the amd64 runner class already hosts the quarantined
TermUIPerf app-shell stall (entry 2). This is runner-class degradation,
not a behavior change in the pans themselves.

**How to investigate.** Reproduce under load on Linux (the arm64 container
via `mise run linux-gate` with a parallel CPU burner, or an amd64 host);
if it fires, capture `SWIFTTUI_FRAME_TRACE` and check whether the two
extra rows arrive as post-hand-off momentum ticks; if so, the fix is a
settle-gated assertion (wait for scroll quiescence) rather than a fixed
expected offset.

### 7. `GestureRunLoopDispatchTests` — Exclusive tap inter-tap window expiry under parallel-gate starvation

**Signature.** "Exclusive tap composition works through the full RunLoop
mouse path" fails with exactly `(counts.double → 0) == 1` plus
`(counts.single → 2) == 0` after a multi-hundred-second test duration
(~279–284 s observed): under heavy parallel-gate starvation the double
tap's second press lands after the 350 ms inter-tap window expires, so the
recognizer emits two singles instead of one double.

**Where it surfaces.** The `Linux repo gate (amd64)` lane under the full
parallel `swift test` run. Firings: 2026-07-21 run 29871856849 (the
`0.1.15` tag, 284 s) and run 29878019612 (`a3581786`, 279 s) — the second
firing met entry 6's register-on-recurrence criterion (that entry's
`feb28468` companion observation was this same decomposition).

**Why this is not treated as a product regression.** The suite's waits are
signal-native, but the inter-tap window is wall-clock by design (F158: the
window resolves at recognizer construction). The test passes in isolation
and on every other lane; the failure only appears when the test itself is
starved for hundreds of seconds on the degraded amd64 runner class.

**How to investigate / candidate hardening.** Drive the second tap through
the `interTapWindowOverride` package seam (F158) so the gate-load wall
clock cannot expire the window, or move the composed Exclusive leg to a
solo lane (the entry-2 pattern).

---

## Fixed flakes

### 2. TermUIPerf app-shell scenario stall on amd64 CI — QUARANTINED 2026-07-13

**Signature.** `ScenarioSmokeTests` "deterministic scenarios write artifact
directories" fails with `timed out waiting for marker '!Menu body'` in
`ExampleAppShellWorkflowScenario` — the wait after the close-menu click sees
no new presented frames for the whole idle window.

**Where it surfaces.** Only the `TermUIPerf Tests` workflow's
`ubuntu-24.04` (amd64) runners: 4/4 failures since the 2026-07-12 scheduled
run (which ran on the pre-Charts-migration baseline, so the flip predates
that migration). The identical suite passes on macOS arm64 and in the
arm64-native Linux container (`swiftly run swift test --package-path
Tools/TermUIPerf` inside the linux-gate image), including after the
2026-07-13 progress-gated-deadline hardening — so the stall is a genuine
no-frame stall on that runner class, not a slow-runner deadline miss.

**Why this is not treated as a product regression (yet).** The swift-tui
Repo Gate runs the full menu/presentation suite on the same amd64 runners
and is green; the stall is specific to the TermUIPerf harness path
(`PerfTerminalHost` + scripted click dispatch under `.sync` render mode).
Suspect window: the 2026-07-11 stress-campaign batch (presentation
dispatch / recognizer adoption / hover re-root routing changes).

**Quarantine.** The workflow sets
`TERMUI_PERF_SMOKE_SKIP=example-app-shell-workflow` (consumed by
`ScenarioSmokeTests`); every other scenario stays covered on amd64, and the
app-shell scenario stays covered on arm64/macOS. Remove the skip when this
entry is closed.

**How to investigate.** Reproduce on an amd64 host (or emulation) with
`swiftly run swift test --package-path Tools/TermUIPerf --filter
ScenarioSmokeTests`; instrument with the run-loop hang diagnostics
(`STUI_HANG_DIAGNOSTICS`) to capture where the loop parks after the
close-menu click; bisect the 2026-07-11 window if it reproduces.
2026-07-21 update: a Rosetta amd64 container (`docker run --platform
linux/amd64 swift:6.3.1` with the tree rsync'd out) deterministically
reproduced the *other* amd64-only quiet stall (the stack-lean cadence
lane; root-caused to observation draft-window deafness and fixed) — use
the same container recipe to re-test this scenario. Note this harness
runs `.sync` render mode, where the draft-window mechanism should not
apply, so treat that fix as untested against this entry until the
container run says otherwise.

### 3. `OffscreenFrameElisionRuntimeTests` — off-screen deadline tick (real-time deadline race) — FIXED 2026-05-30

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

> **Follow-on (#3 below).** The clock fix above closed the deadline-drift race
> but the same suite carried a *second, independent* flake — the onAppear
> registration drop — that the isolated 25/25 saturation run could not surface
> (it needs the full suite's cross-suite MainActor contention). Fixed 2026-05-31.

---

### 4. `OffscreenFrameElisionRuntimeTests` — onAppear registration dropped by the async driver during setup — FIXED 2026-05-31

**Tests.** `OffscreenFrameElisionRuntimeTests` (in
`Tests/SwiftTUITests/OffscreenFrameElisionRuntimeTests.swift`) →
`offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders` (lines 297/331),
`removalTransitionInterleavedWithElisionDrains` (line 840), plus the
setup-registration assertions in the off-screen-completion, on-screen, and
layout-animation tests.

**Was.** A mechanism independent of #2 (the frame-readiness clock did not cover
it). Each test mounts its probe and lets the view's `onAppear` register the
animation (`withAnimation`) or start a removal transition, then asserts the
intermediate state (`activeAnimationCount > 0` / `removingIdentities` non-empty)
before driving the elision under test. That setup used the ASYNC driver
`renderPendingFramesAsync`, which suspends at `acquireFrameArtifactsAsync` and can
DROP a committed frame's tail under heavy parallel MainActor contention (the
`.skipped`/completed-frame-drop arm). When the onAppear-follow-up frame — the one
whose resolve registers the animation/removal — was dropped, registration never
happened and the setup assertion failed. Reproduced **8/8** under 28-process CPU
saturation against the full `SwiftTUITests` suite; passed 12/12 with the suite in
isolation even under CPU load — the drop needs the *full* suite's cross-suite
parallel MainActor contention, which is why #2's isolated 25/25 saturation did not
surface it.

**Fix.** Drive every SETUP phase (mount + the onAppear-follow-up settle, and the
post-removal border-appearance settle) with the SYNCHRONOUS driver
`renderPendingFrames`. It shares the exact same `applyAcquiredFrame` body but
renders straight-line — no suspension, no `.elided`/`.skipped` drop arm — so the
registration is deterministic. The elision path under test is unchanged: every
test still drives its deadline ticks through the ASYNC `renderPendingFramesAsync`.

**Verification.** **0/12 green under 28-process CPU saturation against the full
`SwiftTUITests` suite** — the identical harness reproduced the pre-fix flake 8/8.

### 5. `TaskReadsUnbodiedStateTests` — cross-variant probe-singleton clobber (+ exact-tick frame scrape) — FIXED 2026-07-01

**Tests.** `TaskReadsUnbodiedStateTests` (in
`Tests/SwiftTUITests/TaskReadsUnbodiedStateTests.swift`) → both `@Test` variants,
failing in the shared `runHeldProbe` helper at the
`terminal.frames.first { frameTick($0) == grabbedTick && frameOffset($0) != nil }`
`#require` (was line 102:23).

**Was.** Two compounding harness defects; no framework bug (the imperative
`@State` write/preservation path traced clean under instrumentation — every
same-graph write survived suspend/materialize/discard cycles via the
`stateMutationKeys` overlay).

1. **Shared probe singleton across concurrent variants.** The two `@Test`
   variants run CONCURRENTLY (Swift Testing default), interleaving on the
   MainActor, and both wrote grab bookkeeping to a shared `ProbeGrabState.shared`
   — each `runHeldProbe` also `reset()` it. Under CI-load interleaving, variant A
   could scrape its OWN terminal for variant B's `grabbedTick` (a tick A's
   terminal may never present) → `#require` nil. Diagnosed via an instrumented
   saturated soak whose "impossible" traces (a re-armed gesture one tick after a
   visible write; frames diverging from closure reads) turned out to be two
   interleaved run loops sharing one singleton and one stdout.
2. **Exact-tick frame scrape.** The helper read the grab-instant offset from the
   presented frame whose tick text equaled the grab tick, but the probe's `.task`
   loop advances `tick` on wall-clock 5 ms sleeps while frame presentation is
   CPU-bound — under load, presented frames skip ticks, so that exact frame may
   not exist even with per-run state.

Failed 5 of 8 completed Linux Repo Gate runs between `a210b7be` (the commit
introducing the suite) and `678cc78e` (runs 28484815303, 28538005691,
28540077189, 28545771222, 28548367581); interleaved commits passed, confirming
nondeterminism. Locally reproduced only as the mechanism-2/mechanism-1 hybrid
(3/25 under 28-process CPU saturation) after the scrape was replaced — the pure
CI signature needs slow-runner frame starvation.

**Fix.** (1) One `ProbeGrabState` INSTANCE per `runHeldProbe` call, passed into
the probe view — no cross-variant state at all. (2) Capture `offsetAtGrab` live
inside the gesture's `.onChanged` closure alongside `grabbedTick`, never from an
exact-tick frame; `offset` cannot advance after `isDragging` flips, so the
captured value is exactly what the frozen loop must hold. The regression signal
the suite pins (`finalOffset == offsetAtGrab`) is unchanged.

**Verification.** Structural: no shared state exists between the variants and
the failing `#require` no longer exists; every remaining `#require` is
guaranteed by the input script's completion conditions (the reader only reaches
EOF after the grab values are recorded and frames render past grab + 8). Soak:
0 failures across 35 saturated (28-process CPU load) + 10 isolated runs
post-fix; the pre-fix harness reproduced the cross-variant failure 3/25 under
the identical load.

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

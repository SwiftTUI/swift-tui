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
so treat a failure that is *not* listed here as real until evidence shows
otherwise.

---

## Active flakes

### 1. Run-loop `SIGSEGV` / `SIGBUS` memory corruption — `SwiftTUI/swift-tui#12`

**Signature.** A crash (`SIGSEGV` or `SIGBUS`) on `com.apple.main-thread` inside
run-loop / async-render code — observed sites include
`FrameTailRenderer.setRenderSuspensionHooks`, copying `DefaultRenderer`, and
`SendableLayoutWorkerProxy.layoutSubviews`. It is **memory corruption**: torn
pointers whose bytes are rendered text (em-dash `0xe28094…`, ASCII). That is a
concurrent writer corrupting main-thread-owned memory.

**Where it surfaces.** Whichever run-loop-building suite happens to be running
when the corruption lands — most often `InteractiveRuntimeTests`,
`PortalPrimitiveTests`, or `ActorIsolationSurfaceTests`. The toast test's
`duration: 0.01` (10 ms auto-dismiss) is the most reliable trigger under load.

**Characteristics.**
- **Load/timing-sensitive** and **not reproducible on demand**. It crashed 10/10
  in isolation under one load condition. After the machine was idle, it crashed
  0/30 isolated, 0/4 parallel, and 0/20 under deliberate CPU load.
- **Invisible to both AddressSanitizer and ThreadSanitizer** (both pass clean),
  which rules out simple heap use-after-free and TSan-visible races and points
  at unsafe-pointer / detached-task corruption.
- **Predates** the H1 off-screen-elision work (reproduces on `375dbbb5`). It is
  orthogonal to the render-pipeline optimizations.

**How to identify this flake.** Compare the crash site and signature with the
details above. Re-run the test. If it does not reproduce deterministically, it is
the flake. A real fix needs a forced-repro harness (widen the race window via
injected delays) — see issue #12 for the investigation and suspect seams.

**Repro instrument (2026-05-30).** A production-default-`nil` worker seam,
`FrameTailRenderHooks.beforeOverlayApply` (`FrameTailModels.swift`), fires on the
frame-tail worker immediately before the off-main overlay write. A test can park
the worker inside that window and race a concurrent main-actor read. Wired +
ordering-guarded by `Tests/SwiftTUITests/FrameTailOverlayApplyHookTests.swift`. To
serialize a repro run, set `SWIFTTUI_SWIFT_TEST_SERIALIZED=1` (gate seam → `--num-workers
1`). The `Boxed` copy-on-write path the seam brackets was judged *safe* under value
semantics (worker copies-on-write its own box. The shared `_BoxStorage` is
`Mutex`-guarded with atomic refcount).

**Identified off-main-reach paths now EXHAUSTED (2026-05-30).** Both static paths by
which a live `@MainActor` `ForEachIndexedChildSource` (its mutable `cache` dictionary
is the torn-byte corruptor candidate) was able to reach the off-main frame-tail worker are
**closed**:

- *Current-frame offload* — the eligibility scan forces a full
  `indexedChildSourceWorkerSnapshot` conversion (a live source has
  `canRunOnWorker == false`) before anything goes off-main, so the worker only ever
  sees the value-type snapshot.
- *Retained-reuse* — a 6-agent adversarial trace covered this path (workflow
  `w1u1xkuj0`).
  The one-shot/sync commit path **does** retain a live, unconverted source. The
  snapshot conversion requires `mode == .abortable`, which the one-shot path
  skips: `injectAnimations` → reconcile → `commitOneShotFrame` →
  `storeCommittedFrame` → `RetainedFrameIndex` stores the whole `ResolvedNode`.
  A later frame's off-main worker **does** read that retained source through
  `RetainedInvalidationSummary.init` → `source.identityRoot`, on the
  `swift-tui.frame-tail-renderer` queue. **But every
  reachable off-main accessor reads immutable `let` storage** (`identityRoot`,
  `measurementSignature`) under `MainActor.assumeIsolated` — a benign read (or a clean
  isolation trap), never a torn write. The sole mutator (`cache[index] = …` in
  `child(at:)`) is invoked only on the *current* node's source, which off-main is
  always the value-type snapshot — never the retained live source.
  `computeSupportsRetainedReuse` further returns `false` for any source-bearing node,
  so `isEquivalentFor*` is never even invoked on a source subtree. The mutable
  `LayoutProxyBox.cachedStates` is likewise unreachable (retained reuse returns cached
  values. It never calls `measureContainer`). This vector therefore **cannot produce
  #12's corruption signature** — the crash-repro build was cancelled rather than built.

**Consequence.** With both identified paths closed and the `Boxed` COW path judged
value-semantics-safe, **#12's corruption mechanism is currently unidentified**. Static
analysis has exhausted the named candidates. When #12 is re-prioritized, the
next step is *dynamic*. Reproduce the SEGV under load with the `assumeIsolated`
sites + eligibility scan annotated/under TSan — not another static repro harness.

**Instrumentation update (2026-06-26).** A first increment of that "annotate the
`assumeIsolated` sites" move has landed for one named suspect. The non-`Sendable`
custom-layout proxy `LayoutProxyBox` now routes every entry point through
`preconditionMainActor()` (an explicit `MainActor.preconditionIsolated`) **before**
the `assumeIsolated` (`CustomLayoutErasure.swift`). If that vector reaches code
off the frame-tail worker, it contradicts the static "unreachable" judgment.
It then crashes **deterministically with an attributable message naming the
cause**. It does not cause a silent torn write that reads as anonymous
corruption. It converts one
suspect seam from "judged safe by static analysis" into "self-reporting if the
analysis was wrong". The remaining `assumeIsolated` sites are still un-instrumented.
(Rationale: org-root `docs/proposals/2026-06-26-001-architecture-fragility-improvements-proposal.md`, opportunity #3.)

**Release-checked seams update (2026-07-02).** The 2026-06-26 note above is
superseded: every previously suspected seam is now **release-checked**, not just
the one.

- *Observation bridge* — `withObservationTracking`'s `onChange` hop routes
  through `withCheckedMainActorAccess("ObservationBridge.recordChange")`
  (`SwiftTUIViews/Environment/Observation.swift`), landed `39b7d739`.
- *`LayoutProxyBox`* — the local `preconditionMainActor()` described above was
  refactored into the shared release-checked helper
  `withCheckedMainActorAccess`
  (`SwiftTUICore/Support/CheckedMainActorAccess.swift`). It covers all five entry
  points (`247e4dc3`) after the deterministic off-main trap in `78417f02`.
  **Deleted 2026-07-06 (F11):** `Layout` now requires `Sendable` (and
  `Cache: Sendable`). Every custom layout runs through the `Mutex`-backed
  `LayoutWorkerProxy`. `LayoutProxyBox` and its unsynchronized `cachedStates`
  dictionary no longer exist. The suspect surface is gone by construction, not
  only guarded.
- *`FrameScheduler`* — redesigned lock-based and `Sendable`
  (`OSAllocatedUnfairLock` around all coalescing state, `Pipeline/Scheduler.swift`),
  landed `39b7d739` with `FrameSchedulerConcurrencyTests`. This closed the
  "raced `consumeReadyFrame`" mechanism the commit named as the suspected #1
  class.
- The sibling bridges (`IndexedChildSources` ×4, `LayoutDependentContent` ×2,
  the `.assumedMainActor` host frame bridge in `HostedRasterSurface`) are
  guarded in the same way (`247e4dc3`, `a2eec874`). The only bare `assumeIsolated`
  hops left in core targets are three deliberately-exempt pure read-recording
  scans in `Environment.swift`. Other bare hops are the Android-only `directWake`
  (`RunLoop.swift`) and the Android `@_cdecl` ABI entry points.

**New triage rule (2026-07-02).** Because every suspect seam now carries a
release-mode `preconditionIsolated` guard:

- a crash that presents as a **`preconditionIsolated` trap with an attributable
  accessor name** = the old mechanism, finally located — file it against the
  named seam.
- a **raw `SIGSEGV`/`SIGBUS`** now *falsifies* the `assumeIsolated`-race
  hypothesis class for the guarded seams. Treat it as evidence of non-race
  heap corruption and pursue it dynamically. For example, use `libgmalloc` and
  the release lane below. Do not perform more static seam audits.

The scheduled **Release Soundness Lane**
(`.github/workflows/release-soundness.yml`, `Scripts/release_soundness_lane.sh`,
added 2026-07-02) runs the flaky trio (`InteractiveRuntimeTests`,
`PortalPrimitiveTests`, `ActorIsolationSurfaceTests`) serialized in release
configuration as a `continue-on-error` step. This standing soak lets the
release-checked traps convert this flake into an attributable failure.

*Separate, real-but-benign finding.* The one-shot commit path stores a live
`@MainActor` source into retained state with no snapshot conversion
(`commitOneShotFrame` → `storeCommittedFrame`). It is harmless today (off-main reuse
only reads immutable storage) but is a latent soundness gap: if retained reuse ever
began calling `child(at:)` off-main, it becomes the corruptor. Optional
defense-in-depth: snapshot-convert in the one-shot commit path before
`storeCommittedFrame` (weigh against the full-tree recursion cost on every one-shot
commit). Full analysis: org-root `docs/reports/2026-05-30-flake-bcd-investigation.md`.

**Status (2026-07-07): DORMANT — watching via the daily soak.** No occurrences
have appeared since the seams became release-checked on 2026-07-02. Recent CI
failure logs contain no `SIGSEGV` or `SIGBUS` signatures. All recent gate
failures were the known MainActor-freeze timeout or genuine test failures.
Several heavy local load tests also did not reproduce the crash. Two of the
three historical crash sites no longer exist. F11 **deleted outright**
`SendableLayoutWorkerProxy` and the `LayoutProxyBox` corruptor candidate
(2026-07-06). The strongest suspect surface is gone by construction.

**Soak integrity note (2026-07-07).** The lane's flaky-trio step was
**inert from 2026-07-03 to 2026-07-07**. SwiftPM rejects `--num-workers`
without `--parallel`, so the script stopped after 130 ms. The
`continue-on-error` step still reported green. The statement "the soak has been
quiet" therefore had no value for that window. The command now uses
`--parallel --num-workers 1`. The
serialized flaky-trio soak is genuinely running from 2026-07-08 onward, and
the dormancy evidence above deliberately does not lean on the inert window.
Lesson: a signal-only (`continue-on-error`) step needs its own liveness
test — an instant argument-error failure is indistinguishable from a quiet pass
at the workflow-status level.

**Forced-repro retired (2026-07-07).** The parked-worker `beforeOverlayApply`
repro stays unlanded *by decision*, not backlog: its weaker target (the `Boxed`
COW path) was judged value-semantics-safe and the hook seam is already landed +
ordering-guarded. Its stronger target needed a layout-stage parking seam and
that target was deleted with F11. A new repro requires a new corruption
hypothesis, and none exists — the register's own conclusion stands: the pursuit
is dynamic. The soak's flaky arm now runs under glibc allocator guards
(`MALLOC_CHECK_=3`, `MALLOC_PERTURB_` — `release_soundness_lane.sh
--flaky-only`), so heap misuse traps near its source instead of surfacing as
anonymous torn bytes.

**Tracking.** The historical `SwiftTUI/swift-tui#12` reference predates the
public repository (no such issue exists there). **This register entry is the
tracker of record**. Re-open criteria:

- a **`preconditionIsolated` trap naming an accessor** = the old race class,
  finally located — file against the named seam.
- a **raw `SIGSEGV`/`SIGBUS`** (or an allocator-guard abort) = non-race heap
  corruption — the guard's trap site is the lead. Escalate locally on macOS
  with `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` on the flaky trio.

### 6. `FrameworkStressGestureScrollTests` — stress gesture scroll 025 nested takeover over-pans on Linux CI (resolved 2026-07-23)

**Signature.** "stress gesture scroll 025 nested takeover pans the leaf
scroll view" fails at `FrameworkStressGestureScrollTests.swift` with
`Expectation failed: (inner.value.y → 5) == 3` — the leaf scroll pane ends
two rows past the expected pan target after the nested takeover hand-off.

**Where it surfaces.** This flake occurs only in the `Linux repo gate (amd64)`
lane. It first occurred in the `0.1.5` release-window Repo Gate on 2026-07-13,
and the rerun passed. On 2026-07-18, it occurred at `6bce1644` and `8560d337`
before that day's fix batch. It also occurred at `feb28468`, alongside a 289 s
tap-composition test and a 300 s starvation-cap timeout. The last listed
occurrence was at the `0.1.7` release commit `70feb5cf`, in run 29655794779.
The same day's
`c6ccba5e` run escalated to the whole runtime-test lane timing out at
1200 s. The identical `5` vs `3` overshoot in every assertion-level firing
suggests a load-dependent extra-tick class (two additional momentum/settle
ticks landing before the assertion) rather than randomness.

**Why this is not treated as a product regression.** Every firing tree was
green on the macOS full gate. The arm64-native Linux container gate
(`mise run linux-gate`, worktree mode) passed in 337 s at `c6ccba5e`. This was
the exact tree whose amd64 lane had just timed out wholesale. The lane was red
at commits before and after the 2026-07-18 changes, with the same signature.
The amd64 runner class already hosts the quarantined TermUIPerf app-shell stall
(entry 2). This is runner-class degradation,
not a behavior change in the pans themselves.

**Resolution.** The test used `harness.drag`, which sent `.down`, `.dragged`,
and `.up` before reading the nested scroll offsets. The `.up` event can start
wall-clock momentum. On the slow amd64 runner, its first 33 ms tick advanced
the leaf by two more rows before the assertion. The test now sends `.down` and
`.dragged` directly. It asserts nested-route ownership at the end of the authored
drag, then sends `.up` for cleanup. The arm64 Linux worktree gate passed all
native lanes in 310 s with this boundary.

### 7. `GestureRunLoopDispatchTests` — Exclusive tap inter-tap window expiry under parallel-gate starvation — FIXED 2026-07-24

**Signature.** "Exclusive tap composition works through the full RunLoop
mouse path" fails with exactly `(counts.double → 0) == 1` plus
`(counts.single → 2) == 0`. Observed runs took about 279–284 s. Under heavy
parallel-gate starvation, the second press lands after the 350 ms inter-tap
window expires. The recognizer then emits two single taps instead of one
double tap.

**Where it surfaces.** The `Linux repo gate (amd64)` lane under the full
parallel `swift test` run. Firings: 2026-07-21 run 29871856849 (the
`0.1.15` tag, 284 s) and run 29878019612 (`a3581786`, 279 s) — the second
firing met entry 6's register-on-recurrence criterion (that entry's
`feb28468` companion observation was this same decomposition).

**Why this is not treated as a product regression.** The suite's waits are
signal-native, but the inter-tap window is wall-clock by design (F158: the
window resolves at recognizer construction). The test passes in isolation
and on every other lane. The failure only appears when the test itself is
starved for hundreds of seconds on the degraded amd64 runner class.

**Fix (2026-07-24).** The `interTapWindowOverride` seam was *already* in use
here. The test set a 120 s window, so both firings included the recommended
hardening. The 279–284 s starvation period
outlasted it. The 120 s came from the original gesture-composition commit
(`ac86232d`), not from a considered starvation budget.

Because the window is wall-clock by design (F158: it resolves at recognizer
construction), *any* finite budget races against gate load. The window is now
`.seconds(86_400)`, so no starvation outlasts one day. Nothing in the test waits
on expiry. A lone single tap is reported only after the window closes. The test
asserts `single == 0`, so the run loop still exits on input end. The test
completes in 0.015 s.

A local bite test demonstrated the mechanism without reproducing the
starvation. With the override at `.zero`, the test fails with
`(counts.double → 0) == 1` / `(counts.single → 1) == 0`, the same
decomposition signature. At `.milliseconds(1)` it still passes, because
locally both scripted presses land inside the same millisecond. That is why
this only ever fired on a starved runner, and why the window value — not the
event script — is the controlling variable.

---

### 8. `SwiftTUICoreTests` runner `SIGBUS` — recursive `DrawNode` array dealloc stack overflow — FIXED 2026-07-24

**Signature.** The swiftpm test-runner process for the `SwiftTUICoreTests`
lane dies with `signal code 10` (`SIGBUS`) mid-suite with **zero test
assertion failures**. Hundreds of tests report `passed`, and then the process
vanishes. The crash report (`~/Library/Logs/DiagnosticReports/
swiftpm-testing-helper-*.ips`) shows the faulting thread cycling
`destroy for DrawNode → swift_arrayDestroy →
_ContiguousArrayStorage.__deallocating_deinit → _swift_release_dealloc`
all the way down: **stack exhaustion while recursively releasing a deep
`DrawNode` children chain** (the deep-wrapper-chain layout stress fixtures
build ~2000-deep trees). Distinct mechanism from entry 1 (torn-pointer
corruption). The signal family is the same, but the producer differs. Compare
the faulting stack before you attribute the crash to either entry.

**Evidence it predates unrelated changes.** 2026-07-23: reproduced
identically at pristine `8415e3bb` (baseline worktree) and with the
`CommittedFreshness` refactor applied — same signal, same lane, ~690 tests
green before death in both. Also observed and baseline-A/B'd as
pre-existing during the 2026-07-23 Tab-wrap stamp-coherence session.
Load-dependent: historically intermittent, but reproduced 3/3 on this
machine that day.

**How to identify this flake.** Read the newest
`swiftpm-testing-helper` crash report. The recursive `destroy for
DrawNode` frames are the signature. If the faulting stack differs, treat
it as a new problem.

**Root cause and fix (2026-07-24).** A run with `--no-parallel` identified the
producer: the `DrawExtractorTraversalTests` case "deeply nested placed trees
extract without recursion limits". It built a tree with a depth of **2000**.
On a Swift Testing worker with a 512 KB stack, a bare `DrawNode` chain was safe
at depth 1950 and produced SIGBUS at depth 2000. The fixture was about 2% past
the limit. This explains why the failure was load-dependent and became
consistent after `DrawNode` grew. The same chain releases correctly at depths
2000 and 8000 on an 8 MB stack, which is the main-thread budget for a
runtime-owned draw tree. The problem was the test worker's stack budget, not a
product depth limit. No product change was required.

Fixed by capping that fixture to `1_024`, the depth every other deep-tree
stack-safety fixture already uses. The test keeps its teeth. *Recursive*
extraction exhausts the same worker stack at approximately depth 300. Thus,
1024 still falsifies a recursive extractor and leaves ~2× headroom below the
limit. All three runs passed with 668 tests where the lane had
failed in all three runs, including at a pristine baseline worktree.

If this signature returns, the type has grown enough to move the limit again.
Measure the limit before you change the depth. If the fixtures cannot shrink,
prefer iterative teardown for deep `DrawNode` arrays. This approach already
fixed deep construction paths in the WASI depth-capped chunked resolve and in
the iterative runtime-registration restore walks from `6431a966`.

### 9. `Run SwiftTUI runtime tests` — lane exceeds the 1200 s per-step gate cap under parallel load — FIXED 2026-08-09

**Signature.** The gate step `Run SwiftTUI runtime tests` is killed by the
`Scripts/test_all.sh` watchdog: `TIMEOUT: command timed out after 1200s.
terminating process tree rooted at pid …`, reported as `exit=124`. No test
reports a failure — the lane is cut off mid-run, so the log ends with
passing tests and a terminated process tree. Distinct from entries 1 and 8:
those are signals (SIGSEGV/SIGBUS), this is a watchdog kill with status 124.

**Where it surfaces.** The runtime lane is by far the largest single step
(2,816 tests / 284 suites). Observed hitting the 1200 s cap on **both**
platforms under full parallel gate load (2026-07-23), while passing solo in
~221 s. A second measurement on 2026-07-24 took **238.9 s** on macOS arm64
inside a passing `bun run test`. This is a ~5× local margin. Thus, the failure
appears only on a loaded runner and not on a developer machine.

**Why this reads as a budget problem, not a wedge.** The same lane completes
normally when it is not competing for cores. It takes about 221 s alone and
238.9 s inside a sequential gate. The cap is a fixed per-step wall clock, not
a progress test. A lane that runs 5× slower under contention is therefore
killed exactly like one that parked. The watchdog runs `dump_hang_diagnostics`
against the process tree before terminating it. Read that dump in the failing
run's log to tell a genuine park from slow progress, rather than assuming
either.

**How to identify this flake.** Look for `exit=124` and the
`TIMEOUT:` line for this specific step. If the step exits on a signal, or a
named test actually fails, it is not this entry.

**Resolution (2026-08-09, FIXED).** Neither candidate above was taken: splitting
the lane and raising its budget both leave a wall clock deciding whether a lane
is alive, so both would have moved the cliff rather than removed it. The
watchdog now bounds **silence** instead
(`Scripts/lib/step_watchdog.sh`): it samples the step's log and fires only when
nothing has been written for `SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS`. A lane
running 5× slower under contention keeps emitting per-test output and survives;
a parked lane emits nothing and still dies — sooner than before, because it no
longer has to burn the full cap first. `SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS`
(default 4× the idle bound) is the backstop for a step that livelocks while
still printing. Every existing caller keeps working: the env var's name and
default are unchanged, only its meaning is stricter about what "stuck" means.

**Second defect, found by the new self-test.** `kill_process_tree` was
recursive, and POSIX `sh` has no locals — each recursive call overwrote its
caller's `pid`, so the outermost `send_signal` named the *deepest descendant*
and the root of any tree with children was signalled never. A single-chain tree
(`swiftly` → `swift-test` → `xctest`) still had its leaf killed, which is why
the abort usually appeared to work; a step that respawns children, or a
multi-branch tree, survived the kill entirely and left `run_logged_command`
blocked in `wait` forever. The function is now iterative, signals the root first
so a supervisor cannot spawn a replacement mid-kill, and reaps descendants after.

**Regression cover.** `Scripts/check_step_watchdog.sh` (gate step *Self-test step
watchdog*) drives the real `run_logged_command` with synthetic slow, parked,
silent, and chatty-livelock steps under sub-second bounds — the whole file runs
in ~20 s. It was written before the fix and failed on both defects, and reverting
either one turns it red again. This entry's original note that "a fix cannot be
tested on an idle developer machine" was wrong: the *lane* cannot be, but the
watchdog's decision rule can, and that is where the flake lived.

---

### 10. `HostWireConformanceTests` — S3b detached-backlog observation interval closes before its tasks run — FIXED 2026-08-09

**Signature.** `Run SwiftTUIAndroidHost tests` fails with exactly one issue:

```
conformance-websocket-detached-backlog.jsonl:step 15: exact observation mismatch
  at .discardedInboundChunks[0].bytesBase64
  actual:   "HmNhcHM6eyJhY2NlcHRzRGVsdGFGcmFtZXMiOnRydWV9Cg=="
  expected: "HmNhcHM6eyJhY2NlcHRzRGVsdGE="
```

A second signature belongs to the same defect — same test, same step, a
different axis reached first (the comparator walks an unordered dictionary, so
which axis reports is itself arbitrary):

```
  at .acceptedClientInputs[0]     actual: <absent>   expected: "key:character:N:0\n"
  at .deliveredRecords[1]         actual: <absent>   expected: {baselineGen,epoch,gen,kind,raw}
```

**Original mechanism note — wrong, kept for the record.** This entry read the
first signature as a *reordering* of `discardedInboundChunks`, on the grounds
that `actual[0]` is the value the corpus expects at `[2]`. It is not. Those two
chunks are byte-identical (`\x1ecaps:{"acceptsDeltaFrames":true}\n`), and the
value actually appearing at `[0]` is a **third** occurrence of those bytes: the
runner's own bootstrap capability declaration from `init`, leaking out of setup
into the fixture's observation interval. Nothing was ever reordered.

**Mechanism (corrected 2026-08-09, FIXED).** Not a channel defect at all — a
harness one, and none of it is in `WebHostSceneChannel.discardedInboundChunks`.
The adapter's observation interval could close before a task it depended on had
been scheduled even once, so that task's events landed in the *next* interval or
nowhere. Four hops were at risk; every one was guarded by a *turn* budget, or by
nothing:

| hop | old guard | failure |
| --- | --- | --- |
| client yield → channel `receive` | `deliverToChannel`, 8192 turns — but two yields skipped it entirely (`init` bootstrap, `enqueueCapsForCurrentClient`) | bootstrap caps leak → `discardedInboundChunks[0]` |
| channel `yieldInbound` → gate pump | `take()`, 8192 turns | drain no-ops; whole bootstrap leaks (observed `pumped=0`) |
| reader → `InputEvent` stream → recorder task | none; `settle()`'s "activity stable for 2 turns" | `acceptedClientInputs[0]: <absent>` |
| channel output yield → delivery task | none; same `settle()` guess | `deliveredRecords[1]: <absent>` |

The root error is treating a turn budget as a bound. `Task.yield()` re-enqueues
the current task **without releasing its thread**, so on an oversubscribed
cooperative pool 8192 turns expire in milliseconds while the awaited task never
runs. Instrumentation caught exactly that: `yielded=2 pumped=0` — the channel
had yielded both bootstrap events and the gate's pump task had not executed
once.

**Resolution.** No wait in these adapters polls anything any more — each one
suspends on a signal the producer fires, per
[test synchronisation policy](#why-the-gate-is-otherwise-deterministic):

- **Hop 1** — `WebHostSceneChannel.waitForProcessedInboundCallbacks(atLeast:)`,
  an actor-hosted continuation resumed by `receive` itself, replaces the polled
  `processedInboundCallbackCount()`. `shutdown()` resumes stranded waiters.
  Every client-side yield now goes through `deliverToChannel`, so at most one
  client message is in flight and the drain's target is settled.
- **Hop 2** — the gate's `enqueue` fires a `ConditionSignal`; `take()` awaits
  "an event is queued, or the pump has reached the channel's yield count".
- **Hop 3** — no wait at all: the reader's `InputEvent` sink is created *and
  finished* inside a single drain, so iterating it yields exactly the buffered
  events and terminates. Complete by construction.
- **Hop 4** — `WebHostSceneChannel` gained `yieldedOutputRecordCount()`, the
  output-direction twin of `yieldedInboundEventCount()`; the adapter's delivery
  recorder fires a `ConditionSignal` and `settle()` awaits that count.

A first attempt bounded each wait in *time* (spin, then 1 ms sleeps) instead.
That worked — 0 / 80 and 0 / 48 — but `Scripts/check_test_sync_policies.sh`
correctly rejected it: a sleep-poll is still a clock, just a slower one. The
signal form has no bound at all, which is the point. A wedged producer now hangs
the step and is reported as a wedge, rather than being silently misread as
"nothing was produced".

**Verified 2026-08-09** in the arm64 Linux container (18 cores), against the
prebuilt test binary so no rebuild perturbs the load:

| tree | condition | rate |
| --- | --- | --- |
| before | sequential, 8 hogs | 1 / 12 fail |
| after hop 1 fixed only | sequential, 12 hogs | 3 / 40 fail |
| after hops 1–3 fixed | sequential, 12 hogs | 3–6 / 60 fail |
| **after (all four hops, signal-driven)** | **sequential, 12 hogs** | **0 / 60** |
| **after (all four hops, signal-driven)** | **interleaved, 12 hogs, 6 concurrent × 8 rounds** | **0 / 48** |

Each run carried a 300 s `timeout` so an unbounded waiter that wedged would be
counted as a failure rather than silently inflating the wall clock. None fired.

The interleaved condition is the one the 2026-07-31 table below measured at
40 / 40 fail. Each partial fix only moved the failure to the next unguarded
hop, which is why the intermediate rows matter: the axis that reports is
arbitrary, so a lower rate on one axis is not progress unless every hop is
closed.

**Load-sensitive, and pre-existing.** Measured 2026-07-31 in the arm64 Linux
container, `--filter HostWireConformanceTests`:

| condition | pinned 0.4.5 tree (`7f4908ee`) | tree with WP-1 input stamping |
| --- | --- | --- |
| sequential, moderate load | 4 / 30 fail | 12 / 30 fail |
| interleaved, heavy load | **40 / 40 fail** | **40 / 40 fail** |

The interleaved run is the controlled one — both arms in one container,
alternating, so load and time are shared. At 40/40 on **both**, the defect is
plainly independent of any WP-1 change. The earlier 4-vs-12 split is sampling
noise across two differently-loaded sessions, not a signal. A full head-mode
container gate on an otherwise idle machine passes this lane, which is why the
entry had gone unrecorded.

**If this fires again.** Treat it as a real regression, not this entry. The
corpus was deliberately *not* weakened: making the expectation order-insensitive
(a multiset keyed by `(token, bytes, reason)`) was rejected, because on the
corrected mechanism it would have hidden the defect rather than removed it — the
bytes were never out of order, an interval boundary was in the wrong place. Do
not re-record the corpus against one lucky interleaving either. The lesson
generalizes past this suite: **a turn budget is not a bound**. Any wait spelled
`for _ in 0..<N { await Task.yield() }` is a busy-wait with a random timeout;
wait on a condition, bounded by time.

### 11. `FrameworkStressGestureScrollTests` — stress gesture scroll 024 nested-control pan overshoots on Linux CI (resolved 2026-08-01)

**Signature.** "stress gesture scroll 024 nested control yields only after
scroll threshold" fails with `Expectation failed: (position.value.y → 5) == 3`
— the same two-row `5` vs `3` overshoot as entry 6, in the same suite, on the
`Linux repo gate (amd64)` lane.

**Firings.** 2026-07-31 at `76f01d0b` (run 30666881062) and 2026-08-01 at
`9a25004b` (run 30681771490). Both trees were green on the macOS gate and the
arm64 Linux container worktree gate.

**Mechanism and resolution.** Identical to entry 6: the test drove the pan
with `harness.drag`, whose trailing `.up` can start a wall-clock momentum
tick. On the slow amd64 runner the first 33 ms tick advanced the pan two more
rows before the assertion. The test now sends `.down` and `.dragged`, asserts
the activation-threshold outcome, then sends `.up` for cleanup — the entry-6
boundary.

### 12. amd64 runner-class degradation since 2026-07-29 — timing-sensitive suites turned deterministically red

**Signature.** `Linux repo gate (amd64)` was red on every run from 2026-07-29
at 01:24. The last green run was `b9100b145` on 2026-07-28 at 23:52. In every
failure, three `RunLoopInputEndedTests` exceeded the old 60 s suite limit and
finished after 84–112 s. Most runs also had the visible-screen transcript
failure, with zero bytes in its old 100 ms window. Some runs had the momentum
overshoots from entries 6 and 11.

**Why this is environmental, with direct evidence.** The commit window
between the last green and the first red (`b9100b145..9b4d82a64`) contains
only a docs commit and a public-API-inventory script commit. The decisive
experiment: rerunning the last-green run itself (`gh run rerun 30409356099`,
2026-08-01) — identical tree, identical workflow — reproduced the
`RunLoopInputEndedTests` trio plus a scroll-024 firing on unchanged code.
The arm64 Linux container gate and macOS gate stayed green throughout.

**Response.** Timing-sensitive suites use condition-based or widened boundaries
instead of wall-clock optimism. `RunLoopInputEndedTests` moved to the five-minute
cadence-suite hang bound. The visible-screen test pre-seeds its PTY before it
arms the wait (entry-6/11 fixes cover the momentum class).
A suite that still exceeds the five-minute bound on this runner class is a
real wedge, not this entry.

---

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
that migration). The identical suite passes on macOS arm64 in isolation.
2026-08-05: one firing observed on macOS arm64 *inside a full local repo
gate* (parallel-lane load); the same gate's previous run and an immediate
isolated rerun both passed 4/4 — treat a single in-gate firing on a loaded
arm64 host as this entry, not a new regression. It also passes in
the arm64-native Linux container (`swiftly run swift test --package-path
Tools/TermUIPerf` inside the linux-gate image), including after the 2026-07-13
progress-gated-deadline hardening. Thus, this runner class has a genuine
no-frame stall, not a slow-runner deadline miss.

**Why this is not treated as a product regression (yet).** The swift-tui
Repo Gate runs the full menu/presentation suite on the same amd64 runners
and is green. The stall is specific to the TermUIPerf harness path
(`PerfTerminalHost` + scripted click dispatch under `.sync` render mode).
Suspect window: the 2026-07-11 stress-campaign batch (presentation
dispatch / recognizer adoption / hover re-root routing changes).

**Quarantine.** The workflow sets
`SWIFTTUI_PERF_SMOKE_SKIP=example-app-shell-workflow` (consumed by
`ScenarioSmokeTests`). Every other scenario stays covered on amd64, and the
app-shell scenario stays covered on arm64/macOS. Remove the skip when this
entry is closed.

**How to investigate.** Reproduce on an amd64 host (or emulation) with
`swiftly run swift test --package-path Tools/TermUIPerf --filter
ScenarioSmokeTests`. Instrument with the run-loop hang diagnostics
(`SWIFTTUI_HANG_DIAGNOSTICS`) to capture where the loop parks after the
close-menu click. Bisect the 2026-07-11 window if it reproduces.
2026-07-21 update: a Rosetta amd64 container (`docker run --platform
linux/amd64 swift:6.3.1` with the tree rsync'd out) deterministically
reproduced the *other* amd64-only quiet stall, the stack-lean cadence
lane. Observation draft-window deafness caused that stall, which is now fixed.
Use the same container recipe to re-test this scenario. Note that this harness
runs `.sync` render mode, where the draft-window mechanism does not apply by
design. Treat that fix as untested against this entry until the
container run says otherwise.

### 3. `OffscreenFrameElisionRuntimeTests` — off-screen deadline tick (real-time deadline race) — FIXED 2026-05-30

**Test.** `OffscreenFrameElisionRuntimeTests` →
`offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders`, in
`Tests/SwiftTUITests/OffscreenFrameElisionRuntimeTests.swift`.

**Was.** Under heavy parallel test load it failed at one of three assertions
(which one varied run-to-run): the in-flight `repeatForever` read
`activeAnimationCount == 0`. The loop appeared not to reschedule
(`hasPendingFrame` false). Or `elidedFrameCount` advanced an extra frame after
the on-screen invalidation. The async drain consumed frames at the real
`.now()` through `scheduler.consumeReadyFrame(at: .now())`. Under load, the
off-screen `repeatForever` rescheduled its animation deadline at
`now + minimumLeadTime`. That deadline became ready between the test's
scheduler operations. The drain then consumed an unexpected extra frame and
changed the test's exact `elidedFrameCount` equality. Proven pre-existing: failed identically on `main`
with zero retained reuse (3/3 under full-gate load on `3aaa8282`), independent of
the H2 work. Passed in isolation.

**Fix.** Two parts:
1. **Injectable frame clock.** `RunLoop.frameClock` (default real `.now()`, and
   named `frameReadinessClock` when this flake was fixed) supplies the instant
   both frame drivers compare against pending scheduler deadlines
   (`consumeReadyFrame(at:)`). Production behaviour is unchanged. A runtime test
   can pin it to drive virtual time. The seam has since widened from readiness
   to the whole frame: it is sampled once per frame and carried as
   `frameInstant`. Real-time *waiting* (the event-pump sleeps,
   `waitForPendingFrame`) still uses the wall clock.
2. **Pinned-instant test.** The test freezes the clock to a single `frozenNow`
   captured before any frame is consumed. Every deadline the off-screen
   animation auto-reschedules lands at the real future (`> frozenNow`). Thus,
   the drain cannot see it. Only the test's explicit deadline/invalidation
   requests drive frames. This makes the elision/present counts deterministic. The
   one real-clock assertion (`hasPendingFrame(at: .now() + 100 ms)`) became
   `nextWakeInstant(after: frozenNow) != nil` — the load-independent statement of
   the same "loop is not frozen" invariant.

**Verification.** 11/11 suite green in isolation. **25/25 green under 18-core CPU
saturation** (the original failed 3/3 under full-gate load). Deterministic by
construction — no timing window remains.

> **Follow-on (#3 below).** The clock fix above closed the deadline-drift race.
> The same suite had a *second, independent* flake: the onAppear registration
> drop. The isolated 25/25 saturation run did not expose it (it needs the full
> suite's cross-suite MainActor contention). Fixed 2026-05-31.

---

### 4. `OffscreenFrameElisionRuntimeTests` — onAppear registration dropped by the async driver during setup — FIXED 2026-05-31

**Tests.** `OffscreenFrameElisionRuntimeTests` (in
`Tests/SwiftTUITests/OffscreenFrameElisionRuntimeTests.swift`) →
`offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders` (lines 297/331),
`removalTransitionInterleavedWithElisionDrains` (line 840), plus the
setup-registration assertions in the off-screen-completion, on-screen, and
layout-animation tests.

**Was.** A mechanism independent of #2 (the frame-readiness clock did not cover
it). Each test mounts its probe. The view's `onAppear` then registers the
animation (`withAnimation`) or starts a removal transition. Before it drives the
elision, the test asserts the intermediate state (`activeAnimationCount > 0` /
`removingIdentities` non-empty). That setup used the ASYNC driver
`renderPendingFramesAsync`, which suspends at `acquireFrameArtifactsAsync` and can
DROP a committed frame's tail under heavy parallel MainActor contention (the
`.skipped`/completed-frame-drop arm). When the onAppear-follow-up frame — the one
whose resolve registers the animation/removal — was dropped, registration never
happened and the setup assertion failed. Reproduced **8/8** under 28-process CPU
saturation against the full `SwiftTUITests` suite. The suite passed 12/12 in
isolation, even under CPU load. The drop needs the *full* suite's cross-suite
parallel MainActor contention. Thus, #2's isolated 25/25 saturation did not
expose it.

**Fix.** Drive every SETUP phase (mount + the onAppear-follow-up settle, and the
post-removal border-appearance settle) with the SYNCHRONOUS driver
`renderPendingFrames`. It shares the exact same `applyAcquiredFrame` body but
renders straight-line — no suspension, no `.elided`/`.skipped` drop arm — so the
registration is deterministic. The elision path under test is unchanged: every
test still drives its deadline ticks through the ASYNC `renderPendingFramesAsync`.

**Verification.** **Zero failures in 12 runs under 28-process CPU saturation
against the full `SwiftTUITests` suite.** The identical harness reproduced the
pre-fix flake in all eight runs.

### 5. `TaskReadsUnbodiedStateTests` — cross-variant probe-singleton clobber (+ exact-tick frame scrape) — FIXED 2026-07-01

**Tests.** `TaskReadsUnbodiedStateTests` (in
`Tests/SwiftTUITests/TaskReadsUnbodiedStateTests.swift`) → both `@Test` variants,
failing in the shared `runHeldProbe` helper at the
`terminal.frames.first { frameTick($0) == grabbedTick && frameOffset($0) != nil }`
`#require` (was line 102:23).

**Was.** Two compounding harness defects. No framework bug (the imperative
`@State` write/preservation path traced clean under instrumentation — every
same-graph write survived suspend/materialize/discard cycles via the
`stateMutationKeys` overlay).

1. **Shared probe singleton across concurrent variants.** The two `@Test`
   variants run CONCURRENTLY (Swift Testing default), interleaving on the
   MainActor, and both wrote grab bookkeeping to a shared `ProbeGrabState.shared`
   — each `runHeldProbe` also `reset()` it. Under CI-load interleaving, variant A
   sometimes scraped its OWN terminal for variant B's `grabbedTick`. Variant A's
   terminal did not always present that tick, which produced `#require` nil. An
   instrumented saturated soak had "impossible" traces: a re-armed gesture one tick after a
   visible write. Frames diverging from closure reads) turned out to be two
   interleaved run loops sharing one singleton and one stdout.
2. **Exact-tick frame scrape.** The helper read the grab-instant offset from the
   presented frame whose tick text equaled the grab tick. However, the probe's
   `.task` loop advances `tick` on wall-clock 5 ms sleeps. Frame presentation is
   CPU-bound. Under load, presented frames skip ticks, so that exact frame does
   not always exist even with per-run state.

Failed 5 of 8 completed Linux Repo Gate runs between `a210b7be` (the commit
introducing the suite) and `678cc78e` (runs 28484815303, 28538005691,
28540077189, 28545771222, 28548367581). Interleaved commits passed, which
demonstrated nondeterminism. Local runs reproduced only the mechanism-2/mechanism-1 hybrid
(3/25 under 28-process CPU saturation) after the scrape was replaced — the pure
CI signature needs slow-runner frame starvation.

**Fix.** (1) One `ProbeGrabState` INSTANCE per `runHeldProbe` call, passed into
the probe view — no cross-variant state at all. (2) Capture `offsetAtGrab` live
inside the gesture's `.onChanged` closure alongside `grabbedTick`, never from an
exact-tick frame. `offset` cannot advance after `isDragging` flips, so the
captured value is exactly what the frozen loop must hold. The regression signal
the suite pins (`finalOffset == offsetAtGrab`) is unchanged.

**Verification.** Structural: no shared state exists between the variants and
the failing `#require` no longer exists. Every remaining `#require` is
guaranteed by the input script's completion conditions (the reader only reaches
EOF after the grab values are recorded and frames render past grab + 8). Soak:
0 failures across 35 saturated (28-process CPU load) + 10 isolated runs
post-fix. The pre-fix harness reproduced the cross-variant failure 3/25 under
the identical load.

---

## Triage checklist

When `bun run test` reports a failure:

1. **Identify the failing test + assertion** (the gate prints a `rerun:` command
   per failed step).
2. **Match against an entry above** — same test, same assertion family, same
   crash site? If yes, it is the known flake.
3. **Re-run in isolation** with the printed `--filter`. The active flake (#1) is
   load/timing-sensitive and does not reproduce deterministically in isolation.
   A deterministic isolated failure therefore means it is *not* the flake and is
   real.
4. **Never** wave off an unmatched signature as "probably the flake". Add a new
   entry here only after you have evidence of load or timing sensitivity (passes isolated,
   fails under load) and ruling out a real defect.

---

## Why the gate is otherwise deterministic

So that a *new* flake stands out, the suite deliberately avoids the usual
sources of test flake:

- **Poll-free synchronisation.** Runtime/animation tests use the condition-based
  primitives in `Tests/Support` instead of `sleep`/polling — see
  `SwiftTUITestSupport.docc` ("Poll-free synchronisation primitives for
  deterministic, flake-resistant tests") and `Synchronising-Without-Polling.md`.
- **Injectable frame clock.** A runtime test that drives animation deadlines can
  pin `RunLoop.frameClock` to a frozen instant. The loop then decides frame
  readiness against virtual time instead of the wall clock. Self-rescheduled
  animation deadlines land in the real future relative to the frozen instant.
  They stay invisible to the drain, so CPU contention cannot perturb frame
  counts (see fixed flake #2). The seam is sampled once per frame and carried as
  `frameInstant`. Thus, a pinned clock governs the whole frame, including the
  animation stamp and the scheduling gates. It does not govern only readiness.
- **No wall-clock budget assertions in the gate.** The one wall-clock
  blunder-detector (`RenderPipelineStructureTests.composedRenderTimeBudget`) is
  opt-in behind `SWIFTTUI_RUN_WALLCLOCK_PERF` and **skipped** by the repo gate. Do
  not tighten its 2× multiplier. Timing-sensitive coverage instead uses
  hang-detection against the CI job timeout. For example,
  `FrameSchedulerIntentCoalescingTests` waits on a far-future deadline) or
  deterministic state-machine tests. For example, `InputBatchingResponsivenessTests`
  does not try to reproduce the wall-clock-timing bug it guards).
- **Real-perf measurement lives outside the gate** in `Tools/TermUIPerf`, run on
  schedule / manual dispatch, never as a pass/fail wall-clock assertion.

The repo gate has **no automatic test retries** — `Scripts/test_all.sh` only
prints a `rerun:` command for a failed step. A green gate therefore means the
flakes above did not fire on that run, not that flakiness was retried away.

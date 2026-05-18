# Pipeline Driver Follow-up Audit

**Status:** Findings document, opened 2026-05-17. A re-audit of the render
driver after the pipeline-driver hardening roadmap (Stages 0–8) reported the
original [`PIPELINE_DRIVER_AUDIT.md`](./PIPELINE_DRIVER_AUDIT.md) as 14/17
findings resolved. This document verifies those resolutions against the code
that ships today and catalogues debt the original audit did not reach.

**Scope:** the runtime render driver and its orchestration —
`RuntimeRenderPipeline`, `DefaultRenderer` (`SwiftTUI.swift`),
`FrameTailRenderer`, the `RunLoop` frame driver (`RunLoop+Rendering.swift`),
the late-preference and focus-sync loops, completed-frame drop classification,
and the scheduler. It does **not** re-audit the phase-product types; the
original audit and [`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md)
already found those sound, and that still holds.

**Relationship to the original audit:** the original audit is an honest and
sharp document. This follow-up does not retract it. It records that the
*resolution mechanism* applied to it — Stages 0–8 — closed several findings by
rewording documentation rather than changing the driver, and that one drift
defect worse than any of the original 17 shipped during the same period.

---

## Summary of findings

| # | Finding | Severity | Class | Resolution mechanism |
| --- | --- | --- | --- | --- |
| F1 | `RuntimeRenderPipeline` is ceremony: phase order is asserted by prose and a `precondition`, not composition | Critical | Architecture / dead code | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F2 | `renderPendingFrames` and `renderPendingFramesAsync` are a ~355/~470-line copy-paste fork — the original audit never looked at `RunLoop+Rendering.swift` | Critical | Duplication / drift | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F3 | Resolve still mutates six subsystems; "commit is the side-effect boundary" is still false; draft/discard is renamed checkpoint/restore | Critical | Architecture | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F4 | Every async frame runs `commit` / `finalizeFrame` twice; correctness rests on total `ViewGraph` checkpoint fidelity with no mechanical guard | Critical | Correctness | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F5 | Cancellation is a 1 ms `Task.sleep` busy-poll on the main actor | High | Concurrency | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F6 | The "formalized pipeline" contains two nested bounded-fixpoint loops with underived magic constants, each rendering stale on overflow | High | Contract gap | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F7 | `FrameDropEligibility.Blocker` is still a ~24-flag enumerated correctness surface, with an add-then-subtract blocker pattern | High | Correctness surface | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F8 | Diagnostics cost is now mandatory: the `collectsDiagnostics` opt-out was deleted, so a full-tree `summarize` walk runs every frame | High | Performance | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F9 | `renderAsync` is one API with three concurrency semantics; the WASI synchronous path is untested on CI | High | Portability | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F10 | Three dirty-tracking signals (scheduler / `ViewGraph` / `RunLoop` state diff) must stay coherent by convention | Medium | Architecture | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F11 | The render-tail entry surface is still ~11 functions; sync/async/cancellable tail orchestration is triplicated | Medium | Duplication | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F12 | `RuntimeRenderStageName` is a `CaseIterable` enum used only as metadata, switched on by no control flow | Medium | Dead structure | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F13 | Raster damage gates painting internally but has no global diff to catch missed invalidation | Medium | Soundness | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |
| F14 | The original audit closes findings via documentation rewording; the doc corpus grows faster than load-bearing API | High | Governance | [code+test](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md) |

The linked
[`PIPELINE_DRIVER_RESOLUTION_LEDGER.md`](./PIPELINE_DRIVER_RESOLUTION_LEDGER.md)
is the current source of truth for remediation status and DoD commands.
`Scripts/check_pipeline_driver_resolution_ledger.sh` mechanically verifies that
the ledger is complete, non-`docs` for all current rows, connected to both audit
summary tables, and part of the `bun run test` policy phase.

---

## What the hardening roadmap genuinely fixed

This re-audit confirms the following original findings are legitimately resolved
in code, not just in prose:

- **Original Finding 1** — `Pipeline.swift` / `Renderer<Root>` is deleted. The
  dead formal pipeline no longer exists. ✅
- **Original Finding 6** — the hand-rolled `pthread` worker with a manually
  allocated 8 MB stack is gone. `FrameTailLayoutWorker`
  (`SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift`) is now a
  `DispatchQueue`-backed box on Darwin/Linux. The structured-concurrency
  escape-hatch violation is closed. ✅
- The phase-product types remain cleanly separated, `Sendable`, and well-owned.
  Coordinate-domain discipline is intact. The "computed vs. reused" diagnostic
  vocabulary is intact. None of that regressed.

The bar the project set for itself is high; the findings below are scored
against that bar.

---

## Finding F1 — `RuntimeRenderPipeline` is ceremony, not structure

The original audit's recommended fix **P1b** was: *"Make `DefaultRenderer` drive
a composed phase abstraction so the phase order is enforced by composition
rather than asserted by prose."* The audit table marks this **resolved by
Stage 3**. The code does not support that claim.

`RuntimeRenderPipeline` (`SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift`)
is:

```swift
struct RuntimeRenderPipeline: Sendable {
  var headStage: RuntimeFrameHeadStage          // never read anywhere
  var stageOrder: [RuntimeRenderStageName] { .orderedComposition }  // constant

  init(stageOrder: [RuntimeRenderStageName] = .orderedComposition, ...) {
    precondition(stageOrder == .orderedComposition,
      "Runtime render pipeline stage order must stay canonical.")
  }
```

- `headStage` / `RuntimeFrameHeadStage.isTransactionalWhenAbortable`: assigned,
  **read by nothing** (verified by grep across `SwiftTUIRuntime`).
- `stageOrder` is a parameter whose only legal value is enforced by a
  `precondition`. It is configurability theater: it converts a compile-time
  invariant into a runtime crash.
- `renderOneShot` is `let d = animationInjection(draft); let l = recon(d, …);
  let t = tail(d, l); return commit(d, l, t)`. It threads **4–6
  caller-supplied closures**. The struct does not constrain what those closures
  do; it sequences whatever the caller passes.

So the "composed pipeline" is a struct holding dead config that threads
closures. Phase order is still asserted by prose in
[`ARCHITECTURE.md`](../ARCHITECTURE.md); the only new enforcement is
crash-on-mismatch. **P1b was reported done; what shipped is P1a (rewording)
plus a hollow struct.**

A formalized pipeline requires order to be enforced by a mechanism —
composition, a sequenced executor over a `[Stage]`, or a type that makes an
out-of-order frame unrepresentable. A `precondition` makes it *crash*; prose
makes it *convention*.

---

## Finding F2 — The worst duplication in the codebase is undetected by the original audit

Original Finding 3 ("sync and async heads are ~120 duplicated lines") was scoped
to `SwiftTUI.swift` and marked resolved. The original audit **never examined
`RunLoop+Rendering.swift`**, where the actual frame driver lives — and that file
contains a far worse fork:

| Function | Approx. lines | Role |
| --- | --- | --- |
| `RunLoop.renderPendingFrames` | 95–448 (~355) | synchronous frame driver |
| `RunLoop.renderPendingFramesAsync` | 689–~1160 (~470) | async frame driver |

The two bodies are near-identical: the focus-sync convergence `while` loop,
pointer-capture release, the ~90-field `FrameDiagnosticRecord` construction, the
animation-deadline rescheduling block, and lifecycle carry-forward merging are
all copy-pasted. A change to the focus-sync gate, or a new diagnostic field,
must be made in both places and **will silently desync if one is missed.**

This is precisely the drift class
[`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md) exists to
prevent, sitting in the hottest file in the runtime, unflagged by 17 findings
and 8 hardening stages. Extracting one frame-driver body parameterized by a
render strategy is the single highest-value cleanup available.

---

## Finding F3 — "Commit is the side-effect boundary" is still false

[`ARCHITECTURE.md`](../ARCHITECTURE.md) still states *"Commit is the main-actor
side-effect boundary."* `computeFrameHead` (`SwiftTUI.swift`) mutates, **before
commit**:

- `viewGraph` — `beginFrame`, `invalidate` / `invalidateAndQueueDirty`,
  `setRootEvaluator`, `setEvaluator`, `evaluateDirtyNodes`
- `frameState`, `frameInputs`
- `presentationPortalState`, `observationBridge`, `animationController`

The proof is `abortPreparedFrameHead` (`SwiftTUI.swift`), which rolls back six
things: `registrationDraft.discard()`, `graphDraft.discard(from:)`,
`presentationPortalDraft.discard()`, `observationDraft?.discard()`,
`animationDraft.discard()`, `frameState.restoreCheckpoint(...)`, and
`frameInputs.clear()`.

Original Finding 4 claims this is *"Resolved … prepared heads now use
draft/commit boundaries and the declared rollback-effect model was removed."*
Renaming `checkpoint` to `draft` does not make resolve pure. It is still
transactional rollback of six mutable subsystems, which is only necessary
*because* resolve has side effects. ADR
[`0004-frame-head-abort-reverted.md`](../decisions/0004-frame-head-abort-reverted.md)
records that a genuinely pure abortable head was attempted and reverted; the
draft/discard machinery is the residue of that failure. The architecture doc
was reworded to stop describing the residue.

---

## Finding F4 — Every async frame runs `commit` twice

`previewCompletedFrameCommit` (`SwiftTUI.swift`) runs the full commit planner —
`viewGraph.finalizeFrame` (which emits lifecycle events) plus
`commitPlanner.plan` — against a checkpoint, then restores it:

```swift
let checkpoint = viewGraph.makeCheckpoint()
defer { viewGraph.restoreCheckpoint(checkpoint) }
... finalizeFrame ... commitPlanner.plan ...   // preview, discarded
```

This preview exists only to classify droppability. If the frame is not dropped,
`commitCompletedFrameCandidate` runs `finalizeFrame` + `plan` **again** for
real.

The correctness of the entire async path now rests on
`ViewGraph.makeCheckpoint` / `restoreCheckpoint` being a total, perfect snapshot
of all mutable graph state — including the lifecycle bookkeeping `finalizeFrame`
touches. Any `ViewGraph` field added later that the checkpoint does not capture
produces a silently corrupt graph after a previewed-then-committed frame. This
is a high-blast-radius invariant with no mechanical test.

**Recommended guard:** a test that fails when a stored property is added to
`ViewGraph` without corresponding checkpoint coverage, plus a focused test that
asserts `makeCheckpoint` → mutate → `restoreCheckpoint` is identity over the
full graph state.

---

## Finding F5 — Cancellation is a 1 ms busy-poll on the main actor

`renderCancellableFrameTailLayoutStage` (`SwiftTUI.swift`):

```swift
while cancellationToken.currentState == .queued {
  if await shouldCancelQueued(), cancellationToken.cancelBeforeStart() {
    layoutTask.cancel()
    return .cancelledBeforeStart
  }
  try? await Task.sleep(for: .milliseconds(1))
}
```

This is a hand-rolled condition variable. It adds up to 1 ms of latency to every
cancellable frame's tail-start, burns scheduler wakeups, and ties cancellation
correctness to a sleep granularity. Structured concurrency provides
`withCheckedContinuation` and `AsyncStream` for exactly this signalling pattern.
For a render mode whose entire purpose is latency reduction, a polling loop in
the hot path is self-defeating.

---

## Finding F6 — The pipeline contains two nested bounded-fixpoint loops

A pipeline advertised as "well-defined, formalized" contains two
iterate-to-fixpoint loops, each with an underived magic bound and a
give-up-and-render-stale escape branch:

1. **Late-preference reconciliation** —
   `LatePreferenceReconciliationPolicy.toolbarHostRuntimeBound` sets
   `maximumRelayoutPasses = 4` (`SwiftTUI.swift`). The code comment admits it is
   a placeholder: *"Keep the historical runtime bound explicit until more
   late-preference consumers justify a derived dependency-depth bound."* Up to
   4× measure+place per frame. On overflow, `warnAndCommitLastLayout` renders
   stale geometry and logs `latePreferenceReconciliationLimitIssue`. ADR
   [`0018-late-preference-reconciliation-bound.md`](../decisions/0018-late-preference-reconciliation-bound.md)
   records the bound but not a derivation.

2. **Focus-sync convergence** — `FocusSyncRerenderBudget(maximumRerenders: 16)`
   (`RunLoop+Rendering.swift`). On overflow, `assertionFailure` followed by
   *"present the latest available tree and continue"* — again, a stale tree.

Preference-fed-back layout and focus reconciliation are genuinely fixpoint
problems; the loops are not the defect. The defect is that they contradict the
"phases run once, in order" model the docs sell, and that both bounds are magic
constants with a documented-as-placeholder status.

---

## Finding F7 — Frame-drop eligibility remains a ~24-flag correctness surface

Original Finding 8 was marked *"resolved by Stage 5."*
`FrameDropEligibility.swift` (`SwiftTUICore/Pipeline/`) is still ~14 KB of
`CaseIterable` blocker flags. Droppability is computed by enumerating every
reason a frame *cannot* be dropped; the correctness surface is the power set of
those flags and grows one dimension per feature. A forgotten blocker silently
drops a frame carrying a real lifecycle or task event.

Compounding it, the add-then-subtract pattern: `frameTailCommitDropBlockers`
(`SwiftTUI.swift`) inserts `.retainedLayoutBaseline` and
`.retainedRasterBaseline`, and `completedFrameEligibility` then **subtracts the
same two back out**. A blocker set that is populated in one function and
partially un-populated in another is a bug magnet.

The original audit's **P6** — derive droppability from a small closed property
of `CommitPlan` ("the plan carries no observable side effect") — is the right
shape and was not adopted. At minimum, add a test that fails when a new
committed-side-effect type ships without a corresponding `Blocker`.

---

## Finding F8 — Diagnostics cost is now mandatory and per-frame full-tree

Original Finding 10's resolution **deleted the `collectsDiagnostics` opt-out**.
`FrameDiagnostics.summarize` — which walks the resolved, measured, placed,
semantic, and draw trees — now runs every frame, unconditionally. When a
diagnostics logger is attached, a `FrameDiagnosticRecord` of ~90 fields is
constructed per frame (twice, given F2).

The fix for "a dual code path that could diverge" was to delete the cheap path
and make every frame pay. For a TUI targeting interactive frame rates,
mandatory full-tree instrumentation walks are a real CPU regression presented as
a cleanup. The correct shape is an incremental `summarize`, or a restored cheap
path that cannot diverge because it is the same path with instrumentation
elided.

---

## Finding F9 — One async API, three concurrency semantics

`renderAsync` is genuinely concurrent on Darwin and Linux (a `DispatchQueue`
worker in `FrameTailLayoutWorker`) and a synchronous inline no-op on WASI (the
`#else` branch; ADR
[`0020-off-main-layout-worker-concurrency.md`](../decisions/0020-off-main-layout-worker-concurrency.md)).
It is now documented, but it remains one signature with divergent runtime
behavior, and the Darwin/Linux CI cannot exercise the WASI path. "Documented" is
not "tested": a regression in the synchronous fallback would not be caught.

---

## Finding F10 — Three dirty-tracking signals must agree by convention

Frame freshness is decided by three separate mechanisms that must stay coherent:

- the `FrameScheduler`'s coalesced invalidation set (`Scheduler.swift`);
- `ViewGraph`'s dirty queue and `hasDirtyWork` gate, consulted by
  `computeFrameHead`'s `canUseSelectiveEvaluation` branch, which can skip
  evaluation entirely and set `resolveDuration = .zero`;
- `RunLoop`'s own `previousRenderedState` diff, which calls
  `renderer.forceRootEvaluation()` when state changed or on a focus-sync
  rerender (`RunLoop+Rendering.swift`).

Nothing structural keeps the three in sync. A view that becomes stale through a
path one mechanism tracks but another does not will either over-render or
present stale content, and the failure is not localized to any single type.

---

## Finding F11 — The render-tail entry surface is still combinatorial

Original Finding 9 (13 entry points across the {sync, async, cancellable,
reconciled} cube) was marked *"resolved by Stage 3."* `computeFrameHead` is
correctly shared now, but `SwiftTUI.swift` still exposes, on the tail path:
`render`, `renderAsync`, `renderAsyncCancellable`, `renderView`,
`renderViewAsync`, `renderFusedFrameTail`, `renderAsyncFusedFrameTail`,
`renderCancellableFusedFrameTail`, `renderLayoutResolvingLatePreferences`,
`renderLayoutResolvingLatePreferencesAsync`, `renderFrameTailLayoutAsync`, and
`renderFrameTailAsync`. The sync/async/cancellable tail orchestration is
triplicated — each ~30–80 lines of closure wiring. The cross product is still
managed by duplication, not composition.

---

## Finding F12 — `RuntimeRenderStageName` is metadata wearing a type

`RuntimeRenderStageName` is a `CaseIterable` enum (`head`, `animationInjection`,
`latePreferenceReconciliation`, `fusedFrameTail`, `commit`). It is consumed only
as diagnostic metadata and by the F1 `precondition`. No control flow switches on
it. An enum that nothing dispatches on is documentation in a type's clothing; it
gives the appearance of a staged executor without being one.

---

## Finding F13 — Raster damage gates painting but cannot self-correct

`Rasterizer.rasterizeCollectingVisibleIdentities` consumes an optional
`PresentationDamage` and can skip subtrees outside the dirty row range. If
upstream invalidation fails to include a changed row, there is no global
previous-vs-current diff to discover the miss; stale pixels survive and the
frame still reports a successful raster product.

Damage is "advisory" for hosts but soundness-critical internally. The
`presentationDamage(...)` builder in `FrameTailRenderer` is conservative (it
returns `nil` to force a full repaint on many uncertain cases), which mitigates
the risk in practice — but the dual role of damage as both an advisory hint and
an internal paint gate is unresolved (original Finding 14; P8 not adopted).

---

## Finding F14 — The audit is being used to retire findings, not fix them

This is the central process risk. The original `PIPELINE_DRIVER_AUDIT.md` marks
14 of 17 findings "Resolved." Tracing the resolutions:

- Findings **2, 7, 12, 16** were closed explicitly *by documentation* — *"docs
  now distinguish runtime composition from phase-product order,"* *"documented
  by Stage 6 as a compatibility boundary,"* *"resolved by Stage 8,"* *"resolved
  by Stage 0 source docs and Stage 8 architecture wording."* The code did not
  change; the doc was reworded to match it.
- Finding **1** is genuinely resolved (file deleted). ✅
- Finding **6** is genuinely resolved (`pthread` removed). ✅
- Finding **4** was "resolved" by renaming checkpoints to drafts — see F3.
- Finding **3** was resolved for `SwiftTUI.swift` while a worse instance shipped
  in `RunLoop+Rendering.swift` — see F2.
- Finding **12** (doc/process inversion: 36 docs, 39 plans, 38 proposals, 17
  ADRs for a pre-1.0 single-maintainer package) was "resolved by Stage 8" —
  which *added* documents (ADR-0019, the stage plans). The governance overhead
  is itself the debt, and the resolution grew it.

There are two ways to close a gap between a doc and the code: change the code,
or change the doc. Both turn the audit table green; only one reduces risk. An
audit process that accepts "resolved by documentation" as an outcome
indistinguishable from "resolved by code" will trend toward a fully-green table
and an unchanged driver — and the green table then becomes evidence against
re-investigation.

**Recommendation:** the audit table should record resolution *mechanism* as a
distinct column — `code`, `test`, or `docs` — so a green row means the driver
changed, not that the prose did.

**Current verification:** the remediation ledger linked from the summary table
is the canonical repository artifact for this process guard. It records the
current mechanism, executable DoD, and verifying commit for each finding, and it
keeps the historical independent re-audit separate from the current re-audit
status. `Scripts/check_pipeline_driver_resolution_ledger.sh` validates those
requirements and is wired into the repo policy phase so `bun run test` fails if
the ledger becomes incomplete, drifts away from the audit tables, or reports an
unresolved current re-audit row.

---

## Priority order

1. **F2** — extract a single frame-driver body parameterized by render strategy.
   Mechanical, independently valuable, removes the worst drift hazard, and
   de-risks the rest.
2. **F1 + F12** — either make `RuntimeRenderPipeline` genuinely enforce stage
   order (a sequenced executor over `[Stage]`), or delete the struct and its
   dead config and name it honestly as three orchestration functions. The
   current middle is the worst option.
3. **F5** — replace the busy-poll with a continuation-based signal.
4. **F4** — add a mechanical guard for `ViewGraph` checkpoint totality.
5. **F8** — restore a cheap diagnostics path or make `summarize` incremental.
6. **F7** — adopt P6: derive droppability from a closed `CommitPlan` property,
   or add the missing-blocker regression test.
7. **F14 (process)** — add a resolution-mechanism column to the audit table;
   stop counting documentation rewordings as driver fixes.

The encouraging part is unchanged from the original audit: the project's own
process already diagnosed most of this. The debt is not blindness — it is that
the resolution mechanism keeps aiming at everything except the driver. The
driver is still the unverified monolith. F2 is the cheapest place to start
changing that.

---

## Related docs

- [`PIPELINE_DRIVER_AUDIT.md`](./PIPELINE_DRIVER_AUDIT.md) — the original audit
  this document re-verifies
- [`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md) — hardens
  the phase-product types; still sound
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — the seven-phase claim and the
  "commit is the side-effect boundary" claim this audit tests
- [`ASYNC_FRAME_STALE_POLICY.md`](./ASYNC_FRAME_STALE_POLICY.md) — the
  completed-frame drop policy and blocker model behind F7
- ADR [`0019-composed-runtime-render-pipeline.md`](../decisions/0019-composed-runtime-render-pipeline.md)
  — the composed-driver record F1 tests
- ADR [`0004-frame-head-abort-reverted.md`](../decisions/0004-frame-head-abort-reverted.md)
  — the reverted pure-head attempt behind F3
- ADR [`0018-late-preference-reconciliation-bound.md`](../decisions/0018-late-preference-reconciliation-bound.md)
  — the magic-`4` bound in F6
- ADR [`0020-off-main-layout-worker-concurrency.md`](../decisions/0020-off-main-layout-worker-concurrency.md)
  — the WASI synchronous fallback in F9

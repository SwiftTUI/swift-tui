---
title: "refactor: pipeline driver hardening"
type: refactor
status: proposed
date: 2026-05-16
depends_on:
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/PIPELINE_BOUNDARY_HARDENING.md"
  - "../ASYNC_RENDERING.md"
  - "../HOST_RENDERING_PIPELINES.md"
  - "../ARCHITECTURE.md"
  - "../decisions/0002-seven-phase-pipeline-not-collapsed.md"
  - "../decisions/0004-frame-head-abort-reverted.md"
---

# Pipeline Driver Hardening Implementation Plan

> **For agentic workers:** This is a *staged roadmap*, not a bite-sized TDD plan.
> Each stage below must be expanded into its own detailed plan
> (`docs/plans/YYYY-MM-DD-NNN-<stage>-plan.md`) before execution, following the
> repo's plan format: current source anchors, failing/protective tests first,
> implementation steps, validation commands, and exit criteria. If your agent
> environment has plan/execution skills, use them; otherwise write the detailed
> plan directly. Stages are sequenced by dependency; do not start a later stage
> until its predecessor's exit criteria are met.

**Goal:** Close the gap between the *advertised* seven-phase render pipeline and
the *driver* that runs every frame, by making `DefaultRenderer` execute a
composed phase abstraction (audit proposal **P1b**) rather than a 260-line
imperative monolith — and harden the adjacent contracts (concurrency, raster
soundness, frame-drop surface, presentation seam) the audit flagged.

**Architecture:** The audit
([`PIPELINE_DRIVER_AUDIT.md`](../proposals/PIPELINE_DRIVER_AUDIT.md)) found the
*phase-product types* are sound but the *driver* collapsed the phases into
`renderView` (`Sources/SwiftTUIRuntime/SwiftTUI.swift:295`). This plan builds
toward P1b: a composed pipeline that `DefaultRenderer` drives, where phase order
is enforced by composition and the sync/async/cancellable variants become
execution *strategies* over one composition instead of ~13 forked functions. The
refactor is staged behind contract tests landed first, so the structural change
to the hottest code path is verified, not asserted.

The current async rendering contract in
[`ASYNC_RENDERING.md`](../ASYNC_RENDERING.md) is treated as shipped input, not
proposal text. This roadmap may refine the driver and harden completed-frame
drop classification, but it must preserve the shipped boundaries: resolve,
commit, lifecycle, and ordinary authored layout-dependent content stay on the
main actor; queued tail jobs may cancel only before worker layout starts; started
tail work still finishes; completed stale frames may be skipped only by the
tested visual-only policy and `.emptyVisualOnly` reconciliation.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing
(`import Testing`, `@Test`/`#expect`), SwiftPM multi-module package
(`SwiftTUICore` / `SwiftTUIRuntime`), the existing regression suites
(`PipelineTests`, `LayoutAndRenderingPipelineTests`,
`AsyncFrameTailRenderingTests`, `DiagnosticsAndCacheTests`,
`StackSafetyRegressionTests`), public-API baseline tooling, ADR practice under
`docs/decisions/`.

---

## How to read this roadmap

This document covers all 11 audit proposals (P1–P11), plus the governance-drift
finding that did not receive its own proposal number.
It does **not** contain line-by-line code. Each stage is a unit of work with a
clear exit criterion; expand it into a detailed TDD plan when you reach it.

**Two tracks run in parallel after Stage 0:**

```text
Track A — pipeline composition (the P1b spine)
  Stage 0 ── Stage 1 ── Stage 2 ── Stage 3 ── Stage 4 ── Stage 5
  (tests)    (P2)       (P3)       (P1b)      (P8)       (P6)

Track B — infrastructure hardening (no shared code with the driver)
  Stage 0 ── Stage 6 (P4, P5)
          └─ Stage 7 (P9)

Stage 8 — governance reconciliation — depends on Stage 3 landing.
```

Stage 0 gates structural driver work: it pins the behavior the current monolith
protects only by convention, so both tracks refactor against a safety net. Stage
1 can be expanded into a detailed plan while Stage 0 is being expanded, but its
implementation should not land ahead of the Stage 0 guard subset that covers
head freshness and commit/drop semantics. Stage-specific disabled tests are not
the safety net for unrelated work; they gate the stage that names them. Track B
contributors can work concurrently with Track A once the Stage 0 guard subset
for their touched seam is green.

**Stage map:**

| Stage | Focus | Proposals | Track | Depends on | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 | Pin the contracts with tests | P7, P11, P10 (doc) | gate | — | Low |
| 1 | Unify the render head | P2 | A | Stage 0 guard subset | Low |
| 2 | Name + bound the hidden stages | P3 | A | Stage 1 | Medium |
| 3 | Compose the pipeline (P1b) | P1b | A | Stages 0, 1, 2 | High |
| 4 | Make raster reuse sound | P8 | A | Stage 3 | Medium |
| 5 | Close the frame-drop surface | P6 | A | Stage 3 | High |
| 6 | Concurrency + recursion safety | P4, P5 | B | Stage 0 guard subset | Med–High |
| 7 | Split the presentation seam | P9 | B | Stage 0 guard subset | Medium |
| 8 | Reconcile governance docs | P10, Finding 12 | — | Stage 3 landed | Low |

Track A is strictly sequential (each stage consumes the prior one's structure).
Track B stages are mutually independent and independent of Track A — a second
contributor can run them in parallel. Stage 8 waits for Stage 3.

---

## Stage 0 — Pin the contracts before touching the driver

**Goal:** Build the architecture-contract and retained-reuse invariant tests so
that every later refactor has a mechanical safety net. No production behavior
changes in this stage. See detailed plan:
[`docs/plans/2026-05-17-002-stage-0-contract-guards-plan.md`](./2026-05-17-002-stage-0-contract-guards-plan.md).

**Status:** Shipped.

**Addresses:** P7 (Finding 13), P11 (Findings 13/17), P10 documentation half
(Finding 16).

**Depends on:** Nothing — this stage gates the others.

**Why first:** The audit's "Suggested next step" is explicit — land low-risk
P7/P11 tests in parallel with P2 because they "pin the freshness and commit
semantics that the current monolith protects only by convention," making the
P1b decision safer. Tests written *after* a refactor only prove the new code is
self-consistent; tests written *before* prove the refactor preserved behavior.

**Tasks:**

1. Split the Stage 0 contracts into two explicit groups:
   - **must-pass baseline guards** needed before Stage 1/3 driver edits;
   - **stage-specific pending guards** that may be disabled on current `main`,
     but block the later stage that is named in their disabled reason.
   Existing green tests are not candidates for tolerated regression. Only newly
   added Stage 0 guard tests may be disabled, and only when they expose an
   already-known gap and name the later stage that owns closing it.
2. Add a retained-reuse invariant suite (P7): a test that fails when a
   resolved-derived field mirrored into `PlacedNode` is absent from a projection
   synchronization test; a test that exercises `synchronizeRetainedPhaseMetadata`
   for every field in `PlacedNodeResolvedMetadata`.
3. Add a mechanical classification guard: a test (reflection- or
   manifest-based) that fails when a new `ResolvedNode` stored property ships
   without a measurement/placement/semantics/draw/lifecycle/damage/commit/
   diagnostics classification decision recorded.
4. Add architecture-contract tests (P11), named for the *claimed* architecture
   rather than past incidents:
   - all committed side-effect kinds force non-droppable completed frames;
   - semantic host-frame sequence and damage survive async cancellation/drop;
   - focus / default-focus convergence cannot present stale semantic snapshots;
   - retained layout reuse updates every non-geometry resolved projection;
   - incremental raster repaint is byte-for-byte equal to fresh raster for a
     curated mutation matrix.
   The Stage 3 must-pass subset must include head freshness, sync/async artifact
   parity, commit/drop semantics, semantic host-frame continuity, retained reuse
   freshness, and the normal repo gate. Disabled guards for raster reuse,
   frame-drop surface closure, worker/recursion hardening, or presentation
   seam splitting must name Stage 4, Stage 5, Stage 6, or Stage 7 respectively
   and do not count as Stage 3 coverage.
5. Document `FrameArtifacts` field authority (P10, doc half only — no code):
   classify each field as canonical phase product, decorated/baseline-sensitive
   projection, advisory hint, side-effect plan, or diagnostics. Add this as a
   doc-comment block and an `ARCHITECTURE.md` note.

**Key files:**
- Create: `Tests/SwiftTUICoreTests/RetainedReuseInvariantTests.swift`
- Create: `Tests/SwiftTUITests/PipelineContractTests.swift`
- Reference: `Sources/SwiftTUICore/Resolve/ResolvedNode.swift:740,863`,
  `Sources/SwiftTUICore/Place/PlacedNode.swift:10`,
  `Sources/SwiftTUICore/Measure/LayoutEngine+RetainedLayout.swift:89`
- Modify: `Sources/SwiftTUICore/Commit/FrameArtifacts.swift` (doc comments),
  `docs/ARCHITECTURE.md`
- Detailed plan:
  `docs/plans/2026-05-17-002-stage-0-contract-guards-plan.md`

**Risks:** Some contract tests may *fail on current `main`* — that is a finding,
not a blocker only for newly introduced Stage 0 guards. If a new contract test
cannot pass on the current code, record it as a known gap the relevant later
stage must close, and mark the test `@Test(.disabled("closed by Stage N"))`
rather than weakening the assertion. Existing green tests must stay green.

**Exit criteria:** New invariant/contract suites exist and run; the must-pass
baseline guards pass on current `main`; every disabled stage-specific guard has
a named later stage and disabled-reason; no disabled guard is counted as
coverage for Stage 3; no existing green test regresses. `FrameArtifacts` field
authority is documented.

---

## Stage 1 — Unify the render head

**Goal:** Eliminate the ~120 lines of duplicated head logic between the sync
`renderView` and async `prepareFrameHead`, so P1b composes a head that exists in
exactly one form. See detailed plan:
[`docs/plans/2026-05-16-002-stage-1-unify-render-head-plan.md`](./2026-05-16-002-stage-1-unify-render-head-plan.md).

**Addresses:** P2 (Finding 3).

**Depends on:** Stage 0's must-pass guard subset (shared head freshness, commit
and drop semantics).

**Why here:** Mechanical, independently valuable, and a hard prerequisite for
Stage 3 — you cannot compose a "resolve phase" cleanly while it is forked into
two copies that can silently drift.

**Tasks:**

1. Inventory the shared head logic across `renderView`
   (`SwiftTUI.swift:295`–`556`) and `prepareFrameHead`
   (`SwiftTUI.swift:662`–`811`): registration-draft creation, `resolveContext`
   assembly, `frameState.update`, the `canUseSelectiveEvaluation` gate,
   portal-context derivation, `PresentationPortalRoot` wrapping, root/evaluator
   installation, dirty queueing, transition collection, `renderPipelineTree`,
   `wrapInContainerSafeArea`, animation processing, `retainedInput`,
   `LayoutPassContext` construction.
   Include the async-only `indexedChildSourceWorkerSnapshot` branch in this
   inventory: it is execution-strategy-specific worker-safety work today, not a
   sync-head behavior to accidentally impose on one-shot renders.
2. Extract one `prepareFrameHead`-shaped function that produces the head result
   plus (optionally) the five-subsystem checkpoint bundle.
3. Make checkpoint capture and worker-source snapshotting *opt-in* via
   execution-strategy parameters, so the sync path can call the shared function
   without paying checkpoint-capture or worker-snapshot cost.
4. Re-point the sync `renderView` to call the shared head and then finish
   synchronously; re-point the async path to call it with checkpoints enabled.
5. Verify with `LayoutAndRenderingPipelineTests` and
   `AsyncFrameTailRenderingTests` that both paths still produce identical heads.

**Key files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`renderView`,
  `prepareFrameHead`, `abortPreparedFrameHead` at `:122`)
- Detailed plan: `docs/plans/2026-05-16-002-stage-1-unify-render-head-plan.md`

**Risks:** The sync path currently has *no* checkpoint capture and does not need
the async worker-source snapshot. Unifying must not impose either
allocation/cost on the sync path — keep them behind execution-strategy options
and profile to confirm.

**Exit criteria:** One head implementation; sync and async both delegate to it;
a fix to the selective-evaluation gate now provably reaches both paths;
regression suites green.

---

## Stage 2 — Name and bound the hidden stages

**Goal:** Promote the two unnamed pipeline stages — animation injection and the
late-preference reconciliation loop — into first-class, named units, and remove
the magic reconciliation-pass bound. See detailed plan:
[`docs/plans/2026-05-17-001-stage-2-name-hidden-stages-plan.md`](./2026-05-17-001-stage-2-name-hidden-stages-plan.md).

**Addresses:** P3 (Findings 5 and 11).

**Depends on:** Stage 1.

**Why here:** Stage 3 composes named stages. The loop and animation injection
must become explicit, named entities *before* composition, or the composed
model will once again hide them inside a fused function.

**Tasks:**

1. Name the animation-injection stage: extract
   `animationController.applyInterpolations(to: &resolved)`
   (`SwiftTUI.swift:390`) into a named stage type/function with a documented
   contract — "the eighth stage: mutates the resolved tree between resolve and
   measure." Replace the defensive inline comment with the named type.
2. Name the late-preference reconciliation loop: make
   `renderLayoutResolvingLatePreferences` (`SwiftTUI.swift:559`) a named,
   loop-bearing stage with an explicit, documented fixpoint contract.
3. Apply the same named loop to the async path
   (`renderLayoutResolvingLatePreferencesAsync`) or extract a shared state
   machine that both sync and async wrappers drive, so the bound and
   bound-exceeded policy cannot drift.
4. Replace `maxLatePreferenceReconciliationPasses = 4` (`SwiftTUI.swift:11`)
   with either a derived bound (from preference dependency depth) or a documented
   constant whose rationale is recorded.
5. Decide and implement the bound-exceeded policy explicitly: is exceeding the
   bound a logged degradation (current behavior — renders with stale geometry)
   or a hard diagnostic surfaced to the view author? Record the decision in an
   ADR. The audit calls the current silent-staleness path "a correctness
   compromise presented as a guardrail."

**Key files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift:11,390,559`
- Create: `docs/decisions/0018-late-preference-reconciliation-bound.md`
- Reference: existing `docs/plans/2026-05-12-002-late-preference-reconciliation-plan.md`
- Detailed plan:
  `docs/plans/2026-05-17-001-stage-2-name-hidden-stages-plan.md`
- ADR: `docs/decisions/0018-late-preference-reconciliation-bound.md`

**Risks:** Changing the bound-exceeded behavior from "log and render" to "hard
diagnostic" is a behavior change for any view with a deep preference dependency
chain — gate it behind the Stage 0 contract tests and survey example views
before flipping.

**Exit criteria:** Animation injection and late-preference reconciliation are
named stages with documented contracts; the magic `4` is derived or justified;
the bound-exceeded policy is decided in an ADR and implemented.

---

## Stage 3 — Compose the pipeline (P1b)

**Goal:** Make `DefaultRenderer` drive a composed phase abstraction so phase
order is enforced by composition, not asserted by prose. Collapse Findings 1, 3,
and 9 together. **This is the structural core of the plan.**

**Status:** Shipped. Detailed plan:
[`docs/plans/2026-05-17-003-stage-3-compose-pipeline-plan.md`](./2026-05-17-003-stage-3-compose-pipeline-plan.md).
ADR: [`0019`](../decisions/0019-composed-runtime-render-pipeline.md).

**Addresses:** P1b (Findings 1, 3, 9).

**Depends on:** Stages 0, 1, and 2.

**Why here:** Stages 0–2 made this safe: behavior is pinned by contract tests,
the head exists once, and the hidden stages are named. Only now can composition
be introduced without losing the convention-protected invariants.

**Tasks:**

1. Decide the abstraction's relationship to `Pipeline.swift`'s existing
   `Renderer<Root>`: either (a) extend `Renderer<Root>` into the real driver
   type, or (b) supersede it with a new composed type and delete it. Record the
   choice in an ADR. The abstraction must allow a stage to itself be a *fused
   sub-pipeline* — the audit is explicit that fusing measure/place/raster is a
   legitimate performance choice; composition must express "the tail is one
   fused node," not force seven separately allocated phase calls.
2. Model the real stages, not the advertised seven: `head` (resolve, from
   Stage 1) → `animation injection` (Stage 2) → `late-preference layout loop`
   (Stage 2, a loop-bearing composed stage) → `fused frame tail`
   (measure+place+semantics+draw+raster) → `commit`.
3. Model the head as a *declared-effect* stage. The head must explicitly name
   the subsystems it mutates — `viewGraph`, `frameState`,
   `presentationPortalState`, `observationBridge`, `animationController`
   (Finding 4) — as a typed effect set on the stage itself, and the
   checkpoint/rollback must become a single named transactional-stage construct
   that the async strategy wraps the head in, instead of machinery threaded by
   hand through `prepareFrameHead` / `abortPreparedFrameHead`. This is
   *relocate-and-declare*, not *eliminate*: the five checkpoints still exist and
   still roll back, but they become a visible composition element. It converts
   Finding 4's "unexplained residue" into a declared contract, and makes ADR
   0004's missing invariant — "live registries equal what restore-from-graph
   would build" — natural to express as a Stage 0 guard.
4. Make `DefaultRenderer` execute the composed pipeline, replacing the
   imperative body of `renderView`. The shipped implementation keeps
   `RuntimeRenderPipeline` as a stateless local composition value at each render
   call site instead of storing it on `DefaultRenderer`, because a stored
   pipeline value regressed temporary one-shot renderer lifetimes in the gallery
   text-input smoke path.
5. Reframe sync / async / cancellable as *execution strategies* over the single
   composition rather than ~13 forked functions (`render`, `renderAsync`,
   `renderAsyncCancellable`, `renderView`, `renderViewAsync`, `prepareFrameHead`,
   the `renderFrameTailAsync` overloads, etc. — see Finding 9).
6. Migrate every production entry point onto the composed pipeline; delete or
   relabel the now-redundant forked functions.
7. Resolve the `Renderer<Root>` contradiction: the type referenced *only* by
   `PipelineTests` and `Phase0FoundationTests` is now either the live driver or
   deleted — no third "documented but dead" renderer remains.
8. Preserve the shipped async boundaries from `ASYNC_RENDERING.md`: composition
   must not revive the reverted registration-staging approach, move ordinary
   resolve off-main, cancel started worker work, or treat raw
   `FrameDropEligibility` as permission to skip commit.
9. Profile allocations and frame latency against a pre-Stage-3 baseline.
   Composition can cost allocations the monolith avoids; the fused-tail node
   from Task 1 is the mitigation — confirm it works.

**Key files:**
- Created: `Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift`
- Modified: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`DefaultRenderer`,
  `render`, `renderAsync`, `renderAsyncCancellable`, frame head, and frame-tail
  stage helpers)
- Deleted: `Sources/SwiftTUICore/Pipeline/Pipeline.swift`
- Reference: `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- ADR: `docs/decisions/0019-composed-runtime-render-pipeline.md`

**Risks (highest in the plan):**
- Deep refactor of the hottest code path. Stage behind `PipelineTests`,
  `LayoutAndRenderingPipelineTests`, `AsyncFrameTailRenderingTests`,
  `DiagnosticsAndCacheTests` — all must stay green at every commit.
- Composition can cost allocations the monolith avoids; the fused-tail node and
  profiling (Task 9) are mandatory, not optional.
- Finding 4 (resolve mutates five subsystems; commit is not the side-effect
  boundary) is **declared, not fixed**, here. Task 3 makes the head a
  declared-effect stage and the checkpoint/rollback an explicit transactional
  construct — but this stage does **not** narrow resolve's effect set, move side
  effects toward commit, or retry ADR 0004's abort. Those revert reasons —
  irreversible gesture-recognizer teardown on registry reset, completion
  closures that cannot be un-fired — survive P1b untouched, and attempting them
  here would load a second hard problem onto the hottest path. The Stage 3 ADR
  records that "commit is the side-effect boundary" remains aspirational and
  names the deferred follow-on (below) as the path to it.

**Exit criteria:** No production frame bypasses the composed pipeline; the ~13
render entry points collapse to {execution strategy} × {one composition};
`Renderer<Root>` is either live or gone; allocation/latency profile is within an
agreed tolerance of the pre-stage baseline; the four named suites, focused
`RunLoop.run()` interactive-path coverage, and `bun run test` are green.

---

## Stage 4 — Make raster reuse sound

**Goal:** Separate the pure `DrawNode -> RasterSurface` conversion from the
incremental-repaint reuse adapter, so the optimization cannot silently underpaint.

**Status:** Shipped. Detailed plan:
[`docs/plans/2026-05-17-004-stage-4-raster-reuse-soundness-plan.md`](./2026-05-17-004-stage-4-raster-reuse-soundness-plan.md).

**Addresses:** P8 (Finding 14).

**Depends on:** Stage 3.

**Why here:** Best done after Stage 3, when the raster stage is an explicit
composed node and the contract test for "incremental repaint == fresh raster"
(Stage 0) is in place to verify the split.

**Tasks:**

1. Split `Rasterizer.rasterizeCollectingVisibleIdentities`
   (`Sources/SwiftTUICore/Raster/Rasterizer.swift:55`) into two named
   operations: a fresh-raster path (`draw -> RasterSurface`) and an
   incremental-repaint adapter (`draw + previous + sound damage -> RasterSurface`).
2. Make the incremental adapter's reliance on damage explicit in its type — it
   must take a `PresentationDamage` it treats as *soundness-critical*, not as a
   hint, when it gates whether painting happens.
3. Decide and document: when damage soundness cannot be guaranteed, the adapter
   falls back to fresh raster rather than skipping subtrees. Currently
   `refineDamage` (`Rasterizer+Damage.swift:60`) only compares rows already
   marked dirty and `Rasterizer+Paint.swift:97` can skip subtrees outside the
   dirty range — with no global diff to catch a miss.
4. Wire the Stage 0 contract test ("incremental repaint byte-for-byte equals
   fresh raster for a curated mutation matrix") to assert against both paths.

**Key files:**
- Modified: `Sources/SwiftTUICore/Raster/Rasterizer.swift`
- Referenced: `Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift`,
  `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift`
- Modified: `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- Modified: `Tests/SwiftTUITests/PipelineContractTests.swift`,
  `Tests/SwiftTUICoreTests/RasterizerTests.swift`

**Risks:** The incremental path is performance-critical; the fresh-raster
fallback must trigger only on genuinely unsound damage, not routinely, or the
optimization is lost. Profile the dirty-frame case.

**Exit criteria:** Fresh raster and incremental repaint are separately named and
separately testable; the mutation-matrix contract test passes; damage is typed
as soundness-critical where it gates painting.

---

## Stage 5 — Close the frame-drop correctness surface

**Goal:** Shrink the 20-plus-flag `FrameDropEligibility.Blocker` surface so a new
feature cannot silently drop a frame carrying a real lifecycle or task event.

**Status:** Shipped. Detailed plan:
[`docs/plans/2026-05-17-005-stage-5-frame-drop-surface-plan.md`](./2026-05-17-005-stage-5-frame-drop-surface-plan.md).

**Addresses:** P6 (Finding 8).

**Depends on:** Stage 3.

**Why here:** The async/cancellable execution strategy from Stage 3 owns frame
dropping; reworking the eligibility model is cleaner once that strategy is one
composed thing rather than forked functions.

**Tasks:**

1. Investigate inverting the model: instead of enumerating 20-plus reasons a
   frame *cannot* drop (`Pipeline/FrameDropEligibility.swift:36`), derive
   droppability from a small closed impact product. `CommitPlan` alone is
   probably too narrow because focus, scroll, retained-baseline, presentation,
   graphics, diagnostics, and worker-cache barriers live outside lifecycle and
   handler installation. If a new `CompletedFrameImpact` product is needed,
   scope it here.
2. If the closed-impact derivation is feasible, implement it and delete the
   enum. If it is not, keep the enum but add a mechanical guard test: a test
   that fails when a new committed-side-effect or runtime barrier type ships
   without a corresponding `Blocker` case or closed-impact field.
3. Re-evaluate `completedFramePolicy = .dropCompletedVisualOnly` hardcoded in
   `DefaultRenderer.init` (`SwiftTUI.swift:51`): either make the field genuinely
   configurable or remove the field and document the fixed policy.

**Key files:**
- Modify: `Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift:36`,
  `Sources/SwiftTUIRuntime/SwiftTUI.swift:51`
- Reference: `docs/proposals/ASYNC_FRAME_STALE_POLICY.md`

**Risks:** A wrong droppability derivation drops frames with real events — the
worst possible regression. Gate behind the Stage 0 contract test "all committed
side-effect kinds force non-droppable completed frames."

**Exit criteria:** Either droppability is derived from a closed impact product,
or the enum survives with a guard test that fails on an unclassified new
side-effect/barrier type; the shipped visual-only completed-frame drop behavior
still works; the `completedFramePolicy` field is honest about its
configurability.

**Outcome:** Droppability is now derived from
`FrameDropEligibility.CompletedFrameImpact`, a closed impact product that every
diagnostic `Blocker` maps through exhaustively. The `Blocker` enum remains the
diagnostics vocabulary. `DefaultRenderer` no longer stores a private
constant-like `completedFramePolicy`; completed-frame candidate creation
defaults to `.dropCompletedVisualOnly` at the decision point unless an explicit
internal override is supplied.

---

## Stage 6 — Structured concurrency and recursion safety (Track B)

**Goal:** Bring the off-main layout worker under structured concurrency (or
properly isolate it), and treat deep layout recursion as the unbounded-input
hazard it is.

**Status:** Active in
[`docs/plans/2026-05-17-004-stage-6-worker-recursion-hardening-plan.md`](./2026-05-17-004-stage-6-worker-recursion-hardening-plan.md).
The first tranche isolates and ADR-justifies the large-stack worker, closes the
`@safe` policy bypass, and documents the WASI fallback. The remaining tranche is
the full explicit layout work-stack migration described in
[`docs/proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md`](../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md).

**Addresses:** P4 (Findings 6, 7), P5 (Finding 6).

**Depends on:** Stage 0's guard subset for the worker/layout seam. Runs parallel
to Track A.

**Why parallelizable:** This stage touches `FrameTailRenderer.swift` and the
layout engine's recursion — no shared code with the driver composition. It can
start as soon as Stage 0 is green and run alongside Track A.

**Tasks:**

1. Audit and migrate layout-engine recursion depth (P5): convert built-in
   recursive layout measurement and placement walks to explicit work stacks.
   Temporary graceful depth limits may be used as interim guards or
   custom-layout compatibility boundaries, but the final built-in layout
   architecture is iterative. The 8 MB stack and `StackSafetyRegressionTests`
   are mitigation, not a fix — a sufficiently nested view tree remains an
   unbounded-input crash until the migration lands.
2. Replace the hand-rolled `pthread` worker
   (`Rendering/FrameTailRenderer.swift:377`–`378`, `pthread_create` with a
   manual 8 MB stack, `pthread_join` in `deinit`,
   `Unmanaged.passRetained`/`fromOpaque`, `DispatchSemaphore`+`Mutex`) with a
   task-based or `Executor`-based worker.
3. If Task 1 proves a deep stack is genuinely required, isolate all unsafe
   thread code behind a single audited type, and amend the
   `structured-concurrency-escape-hatches` `prek.toml` hook to also cover `@safe`
   — closing the loophole the audit found (the policy is "satisfied on a
   technicality").
4. Write an ADR justifying whichever path is taken.
5. Decide the WASI behavior (Finding 7): the `#else` branch
   (`FrameTailRenderer.swift:485`) runs off-main rendering inline and
   synchronously — "one API, three semantics." Either document the synchronous
   fallback as accepted, or gate the async API off where it cannot be honored.

**Key files:**
- Modify: `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift:311,377,471,485`
- Modify: `prek.toml` (escape-hatch hook banlist)
- Reference: `Tests/SwiftTUICoreTests/StackSafetyRegressionTests.swift`,
  `docs/proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md`,
  `docs/proposals/OFF_MAIN_PIPELINE_RENDERING.md`,
  `docs/proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md`
- Create: `docs/decisions/00NN-off-main-layout-worker-concurrency.md`

**Risks:** The 8 MB stack exists because layout recurses deeply; removing the
`pthread` without first bounding recursion could reintroduce stack overflow on a
default-sized task stack. The recursion audit is first for that reason.

**Exit criteria:** No hand-rolled `pthread` outside a single audited,
ADR-justified type; the escape-hatch hook covers `@safe`; WASI's divergent
semantics are documented or gated; built-in layout recursion has migrated to
explicit work stacks.

---

## Stage 7 — Split the host presentation seam (Track B)

**Goal:** Decompose `PresentationSurface` so non-terminal hosts (WebHost,
SwiftUIHost, JSON, accessible) no longer inherit raw-mode and cursor-write
obligations to receive a committed frame.

**Status:** Shipped in
[`docs/plans/2026-05-17-003-stage-7-presentation-seam-plan.md`](./2026-05-17-003-stage-7-presentation-seam-plan.md).

**Addresses:** P9 (Finding 15).

**Depends on:** Stage 0's guard subset for the presentation seam. Runs parallel
to Track A.

**Why parallelizable:** Touches the presentation/runtime layer, not the driver.
Independent of Track A; can run alongside it after Stage 0.

**Tasks:**

1. Split `PresentationSurface`
   (`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift:142`) into
   focused roles: surface metrics provider, terminal command writer, raster
   presentation surface, semantic host-frame presentation surface, and
   damage-aware variants.
2. Compose all roles for existing terminal hosts so they are unaffected.
3. Re-point semantic-host frames (`PresentationSurface.swift:206`) and
   `RunLoop.presentCommittedFrame` (`RunLoop/RunLoop+Rendering.swift:1436`) onto
   the narrower role(s) they actually consume — making the producer/consumer
   contract explicit and reducing the semantic/damage-aware/fallback branch
   ambiguity.
4. Preserve the current semantic-host sequencing contract: semantic host-frame
   surfaces receive monotonically increasing `SemanticHostFrame.sequence` values
   and `PresentationDamage` as advisory raster damage. Dispatch must still prefer
   semantic host-frame consumers before plain damage-aware raster consumers so
   damage and semantic metadata are not dropped.

**Key files:**
- Modify: `Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift:142,206`,
  `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:1436`
- Reference: `docs/proposals/SEMANTIC_HOST_FRAME_API.md`,
  `docs/HOST_RENDERING_PIPELINES.md`,
  `docs/plans/2026-05-13-001-host-presentation-damage-plan.md`

**Risks:** This is a public/SPI surface change for host packages — run the
public-API baseline tooling, preserve compatibility adapters where practical,
and coordinate with WebHost/SwiftUIHost peers (per ADR 0007, host packages are
peers).

**Exit criteria:** `PresentationSurface` is decomposed into composable roles;
terminal hosts are behavior-unchanged; semantic hosts no longer implement
terminal obligations; `presentCommittedFrame` dispatch is explicit.

---

## Stage 8 — Reconcile governance with the code

**Goal:** Make the documentation true again now that the driver is the composed
pipeline, and close the governance-drift finding.

**Addresses:** Finding 12, finish P10 (Finding 16), supersede ADR 0002.

**Depends on:** Stage 3 landed; ideally Stages 4–7 landed too.

**Why last:** Until Stage 3 lands, the docs *should not* be rewritten to claim a
composed pipeline. This stage records what is now true, not what is aspirational.

**Tasks:**

1. Update [`ARCHITECTURE.md`](../ARCHITECTURE.md): describe the real composed
   pipeline (head → animation injection → late-preference layout loop → fused
   frame tail → commit) and the execution strategies. Remove the claim that the
   seven-phase ordering is "visible in `DefaultRenderer`" if Stage 3 chose to
   model the real stages rather than seven.
2. Amend ADR
   [`0002-seven-phase-pipeline-not-collapsed.md`](../decisions/0002-seven-phase-pipeline-not-collapsed.md):
   record that the *type split* is what was defended and that the *driver* now
   composes the real stages — superseded by the Stage 3 ADR.
3. Update [`AGENTS.md`](../../AGENTS.md) pipeline claims to match.
4. Finish P10: ensure the `FrameArtifacts` field-authority documentation from
   Stage 0 is reflected wherever `FrameArtifacts` is described as architectural
   evidence; redirect host adapters/tests toward phase-specific products.
5. Mark this plan `status: shipped` and cross-link the per-stage detailed plans.
6. Update [`TODO.md`](../TODO.md) and
   [`CHANGELOG.md`](../CHANGELOG.md): remove the active roadmap item only after
   the shipped driver and supporting hardening stages have landed, then add a
   concise changelog entry with short-hash-prefixed doc links.

**Key files:**
- Modify: `docs/ARCHITECTURE.md`, `AGENTS.md`,
  `docs/decisions/0002-seven-phase-pipeline-not-collapsed.md`,
  `docs/proposals/PIPELINE_DRIVER_AUDIT.md` (mark findings resolved)

**Risks:** Low. The risk is *not* doing it — leaving docs that re-assert the
old model after the code moved, recreating Finding 12.

**Exit criteria:** `ARCHITECTURE.md`, `AGENTS.md`, and ADR 0002 describe the
shipped driver; the audit's findings are annotated resolved/deferred; no doc
asserts a pipeline shape the code does not have.

---

## Proposal → stage traceability

| Proposal | Finding(s) | Stage |
| --- | --- | --- |
| P1b — composed pipeline | 1, 3, 9 | Stage 3 |
| P2 — de-duplicate head | 3 | Stage 1 |
| P3 — name and bound the loop | 5, 11 | Stage 2 |
| P4 — structured-concurrency worker | 6, 7 | Stage 6 |
| P5 — audit recursion depth | 6 | Stage 6 |
| P6 — constrain frame-drop surface | 8 | Stage 5 |
| P7 — retained-reuse invariant tests | 13 | Stage 0 |
| P8 — split fresh/incremental raster | 14 | Stage 4 |
| P9 — split presentation interfaces | 15 | Stage 7 |
| P10 — `FrameArtifacts` as inspection product | 16 | Stage 0 (doc) + Stage 8 |
| P11 — architecture-contract tests | 13, 17 | Stage 0 |
| — governance drift | 12 | Stage 8 |
| — resolve side-effect boundary | 4 | declared in Stage 3 (Task 3); narrowing deferred |
| — `FrameDiagnostics` god struct | 10 | **unscheduled gap — see note below** |
| P1a — demote the seven-phase claim | 1 | superseded by P1b (Stage 3) |

Every audit *proposal* (P1–P11) maps to a stage. Three findings have no
proposal of their own. Finding 12 (governance drift) is closed by Stage 8.
Finding 4 (resolve side-effect boundary) is *declared* by Stage 3's Task 3, and
its further *narrowing* is a named deferred follow-on. Finding 10
(`FrameDiagnostics` god struct) is an open gap this plan does not yet schedule.
P1a is intentionally not scheduled: the P1b decision (Stage 3) makes the docs
true by changing the code instead of the prose, and Stage 8 performs the doc
reconciliation P1a would have done alone.

## Deferred follow-on — narrow the resolve effect set (Finding 4)

Not a stage of this plan; a separate future effort that **depends on Stage 3**
landing. Stage 3 *declares* the head's five-subsystem effect set; it does not
shrink it. The path to the audit's Finding 4 — making "commit the side-effect
boundary" — and to reviving ADR 0004's abandoned abortable head (its Stage 3D)
is to audit, with the declared effect set in hand, which of `viewGraph`,
`frameState`, `presentationPortalState`, `observationBridge`, and
`animationController` genuinely must mutate in the head versus could defer
toward commit.

This is deliberately deferred, not scoped out:

- ADR 0004's revert was an *implementation* divergence — `finishFrame` restored
  handlers from per-frame draft registries instead of from the committed graph,
  silently dropping alias-only nodes on `.resetAll` — not a proof of
  impossibility. Its post-mortem gives a concrete next-attempt recipe (restore
  from the graph; keep the draft as a side-channel only).
- But the genuinely irreversible effects it names — gesture-recognizer teardown
  on registry reset, completion closures that fire user code — are real and
  unsolved, so this must be its own plan with its own ADR, not a Stage 3 task.
- The post-mortem is explicit that the next attempt must budget end-to-end
  `RunLoop.run()` interactive coverage (scroll bursts, drag sequences, click
  resolution); deterministic unit tests did not catch the original regression.

Separately, **Finding 10** (`FrameDiagnostics` is a ~30-field `Equatable`
god struct, and `collectsDiagnostics` creates a second render path) also has no
proposal. Its dual-path concern overlaps Stage 3 — composition should not ship
two divergent render paths — while its god-struct decomposition is independent.
This plan does not yet place it; that is an open decision below.

## Open decisions to settle inside the stages

These are deliberately deferred to the detailed plans, not pre-decided here:

1. **Post-Stage 3** — where Finding 10 (`FrameDiagnostics` god struct, dual
   `collectsDiagnostics` render path) is handled: folded into a follow-up
   dual-path-collapse task, given its own stage, or left to a separate plan.

## Suggested first action

Stage 0 through Stage 5 now have detailed shipped plans, completing Track A.
Stage 7 is shipped on Track B, and Stage 6 has an active detailed plan with the
worker isolated and ADR-justified. Continue **Stage 6** by executing the full
explicit layout work-stack migration; Stage 8 governance reconciliation can
follow once the remaining hardening implementation lands.

## Related docs

- [`PIPELINE_DRIVER_AUDIT.md`](../proposals/PIPELINE_DRIVER_AUDIT.md) — the
  findings this plan addresses
- [`PIPELINE_BOUNDARY_HARDENING.md`](../proposals/PIPELINE_BOUNDARY_HARDENING.md)
  — hardened the phase-product *types*; this plan hardens the *driver*
- [`ASYNC_RENDERING.md`](../ASYNC_RENDERING.md) — shipped async frame-tail,
  cancellation, and completed-frame drop contract this roadmap must preserve
- [`HOST_RENDERING_PIPELINES.md`](../HOST_RENDERING_PIPELINES.md) — current
  host presentation and semantic host-frame producer/consumer path
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — the seven-phase claim under revision
- ADR [`0002`](../decisions/0002-seven-phase-pipeline-not-collapsed.md),
  ADR [`0004`](../decisions/0004-frame-head-abort-reverted.md)
- [`OFF_MAIN_PIPELINE_RENDERING.md`](../proposals/OFF_MAIN_PIPELINE_RENDERING.md),
  [`ASYNC_FRAME_STALE_POLICY.md`](../proposals/ASYNC_FRAME_STALE_POLICY.md),
  [`SEMANTIC_HOST_FRAME_API.md`](../proposals/SEMANTIC_HOST_FRAME_API.md)

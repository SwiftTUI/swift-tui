# Async Frame Stale Policy

## Status

Stages 1 through 6 are implemented. The Stage 4 drop-blocker classifier exposes
explicit runtime signals for the formerly unobservable blocker families, Stage 5
added skipped-frame reconciliation scaffolding, and Stage 6 now drops stale
completed visual-only candidates through `.emptyVisualOnly` reconciliation while
preserving ordered commit for every non-droppable candidate. Scheduler Stages 3A
through 3D are implemented. The first Stage 3C, abortable prepared frame heads,
was attempted and reverted; see
[`../plans/2026-04-26-002-frame-head-abort-plan.md`](../plans/2026-04-26-002-frame-head-abort-plan.md).
The shipped replacement is the Option 3 draft-transaction tranche recorded in
[`../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md`](../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md).

Pre-start queued-tail cancellation has shipped. Started frame-tail work is still
awaited, and non-droppable completed candidates still commit in order. The only
completed-frame non-commit path is the narrow stale visual-only policy described
below. See
[`ASYNC_RENDER_GENERATION_SCHEDULER.md`](ASYNC_RENDER_GENERATION_SCHEDULER.md)
for the shipped generation scheduler design. For the consolidated current
status, see
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md).

The current async frame-tail renderer preserves ordered side effects: when a
worker frame finishes with lifecycle, focus, task, preference, animation,
registration, retained-cache, presentation, or diagnostic barriers, the main
actor commits it before newer input state is rendered and presented. When a
completed candidate is stale and classified visual-only, the runtime aborts the
prepared frame head, discards the completed tail output, logs a dropped-frame
diagnostic row, and immediately renders the newest desired state.

This document defines the shipped requirements and the remaining non-empty
reconciliation boundary.

## Proposal Summary

Completed-frame dropping should become an explicit stale-frame policy, not a
side effect of generation comparison. The first actionable drop target is a
completed async frame-tail result that is both stale and proven visual-only. In
that case the runtime may discard the completed artifacts before frame commit,
abort the prepared frame head, preserve the previously committed runtime
baseline, and immediately render the newest desired state.

The proposal has three parts:

1. Split frame finish into a side-effect-free candidate phase and an explicit
   commit phase.
2. Expand `FrameDropEligibility` until an empty blocker set is a real runtime
   verdict for a narrow visual-only case.
3. Add a skipped-frame reconciliation object, initially empty for visual-only
   drops, so future stateful skipped-frame policies have a durable extension
   point instead of bypassing commit semantics ad hoc.

All three pieces are now implemented and tested for empty visual-only
reconciliation. Completed worker results still keep ordered-commit behavior
unless the policy proves a stale candidate has no non-visual barriers.

## Problem

Off-main frame-tail rendering creates a new kind of stale result:

```
frame A resolves and starts worker layout/raster
input arrives and mutates state
frame B is scheduled
frame A finishes after B is already desired
```

The tempting optimization is to drop frame A and render B. That is not currently
safe. A computed pipeline frame is not just a terminal byte payload. It carries
the semantic snapshot, commit plan, lifecycle edges, focus sync inputs,
animation state, retained layout cache inputs, raster reuse baseline, and
diagnostics for one resolved state.

Dropping it without a reconciliation model can produce:

- missing `onAppear` / `onDisappear` transitions,
- lost task starts or cancellations,
- focus binding and focused-value drift,
- scroll-position drift,
- stale preference-observation state,
- retained layout/raster caches based on the wrong committed tree,
- animation controller state sampled against an uncommitted placed tree,
- misleading diagnostics.

## Distinction From Async Presentation Drops

Async presentation may drop stale terminal writes after a frame has already
committed. That is a different layer.

Presentation drops discard terminal output bytes and recover with full repaint
when the next committed surface is presented. The stateful pipeline has already
advanced. Lifecycle, focus, tasks, registries, and retained-frame state have
already been reconciled on the main actor.

Pipeline stale-frame drops would discard artifacts before commit. That means the
runtime must either prove there are no side effects to skip or run equivalent
side effects through a reconciliation pass.

## Current Contract

The current runtime contract is:

- resolve runs on the main actor,
- built-in layout may run on the frame-tail worker,
- `SendableLayout` custom layout and worker-safe framework layouts may run on
  the frame-tail worker,
- ordinary custom layout falls back to the main actor,
- overlay application, semantics, draw, and raster run on the worker,
- queued tail jobs may cancel before worker layout starts when superseded by a
  newer render intent,
- the main actor awaits any started worker job,
- non-droppable frames commit in order,
- started computed frames are awaited, and completed candidates are dropped only
  when stale, visual-only, and reconciled through `.emptyVisualOnly`,
- newer frames are not presented ahead of older uncommitted side effects.

The async stress tests intentionally enforce this behavior. They block worker
work, queue input, and verify that non-droppable frames do not get skipped or
presented out of order, while stale visual-only candidates are discarded before
commit.

## Policy

Drop only completed computed pipeline frames that the dedicated completed-frame
policy proves are stale, visual-only, and reconcilable with `.emptyVisualOnly`.
Pre-start queued-tail cancellation remains the only cancellation path.

The stale-frame policy must classify a frame before dropping it:

```
enum FrameDropEligibility {
  case mustCommit
  case canDropVisualOnly
  case canCancelBeforeWorkerStart
}
```

The exact names can change. The required distinction cannot:

- **must commit**: the frame has side effects that must be applied or
  reconciled.
- **can drop visual only**: the frame has no semantic, lifecycle, focus,
  preference, task, animation, registration, or retained-cache transition that
  matters independently of terminal output.
- **can cancel before worker start**: the frame has not begun worker-owned cache
  mutation and has not produced artifacts that need commit or reconciliation.

The default classification must be `mustCommit`.

## Drop Barriers

A frame is not droppable if any of these are true:

- its resolved tree changes lifecycle ownership,
- its commit plan contains lifecycle or task work,
- it installs or removes runtime handlers,
- it changes the semantic focus graph,
- it participates in focus binding or focused-value sync,
- it participates in scroll-position sync,
- it carries preference-observation updates,
- it advances animation transition bookkeeping,
- it changes the retained-frame baseline used by later incremental layout or
  raster work,
- it includes custom-layout cache updates,
- it is the first frame after resize, terminal surface incompatibility, or
  presentation drop recovery,
- diagnostics are configured to require complete per-frame records.

These barriers are intentionally broad. They can be relaxed only with tests that
prove the skipped work is either irrelevant or reconciled elsewhere.

## Shipped Safe First Target

The first stale-frame optimization is cancellation before worker start.

If a frame is queued for the frame-tail worker but has not started, and a newer
generation supersedes it, the runtime can cancel the queued job before any
worker-owned retained state changes. Even then, the main actor must not have
treated that frame as committed. It should discard the resolve result and rerun
from the newest state.

This is safer than dropping a completed worker result because it avoids cache
and artifact reconciliation. It shipped with generation IDs, frame-head
draft/checkpoint abort proof, composed runtime tests, and TSV cancellation
diagnostics.

## Completed Visual-Only Drop Target

The first completed-frame drop target is intentionally narrow:

```
frame A prepares on the main actor
frame A tail starts and completes on the worker
newer desired generation B exists before A commits
frame A has no nonvisual commit effects
frame A is discarded before finish/commit side effects are applied
frame B is rendered from the last committed runtime baseline
```

This is not frame skipping in the general case. It is dropping a completed
worker result that would only have changed terminal pixels, while preserving the
same runtime state the user would have seen if frame A had never existed.

The first allowed case should be a superseded animation tick or other
draw/raster-only update with all of these properties:

- no lifecycle appear, disappear, change, task-start, or task-cancel operations,
- no runtime handler, focus, scroll, command, pointer, gesture, or drop registry
  change,
- no preference-observation delta,
- no animation completion, transition insertion/removal bookkeeping, or one-shot
  animation transaction that must commit,
- no worker custom-layout cache update that needs to become the committed cache
  baseline,
- no retained layout or raster baseline update that a future frame would rely on,
- no presentation full-repaint recovery, surface-size change, graphics attachment
  replay barrier, or incompatible previous-surface transition,
- no diagnostic mode that requires every completed frame to be represented as a
  committed frame row.

If any signal is missing, the frame remains `mustCommit`.

## Finish Candidate Boundary

The current `finishFrame` path computes commit data and mutates committed runtime
state in one step: it finalizes the `ViewGraph`, commits runtime registrations,
commits animation frame-head state, applies worker custom-layout cache updates,
prunes measurement cache, and stores the retained frame baseline. A completed
frame cannot be dropped safely after that work has already happened.

The runtime needs a two-step finish boundary:

```swift
struct CompletedFrameCandidate {
  var generation: RenderGeneration
  var draft: FrameHeadDraft
  var tailOutput: AsyncFrameTailDraftOutput
  var artifacts: FrameArtifacts
  var finishEffects: FrameFinishEffects
  var eligibility: FrameDropEligibility
}

@MainActor
func makeCompletedFrameCandidate(
  draft: FrameHeadDraft,
  tailOutput: AsyncFrameTailDraftOutput
) -> CompletedFrameCandidate

@MainActor
func commitCompletedFrameCandidate(_ candidate: CompletedFrameCandidate)

@MainActor
func discardCompletedFrameCandidate(
  _ candidate: CompletedFrameCandidate,
  reconciliation: SkippedFrameReconciliation
)
```

The exact type names can change. The ownership split cannot:

- `makeCompletedFrameCandidate` may compute the same artifacts and commit plan
  the runtime needs for classification, but any mutation it performs must be
  draft-owned, checkpoint-backed, or revertible before returning.
- `commitCompletedFrameCandidate` is the only path that may commit graph
  finalization, runtime registration changes, animation frame-head transactions,
  worker custom-layout cache updates, retained layout/raster baselines, and
  lifecycle/task commit plans.
- `discardCompletedFrameCandidate` aborts the prepared frame head, discards the
  tail output, applies skipped-frame reconciliation, and leaves retained runtime
  state equal to the last committed frame.

There are two viable implementation shapes:

1. **Preview-first finish.** Add preview APIs for `ViewGraph` lifecycle
   finalization and registration restoration so `makeCompletedFrameCandidate`
   can compute commit data without mutating live state.
2. **Checkpointed finish.** Run the existing finish work behind an expanded
   checkpoint and restore it if the frame is discarded.

Prefer the preview-first shape if it stays local. Use the checkpointed shape only
if preview APIs duplicate too much commit logic. In either case, tests must prove
that discarding a completed candidate leaves actions, key commands, pointer
routes, drop destinations, lifecycle state, task state, animation state, custom
layout cache state, retained layout state, and retained raster state identical to
the pre-candidate baseline.

## Drop Decision

Dropping is legal only when all of the following are true:

1. The tail job state is `completed`.
2. The completed candidate's render generation is older than the newest desired
   generation observed by the run loop.
3. `FrameDropEligibility.classify(candidate)` returns no blockers.
4. The selected stale-frame policy is `drop_completed_visual_only`.
5. `SkippedFrameReconciliation` for the candidate is empty or contains only
   explicitly allowed diagnostic bookkeeping.

Generation staleness is necessary but never sufficient. A stale candidate with
any blocker follows the existing ordered-commit path.

The run-loop decision shape should stay single-render-per-renderer:

```swift
let candidate = renderer.makeCompletedFrameCandidate(draft: draft, tail: tail)
let decision = completedFramePolicy.decide(
  candidate: candidate,
  newestDesired: coordinator.newestDesired
)

switch decision {
case .commitOrdered:
  let artifacts = renderer.commitCompletedFrameCandidate(candidate)
  commitAndPresent(artifacts)

case .dropVisualOnly(let reconciliation):
  renderer.discardCompletedFrameCandidate(candidate, reconciliation: reconciliation)
  scheduler.requestReplacementForNewestDesired()
}
```

The runtime still must not present newer state ahead of an older frame that has
nonvisual work. The only behavior change is that a proven visual-only candidate
may be treated like an uncommitted draft instead of a committed frame.

## Required Generation Model

Add explicit generation identity to the render path:

```
struct RenderGeneration: Sendable, Equatable, Comparable {
  var rawValue: UInt64
}
```

Each scheduled render receives a generation. Worker submissions carry the
generation they were derived from. Results return with that generation. The main
actor compares the result against the newest desired generation before deciding
whether to commit, reconcile, or discard.

Generation comparison alone is not enough. It only says that a result is older
than desired; it does not say that skipping it is safe.

## Reconciliation Shape

Every skipped completed frame should flow through a reconciliation object, even
when the first supported reconciliation is empty:

```
struct SkippedFrameReconciliation {
  var mode: Mode
  var lifecycle: [LifecycleOperation]
  var taskOperations: [TaskOperation]
  var handlerInstallations: [HandlerInstallation]
  var focusSync: FocusSyncDelta
  var scrollSync: ScrollSyncDelta
  var preferences: PreferenceObservationDelta
  var animation: AnimationReconciliation
  var retainedStateAction: RetainedStateAction
  var presentationRecovery: PresentationRecoveryAction
  var diagnostics: DroppedFrameDiagnostics

  enum Mode {
    case emptyVisualOnly
    case appliedSideEffects
    case blocked
  }
}
```

A skipped frame should either:

- produce `.emptyVisualOnly` because it is proven visual-only, or
- produce a reconciliation that advances main-actor state as if the necessary
  nonvisual side effects had been committed.

If the runtime cannot produce that reconciliation, it must commit the frame.

For the first tranche, only `.emptyVisualOnly` is allowed. Non-empty
reconciliation is a future policy and must not be smuggled into the visual-only
drop work. That keeps the first behavior change small: the runtime proves there
is nothing to reconcile, then drops the pixels.

Later non-empty reconciliation can be considered only after each state family has
an explicit delta type and ordering rule:

1. lifecycle and task transitions,
2. runtime handler registration changes,
3. focus graph, focus binding, focused values, and scroll sync,
4. preference-observation deltas,
5. animation transactions, completions, transition bookkeeping, and deadlines,
6. retained layout/raster/cache baselines,
7. presentation repaint recovery.

The commit order for non-empty reconciliation must match ordinary frame commit
order. If an effect cannot be represented as a deterministic delta, that effect
is a drop blocker.

## Diagnostics

Before enabling stale-frame dropping, diagnostics should expose:

- render generation, layout generation, raster generation,
- desired generation and coalesced intent-request pressure,
- coalesced event batches and wake causes,
- worker queue/result timings,
- current stale-frame policy,
- current drop blockers from `FrameDropEligibility`.

Already-shipped diagnostics cover those passive signals. Before enabling actual
cancellation or dropping, add:

- tail job state (`queued`, `started`, `completed`, `cancelled_before_start`),
- newest desired generation at tail start and at result receipt,
- cancellation reason,
- cancellation count,
- whether reconciliation ran,
- whether presentation needed full repaint recovery afterward.

Completed-frame dropping needs additional fields:

- `tail_job_state=dropped_completed` for completed worker output discarded before
  commit,
- `stale_frame_policy=drop_completed_visual_only` for the narrow drop path,
- `drop_decision`: `commit_ordered`, `drop_visual_only`, or `blocked`,
- `drop_generation`: the discarded render generation,
- `newest_desired_at_drop`: the desired generation that superseded it,
- `drop_reconciliation_mode`: `empty_visual_only`, `applied_side_effects`, or
  `blocked`,
- `drop_reconciliation_effects`: a stable summary such as `-` for empty or a
  comma-separated list for future non-empty reconciliation,
- `presentation_recovery_after_drop`: whether the next committed frame forced a
  full repaint because a raster baseline was skipped.

Diagnostics must count both:

- input accepted while the main actor was suspended,
- frames skipped or cancelled because newer input superseded them.

The two counters answer different questions. The first proves responsiveness;
the second measures staleness pressure.

A dropped candidate should produce a diagnostic row even though it is not
presented. That row is evidence that the policy made an explicit decision. It
must be distinguishable from both `cancel_pending_before_start` and
`commit_ordered`.

## Migration Plan

### Stage 1: Document and assert ordered commit

- [x] Keep the current no-drop behavior.
- [x] Add a dedicated test name that states computed async frames commit in order
  even when newer input is queued.
- [x] Add diagnostics text explaining that stale worker results are currently
  committed, not dropped.

Stage 1 result:

- `AsyncFrameTailRenderingTests` names the ordered-commit contract directly:
  computed async frames commit in order even when newer input is queued.
- `FrameDiagnosticsLogger` writes `stale_frame_policy=commit_ordered` for every
  runtime diagnostics row.

Commit boundary:

```bash
git commit -m "test(runtime): assert stale async frames commit in order"
```

### Stage 2: Add generation IDs without dropping

- [x] Thread a render generation through `DefaultRenderer.renderAsync` and
  `FrameTailRenderer`.
- [x] Log generation IDs in `FrameDiagnostics`.
- [x] Assert results still commit in order.
- [x] Do not change scheduling or presentation behavior.

Stage 2 result:

- `RenderGeneration` is a monotonic ID assigned per `DefaultRenderer` render
  pass.
- `FrameRenderGenerations` records render, layout input/output, and raster
  input/output generation IDs in `FrameDiagnostics`.
- Runtime TSV diagnostics include generation columns without enabling
  cancellation or stale-result dropping.

Commit boundary:

```bash
git commit -m "refactor(runtime): tag async render generations"
```

### Stage 3: Add cancellation before worker start

Design prerequisite:

- [x] Land the render-generation scheduler design in
  [`ASYNC_RENDER_GENERATION_SCHEDULER.md`](ASYNC_RENDER_GENERATION_SCHEDULER.md).
- [x] Coalesce not-yet-started render intent before starting the next render.
- [x] Extract the async renderer frame-head and finish boundaries.
- [x] Redesign prepared-frame rollback or draft-only side effects before worker
  tail work can be cancelled. The first abort implementation was reverted; the
  shipped replacement is the Option 3 draft transaction.

- [x] Rebaseline diagnostics and runtime-path coverage before changing behavior.
- [x] Redesign prepared frame heads around draft-only side effects. Do not rebuild
  live registries from per-frame draft snapshots.
- [x] Teach the serial worker to skip jobs that have not started and are
  superseded.
- [x] Restrict cancellation to jobs with no worker-owned mutation.
- [x] Rerender from newest state after cancellation.
- [x] Keep completed worker results on the ordered commit path.

Stage 3 result:

- Prepared frame heads use draft runtime registrations and checkpoint-backed
  abort proof.
- Queued tail jobs may cancel before worker layout starts when a newer render
  intent is pending.
- Started and completed tail jobs still commit in order.
- Diagnostics report `tail_job_state`, `tail_cancel_reason`,
  `cancelled_render_count`, desired-generation snapshots, and stale-frame
  policy.

Commit boundary:

```bash
git commit -m "feat(runtime): cancel superseded unstarted frame-tail jobs"
```

### Stage 4: Classify visual-only completed frames

- [x] Add a conservative `FrameDropEligibility` classifier.
- [x] Start with all completed frames classified as `mustCommit`.
- [x] Add tests for the currently observable blockers.
- [x] Add explicit blocker signals for preference-observation deltas,
  focus-binding and focused-value drift, scroll-sync deltas, animation
  completions, animation transition bookkeeping, one-shot animation transactions,
  worker custom-layout cache updates, retained layout/raster baseline updates,
  presentation full-repaint recovery, graphics replay barriers, and
  diagnostics-required full records.
- [x] Add a candidate-level classifier that can distinguish
  `mustCommit(blockers:)` from `canDropVisualOnly` only after every formerly
  `.unobservable` barrier has an explicit signal.
- [x] Keep `FrameDropEligibility.canDrop` false until the candidate classifier
  proves the narrow visual-only case with runtime-path tests.

Stage 4 result so far:

- `FrameDropEligibility` classifies completed frames as diagnostic blockers.
- `FrameDiagnosticsLogger` writes the classifier result as `drop_blockers`.
- Explicit blocker signals now cover runtime focus sync, focused-value sync,
  scroll sync, preference-observation deltas, animation completions,
  transition bookkeeping, one-shot animation transactions, worker custom-layout
  cache updates, retained layout/raster baseline updates, presentation repaint
  recovery, graphics replay barriers, and diagnostics-required full records.
- `FrameDropEligibility.Candidate` can now report `.canDropVisualOnly` for a
  fully classified candidate with an empty blocker set. The legacy artifact
  classifiers still inject `.unobservable` when neither frame artifacts nor
  runtime context expose a specific blocker.
- `FrameDropEligibility.canDrop` remains false for every decision, including
  `.canDropVisualOnly`; runtime code must use `CompletedFramePolicy` plus an
  available reconciliation result instead of this raw compatibility flag.
- The classifier alone does not drop or reconcile frames. Stage 6 composes it
  with generation comparison and `.emptyVisualOnly` reconciliation for the
  narrow shipped policy.

Target Stage 4 result:

- `.unobservable` is gone from frames that have been fully classified.
- A frame that carries no lifecycle, task, handler, focus, scroll, preference,
  animation, cache, retained-baseline, or presentation barrier can produce an
  empty blocker set.
- Existing blocker tests remain, and each newly observable blocker has a focused
  unit test plus at least one composed runtime-path regression where relevant.

Commit boundary:

```bash
git commit -m "refactor(runtime): classify stale frame drop eligibility"
```

### Stage 5: Reconciliation for skipped completed frames

- [x] Add `SkippedFrameReconciliation` with `.emptyVisualOnly`,
  `.appliedSideEffects`, and `.blocked` modes.
- [x] Wire completed-frame drop decisions through the reconciliation object even
  when the selected case is empty.
- [x] Prove that `.emptyVisualOnly` leaves lifecycle, task, focus, preference,
  animation, registration, custom-layout cache, retained layout, retained raster,
  and presentation state unchanged from the last committed frame.
- [x] Keep `.appliedSideEffects` unavailable to runtime policy until a later
  proposal defines exact delta types and commit order.
- [x] Keep the default path as ordered commit.

Stage 5 result:

- `SkippedFrameReconciliation` now represents `.emptyVisualOnly`,
  `.appliedSideEffects`, and `.blocked` outcomes. Only `.emptyVisualOnly` is
  available to runtime skip policy.
- `CompletedFrameDropDecision` carries both the eligibility decision and the
  selected reconciliation. The current completed-frame path records
  `commit_ordered` decisions with blocked reconciliation.
- Test-only completed-tail discard coverage routes through
  `.emptyVisualOnly`, aborts the prepared frame head, discards the tail output,
  and leaves the last committed runtime/presentation state intact.
- `.appliedSideEffects` remains explicitly unavailable to runtime policy, so
  non-empty skipped-frame reconciliation cannot be introduced accidentally.
- No runtime behavior drops or reconciles completed frames.

Commit boundary:

```bash
git commit -m "feat(runtime): reconcile skipped async frame results"
```

### Stage 6: Drop completed visual-only frames

- [x] Split the async finish path into candidate creation and explicit commit.
- [x] Add a completed-frame policy object that compares candidate generation to
  the newest desired generation and consults `FrameDropEligibility`.
- [x] When a stale candidate is visual-only, discard it through
  `discardCompletedFrameCandidate(..., reconciliation: .emptyVisualOnly)`.
- [x] Emit a dropped-frame diagnostics row with generation, decision,
  reconciliation, and presentation-recovery fields.
- [x] Preserve ordered commit for every non-droppable completed candidate.
- [x] Do not enable non-empty reconciliation.

Stage 6 result:

- Async frame-tail completion now builds a `CompletedFrameCandidate` before
  committing. Candidate creation previews the commit plan under a `ViewGraph`
  checkpoint, restores that preview, and leaves live registration, lifecycle,
  animation, custom-layout cache, measurement-cache, and retained-tail commits
  to `commitCompletedFrameCandidate`.
- `CompletedFramePolicy` compares the completed candidate's generation against
  the newest desired generation surfaced by the run loop and consults
  `FrameDropEligibility`. The shipped renderer uses
  `.dropCompletedVisualOnly`.
- A stale completed candidate whose blocker set is empty returns
  `tail_job_state=dropped_completed`, aborts the prepared frame head, discards
  the completed tail output through `.emptyVisualOnly` reconciliation, preserves
  the previously committed runtime and presentation baseline, and lets the next
  queued generation render from the latest state.
- Every current candidate and every candidate with lifecycle, task, handler,
  focus, scroll, preference, animation, custom-layout cache, retained-baseline,
  presentation, graphics, diagnostic, or registration barriers still commits in
  order. Blocked decisions remain `commit_ordered` or `blocked`, not dropped.
- Dropped-frame diagnostics rows now include `drop_decision`,
  `drop_generation`, `newest_desired_at_drop`, `drop_reconciliation_mode`,
  `drop_reconciliation_effects`, and `presentation_recovery_after_drop`.
- Test coverage proves candidate creation does not publish draft command
  registrations into the live registry, and the `.emptyVisualOnly` test discard
  path now discards a completed candidate instead of only a rendered tail.
- Runtime-path coverage proves a stale visual-only frame is not presented, the
  replacement frame presents the newest state, and the TSV row records
  `drop_visual_only` with `empty_visual_only` reconciliation.
- `.appliedSideEffects` remains unavailable to runtime policy, so non-empty
  skipped-frame reconciliation is still a separate proposal.

Commit boundary:

```bash
git commit -m "feat(runtime): drop visual-only stale frame results"
```

## Required Tests

- Queued input during a blocked worker does not present newer state ahead of the
  blocked frame under the current policy.
- Generation IDs increase monotonically across rerenders and focus-sync loops.
- Superseded jobs can be cancelled only before worker start.
- Completed worker results still commit unless explicitly classified droppable.
- A completed visual-only candidate can be dropped only after a newer desired
  generation exists.
- Dropping a visual-only candidate leaves live action, key, pointer, gesture,
  command, drop, lifecycle, task, focus, preference, animation, custom-layout
  cache, retained layout, retained raster, and presentation state equal to the
  last committed frame.
- Lifecycle appear/disappear edges are not lost when a frame is superseded.
- Tasks start and cancel exactly once across skipped generations.
- Focus binding and focused values converge after a skipped or cancelled
  generation.
- Scroll-position sync remains deterministic.
- Retained layout/raster caches do not reuse artifacts from uncommitted frames.
- Presentation drop recovery still forces full repaint independently of pipeline
  cancellation.
- Diagnostics report generation, drop decision, blocker set, reconciliation
  mode, and presentation recovery state.

## Recommendation

Keep ordered commit for every started or completed tail job that is not both
stale and fully classified as visual-only.

The shipped tranche is intentionally narrow: drop only completed frames that are
stale, have an empty blocker set, and use `.emptyVisualOnly` reconciliation.
Treat non-empty side-effect reconciliation as a separate proposal after the
visual-only path has proved useful and safe on real gallery/layout diagnostics.

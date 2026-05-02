# Async Frame Stale Policy

## Status

Stages 1 and 2 are implemented. The observational drop-blocker classifier
described in Stage 4 is also implemented, but it is diagnostic only for
completed-frame drops. Scheduler Stages 3A through 3D are implemented. The first
Stage 3C, abortable prepared frame heads, was attempted and reverted; see
[`../plans/2026-04-26-002-frame-head-abort-plan.md`](../plans/2026-04-26-002-frame-head-abort-plan.md).
The shipped replacement is the Option 3 draft-transaction tranche recorded in
[`../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md`](../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md).

Pre-start queued-tail cancellation has shipped. Ordered commit remains the
policy for started or completed frame-tail work and all future
completed-frame-dropping work. See
[`ASYNC_RENDER_GENERATION_SCHEDULER.md`](ASYNC_RENDER_GENERATION_SCHEDULER.md)
for the shipped generation scheduler design. For the consolidated current
status, see
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md).

The current async frame-tail renderer intentionally preserves ordered commit:
when a worker frame finishes, the main actor commits it before newer input state
is rendered and presented. This is conservative, but correct. It avoids
skipping lifecycle, focus, task, preference, animation, and retained-cache side
effects.

This document defines the requirements for changing that policy later.

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
- frames commit in order,
- started and completed computed frames are not dropped,
- newer frames are not presented ahead of older uncommitted side effects.

The async stress tests intentionally enforce this behavior. They block worker
work, queue input, and verify that the blocked frame does not get skipped or
presented out of order.

## Policy

Do not drop started or completed computed pipeline frames until a dedicated
completed-frame policy is implemented and tested. Pre-start queued-tail
cancellation is the only shipped non-commit path.

Any future stale-frame policy must classify a frame before dropping it:

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

If dropping completed results is ever needed, introduce a main-actor
reconciliation pass:

```
struct SkippedFrameReconciliation {
  var lifecycle: [LifecycleOperation]
  var taskOperations: [TaskOperation]
  var handlerInstallations: [HandlerInstallation]
  var focusSync: FocusSyncDelta
  var scrollSync: ScrollSyncDelta
  var preferences: PreferenceObservationDelta
  var retainedStateAction: RetainedStateAction
  var diagnostics: DroppedFrameDiagnostics
}
```

A skipped frame should either:

- produce an empty reconciliation because it is proven visual-only, or
- produce a reconciliation that advances main-actor state as if the necessary
  nonvisual side effects had been committed.

If the runtime cannot produce that reconciliation, it must commit the frame.

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

Diagnostics must count both:

- input accepted while the main actor was suspended,
- frames skipped or cancelled because newer input superseded them.

The two counters answer different questions. The first proves responsiveness;
the second measures staleness pressure.

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
- [ ] Add signals for the currently-unobservable barriers: animation
  completions, preference observation deltas, focus-binding drift relative to
  the previous frame, retained baseline updates, and presentation repaint
  dependencies.
- [ ] Only then permit a narrow visual-only case, such as a superseded animation
  tick with no lifecycle, focus, preference, task, handler, custom-layout cache,
  or retained-baseline transition.

Stage 4 result so far:

- `FrameDropEligibility` classifies completed frames as diagnostic blockers.
- `FrameDiagnosticsLogger` writes the classifier result as `drop_blockers`.
- The classifier intentionally injects `.unobservable` when no specific blocker
  is found, so `canDrop` remains false for every classified runtime frame.
- No runtime behavior uses the classifier to drop or reconcile frames.

Commit boundary:

```bash
git commit -m "refactor(runtime): classify stale frame drop eligibility"
```

### Stage 5: Reconciliation for skipped completed frames

- Add a main-actor reconciliation pass for any skipped completed frame.
- Apply lifecycle/task/focus/preference/retained-state deltas in a deterministic
  order.
- Force presentation repaint recovery when raster baselines no longer match.
- Keep the default path as ordered commit.

Commit boundary:

```bash
git commit -m "feat(runtime): reconcile skipped async frame results"
```

## Required Tests

- Queued input during a blocked worker does not present newer state ahead of the
  blocked frame under the current policy.
- Generation IDs increase monotonically across rerenders and focus-sync loops.
- Superseded jobs can be cancelled only before worker start.
- Completed worker results still commit unless explicitly classified droppable.
- Lifecycle appear/disappear edges are not lost when a frame is superseded.
- Tasks start and cancel exactly once across skipped generations.
- Focus binding and focused values converge after a skipped or cancelled
  generation.
- Scroll-position sync remains deterministic.
- Retained layout/raster caches do not reuse artifacts from uncommitted frames.
- Presentation drop recovery still forces full repaint independently of pipeline
  cancellation.
- Diagnostics report generation, drop reason, and reconciliation state.

## Recommendation

Keep the current ordered-commit policy for any started or completed tail job
until eligibility classification and reconciliation are both tested.

The next concrete tranche should return to Stage 3C, not Stage 3D directly:
first redesign prepared frame heads so side effects are draft-only or safely
abortable, using the post-mortem from the reverted attempt as the starting
constraint. Then implement Stage 3D as cancellation before worker start only. Do
not start by dropping completed worker results. Pre-start cancellation is the
safest first optimization because it avoids reconciling already-computed frame
artifacts and worker-owned cache effects.

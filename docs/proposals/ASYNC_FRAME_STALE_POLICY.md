# Async Frame Stale Policy

## Status

Proposed policy for any future frame-tail cancellation or generation-dropping
work.

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
- custom layout falls back to the main actor,
- overlay application, semantics, draw, and raster run on the worker,
- the main actor awaits the worker,
- frames commit in order,
- computed frames are not dropped,
- newer frames are not presented ahead of older uncommitted side effects.

The async stress tests intentionally enforce this behavior. They block worker
work, queue input, and verify that the blocked frame does not get skipped or
presented out of order.

## Policy

Do not drop computed pipeline frames until a dedicated generation policy is
implemented and tested.

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

## Safe First Target

The first plausible stale-frame optimization is cancellation before worker
start.

If a frame is queued for the frame-tail worker but has not started, and a newer
generation supersedes it, the runtime can cancel the queued job before any
worker-owned retained state changes. Even then, the main actor must not have
treated that frame as committed. It should discard the resolve result and rerun
from the newest state.

This is safer than dropping a completed worker result because it avoids cache
and artifact reconciliation. It still needs generation IDs and tests.

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

- render generation,
- worker queue generation,
- worker result generation,
- newest desired generation at result receipt,
- drop eligibility,
- drop reason,
- whether reconciliation ran,
- whether presentation needed full repaint recovery afterward.

Diagnostics must count both:

- input accepted while the main actor was suspended,
- frames skipped or cancelled because newer input superseded them.

The two counters answer different questions. The first proves responsiveness;
the second measures staleness pressure.

## Migration Plan

### Stage 1: Document and assert ordered commit

- Keep the current no-drop behavior.
- Add a dedicated test name that states computed async frames commit in order
  even when newer input is queued.
- Add diagnostics text explaining that stale worker results are currently
  committed, not dropped.

Commit boundary:

```bash
git commit -m "test(runtime): assert stale async frames commit in order"
```

### Stage 2: Add generation IDs without dropping

- Thread a render generation through `DefaultRenderer.renderAsync` and
  `FrameTailRenderer`.
- Log generation IDs in `FrameDiagnostics`.
- Assert results still commit in order.
- Do not change scheduling or presentation behavior.

Commit boundary:

```bash
git commit -m "refactor(runtime): tag async render generations"
```

### Stage 3: Add cancellation before worker start

- Teach the serial worker to skip jobs that have not started and are superseded.
- Restrict cancellation to jobs with no worker-owned mutation.
- Rerender from newest state after cancellation.
- Keep completed worker results on the ordered commit path.

Commit boundary:

```bash
git commit -m "feat(runtime): cancel superseded unstarted frame-tail jobs"
```

### Stage 4: Classify visual-only completed frames

- Add a conservative `FrameDropEligibility` classifier.
- Start with all completed frames classified as `mustCommit`.
- Add tests for the barriers listed above.
- Only then permit a narrow visual-only case, such as a superseded animation
  tick with no lifecycle, focus, preference, task, handler, custom-layout cache,
  or retained-baseline transition.

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

Keep the current ordered-commit policy until generation tagging, cancellation,
eligibility classification, and reconciliation are all tested.

The next concrete tranche should be Stage 1 or Stage 2. Do not start by
dropping completed worker results. Cancellation before worker start is the
safest first optimization because it avoids reconciling already-computed frame
artifacts and worker-owned cache effects.

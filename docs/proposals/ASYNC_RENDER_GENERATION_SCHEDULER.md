# Async Render Generation Scheduler

## Status

Stages 3A through 3D are implemented. The first Stage 3C frame-head abort
attempt was reverted; see
[`../plans/2026-04-26-002-frame-head-abort-plan.md`](../plans/2026-04-26-002-frame-head-abort-plan.md).
The shipped replacement is the Option 3 draft-transaction tranche recorded in
[`../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md`](../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md).

The shipped runtime can cancel a queued tail job before worker layout starts
when a newer render intent is pending. The corresponding prepared frame head is
discarded through draft runtime registrations plus graph/state checkpoints.
Completed and started tail work stays on the ordered-commit path.

For the consolidated current status, see
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md).

## Problem

Stage 2 added render-generation diagnostics, but generations are still passive.
The current async path is:

```
RunLoop consumes ScheduledFrame
RunLoop handles focus-sync rerenders in a local loop
RunLoop awaits DefaultRenderer.renderAsync(...)
DefaultRenderer resolves and mutates renderer-owned main-actor state
DefaultRenderer submits layout/raster tail work
RunLoop commits and presents returned artifacts
RunLoop drains the next event batch
```

Input can be queued while the main actor is suspended, but those queued events
are not handled until the current render returns. That is why the existing
ordered-commit tests pass: the run loop does not create a newer desired
generation while the current frame is still in flight.

Adding cancellation only to the serial worker is therefore insufficient:

- there is normally only one active render submission per `DefaultRenderer`,
- a newer render is not submitted while the current render is awaited,
- by the time tail work exists, resolve has already updated live renderer
  structures,
- discarding the tail result without a renderer abort path can leave `ViewGraph`,
  runtime registrations, animation state, or diagnostics inconsistent.

## Goals

- Preserve ordered commit for any frame whose worker job has started.
- Coalesce queued render intent before starting a new frame.
- Create a cancellable pre-start worker boundary only after renderer state can
  safely abort a prepared frame.
- Keep completed worker results on the existing ordered-commit path.
- Make cancellation pressure visible in diagnostics before enabling skips.

## Non-goals

- Dropping completed worker results.
- Reconciling skipped lifecycle, task, focus, preference, animation, or retained
  cache effects.
- Running `View.body` or runtime registration mutation off the main actor.
- Allowing multiple concurrent renders against one `DefaultRenderer`.

## Design

### 1. Separate desired generation from render generation

The run loop needs a main-actor generation coordinator:

```swift
package struct RenderIntentGeneration: Comparable, Equatable, Sendable {
  package var rawValue: UInt64
}

@MainActor
package final class RunLoopRenderGenerationCoordinator {
  package private(set) var newestDesired: RenderIntentGeneration
  package private(set) var activeRender: RenderGeneration?
  package private(set) var pendingIntent: ScheduledFrame?

  package func recordDesiredFrame(_ frame: ScheduledFrame)
  package func beginRender() -> (RenderGeneration, ScheduledFrame)?
  package func finishRender(_ generation: RenderGeneration)
}
```

`RenderIntentGeneration` answers "what state does the run loop now want?"
`RenderGeneration` continues to answer "which renderer pass produced this
artifact bundle?"

The two start equal for the current ordered path. They intentionally diverge
once input is observed during an active render.

### 2. Coalesce render intent before rendering

The first implementation step should stay entirely in `RunLoop`:

1. Drain all immediately available event batches before starting a render.
2. Handle those events on the main actor.
3. Let `FrameScheduler` coalesce their invalidations into one `ScheduledFrame`.
4. Start exactly one render for the newest coalesced intent.

This cancels only not-yet-started render intent. It does not cancel a renderer
pass that has begun, and it does not require any rollback support.

This is a real improvement under input bursts because a queue of input batches
arriving while a frame is rendering can collapse into one next render instead
of one render per batch.

Diagnostics should add:

- `desired_generation`
- `render_generation`
- `coalesced_event_batches`
- `coalesced_wake_causes`
- `stale_frame_policy=commit_ordered`

### 3. Add a frame-head draft before worker cancellation

Worker pre-start cancellation is only safe after `DefaultRenderer` can prepare a
frame head that is either committed or aborted.

The previous implementation attempted this by staging runtime registrations and
then restoring live registries from the per-frame draft. That was the wrong
source of truth: the draft captured only the current dirty frontier and cache
hits, not every committed handler and alias still live outside the current
resolve walk.

Target shape:

```swift
@MainActor
package struct FrameHeadDraft {
  package var generation: RenderGeneration
  package var resolved: ResolvedNode
  package var frameTailInput: FrameTailInput
  package var commitInputs: FrameCommitInputs
  package var abort: @MainActor () -> Void
}

@MainActor
package func prepareFrameHead(...) -> FrameHeadDraft

@MainActor
package func finishFrame(
  draft: FrameHeadDraft,
  tail: FrameTailOutput
) -> FrameArtifacts
```

The hard requirement is not the exact type shape. The hard requirement is that
`abort` restores or discards every live effect produced while preparing the
draft.

The draft must account for:

- `ViewGraph.beginFrame()` state,
- dirty-node evaluation and `ViewNode.apply(...)`,
- runtime registry reset/install work,
- presentation host composition,
- animation transition collection and interpolation state,
- worker custom-layout cache updates,
- retained frame-tail inputs.

If these cannot be restored cheaply, the next prerequisite is a
snapshot-producing resolve path that writes into draft registration builders and
draft graph state instead of live committed state.

## Restart Proposal

Resume from the shipped prepare-tail-finish split, with ordered commit preserved
throughout the first tranche.

### R0: Rebaseline Cancellation Pressure And Runtime Coverage

Before changing runtime behavior:

- Run diagnostics on real examples that exercise async layout and runtime input:
  gallery, layouts, and any host/demo surface with ScrollView-heavy content.
- Inspect `coalesced_intent_requests`, `coalesced_event_batches`,
  worker layout/raster timings, `drop_blockers`, and main-actor
  blocked/suspended timings.
- Add composed async-path tests before implementation. The minimum set is:
  gallery tab click, ScrollView indicator click, ScrollView indicator drag,
  pointer scroll burst, key command dispatch, drop destination dispatch, focus
  sync rerender, and lazy indexed ScrollView content.
- Prefer `RunLoop.run()` and real-shaped event streams for those tests. Direct
  `handleMouseEvent` plus `renderPendingFrames` is not enough to catch the
  failure class from the reverted attempt.

Exit with a diagnostics-backed list of the frames that would benefit from
pre-start cancellation and the blockers that keep completed results on the
ordered-commit path.

### R1: Make Prepared Frame Side Effects Draft-Only

Redesign Stage 3C around draft-only effects first, checkpoint/restore second.
The prepared frame should be an object that either:

- finishes exactly once and applies side effects to live runtime state, or
- aborts exactly once and discards side effects that never reached live runtime
  state.

Implementation direction:

- Route runtime registration changes into a `FrameHeadRegistrationDraft` or
  equivalent commit builder during resolve.
- Do not clear or mutate live registries during `prepareFrameHead`.
- At `finishFrame`, apply the recorded mutation to live registries and restore
  handlers from the committed graph if a rebuild is needed.
- At `abortFrameHead`, discard the draft. If any live state has already mutated,
  restore it from a checkpoint whose coverage is proven by tests.
- Keep animation completions deferred until `finishFrame`; abort discards the
  deferred completions.
- Keep worker custom-layout cache updates in `FrameTailLayoutOutput` and apply
  them only from `finishFrame`.

The most important rule: do not merge draft registry snapshots into live as the
post-reset restore mechanism. If live registries need reconstruction, walk the
committed `ViewGraph` and restore each node's committed handlers, including alias
nodes.

Required R1 proof:

- abort after a broad reset-shaped prepare leaves actions, pointer routes,
  gestures, key commands, drop destinations, focus bindings, focused values,
  scroll positions, lifecycle, tasks, and preference observations intact;
- abort after selective dirty evaluation leaves untouched sibling and alias
  handlers intact;
- abort does not fire lifecycle/task effects or animation completions;
- a fresh render after abort produces the same artifacts and live registrations
  as if the aborted frame had never been prepared.

### R2: Add Pre-Start Cancellation

After R1, add explicit tail-job states:

```swift
enum FrameTailJobState: Sendable {
  case queued(RenderGeneration)
  case started(RenderGeneration)
  case completed(RenderGeneration)
  case cancelledBeforeStart(RenderGeneration)
}
```

Cancellation is legal only while the job is queued. The dequeue boundary is the
last cancellation point. Once layout, custom-layout cache work, overlay
application, semantics, draw, or raster has started, the job is `mustCommit`.

The run-loop shape is:

1. Prepare a frame head on the main actor.
2. Submit the tail as queued work.
3. Continue accepting event batches while the tail remains queued.
4. If newer desired state arrives and the token cancels before start, abort the
   prepared frame and prepare the newest generation.
5. If the tail has started or completed, await it, finish the frame, and commit
   in order before rendering newer state.

Diagnostics for this stage should add:

- `tail_job_state`
- `tail_cancel_reason`
- `cancelled_render_count`
- `newest_desired_at_tail_start`
- `newest_desired_at_tail_result`
- `stale_frame_policy=cancel_pending_before_start`

### R3: Keep Completed-Frame Drops Out Of Scope

Completed worker results remain ordered-commit during this restart. The
observational `FrameDropEligibility` classifier is useful for diagnostics, but it
is not yet an action policy. A later stage can make a narrow visual-only case
droppable only after each currently-unobservable barrier has either a diagnostic
signal or a reconciliation path.

### 4. Add a cancellable tail submission

Only after frame-head abort exists should `FrameTailRenderer` gain cancellable
submissions.

```swift
package enum FrameTailCancellation: Sendable {
  case cancelledBeforeStart(RenderGeneration)
}

package enum FrameTailSubmissionResult: Sendable {
  case completed(FrameTailOutput)
  case cancelled(FrameTailCancellation)
}

package func submitTail(
  _ input: FrameTailInput,
  cancellation: FrameTailCancellationToken
) async -> FrameTailSubmissionResult
```

The worker may check cancellation at dequeue time only. Once it starts layout,
custom-layout cache work, overlay application, semantics, draw, or raster, the
job becomes `mustCommit` and returns completed output.

This keeps the first cancellation target narrow:

```
queued, not started -> may cancel
started or completed -> ordered commit
```

### 5. Let the run loop race event intake with tail completion

With draft abort and cancellable tail submission available, the run loop can
observe events while a tail job is queued:

```swift
while running {
  let draft = renderer.prepareFrameHead(...)
  let tailTask = Task { await renderer.submitTail(draft.frameTailInput, cancellation: token) }

  while true {
    switch await next(tailTask, eventPump) {
    case .eventBatch(let events):
      handle(events)
      coordinator.recordDesiredFrame(...)
      if token.cancelIfNotStarted() {
        renderer.abort(draft)
        break // prepare newest generation
      }
      continue // started: must commit when tail completes

    case .tail(.completed(let tail)):
      let artifacts = renderer.finishFrame(draft: draft, tail: tail)
      commitAndPresent(artifacts)
      break

    case .tail(.cancelled):
      renderer.abort(draft)
      break
    }
  }
}
```

This is deliberately still single-render-per-renderer. It does not permit two
resolved frames to be in flight against one renderer.

## Diagnostics

Add fields before enabling runtime cancellation:

- `desired_generation`
- `active_render_generation`
- `newest_desired_at_result`
- `tail_job_state`: `queued`, `started`, `completed`, `cancelled_before_start`
- `tail_cancel_reason`
- `coalesced_event_batches`
- `cancelled_render_count`
- `stale_frame_policy`: `commit_ordered` or `cancel_pending_before_start`

The important distinction is:

- queued input during suspension measures responsiveness,
- coalesced event batches measure avoided renders,
- cancelled render count measures actual stale-generation pressure.

## Migration Plan

### Stage 3A: Coalesce not-yet-started render intent

- [x] Drain all currently queued event batches before starting the next render.
- [x] Keep completed and active renders on the ordered-commit path.
- [x] Add diagnostics for desired generation and coalesced event batches.
- [x] Add tests proving an input burst queued during a blocked render produces one
  next render for the final state.

Stage 3A result:

- The run loop drains all currently buffered event batches before starting the
  next render.
- Runtime TSV diagnostics include `desired_generation`,
  `coalesced_event_batches`, and `coalesced_wake_causes`.
- The ordered-commit regression now proves a queued input burst still commits
  the already-blocked frame, then renders only the final coalesced state.

Commit boundary:

```bash
git commit -m "refactor(runtime): coalesce queued render intent"
```

### Stage 3B: Extract frame-head draft and finish boundary

- [x] Split `DefaultRenderer.renderViewAsync` into prepare-tail-finish helpers.
- [x] Keep behavior identical and still await every tail result.
- [x] Add tests proving sync and async render artifacts remain equivalent.

Stage 3B result:

- `DefaultRenderer.renderViewAsync` now prepares a `FrameHeadDraft`, awaits the
  async tail, then finishes the frame through an explicit commit/diagnostics
  boundary.
- The split preserves ordered commit and does not add cancellation or abort
  behavior.
- Async frame-tail tests include a sync/async artifact parity check with
  diagnostics disabled so timing fields cannot mask pipeline drift.

Commit boundary:

```bash
git commit -m "refactor(renderer): split async frame head and commit"
```

### Stage 3C: Add frame-head abort or draft-only side effects

Execution plan:

- [`../plans/2026-04-26-002-frame-head-abort-plan.md`](../plans/2026-04-26-002-frame-head-abort-plan.md)
- [`../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md`](../plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md)

- [x] Add an abort path for prepared frame heads, or route resolve side effects
  into draft-only state.
- [x] Prove abort leaves `ViewGraph`, runtime registrations, focus sync,
  animation state, and diagnostics ready for a fresh render.

Stage 3C result:

The first checkpoint/registration-staging implementation was reverted after real
runtime scrolling and clicking regressions. The shipped replacement routes
runtime registrations through draft registries, rebuilds live registrations from
the committed `ViewGraph`, and uses checkpoints for graph, frame resolve,
observation, animation, lifecycle/task, retained tail, and worker-cache state.
The abort path remains package-internal test infrastructure; it is not a public
renderer API.

### Stage 3D: Add cancellable pre-start tail jobs

- [x] Add dequeue-time cancellation to the frame-tail worker.
- [x] Cancel only jobs that have not started.
- [x] Return started jobs through the ordered-commit path.
- [x] Keep cancellation disabled for completed results.

Stage 3D result:

The run loop uses the cancellable tail path only while a tail job is queued.
When a newer render intent is pending before worker layout starts, it cancels
the queued tail, discards the prepared frame head, logs
`tail_job_state=cancelled_before_start`, and prepares the newer generation.
Started and completed jobs still finish and commit in order.

Commit boundary:

```bash
git commit -m "feat(runtime): cancel superseded unstarted frame-tail jobs"
```

## Required Tests

- Input queued while a render is blocked can coalesce into one next render.
- Render-intent coalescing does not skip the currently blocked committed frame.
- Generation diagnostics show desired generation ahead of active generation
  under queued input.
- A prepared frame head can be aborted without leaving stale runtime
  registrations installed.
- A prepared frame head can be aborted without firing lifecycle or task commit
  effects.
- A queued tail job can be cancelled before its worker hook fires.
- A tail job that has fired its worker-start hook cannot be cancelled and must
  commit in order.
- Focus synchronization still converges after a coalesced or cancelled
  generation.
- Scroll-position sync and preference observation remain deterministic.

## Recommendation

Keep the cancellation point at dequeue time only: a queued tail job may be
cancelled before it starts, while started or completed tail work must still
finish through the ordered-commit path. Completed-frame dropping remains a
separate future tranche.

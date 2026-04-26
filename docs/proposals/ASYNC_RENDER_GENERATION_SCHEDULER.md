# Async Render Generation Scheduler

## Status

Stages 3A, 3B, and 3C implemented. Draft design for Stage 3D after
[`ASYNC_FRAME_STALE_POLICY.md`](ASYNC_FRAME_STALE_POLICY.md) Stage 2.

The short version: do not implement worker-job cancellation directly inside
`FrameTailRenderer` until the worker has an explicit pre-start submission state.
The run loop can now represent queued render intent, and `DefaultRenderer` can
abort a prepared frame head, but completed and started tail work still stays on
the ordered-commit path.

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

- [x] Add an abort path for prepared frame heads, or route resolve side effects
  into draft-only state.
- [x] Prove abort leaves `ViewGraph`, runtime registrations, focus sync,
  animation state, and diagnostics ready for a fresh render.

Stage 3C result:

- Async frame-head preparation now starts a single-use draft transaction. A draft
  can finish or abort exactly once.
- `ViewGraph` and `FrameResolveState` are checkpointed before frame-head
  mutation and restored on abort.
- Runtime registrations resolve into draft registries and are installed into
  live registries only when the frame finishes.
- `AnimationController` defers frame-head completion closures until finish and
  restores animation state on abort.
- Retained frame-tail state remains commit-only and is included in the abort
  checkpoint seam.
- `AsyncFrameTailRenderingTests` covers graph/registration rollback and
  animation-completion discard for a prepared frame head.

Commit boundary:

```bash
git commit -m "refactor(renderer): abort uncommitted frame heads"
```

### Stage 3D: Add cancellable pre-start tail jobs

- Add dequeue-time cancellation to the frame-tail worker.
- Cancel only jobs that have not started.
- Return started jobs through the ordered-commit path.
- Keep cancellation disabled for completed results.

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

Implement Stage 3D next. Keep the cancellation point at dequeue time only: a
queued tail job may be cancelled before it starts, while started or completed
tail work must still finish through the ordered-commit path.

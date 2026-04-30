---
adr: "0004"
title: "Frame-head abort attempted and reverted"
status: reverted
date: 2026-04-26
sources:
  - docs/plans/2026-04-26-002-frame-head-abort-plan.md
  - docs/proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md
  - docs/ASYNC_RENDERING.md
---

# ADR-0004: Frame-head abort attempted and reverted

## Context

The async frame-tail renderer offloads measure → place → semantics →
draw → raster onto a worker. Stages 3A and 3B of the
[ASYNC_RENDER_GENERATION_SCHEDULER](../proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md)
proposal landed cleanly: the run loop coalesces queued render intent
before rendering, and `DefaultRenderer.renderViewAsync` has explicit
prepare-tail-finish helpers.

Stage 3C — making prepared frame heads abortable — was the next
tranche. The goal was to let a future runtime cancel a queued,
not-yet-started frame-tail job without committing stale renderer state:

```swift
let draft = renderer.prepareFrameHead(...)
renderer.abort(draft)
let next = await renderer.renderAsync(...)
```

After aborting `draft`, the renderer must behave as though that frame
head was never prepared.

## Decision

Stage 3C was implemented (commits `16e4917`, `40a17fc`) and then
**reverted** (commits `56995ff`, `263003f`, plus cleanup in `c30c5fe`).
The animation-completion deferral landed in `0cacb9e` is kept; the
checkpoint scaffolding on `ViewGraph` / `ViewNode` /
`DependencyTracker` / `FrameResolveState` was deleted as dead code.

## Status

Reverted. The current async-rendering contract retains commit-only
ordering with no worker cancellation; the only stale-frame policy is
`mustCommit`.

## What broke

Real-terminal scrolling and clicking regressed against the gallery
example. Reverting just the registration staging restored expected
behavior, but keeping the abort scaffolding around the revert was
incompatible with staging removal — the abort path depended on
`FrameHeadDraft` having consume/restore mechanics, so the abort path
had to come out too.

## Root cause

The implementation diverged from the plan in one critical step. The plan
said to apply the recorded live mutation and then **restore handlers
from the committed graph** by walking `ResolvedNode`s and replaying each
node's `NodeHandlers` into the live registries. The implementation did
something narrower: it merged the per-frame draft registry snapshots
into live.

Those are not equivalent. Draft registries only contain what was
*touched during the current frame's resolve* — the dirty frontier's
evaluator plus cache-hits. They omit:

- Subtrees outside the dirty frontier whose evaluators never ran.
- Alias-only nodes (e.g. ScrollView vertical/horizontal indicator
  identities) promoted out of the dirty frontier.
- Anything in `nodesByIdentity` whose evaluator chain didn't walk this
  frame.

For `.removeSubtrees(roots)` the bug was mostly self-cancelling. For
`.resetAll` the bug was direct: live registries were wiped, but the
draft only carried what the root evaluator walked. Alias nodes
disappeared from live until the next full re-resolve.

User-visible symptom: scroll-indicator clicks missed, drag-tracking
fired against stale handlers, `.keyCommand` and `.dropDestination` fell
through to the wrong scope.

## Why tests didn't catch it

Most existing scroll/click coverage drives `RunLoop.handleMouseEvent`
synchronously and then renders pending frames — never entering
`renderViewAsync`. Tests that do exercise the async path use the
terminal-input harness, which does not exercise the registration
staging that was added.

## Consequences

- Worker-job cancellation remains unimplemented. The runtime can
  coalesce queued render intent before starting a later render, but it
  cannot drop a frame already in flight.
- The next cancellation step must be redesigned around **draft-only
  side effects** or another rollback model before `FrameTailRenderer`
  accepts cancellable submissions.
- Future async-rendering tests must exercise the `RunLoop.run()` path
  end-to-end against real-shaped event streams (scroll bursts, drag
  sequences, click resolution) — not just synchronous handler calls.

This ADR is preserved as institutional memory: a sufficiently subtle
runtime invariant can be silently violated by a "structural"
implementation that looks correct in isolation. The next attempt should
budget extra time for end-to-end coverage of the kind that reproduced
this regression.

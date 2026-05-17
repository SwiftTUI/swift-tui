---
adr: "0019"
title: "Runtime render pipeline is composed in SwiftTUIRuntime"
status: accepted
date: 2026-05-17
sources:
  - docs/proposals/PIPELINE_DRIVER_AUDIT.md
  - docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
  - docs/plans/2026-05-17-003-stage-3-compose-pipeline-plan.md
  - Sources/SwiftTUIRuntime/SwiftTUI.swift
---

# ADR-0019: Runtime render pipeline is composed in SwiftTUIRuntime

## Context

`SwiftTUICore.Pipeline.Renderer<Root>` described a clean seven-phase closure
pipeline, but production frames never used it. `DefaultRenderer` owns the real
runtime concerns: main-actor view evaluation, live graph mutation, runtime
registrations, presentation portals, observation tracking, animation
transactions, retained tail input, async worker boundaries, and completed-frame
drop policy.

Those effects cannot be represented honestly by the generic core helper without
turning it into another runtime. Keeping both would preserve the audit finding:
a documented renderer exists, while production frames take a separate path.

## Decision

Supersede the generic `Renderer<Root>` with a runtime-owned
`RuntimeRenderPipeline` and remove the old production type.

The runtime composition models the actual stages:

```text
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit
```

The frame tail remains fused. Measure, place, semantics, draw, and raster are
still visible in `FrameArtifacts` and diagnostics, but the runtime schedules
them as one performance node.

### Stage order is enforced by the executor, not by prose (F1, F12 amendment)

The initial Stage 3 implementation of `RuntimeRenderPipeline` was ceremony: it
threaded caller closures, stored an unread `headStage` field, and guarded a
frozen `stageOrder` array with a `precondition`. Stage order was asserted by a
comment and a run-time check, not enforced by a mechanism — the audit recorded
this as Finding F1, with the `CaseIterable` stage enum (F12) carrying metadata
that no control flow ever switched on.

The pipeline-driver follow-up resolves this with **Option B (real
composition)**: `RuntimeRenderPipeline` is now a *sequenced executor*. Each
`render*` entry point iterates `RuntimeRenderStageName.orderedComposition` and
dispatches every stage through an **exhaustive `switch`** on the case,
invoking the caller-supplied handler stored in a small `...StageHandlers`
struct keyed by stage. Stage order is therefore a structural property of the
executor loop: adding, removing, or reordering a case forces every `switch` to
be updated, so the ordering cannot drift silently. The `headStage` field, the
`stageOrder` initializer parameter, the canonical-order `precondition`, and the
unread `RuntimeFrameHeadStage` config type are all deleted — there is no
expressible pipeline that runs a non-canonical order.

Option A (delete the pipeline type and let the three `render*` functions call
the stages directly) was the measured fallback. It was **not** taken: the
allocation-budget guard (`RenderPipelineStructureTests.composedRenderAllocationBudget`,
1000 frames of a 20-row `VStack`/`ForEach` at 80×40) measured ~4.45s pre-refactor
and ~4.64s post-refactor in a debug build — well within the 2× regression budget.
Option B added no measurable hot-path cost, so the real-composition executor
stands.

The head remains an abortable transactional stage, but it no longer exposes a
declared rollback-effect set. The follow-on Finding 4 work moved presentation,
observation, animation, registration publication, and frame-input state behind
draft or commit boundaries. Internal graph/frame selector restore mechanics are
implementation details of prepared-frame discard, not a runtime pipeline
contract.

## Status

Accepted on 2026-05-17 as Stage 3 of the pipeline-driver hardening roadmap.
Amended on 2026-05-17 after the Finding 4 resolve-effect narrowing plan removed
the declared frame-head effect model.
Amended again on 2026-05-17 by the pipeline-driver follow-up (Phase 2): stage
order is now enforced by the sequenced-executor loop rather than a `precondition`,
resolving findings F1 and F12.

## Consequences

- `DefaultRenderer` is the live runtime driver and all production render
  strategies execute one composition.
- `RuntimeRenderPipeline` stays stateless at the render call sites instead of
  being stored on `DefaultRenderer`; the pipeline is the ordering contract, not
  renderer-owned mutable state. It is a sequenced executor with no
  configuration: stage order is the canonical `RuntimeRenderStageName`
  composition the executor loop walks, enforced by exhaustive `switch`
  dispatch rather than a `precondition`.
- The old generic renderer is removed from public API instead of being relabeled
  as architecture.
- Commit is the side-effect boundary for lifecycle, task, registration, focus,
  presentation, and animation effects. A prepared frame head can still be
  discarded before commit, but its internal draft/checkpoint mechanics do not
  publish user-visible runtime state.
- Future stages can refine raster reuse and completed-frame drop policy against
  one runtime composition instead of multiple forked render bodies.

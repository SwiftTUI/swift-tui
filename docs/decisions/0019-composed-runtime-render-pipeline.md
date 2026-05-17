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

The head is a declared-effect transactional stage. It names the five existing
mutable subsystems: `viewGraph`, `frameState`, `presentationPortalState`,
`observationBridge`, and `animationController`. Async cancellation still uses
the existing checkpoint/rollback mechanics; this ADR relocates and names that
contract, it does not narrow the effect set.

## Status

Accepted on 2026-05-17 as Stage 3 of the pipeline-driver hardening roadmap.

## Consequences

- `DefaultRenderer` is the live runtime driver and all production render
  strategies execute one composition.
- `RuntimeRenderPipeline` stays stateless at the render call sites instead of
  being stored on `DefaultRenderer`; the pipeline is the ordering contract, not
  renderer-owned mutable state.
- The old generic renderer is removed from public API instead of being relabeled
  as architecture.
- "Commit is the only side-effect boundary" remains aspirational. Moving the
  head's live mutations toward commit is a future architectural change, not part
  of Stage 3.
- Future stages can refine raster reuse and completed-frame drop policy against
  one runtime composition instead of multiple forked render bodies.

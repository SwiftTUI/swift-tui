---
title: "refactor: compose the runtime render pipeline"
type: refactor
status: completed
date: 2026-05-17
depends_on:
  - "./2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "./2026-05-16-002-stage-1-unify-render-head-plan.md"
  - "./2026-05-17-001-stage-2-name-hidden-stages-plan.md"
  - "./2026-05-17-002-stage-0-contract-guards-plan.md"
  - "../decisions/0018-late-preference-reconciliation-bound.md"
---

# Stage 3 Plan: Compose the Runtime Render Pipeline

## Goal

Make `DefaultRenderer` execute one explicit runtime composition instead of
owning the frame order as a long imperative method body. The composition models
the real runtime stages:

```text
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit
```

The fused frame tail intentionally keeps measure, place, semantics, draw, and
raster together as one performance node. The public seven-phase products remain
the inspection model, but the runtime driver must model its actual scheduling
shape.

## Current Source Anchors

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `DefaultRenderer.render(...)`, `renderAsync(...)`, and
    `renderAsyncCancellable(...)` are production entry points.
  - `computeFrameHead(...)` is the Stage 1 unified head seam.
  - `AnimationInjectionStage` and `LatePreferenceReconciliationStage` are the
    Stage 2 named hidden stages.
  - `renderView(...)` still contains sync tail and commit orchestration.
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `FrameHeadDraft`, `FrameHeadCheckpoints`, `FrameTailInput`, and tail output
    records are the products the composed runtime pipeline should pass between
    stages.
- `Sources/SwiftTUICore/Pipeline/Pipeline.swift`
  - The generic `Renderer<Root>` is not the live runtime driver. Stage 3 must
    either make it live or remove it.

## Decisions

- Supersede the generic `Renderer<Root>` with a runtime-owned composed pipeline
  and delete the old production type. `DefaultRenderer` needs main-actor view
  evaluation, runtime registries, frame-head checkpoints, animation
  transactions, and async execution strategies; the generic core helper cannot
  honestly model that without becoming a second runtime.
- Keep the frame tail fused. Composition should express one tail node rather
  than allocate separate runtime call objects for measure/place/semantics/draw/
  raster.
- Treat the frame head as a declared-effect transactional stage. Stage 3 names
  the five existing mutable subsystems; it does not attempt to move those
  effects to commit.

See ADR-0019.

## Tasks

- [x] Create the Stage 3 ADR documenting the `Renderer<Root>` decision, fused-tail
   choice, and declared-effect head contract.
- [x] Add a runtime pipeline composition type with ordered stage names, the
   frame-head effect set, and sync/async/cancellable execution strategies.
- [x] Split animation injection out of `computeFrameHead(...)` so the head draft is
   produced first, then explicitly rewritten by the animation-injection stage.
- [x] Extract one-shot fused-tail and commit helpers, and route `render(...)`
   through the composed pipeline.
- [x] Extract async late-preference and fused-tail helpers, and route
   `renderAsync(...)` plus `renderAsyncCancellable(...)` through the same
   composition with execution-strategy-specific cancellation/drop behavior.
- [x] Delete the old production `Renderer<Root>` and `NoOpRoot` helper, then update
   tests and public-API baselines so no dead driver remains in the product.
- [x] Add focused tests for the runtime composition metadata and keep the Stage 0
   contract suites green.
- [x] Run validation.

## Implementation Notes

- `RuntimeRenderPipeline` is a stateless runtime composition value created at
  the render call sites. It is intentionally not stored in `DefaultRenderer`:
  an intermediate stored-value version changed the renderer's stored layout and
  regressed `Examples/gallery`'s `TextInputTab` one-shot render path. Keeping
  the pipeline local preserves the explicit composition without making it part
  of renderer state.
- `RuntimeRenderPipeline.stageOrder` is computed from the canonical static
  order, so call-site creation does not allocate a fresh stage-order array per
  frame.
- `Renderer<Root>` and `NoOpRoot` were removed from the public surface. The
  public API inventory and baseline were regenerated to make that removal
  explicit.

## Validation

Passed:

- `swiftly run swift test --filter SwiftTUITests.RuntimeRenderPipelineTests`
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
- `swiftly run swift test --filter SwiftTUITests.Phase0FoundationTests`
- `swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests`
- `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
- `swiftly run swift test --filter SwiftTUITests`
- `swiftly run swift test --filter SwiftTUITerminalTests`
- `swiftly run swift test --package-path Examples/gallery`
- `Scripts/generate_public_api_inventory.sh --check`

Perf smoke:

- `sh Scripts/run_perf_smoke.sh` on pre-Stage-3 `b9af46e8` and this stage.
- Current sync versus pre-Stage-3 sync: input latency p50/p95
  `143.362167 ms -> 105.114958 ms`; total CPU seconds
  `0.219088 -> 0.154668`; classification `clear win`.
- Current async versus pre-Stage-3 async: input latency p50/p95
  `89.035625 ms -> 96.970917 ms`; total CPU seconds
  `0.170730 -> 0.186251`; classification `no meaningful movement`.
- Current sync versus current async: input latency p50/p95
  `105.114958 ms -> 96.970917 ms`; total CPU seconds
  `0.154668 -> 0.186251`; classification `latency win with CPU cost`.

Final repo gate:

- `bun run test` passed. Full log:
  `/tmp/swift-tui-test-gate-20260517-035430-62259.log`.

## Exit Criteria

- Production render entry points enter through the runtime composition.
- The frame head declares the five mutated subsystems and keeps abort rollback
  as an explicit transactional-stage concern.
- The old generic `Renderer<Root>` no longer ships as production public API.
- Sync and async artifact parity, commit/drop guards, retained-reuse guards, and
  runtime pipeline tests pass.
- Public API baseline files match the new surface.
- The repo gate passes.

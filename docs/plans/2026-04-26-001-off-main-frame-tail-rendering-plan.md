---
title: "refactor: stage off-main frame-tail rendering"
type: refactor
status: active
date: 2026-04-26
proposal: "../proposals/OFF_MAIN_PIPELINE_RENDERING.md"
---

# refactor: stage off-main frame-tail rendering

## Overview

Migrate the deterministic frame tail toward off-main execution without changing
the authoring model or committing runtime side effects from a worker.

The target first seam is:

`measure -> place -> semantics -> draw -> raster`

The main actor keeps ownership of:

- authored view evaluation and `ViewGraph` mutation,
- animation controller state until value snapshots exist,
- focus/focused-values/scroll synchronization,
- runtime registration mutation,
- lifecycle/task commit,
- terminal presentation,
- frame ordering.

This plan intentionally starts with synchronous extraction before introducing
any async worker. The goal is to prove the architectural seam first, then move
the seam behind a per-renderer serial worker.

## Problem Frame

`ASYNC_PRESENTATION.md` moved terminal writes off the caller, but heavy frames
can still block the main actor while layout, placement, draw extraction, or
rasterization runs. The existing runtime is not greenfield: `DefaultRenderer`
does resolve, retained graph management, animation processing, measurement,
placement, rasterization, commit planning, diagnostics, and retained-frame
updates in one `@MainActor` method.

Moving the whole pipeline at once would force user-authored `View.body`,
bindings, task-local authoring context, live registries, and `ViewGraph`
evaluators across actor boundaries. That is too much risk for a first step.

The viable path is to extract and then offload the pure-ish frame tail.

## Requirements Trace

- R1. Preserve current visible output and lifecycle behavior.
- R2. Preserve focus-sync rerender semantics.
- R3. Preserve animation tick behavior, including removal overlays.
- R4. Preserve retained layout and raster reuse.
- R5. Preserve incremental presentation damage correctness.
- R6. Keep live runtime registries main-actor-owned.
- R7. Keep frame commit ordered; do not drop computed pipeline frames.
- R8. Add diagnostics that can prove main-actor blocked-time improvement.
- R9. Keep the public authoring surface unchanged.
- R10. Keep `bun run test` green before the migration is considered complete.

## Scope Boundaries

In scope:

- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- package-internal frame-tail helper types
- frame diagnostics for worker timing
- focused runtime tests and benchmarks

Out of scope:

- off-main `resolve`
- public API changes
- internal parallel layout/raster traversal
- frame dropping or out-of-order commit
- broad locking of live runtime registries
- process-level renderer isolation

## Architecture Direction

The migration should produce this shape:

```
MainActor:
  resolve frame head
  process animation state needed before layout
  submit frame-tail input

FrameTailRenderer:
  measure
  place
  semantics
  draw
  raster

MainActor:
  apply any main-actor-only animation overlay phase still needed
  finalize ViewGraph frame
  plan commit
  run focus-sync decision
  present
  apply lifecycle/task/preference commits
```

The first working version may split the tail around main-actor animation overlay
logic:

```
worker: measure -> place
main: capture/apply placed overlays
worker: semantics -> draw -> raster
main: commit -> present
```

That two-hop shape is acceptable as an interim safety step. The final version
should prefer a single worker tail once removal-overlay state can be passed as a
value snapshot.

## Stage 0: Characterization

**Goal:** Prove whether tail offload is likely to help before changing runtime
shape.

- [ ] Add or document a repeatable diagnostics invocation for the gallery demo.
- [ ] Add or document a repeatable diagnostics invocation for the layouts
  example.
- [ ] Add a synthetic large-tree benchmark or test helper if existing examples
  do not produce measurable tail time.
- [ ] Capture baseline frame diagnostics for:
  - resolve duration,
  - measure duration,
  - place duration,
  - semantics duration,
  - draw duration,
  - raster duration,
  - commit duration,
  - presentation duration.
- [ ] Decide whether tail time is large enough to justify Stage 1.

Stop condition:

- If realistic workloads are dominated by resolve, focus sync, or commit, stop
  here and record the result in the proposal. Do not add worker complexity.

Validation:

```bash
swiftly run swift test --filter TerminalUITests.Phase1BenchmarkScenariosTests
bun run test
```

## Stage 1: Extract Synchronous Frame Tail

**Goal:** Split the seam while everything still runs on the main actor.

- [ ] Introduce package-internal `FrameTailInput`.
- [ ] Introduce package-internal `FrameTailOutput`.
- [ ] Introduce package-internal `FrameTailDiagnostics`.
- [ ] Extract a synchronous helper from `DefaultRenderer.renderView(...)`:

  ```swift
  private func renderFrameTail(_ input: FrameTailInput) -> FrameTailOutput
  ```

- [ ] Keep all current state ownership unchanged.
- [ ] Keep `DefaultRenderer.render(...)` public behavior unchanged.
- [ ] Preserve current `FrameDiagnostics` output shape.
- [ ] Add a narrow regression test that compares current one-shot render output
  to the extracted-tail path if such a test hook is practical.

Commit boundary:

```bash
git commit -m "refactor(renderer): extract frame tail"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.TerminalPresentationTests
swiftly run swift test --filter TerminalUITests.Phase1BenchmarkScenariosTests
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests
```

## Stage 2: Separate Tail-Owned Retained State

**Goal:** Make the future worker own the caches it mutates.

- [ ] Split `RetainedFrameStore` into main-actor commit state and tail state.
- [ ] Move previous-raster-surface lookup into the tail state.
- [ ] Move retained-layout session input into the tail state or a sendable
  retained-layout snapshot.
- [ ] Keep `ViewGraph` lifecycle/finalization state on the main actor.
- [ ] Confirm retained layout reuse still works for animation tick frames.
- [ ] Confirm raster damage refinement still receives previous-surface data.

Commit boundary:

```bash
git commit -m "refactor(renderer): isolate frame-tail retained state"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.AnimationPipelineTests
swiftly run swift test --filter TerminalUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter TerminalUITests.TerminalGraphicsProtocolTests
```

## Stage 3: Resolve Animation Overlay Boundary

**Goal:** Decide how removal overlays interact with the worker seam.

Option A, safer first cut:

- [ ] Worker computes baseline `measured` and `placed`.
- [ ] Main actor runs `animationController.capturePlacedTree(...)`.
- [ ] Main actor runs `animationController.applyPlacedOverlays(...)`.
- [ ] Worker computes `semantics`, `draw`, and `raster` from the overlay-applied
  placed tree.

Option B, target shape:

- [ ] Add a sendable removal-overlay snapshot to `FrameTailInput`.
- [ ] Worker applies placed overlays before semantics/draw/raster.
- [ ] Main actor receives updated baseline placement metadata for animation
  controller bookkeeping.

Recommendation:

- Implement Option A first if Stage 2 exposes any sendability or lifecycle
  uncertainty.
- Move to Option B only after parity tests are green.

Commit boundary:

```bash
git commit -m "refactor(renderer): stage animation overlays across frame tail"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter TerminalUITests.AnimationPipelineTests
bun run test
```

## Stage 4: Add Serial FrameTailRenderer Worker

**Goal:** Move extracted tail computation behind a per-renderer serial worker.

- [ ] Add `FrameTailRenderer`.
- [ ] Prefer a Swift actor if strict sendability is clean.
- [ ] Use a serial `DispatchQueue`-backed class if existing mutable pipeline
  components make actor sendability noisy without adding safety.
- [ ] Give each `DefaultRenderer` its own worker.
- [ ] Keep worker-owned `LayoutEngine`, `SemanticExtractor`, `DrawExtractor`,
  `Rasterizer`, and tail retained state private to the worker.
- [ ] Keep a synchronous test path if needed for deterministic unit coverage.
- [ ] Add worker timing diagnostics:
  - enqueue-to-start latency,
  - tail compute duration,
  - completion-to-main-commit latency.

Commit boundary:

```bash
git commit -m "refactor(renderer): add frame-tail worker"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.Phase1BenchmarkScenariosTests
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests
swiftly run swift test --filter TerminalUITests.HostedSurfaceRegressionTests
```

## Stage 5: Convert Runtime Rendering Boundary To Async

**Goal:** Let the main actor suspend while tail computation runs.

- [ ] Add async render entry point on `DefaultRenderer`.
- [ ] Convert `RunLoop.renderPendingFrames(renderedFrames:)` to async or route
  through an async helper.
- [ ] Preserve ordered frame commit.
- [ ] Do not drop computed frames.
- [ ] Confirm input and signal readers can enqueue work while the main actor is
  suspended awaiting the worker.
- [ ] Keep focus-sync rerender loop intact.
- [ ] Keep animation deadline scheduling after commit.
- [ ] Keep presentation after commit decision and before lifecycle application
  exactly where current semantics require it.

Commit boundary:

```bash
git commit -m "refactor(runtime): await frame-tail rendering"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests
swiftly run swift test --filter TerminalUITests.FocusTransitionTests
swiftly run swift test --filter TerminalUITests.GestureRunLoopDispatchTests
swiftly run swift test --filter TerminalUITests.HostedSceneSessionTests
```

## Stage 6: Runtime Stress Tests

**Goal:** Prove off-main tail rendering does not reorder or lose runtime
effects.

- [ ] Add a blocking/fake tail worker test that suspends tail rendering.
- [ ] While the tail is blocked, enqueue an input event.
- [ ] Assert the input is accepted by the runtime but does not commit ahead of
  the blocked frame.
- [ ] Assert lifecycle events fire once and in order.
- [ ] Assert focus sync still rerenders as needed after tail completion.
- [ ] Assert animation deadlines still reschedule.
- [ ] Assert diagnostics report worker timing.

Commit boundary:

```bash
git commit -m "test(runtime): cover async frame-tail ordering"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests
bun run test
```

## Stage 7: Evaluate And Decide

**Goal:** Keep or revert the async runtime path based on measured benefit.

- [ ] Re-run Stage 0 workloads.
- [ ] Compare main-actor blocked time before/after.
- [ ] Compare input-to-state-mutation latency under tail-heavy load.
- [ ] Compare total frame duration.
- [ ] Compare animation smoothness in the gallery.
- [ ] Record results in `docs/proposals/OFF_MAIN_PIPELINE_RENDERING.md`.

Keep condition:

- Main-actor blocked time or input latency improves on tail-heavy workloads
  without meaningful total-frame regression.

Reconsider condition:

- Total frame time worsens and responsiveness does not measurably improve.

Commit boundary:

```bash
git commit -m "docs(renderer): record off-main frame-tail results"
```

Final validation:

```bash
bun run test
```

## Future Work: Off-Main Resolve

Do not begin this until Stage 7 proves frame-tail offload is insufficient.

Required future seams:

- explicit authoring context instead of task-local-only lookup,
- snapshot-producing resolve side effects,
- main-actor apply phase for runtime registrations,
- non-main observation tracking model,
- `ViewGraph` evaluator isolation changes,
- lifecycle diffing independent from live graph mutation.

This is a separate project and should get its own proposal update before any
implementation starts.

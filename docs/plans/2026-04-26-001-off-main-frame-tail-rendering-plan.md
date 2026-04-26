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

- [x] Add or document a repeatable diagnostics invocation for the gallery demo.
- [x] Add or document a repeatable diagnostics invocation for the layouts
  example.
- [x] Add a synthetic large-tree benchmark or test helper if existing examples
  do not produce measurable tail time.
- [x] Capture baseline frame diagnostics for:
  - resolve duration,
  - measure duration,
  - place duration,
  - semantics duration,
  - draw duration,
  - raster duration,
  - commit duration,
  - presentation duration.
- [x] Decide whether tail time is large enough to justify Stage 1.

Characterization surfaces:

- CLI demos can write tab-separated frame diagnostics with
  `TERMUI_DIAGNOSTICS=/tmp/termui-diagnostics.tsv`:

  ```bash
  cd Examples/gallery
  TERMUI_DIAGNOSTICS=/tmp/gallery-termui-diagnostics.tsv swiftly run swift run gallery-demo

  cd ../layouts
  TERMUI_DIAGNOSTICS=/tmp/layouts-termui-diagnostics.tsv swiftly run swift run layouts-demo
  ```

- `Phase1BenchmarkScenariosTests.largeStaticTreePhaseTimingScenario` is the
  deterministic synthetic large-tree benchmark for this migration. It asserts
  that phase timings exist and that a 160-row static tree drives substantial
  measured, placed, and draw-node work.

Stage 0 result:

- The focused benchmark suite passes with the synthetic large-tree scenario.
- The scenario is sufficient to justify Stage 1 seam extraction because it gives
  a repeatable, non-interactive workload where the frame tail is represented in
  diagnostics without depending on wall-clock thresholds.

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

- [x] Introduce package-internal `FrameTailInput`.
- [x] Introduce package-internal `FrameTailOutput`.
- [x] Introduce package-internal `FrameTailDiagnostics`.
- [x] Extract a synchronous helper from `DefaultRenderer.renderView(...)`:

  ```swift
  private func renderFrameTail(_ input: FrameTailInput) -> FrameTailOutput
  ```

- [x] Keep all current state ownership unchanged.
- [x] Keep `DefaultRenderer.render(...)` public behavior unchanged.
- [x] Preserve current `FrameDiagnostics` output shape.
- [x] Cover extracted-tail behavior through the existing public renderer path.

Stage 1 result:

- `DefaultRenderer.renderView(...)` now delegates
  `measure -> place -> semantics -> draw -> raster` to a synchronous
  `@MainActor` frame-tail helper.
- No separate regression hook was needed because the extracted helper remains
  private and single-path; the existing presentation, benchmark, and
  interactive runtime suites exercise the same public renderer path.

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

- [x] Replace `RetainedFrameStore` with tail-owned retained state while keeping
  commit state stateless on the main actor.
- [x] Move previous-raster-surface lookup into the tail state.
- [x] Move retained-layout session input into the tail state or a sendable
  retained-layout snapshot.
- [x] Keep `ViewGraph` lifecycle/finalization state on the main actor.
- [x] Confirm retained layout reuse still works for animation tick frames.
- [x] Confirm raster damage refinement still receives previous-surface data.

Stage 2 result:

- `FrameTailRetainedState` now owns the retained layout index and previous
  raster surface.
- `FrameTailInput` receives a retained-state snapshot, so `renderView(...)`
  no longer reaches into retained layout or raster fields directly.
- `ViewGraph.finalizeFrame(...)`, commit planning, artifact assembly, and
  lifecycle state remain on the main actor. The previous store only contained
  tail reuse data, so no empty main-actor retained store was added.

Commit boundary:

```bash
git commit -m "refactor(renderer): isolate frame-tail retained state"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.AnimationPipelineIntegrationTests
swiftly run swift test --filter TerminalUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter TerminalUITests.TerminalGraphicsProtocolTests
```

## Stage 3: Resolve Animation Overlay Boundary

**Goal:** Decide how removal overlays interact with the worker seam.

Option A, safer first cut:

- [x] Worker computes baseline `measured` and `placed`.
- [x] Main actor runs `animationController.capturePlacedTree(...)`.
- [x] Main actor runs `animationController.applyPlacedOverlays(...)`.
- [x] Worker computes `semantics`, `draw`, and `raster` from the overlay-applied
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

Stage 3 result:

- The current synchronous path now has the same two-hop shape that the first
  worker implementation should use: layout tail, main-actor placed overlays,
  raster tail.
- The animation controller remains main-actor-owned. Option B is deferred until
  removal-overlay state can be passed as an explicit value snapshot.

Commit boundary:

```bash
git commit -m "refactor(renderer): stage animation overlays across frame tail"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter TerminalUITests.AnimationPipelineIntegrationTests
bun run test
```

## Stage 4: Add Serial FrameTailRenderer Worker

**Goal:** Move extracted tail computation behind a per-renderer serial worker.

- [x] Add `FrameTailRenderer`.
- [x] Evaluate a Swift actor against strict sendability.
- [x] Use a serial `DispatchQueue`-backed class because existing mutable pipeline
  components make actor sendability noisy without adding safety.
- [x] Give each `DefaultRenderer` its own worker.
- [x] Keep worker-owned `LayoutEngine`, `SemanticExtractor`, `DrawExtractor`,
  `Rasterizer`, and tail retained state private to the worker.
- [x] Keep a synchronous test path if needed for deterministic unit coverage.
- [x] Add worker timing diagnostics:
  - enqueue-to-start latency,
  - tail compute duration,
  - completion-to-main-commit latency.

Stage 4 result:

- `DefaultRenderer` now delegates retained-state access, layout tail, raster
  tail, measurement-cache pruning, and committed-frame storage to a private
  per-renderer `FrameTailRenderer`.
- The worker uses a serial `DispatchQueue` where available and falls back to
  inline execution when Dispatch is unavailable.
- `FrameDiagnostics.workerTimings` and `FrameDiagnosticsLogger` now expose
  layout/raster enqueue and compute timings plus completion-to-commit delay.
- The public synchronous render path still waits for the worker. Main-actor
  suspension is deferred to Stage 5.

Commit boundary:

```bash
git commit -m "refactor(renderer): add frame-tail worker"
```

Validation:

```bash
swiftly run swift test --filter TerminalUITests.Phase1BenchmarkScenariosTests
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests
swiftly run swift test --package-path GUI/SwiftUITUIGUI --filter hosted_surface
```

## Stage 5: Convert Runtime Rendering Boundary To Async

**Goal:** Let the main actor suspend while tail computation runs.

- [x] Add async render entry point on `DefaultRenderer`.
- [x] Convert `RunLoop.renderPendingFrames(renderedFrames:)` to async or route
  through an async helper.
- [x] Preserve ordered frame commit.
- [x] Do not drop computed frames.
- [x] Confirm input and signal readers can enqueue work while the main actor is
  suspended awaiting the worker.
- [x] Keep focus-sync rerender loop intact.
- [x] Keep animation deadline scheduling after commit.
- [x] Keep presentation after commit decision and before lifecycle application
  exactly where current semantics require it.

Stage 5 result:

- `DefaultRenderer.renderAsync` now exposes an async runtime render path.
- `RunLoop.runWithInstalledAnimationSinks()` routes through
  `renderPendingFramesAsync(renderedFrames:)`, while the existing synchronous
  `renderPendingFrames(renderedFrames:)` remains available for deterministic
  package tests.
- The runtime awaits the frame-tail raster worker and preserves the existing
  presentation, lifecycle, focus-sync, animation-deadline, diagnostics, and
  transient-press ordering.
- Validation found that `LayoutProxyBox` custom-layout callbacks still use
  `MainActor.assumeIsolated`; moving layout to the Dispatch worker traps for
  authored `Layout` content. Stage 5 therefore keeps layout on the main actor
  and runs the Sendable semantics/draw/raster tail on the worker. Fully
  off-main layout requires a later custom-layout isolation design.

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

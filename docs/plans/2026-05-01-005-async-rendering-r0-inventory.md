---
title: "test: rebaseline async rendering cancellation pressure"
type: test
status: shipped
date: 2026-05-01
depends_on:
  - "2026-04-26-002-frame-head-abort-plan.md"
  - "../ASYNC_RENDERING.md"
---

# test: rebaseline async rendering cancellation pressure

## Goal

Complete the R0 checkpoint from
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md): improve diagnostics and
confirm composed `RunLoop.run()` coverage before restarting any frame-head abort
or tail-cancellation behavior.

This is a no-behavior-change stage. Ordered commit remains the only runtime
policy.

## Diagnostic Inventory

`TERMUI_DIAGNOSTICS` now records the cancellation-pressure fields that already
existed plus the layout-dependent fallback fields needed by the layout-time
geometry seam:

- `main_actor_blocked_ms`
- `main_actor_suspended_ms`
- `worker_layout_enqueue_ms`
- `worker_layout_compute_ms`
- `worker_raster_enqueue_ms`
- `worker_raster_compute_ms`
- `coalesced_intent_requests`
- `coalesced_event_batches`
- `drop_blockers`
- `stale_frame_policy`
- `layout_dependent_realizations`
- `layout_dependent_cache_hits`
- `layout_dependent_main_actor_fallbacks`

Current interpretation rules:

- `stale_frame_policy` must remain `commit_ordered`.
- `drop_blockers` is observational only; it does not authorize dropping a
  completed frame.
- `layout_dependent_main_actor_fallbacks > 0` means layout had to realize
  authored geometry content and therefore could not run on the frame-tail layout
  worker for that frame.

## Runtime-Path Coverage Map

The R0 failure class must be covered through composed `RunLoop.run()` paths, not
only direct `handleKeyPress`, `handleMouseEvent`, or renderer calls.

Current automated coverage:

| Scenario | Coverage |
| --- | --- |
| Gallery tab click | `Examples/gallery/Tests/GalleryDemoViewsTests/GalleryTabSwitchTests.swift` / `clickingGalleryTabSwitchesSelection` |
| ScrollView indicator click | `Tests/SwiftTUITests/InteractiveRuntimeTests.swift` / `mouseClickOnScrollIndicatorJumpsToLocation` |
| ScrollView indicator drag | `Tests/SwiftTUITests/InteractiveRuntimeTests.swift` / `mouseDragOnScrollIndicatorTracksDraggedPosition` |
| Pointer scroll burst | `Tests/SwiftTUITests/InteractiveRuntimeTests.swift` / `runLoopBatchesQueuedScrollBursts` |
| Pointer scroll burst through lazy content | `Tests/SwiftTUITests/InteractiveRuntimeTests.swift` / `runLoopBatchesQueuedScrollBurstsWithLazyStacks` |
| Key-command dispatch through async runtime | `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` / `runLoopRunDispatchesFrameHeadScaffoldRegistrations` |
| Drop-destination dispatch through async runtime | `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` / `runLoopRunDispatchesFrameHeadScaffoldRegistrations` |
| Focus sync on async runtime path | `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` / `publicSendableLayoutFocusSyncRerenderConvergesOnRuntimePath` |
| Layout-dependent fallback diagnostics | `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` / `runtimeDiagnosticsLoggerRecordsGeometryResolutionDiagnostics` |

## Verification Log

- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - passed, 23 tests in 1 suite.
- `swiftly run swift test --filter 'SwiftTUITests.InteractiveRuntimeTests/(mouseClickOnScrollIndicatorJumpsToLocation|mouseDragOnScrollIndicatorTracksDraggedPosition|runLoopBatchesQueuedScrollBurstsWithLazyStacks)'`
  - passed, 3 tests in 1 suite.
- `swiftly run swift test --package-path Examples/gallery --filter 'GalleryDemoViewsTests.GalleryTabSwitchTests/clickingGalleryTabSwitchesSelection'`
  - passed, 1 test in 1 suite.

## Remaining Manual Evidence

Before enabling any cancellation behavior, still capture short interactive
`TERMUI_DIAGNOSTICS` samples from the real gallery and layouts executables:

```bash
cd Examples/gallery
TERMUI_DIAGNOSTICS=/tmp/gallery-termui-diagnostics.tsv swiftly run swift run gallery-demo

cd ../layouts
TERMUI_DIAGNOSTICS=/tmp/layouts-termui-diagnostics.tsv swiftly run swift run layouts-demo
```

Use those samples to identify the frames with the highest
`coalesced_intent_requests`, worker queue delays, or
`layout_dependent_main_actor_fallbacks`.

## Next Boundary

Do not proceed to pre-start tail cancellation from this checkpoint. The next
implementation stage is R1: make prepared frame-head side effects draft-only or
otherwise safely abortable. That stage still requires design review before code,
because the previous frame-head abort implementation was reverted after real
gallery scrolling and clicking regressions.

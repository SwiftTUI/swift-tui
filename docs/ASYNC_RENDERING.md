# Async Rendering

This page is the current-state map for async presentation, off-main frame-tail
rendering, custom-layout worker eligibility, and future stale-frame handling.
Use it as the entry point before reading the supporting proposal files.

## Current Contract

The runtime has a guarded async frame-tail path. It improves main-actor
responsiveness without changing the public authoring model or skipping committed
runtime side effects.

The current frame ownership model is:

```
main actor: resolve -> animation interpolation
worker when eligible: measure -> place
main actor fallback: ordinary custom Layout measure -> place
worker: placed-overlay application -> semantics -> draw -> raster
main actor: commit -> present -> lifecycle
writer queue: terminal write(2)
```

The important invariant is ordered commit. When a worker frame starts or
finishes, the main actor commits it before rendering and presenting newer state.
Computed pipeline frames are not dropped.

## What Has Landed

- POSIX terminal writes are offloaded from `TerminalHost.present(_:)` to a
  queue-backed `PresentationWriter`. Presentation planning still runs on the
  caller's actor.
- `DefaultRenderer.renderAsync(...)` is the interactive runtime path.
- A private per-renderer `FrameTailRenderer` owns frame-tail layout/raster work,
  retained tail state, previous-surface reuse, and worker timing diagnostics.
- Built-in layout can run on the frame-tail layout worker.
- Public custom layouts can opt in to worker layout with `SendableLayout`.
- Framework-owned layouts that can satisfy the worker contract have moved to
  `SendableLayout`, including `WindowHostLayout`, `ScrollViewLayout`, and
  `TabViewContainerLayout`.
- Lazy indexed child sources can be snapshotted on the main actor and then used
  by worker layout when their visible children are worker-safe.
- Runtime diagnostics record render generations, worker timings, main-actor
  blocked/suspended time, coalesced event batches, and
  `stale_frame_policy=commit_ordered`.
- Async stress tests cover blocked worker tails, queued input, ordered commit,
  sync/async artifact parity, `SendableLayout` worker execution, retained layout
  reuse, focus convergence, and framework layout worker paths.

## What Still Runs On The Main Actor

- `View.body` and authored dynamic-property evaluation.
- `@State`, `Binding`, observation tracking, focus synchronization, scroll sync,
  lifecycle, task, command, gesture, and runtime registration mutation.
- Ordinary public `Layout` conformers that do not opt in to `SendableLayout`.
- Custom layouts with non-Sendable caches or main-actor-only proxy state.
- Commit planning effects and lifecycle/task application.
- Terminal presentation state synchronization before output is handed to the
  writer queue.

## What Is Not Implemented

Worker-job cancellation is not implemented.

The runtime can coalesce queued render intent before starting a later render, and
`DefaultRenderer` has an explicit prepare-tail-finish split. A broader
frame-head abort implementation was attempted and then reverted after real
runtime regressions in scrolling and clicking. The retained code does not expose
a safe `abortFrameHead` path for cancelling a prepared frame.

That means the next cancellation step must be redesigned around draft-only
side effects or another rollback model before `FrameTailRenderer` accepts
cancellable submissions.

Completed worker results are also not classified or dropped as visual-only
frames. The default and only runtime policy is `mustCommit`.

## Progress Map

| Area | Status | Notes |
| --- | --- | --- |
| Async terminal writes | Shipped | Writer queue handles blocking `write(2)` work. |
| Guarded frame-tail worker | Shipped | Layout offload is conditional; raster tail is async. |
| Render generation diagnostics | Shipped | Generations identify render, layout, and raster work. |
| Ordered stale-frame policy | Shipped | Started/completed worker frames commit in order. |
| Render-intent coalescing | Shipped | Queued input can collapse before the next render begins. |
| Frame-head prepare/finish split | Shipped | Useful seam, but not an abortable transaction. |
| Public `SendableLayout` opt-in | Shipped | Worker-safe custom layouts off-main. |
| Framework layout migration | Shipped for known safe layouts | Continue layout by layout. |
| Lazy indexed child snapshots | Shipped | Main actor resolves visible children before worker use. |
| Abortable prepared frame heads | Not shipped | Previous implementation was reverted. |
| Cancellable pre-start tail jobs | Not shipped | Blocked on safe abort or draft-only effects. |
| Visual-only completed-frame drops | Not shipped | Requires an eligibility classifier. |
| Off-main resolve | Not planned near-term | Would require a new authoring and registration model. |

## Supporting Documents

- [proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md) records the
  queue-backed POSIX terminal writer design.
- [proposals/OFF_MAIN_PIPELINE_RENDERING.md](proposals/OFF_MAIN_PIPELINE_RENDERING.md)
  records the original frame-tail offload design and implementation notes.
- [proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md](proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md)
  records the `SendableLayout` opt-in model, framework-layout migration, and lazy
  indexed-child snapshot work.
- [proposals/ASYNC_FRAME_STALE_POLICY.md](proposals/ASYNC_FRAME_STALE_POLICY.md)
  defines why computed async pipeline frames still commit in order.
- [proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md](proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md)
  is the future-work design for render intent, abortability, and cancellable
  pre-start tail jobs.
- [plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md)
  records the shipped initial frame-tail worker plan.
- [plans/2026-04-26-002-frame-head-abort-plan.md](plans/2026-04-26-002-frame-head-abort-plan.md)
  records the reverted frame-head abort attempt and the post-mortem.

## Code Anchors

- `Sources/TerminalUI/TerminalUI.swift`: `DefaultRenderer`,
  `FrameTailRenderer`, `FrameHeadDraft`, render generation sequencing, worker
  timings, and frame finish.
- `Sources/TerminalUI/RunLoop+Rendering.swift`: async render loop, input
  coalescing, ordered commit, and diagnostics emission.
- `Sources/TerminalUI/FrameDiagnosticsLogger.swift`: TSV diagnostics fields for
  generations, worker timings, main-actor timings, coalescing, and stale policy.
- `Sources/View/Layout/Layout.swift`: public `SendableLayout` opt-in and
  worker-capable layout erasure.
- `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`: async tail,
  ordered commit, coalescing, `SendableLayout`, lazy snapshot, and framework
  layout regression coverage.

## Decision Rules

- Do not move `resolve` off-main as part of frame-tail work.
- Do not force ordinary public `Layout` conformers onto the worker.
- Do not drop a computed pipeline frame unless a tested eligibility classifier
  proves the frame has no side effects that need commit or reconciliation.
- Do not add worker cancellation inside `FrameTailRenderer` until prepared frame
  side effects can be aborted or isolated in draft-only state.
- Keep full `bun run test` as the completion gate for runtime or shared renderer
  changes.

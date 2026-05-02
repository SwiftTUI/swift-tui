# Async Rendering

This page is the current-state map for async presentation, off-main frame-tail
rendering, layout-dependent content realization, custom-layout worker
eligibility, and future stale-frame handling. Use it as the entry point before
reading the supporting proposal files.

## Current Contract

The runtime has a guarded async frame-tail path. It improves main-actor
responsiveness without changing the public authoring model or skipping committed
runtime side effects.

The current frame ownership model is:

```
main actor: resolve -> animation interpolation
worker when eligible: measure -> place
main actor fallback: ordinary custom Layout, main-actor-only indexed child
  sources, or layout-dependent content realization during layout
worker: placed-overlay application -> semantics -> draw -> raster
main actor: commit -> present -> lifecycle
writer queue: terminal write(2)
```

The important invariant is ordered commit for any worker frame that has started.
Started and completed worker frames commit before newer state is presented.
Queued frame-tail jobs may be cancelled before worker layout starts when a newer
render intent is already pending; the corresponding prepared frame head is
discarded through the draft/checkpoint transaction. Computed pipeline frames
that have started are not dropped. Layout-dependent content realization is part
of the current frame's layout work; any realized subtree is folded back into the
committed resolved tree before semantics, draw, raster, and lifecycle commit.

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
- Layout-dependent content boundaries let resolve leave a placeholder that
  layout can realize from concrete placement geometry. `GeometryReader` is the
  first public adopter: its content is realized from final bounds, safe-area
  insets, cell metrics, pointer capabilities, and the placed-frame table.
- Public anchor preferences and `GeometryProxy.frame(in:)` resolve against
  placed frames instead of the old resolve-time `terminalSize` local-geometry
  bridge.
- Frame-head runtime registrations are collected in scratch draft registries
  and committed only during frame finish. Live runtime registries are rebuilt
  from the committed `ViewGraph` and committed node handlers/aliases, not from a
  per-frame draft snapshot.
- Prepared frame heads have checkpoint-backed abort coverage for graph state,
  frame resolve state, observation tracking, animation transactions, lifecycle
  and task effects, retained tail inputs, and worker custom-layout cache updates.
- The interactive runtime can cancel a queued tail job before worker layout
  starts. Started and completed tail work still follows ordered commit.
- Cancelled frame-head render invalidations replay their animation request and
  batch ID into the replacement scheduler work without replaying input actions
  or overriding newer explicit animation intent.
- Runtime diagnostics record render generations, worker timings, main-actor
  blocked/suspended time, coalesced event batches, coalesced intent-request
  pressure, geometry-resolution misses, explicit drop blockers, tail job state,
  tail cancellation reason, cancelled render count, desired-generation snapshots,
  and stale-frame policy. Completed frames report `commit_ordered`; cancelled
  rows report `cancel_pending_before_start`.
- Async stress tests cover blocked worker tails, queued input, ordered commit,
  sync/async artifact parity, `SendableLayout` worker execution, retained layout
  reuse, focus convergence, framework layout worker paths, aborted prepared
  frame heads, queued-tail cancellation, and main-actor fallback when
  layout-dependent content is present.
- The post-Option-3 gallery one-shot animation regression is covered by
  gallery-path and deterministic async-tail diagnostics. See
  [plans/2026-05-01-007-gallery-animation-regression-notes.md](plans/2026-05-01-007-gallery-animation-regression-notes.md)
  for the regression guard, root cause, and replay contract.

## What Still Runs On The Main Actor

- `View.body` and authored dynamic-property evaluation.
- `@State`, `Binding`, observation tracking, focus synchronization, scroll sync,
  lifecycle, task, command, gesture, and runtime registration mutation.
- Ordinary public `Layout` conformers that do not opt in to `SendableLayout`.
- Custom layouts with non-Sendable caches or main-actor-only proxy state.
- Layout-dependent authored content realization, including `GeometryReader`
  content. In async rendering, a tree with layout-dependent content keeps the
  layout pass on the main actor and records a fallback diagnostic; raster work
  still runs on the frame-tail worker.
- Commit planning effects and lifecycle/task application.
- Terminal presentation state synchronization before output is handed to the
  writer queue.

## What Is Not Implemented

Off-main realization of arbitrary authored layout-dependent content is not
implemented. A worker-safe snapshot model would have to prove the same runtime
registration, state, observation, lifecycle, task, focus, command, drop, and
preference guarantees that ordinary main-actor view evaluation has today.

Cancellation after worker layout starts is not implemented and is intentionally
out of scope. A started or completed worker frame must still finish and commit
in order.

Completed worker results are classified conservatively by
`FrameDropEligibility`, including runtime focus/preference/animation,
retained-baseline, presentation-recovery, graphics-replay, and diagnostics
barriers. The candidate-level classifier can identify a fully observed
visual-only candidate, and skipped-frame reconciliation now has an explicit
empty-visual-only staging type. `FrameDropEligibility.canDrop` remains false and
no runtime path drops completed frames. Off-main resolve is not planned
near-term.

## Shipped Option 3 Boundary

Option 3 shipped the conservative pipeline-split tranche. For this document,
"pipeline split" means the existing prepare-tail-finish seam is precise enough
that a prepared frame can be discarded only when its worker tail has not started.
It does not mean moving `resolve` off the main actor, allowing multiple
concurrent renders against one `DefaultRenderer`, or presenting newer state
ahead of started/completed tail work.

Keep these terms separate:

- **Render intent**: scheduler/run-loop demand for a new frame. Coalescing
  not-yet-started render intent has shipped.
- **Frame head**: main-actor resolve, observation, registration collection,
  animation interpolation, and tail-input preparation. It is abortable only
  before the corresponding tail job starts.
- **Tail job**: the measure/place through raster work submitted to
  `FrameTailRenderer`.
- **Pre-start tail cancellation**: cancelling a queued tail job before the
  worker begins layout, then discarding the corresponding prepared frame head.
  If the cancelled frame carried render invalidation plus animation intent, that
  invalidation intent is merged back into the pending replacement frame.
- **Started/completed tail work**: any tail job whose worker has begun layout
  or returned output. These frames must still finish and commit in order.

The dequeue boundary is the only cancellation point:

- `queued`: may cancel if superseded by a newer desired generation before the
  worker starts.
- `started`: must finish and commit in order.
- `completed`: must finish and commit in order.
- `cancelled-before-start`: abort the corresponding frame head and prepare the
  newest generation.

Diagnostics distinguish pressure from behavior. Existing fields such as
`coalesced_event_batches` and `coalesced_intent_requests` measure queued input
and avoided renders; cancellation fields measure actual queued-tail
cancellations:

- `tail_job_state`
- `tail_cancel_reason`
- `cancelled_render_count`
- `newest_desired_at_tail_start`
- `newest_desired_at_tail_result`
- `scheduled_animation_request`
- `scheduled_animation_batch`
- `animation_controller_active_animations`
- `animation_controller_pending_work`
- `stale_frame_policy=cancel_pending_before_start`

Completed rows report `stale_frame_policy=commit_ordered`; cancelled rows report
`stale_frame_policy=cancel_pending_before_start`. Started/completed tail jobs
must continue to report and follow ordered commit.

## Runtime Diagnostics Samples

Fresh composed-example diagnostics for the shipped tranche were captured on
2026-05-01:

```bash
TERMUI_DIAGNOSTICS=/tmp/gallery-termui-diagnostics-20260501.tsv swiftly run swift run gallery-demo
TERMUI_DIAGNOSTICS=/tmp/layouts-termui-diagnostics-20260501.tsv swiftly run swift run layouts-demo
```

The gallery sample includes cancelled queued-tail rows with
`tail_job_state=cancelled_before_start`, `tail_cancel_reason=newer_render_intent`,
and `stale_frame_policy=cancel_pending_before_start`. Subsequent completed rows
return to `stale_frame_policy=commit_ordered`. The layouts sample stayed on
ordered commit with `tail_job_state=completed` and showed coalesced input
pressure without actual cancellation.

## Future Tranche: Completed Visual-Only Drops

Do not drop completed worker results in the Option 3 tranche. Once pre-start
cancellation is proven, the existing `FrameDropEligibility` classifier can be
expanded from observational to actionable for a narrow visual-only case. The
detailed proposal lives in
[proposals/ASYNC_FRAME_STALE_POLICY.md](proposals/ASYNC_FRAME_STALE_POLICY.md):
split async frame finish into candidate creation plus explicit commit, classify
completed candidates before commit, discard only stale candidates with no
lifecycle, task, focus, preference, scroll, animation, handler, custom-layout
cache, retained-baseline, or presentation repaint barriers, and route every
skipped completed frame through an explicit reconciliation object. The first
allowed reconciliation mode is empty visual-only; non-empty skipped-frame
side-effect reconciliation remains a later proposal.

## Progress Map

| Area | Status | Notes |
| --- | --- | --- |
| Async terminal writes | Shipped | Writer queue handles blocking `write(2)` work. |
| Guarded frame-tail worker | Shipped | Layout offload is conditional; raster tail is async. |
| Render generation diagnostics | Shipped | Generations identify render, layout, and raster work. |
| Ordered stale-frame policy | Shipped | Started/completed worker frames commit in order. |
| Render-intent coalescing | Shipped | Queued input can collapse before the next render begins. |
| Frame-head prepare/finish split | Shipped | Prepared heads can be aborted before tail start. |
| Public `SendableLayout` opt-in | Shipped | Worker-safe custom layouts off-main. |
| Framework layout migration | Shipped for known safe layouts | Continue layout by layout. |
| Lazy indexed child snapshots | Shipped | Main actor resolves visible children before worker use. |
| Layout-dependent content realization | Shipped for `GeometryReader` and anchor geometry | Forces main-actor layout fallback when arbitrary authored content is present. |
| Abortable prepared frame heads | Shipped | Draft registries plus graph/state checkpoints protect live runtime state. |
| Cancellable pre-start tail jobs | Shipped | Only queued jobs can cancel; started/completed jobs commit in order. |
| Cancelled animation intent replay | Shipped | Replays invalidation-scoped animation metadata without replaying input or replacing newer explicit animation. |
| Visual-only completed-frame drops | Not shipped | Explicit blocker signals, candidate classification, and reconciliation scaffolding exist; candidate commit/discard and drop policy do not. |
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
  defines why computed async pipeline frames still commit in order and records
  the conservative drop-blocker classifier.
- [proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md](proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md)
  records render intent, prepared-frame abortability, and shipped cancellable
  pre-start tail jobs.
- [plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md)
  records the shipped initial frame-tail worker plan.
- [plans/2026-04-26-002-frame-head-abort-plan.md](plans/2026-04-26-002-frame-head-abort-plan.md)
  records the reverted frame-head abort attempt and the post-mortem.
- [plans/2026-05-01-001-layout-dependent-content-realization-plan.md](plans/2026-05-01-001-layout-dependent-content-realization-plan.md)
  records the shipped layout-time realization seam for `GeometryReader`.
- [plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md](plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md)
  records the shipped anchor preference and `GeometryProxy.frame(in:)` API.
- [plans/2026-05-01-003-layout-dependent-container-audit.md](plans/2026-05-01-003-layout-dependent-container-audit.md)
  records the audit of remaining container geometry and worker-eligibility
  assumptions.
- [plans/2026-05-01-004-layout-dependent-container-hardening-plan.md](plans/2026-05-01-004-layout-dependent-container-hardening-plan.md)
  records the container regression coverage around layout-dependent geometry.
- [plans/2026-05-01-005-async-rendering-r0-inventory.md](plans/2026-05-01-005-async-rendering-r0-inventory.md)
  records the R0 diagnostics and composed-runtime coverage checkpoint for
  restarting async cancellation work.
- [plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md](plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md)
  records the shipped Option 3 implementation for draft frame-head transactions,
  prepared-frame abort proof, and queued-tail cancellation.

## Code Anchors

- `Sources/TerminalUI/TerminalUI.swift`: `DefaultRenderer`,
  `FrameTailRenderer`, `FrameHeadDraft`, render generation sequencing, worker
  timings, and frame finish.
- `Sources/TerminalUI/RunLoop+Rendering.swift`: async render loop, input
  coalescing, queued-tail cancellation, ordered commit, and diagnostics
  emission.
- `Sources/Core/Scheduler.swift`: render-intent coalescing and cancelled
  animation-intent replay into replacement work.
- `Sources/TerminalUI/FrameDiagnosticsLogger.swift`: TSV diagnostics fields for
  generations, worker timings, main-actor timings, coalescing, drop blockers,
  tail cancellation, stale policy, and geometry resolution misses.
- `Sources/Core/FrameHeadRegistrationDraft.swift`: scratch runtime
  registrations and commit-time restoration from the committed graph.
- `Sources/Core/FrameDropEligibility.swift`: conservative observational
  classifier for completed-frame drop blockers.
- `Sources/Core/LayoutDependentContent.swift`: layout-time realization
  boundaries, realization context, and per-pass realization cache.
- `Sources/View/GeometryReading/GeometryReader.swift`: public adopter that
  realizes content from placed geometry instead of resolve-time terminal size.
- `Sources/View/Layout/Layout.swift`: public `SendableLayout` opt-in and
  worker-capable layout erasure.
- `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`: async tail,
  ordered commit, coalescing, `SendableLayout`, lazy snapshot, and framework
  layout regression coverage.

## Decision Rules

- Do not move `resolve` off-main as part of frame-tail work.
- Do not force ordinary public `Layout` conformers onto the worker.
- Do not move arbitrary layout-dependent content realization onto the worker
  without a separate snapshot contract for authored view evaluation and runtime
  side effects.
- Do not drop a computed pipeline frame unless a tested eligibility classifier
  proves the frame has no side effects that need commit or reconciliation.
- Do not treat the current observational `FrameDropEligibility` result as
  permission to drop; it is diagnostic until an actionable policy is tested.
- Do not cancel worker work after layout has started; pre-start cancellation is
  the only shipped cancellation point.
- Keep full `bun run test` as the completion gate for runtime or shared renderer
  changes.

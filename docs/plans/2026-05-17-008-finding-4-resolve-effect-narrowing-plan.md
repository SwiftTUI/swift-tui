---
title: "refactor: pipeline driver follow-up remediation"
type: refactor
status: shipped
date: 2026-05-17
depends_on:
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/PIPELINE_BOUNDARY_HARDENING.md"
  - "../ARCHITECTURE.md"
  - "../decisions/0004-frame-head-abort-reverted.md"
  - "../decisions/0018-late-preference-reconciliation-bound.md"
  - "../decisions/0019-composed-runtime-render-pipeline.md"
  - "../decisions/0020-off-main-layout-worker-concurrency.md"
---

# Finding 4 Resolve-Effect Narrowing Plan

## Context

Finding 4 in
[`PIPELINE_DRIVER_AUDIT.md`](../proposals/PIPELINE_DRIVER_AUDIT.md) says the
runtime does not yet make commit the only side-effect boundary. Stage 3 of the
pipeline-driver hardening roadmap made this residue explicit by declaring the
frame head's five mutable effects:

- `viewGraph`
- `frameState`
- `presentationPortalState`
- `observationBridge`
- `animationController`

That declaration is a contract marker, not the destination. The destination is
a prepared frame head that can be abandoned without restoring live runtime
state. All irreversible or externally visible work should either happen only in
commit or be captured in draft-owned state that is discarded when the prepared
frame does not commit.

Status: complete. The runtime head remains abortable, but it no longer exposes
or maintains a declared rollback-effect set. Commit is the boundary that
publishes lifecycle, task, registration, focus, presentation, and animation
effects; prepared-frame discard mechanics for internal graph/frame selector
state are implementation details.

ADR
[`0004-frame-head-abort-reverted.md`](../decisions/0004-frame-head-abort-reverted.md)
is the constraint that governs this migration. The reverted attempt failed
because it restored live runtime registrations from per-frame draft registries
instead of committed graph truth. Any renewed narrowing must preserve committed
graph restoration until the relevant effect is proven draft-only.

## End State

The desired end state is:

- `resolve` can build a prepared frame from immutable inputs plus draft-owned
  mutable products.
- Abandoning a prepared frame does not call broad live-state restore routines.
- `commit` is the only boundary that installs lifecycle events, runtime
  registrations, focus/default-focus state, presentation state changes,
  animation completions, task starts/cancels, and host-visible effects.
- The async renderer can cancel a not-yet-started tail by discarding a prepared
  frame draft and replaying the render intent, without rebuilding live runtime
  state from a rollback snapshot.
- The runtime tests prove this through `RunLoop.run()` or composed
  `RunLoop`-level paths, not only direct renderer helpers.

The migration is complete: the declared frame-head effect model has been
removed, and the docs no longer need to qualify "commit is the side-effect
boundary" for user/runtime-visible effects.

## Current Effect Audit

| Effect | Current mutation in frame head | Can move now? | Destination |
| --- | --- | --- | --- |
| `viewGraph` | `ViewGraphFrameDraft` owns abort discard and committed runtime-registration publication. Live graph restore remains an internal prepared-frame discard detail rather than an exposed runtime-head effect. | Complete for F4-G. | Keep graph publication committed; do not reconstruct live runtime registries from draft registries. |
| `frameState` | `prepareInputs(from:proposal:)` returns value-owned current-frame inputs; retained state only tracks previous-frame selector memory used to decide whether root evaluation is required. | Complete for F4-G. | Keep `FrameResolveInputs` as the prepared-head input surface. |
| `presentationPortalState` | `PresentationPortalDraft` owns coordinator-handle injection, declarative reconciliation, overlay entries, and dismiss-stack changes for the prepared frame. | Complete for F4-E/F4-G. | Publish portal visibility only when the frame commits. |
| `observationBridge` | `ObservationBridgeDraft` owns the prepared tracking pass and observed identity table. Observation callbacks still consult the committed pass table until the draft commits. | Complete for F4-E/F4-G. | Publish observation routes only when the frame commits. |
| `animationController` | `AnimationFrameDraft` owns transition collection, resolved-tree animation diffing, placed-overlay sampling, and deferred frame-head completions for the prepared frame. | Complete for F4-F/F4-G. | Publish draft controller state only after the commit plan is accepted; discard abandoned drafts without restoring the live controller. |

## Work Stages

### F4-A: Baseline guardrails and documentation

Status: complete.

- Add a contract test that pins the five declared runtime-head effects and the
  canonical stage order.
- Add a registration-restore test that proves draft registries are not the
  source of truth when committing after a live reset; committed graph handlers,
  including alias-only handlers, must be restored.
- Correct architecture wording so it says commit is the named side-effect plan,
  but the frame head still owns the declared mutable effect set.
- Link this plan from the live TODO and Finding 4 follow-up docs.

### F4-B: Protective interactive coverage

Add `RunLoop`-level coverage before moving effects:

- Scroll bursts: repeated mouse scroll input through `RunLoop.run()` must keep
  scroll routes and scroll-position geometry live after a blocked or discarded
  prepared frame.
- Drag sequences: active gesture recognizers must survive any reset or draft
  discard boundary that occurs between pointer-down and pointer-up.
- Click resolution: a click routed by a committed semantic snapshot must not be
  replaced by draft pointer/action handlers until commit.
- Key/drop scopes: committed `.keyCommand` and `.dropDestination` handlers must
  stay scoped to the committed graph while a prepared frame is blocked.
- Presentation portals: sheet/popover/menu state visible to input handling must
  remain the committed state until commit.
- Animation completions: completion closures may fire only after commit and
  must be discarded for abandoned prepared heads.

This stage may add test hooks, but only hooks that expose state already used by
runtime composition. Avoid production behavior changes here unless the coverage
proves a draft effect is already visible to live input; in that case, keep the
fix limited to preserving the committed input surface.

Status: complete.

Evidence:

- Existing `AsyncFrameTailRenderingTests` coverage already guarded blocked
  frame-head key-command dispatch, drop-destination dispatch, selective sibling
  command state, animation completion deferral, and abandoned prepared-head
  animation completion discard.
- Added composed `RunLoop` guards for scroll bursts, click action routing,
  active drag-recognizer continuity, and presentation Escape dismissal while an
  async frame head is blocked before raster/commit.
- The presentation guard exposed a real draft leak. `DefaultRenderer` now keeps
  Escape dismissal routed through the last committed presentation portal state
  until the candidate frame commits.

### F4-C: Resolve input split

Status: complete.

Extract a value-owned input bundle from `FrameResolveState.update`:

- Create a per-frame value containing invalidation summary, environment values,
  focused values, transaction, proposal, and selective-evaluation decision.
- Make evaluator closures read that value through the frame context instead of
  relying on early mutation of shared `FrameResolveState` where possible.
- Keep the old state as the committed previous-frame memory until the split is
  proven by sync/async parity and selective-evaluation tests.

Exit criterion: `frameState` is no longer part of the abortable head checkpoint,
or its checkpoint contains only previous-frame selector memory rather than
current-frame values.

Evidence:

- `FrameResolveInputs` carries invalidation summary, environment snapshots,
  focused values, transaction, proposal, and the selective-evaluation decision.
- `FrameResolveState` checkpoints now contain only previous-frame selector
  memory (`forceRootEvaluation`, focused identity, pressed identity, and
  proposal).
- Reused evaluator contexts refresh from `FrameResolveInputBox` before
  resolving, and proposal-sensitive TabView layout reads the same prepared
  input bundle.

### F4-D: Draft runtime registrations and graph transaction

Status: complete for runtime-registration publication; graph node mutation still
remains in the declared frame-head effect set.

Turn the current graph-restoration lesson into a real draft boundary:

- Preserve `ViewGraph.restoreCurrentFrameRuntimeRegistrations(into:)` as the
  committed source of truth during the migration.
- Add a graph-frame draft that owns newly evaluated node handlers, lifecycle
  pre-work, registration aliases, and evaluator changes until commit.
- Commit by publishing the graph-frame draft and then restoring registrations
  from the committed graph.
- Abort by discarding the draft without mutating live runtime registries.

Exit criterion: `FrameHeadRegistrationDraft` no longer needs to reset live
registries during commit because no draft handlers were visible to live state.

Evidence:

- Added `ViewGraphFrameDraft`, which owns the abort-time `ViewGraph` checkpoint
  and the runtime-registration publication plan for unchanged, full, and
  selective dirty frames.
- Reduced `FrameHeadRegistrationDraft` to a scratch registration collector used
  only for draft drop-eligibility classification; it no longer stores live
  registries, records live mutations, or commits by resetting live registries.
- Commit now finalizes the graph, then publishes runtime registrations from the
  committed graph via `ViewGraphFrameDraft.commitRuntimeRegistrations(from:)`.
  Abort discards the graph draft and restores its checkpoint without touching
  live runtime registries.
- Added graph tests for committed graph publication and discard without live
  registry mutation.

### F4-E: Observation and presentation drafts

Status: complete for observation routes and presentation portal visibility.

Move the two context-coupled subsystems behind drafts:

- Observation: record observed identities and callback pass IDs in a prepared
  observation draft; publish them on commit.
- Presentation portals: route coordinator mutations into a prepared portal
  draft; publish overlay stack and dismiss-stack changes on commit.

Exit criterion: abandoning a prepared head cannot change observation invalidation
routes or presentation portal visibility.

Evidence:

- Added `ObservationBridgeDraft`, which records the prepared tracking pass and
  observed identities without publishing them to `ObservationBridge` until the
  frame commits. Observation callbacks before commit still check the committed
  pass table and are ignored for draft-only observations.
- Added `PresentationPortalDraft`, which receives portal handle injection,
  declarative coordinator reconciliation, overlay entries, and dismiss-stack
  state during resolve. Commit installs the draft registry as the live
  `PresentationPortalState` registry so handles captured during the committed
  frame continue to address live coordinator state; abort discards it without
  restoring a live checkpoint.
- Removed presentation-portal and observation-bridge checkpoints from
  `FrameHeadCheckpoints`; abort now discards their drafts instead of calling
  broad restore routines.
- Added focused observation coverage proving a prepared observation draft is
  invisible until commit. Existing blocked async presentation coverage continues
  to prove draft sheets stay out of Escape dismissal until commit.

### F4-F: Animation transaction finalization

Status: complete.

Finish the animation side of the boundary:

- Keep transition collection pass-owned.
- Publish transition registrations and placed-overlay state only when the frame
  commits.
- Execute completion closures only after commit accepts the frame.

Exit criterion: `animationController` is no longer in the declared head effect
set.

Evidence:

- Added `AnimationFrameDraft`, which clones the committed animation controller
  state for a prepared frame and routes transition registration, animation
  diffing, placed-overlay sampling, and completion deferral into that draft.
- Commit publishes the draft controller state to the live renderer controller
  and then executes deferred frame-head completions. Abort and completed-frame
  drop discard the draft without restoring a live animation checkpoint.
- Removed the animation checkpoint from `FrameHeadCheckpoints`.
- Added focused coverage proving a prepared transition animation is visible in
  the draft controller but not in the live controller until commit.

### F4-G: Remove the declared head effect set

Status: complete.

- Remove or empty `FrameHeadDeclaredEffect.runtimeHead`.
- Remove abort rollback checkpoints for the five subsystems from the declared
  runtime pipeline model.
- Update ADR/proposal/status docs to state that commit is the side-effect
  boundary without qualification for user/runtime-visible effects.
- Verify queued-tail cancellation against the now-discardable prepared-head
  contract.

Evidence:

- Removed `FrameHeadDeclaredEffect`, `FrameHeadDeclaredEffectSet`, and
  `RuntimeFrameHeadStage.declaredEffects` from the runtime pipeline contract.
- Updated pipeline contract tests to assert the stage order and abortable head
  contract without pinning a rollback-effect list.
- Updated architecture, ADR 0019, the pipeline audit, the original hardening
  plan, and the live tracker so Finding 4 is no longer described as deferred.
- Verified queued-tail cancellation is already shipped through
  `DefaultRenderer.renderAsyncCancellable`, `FrameTailJobCancellationToken`,
  `RunLoop` cancelled-intent replay, and
  `AsyncFrameTailRenderingTests.queuedFrameTailCancelsBeforeWorkerLayoutStarts`.

## Stop Conditions

Stop before implementation, and record a decision, if any stage would require:

- Executing authored user closures before commit.
- Reconstructing live runtime registries from draft registries.
- Making observation callbacks point at a graph draft that is not committed.
- Changing public interaction semantics for key commands, drops, gestures,
  presentation dismissal, focus, or animation completions.

## Validation

Minimum validation for each implementation stage:

- Focused tests for the touched subsystem.
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  after changes that touch async runtime behavior.
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests` after
  pipeline contract changes.
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests` after graph
  or registration-restore changes.
- `bun run test` before considering a stage complete.

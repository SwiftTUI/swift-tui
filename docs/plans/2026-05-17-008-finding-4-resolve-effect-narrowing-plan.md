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

The migration is complete only when `FrameHeadDeclaredEffect.runtimeHead` is
empty or removed, and the docs no longer need to qualify "commit is the
side-effect boundary."

## Current Effect Audit

| Effect | Current mutation in frame head | Can move now? | Destination |
| --- | --- | --- | --- |
| `viewGraph` | `beginFrame`, invalidation, evaluator installation, dirty evaluation, snapshot reuse, lifecycle pre-work, and node registration capture. | No wholesale move. This is the main retained-graph owner. | Introduce a prepared graph-frame draft or equivalent graph transaction whose node/evaluator/registration mutations are not visible to live runtime registries until commit. |
| `frameState` | `update(from:proposal:)` refreshes invalidation, environment, transaction, focus, proposal, and selective-evaluation flags before graph evaluation. | Partially. The input bundle can be separated before deeper graph work. | Split immutable `FrameResolveInputs` from mutable cross-frame state, then make prepared heads carry the per-frame values without mutating shared state until commit or checkpoint-free discard. |
| `presentationPortalState` | Portal coordinator handles are injected during resolution and may update coordinator registries. | Not without a draft portal registry. | Add a portal-state draft/checkpoint wrapper that records presented overlay changes and installs them only when the commit plan is accepted. |
| `observationBridge` | The bridge attaches the current `ViewGraph`, begins a tracking pass, and records observed identities for invalidation callbacks. | Not yet. Observation callbacks can race with prepared-frame visibility. | Make observation tracking pass-owned: a prepared frame records observations into a draft table and commit swaps them in. Callbacks before commit must still target the committed pass. |
| `animationController` | Begins a frame-head transaction, collects transitions, and defers completion closures in abortable mode. | Closest to ready, but still tied to resolved-tree processing and completion ordering. | Keep the explicit transaction, then narrow it so all completion execution and transition publication occur at commit. Aborted heads should only discard the transaction object. |

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

### F4-D: Draft runtime registrations and graph transaction

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

### F4-E: Observation and presentation drafts

Move the two context-coupled subsystems behind drafts:

- Observation: record observed identities and callback pass IDs in a prepared
  observation draft; publish them on commit.
- Presentation portals: route coordinator mutations into a prepared portal
  draft; publish overlay stack and dismiss-stack changes on commit.

Exit criterion: abandoning a prepared head cannot change observation invalidation
routes or presentation portal visibility.

### F4-F: Animation transaction finalization

Finish the animation side of the boundary:

- Keep transition collection pass-owned.
- Publish transition registrations and placed-overlay state only when the frame
  commits.
- Execute completion closures only after commit accepts the frame.

Exit criterion: `animationController` is no longer in the declared head effect
set.

### F4-G: Remove the declared head effect set

When all five effects have moved to draft or commit:

- Remove or empty `FrameHeadDeclaredEffect.runtimeHead`.
- Remove abort rollback checkpoints for the five subsystems.
- Update ADR/proposal/status docs to state that commit is the side-effect
  boundary without qualification.
- Revisit queued-tail cancellation using the now-discardable prepared head.

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

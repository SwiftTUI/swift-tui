---
title: "refactor: make prepared frame heads abortable"
type: refactor
status: reverted
date: 2026-04-26
proposal: "../proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md"
---

# refactor: make prepared frame heads abortable

> **Note:** This implementation was reverted. The consolidated current-state
> summary lives in [../ASYNC_RENDERING.md](../ASYNC_RENDERING.md).

## Overview

Make `DefaultRenderer` frame-head preparation reversible so a future runtime
can cancel a queued, not-yet-started frame-tail job without committing stale
renderer state.

This is Stage 3C of
[`ASYNC_RENDER_GENERATION_SCHEDULER.md`](../proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md).
Stages 3A and 3B already landed:

- the run loop coalesces not-yet-started render intent before rendering,
- `renderViewAsync` now has explicit prepare-tail-finish helpers.

This tranche does not add worker cancellation and does not drop completed frame
tails. Its only job is to make this sequence safe and test-backed:

```swift
let draft = renderer.prepareFrameHead(...)
renderer.abort(draft)
let next = await renderer.renderAsync(...)
```

After aborting `draft`, the renderer must behave as though that frame head was
never prepared.

## Implementation Result

Stage 3C is implemented.

- `DefaultRenderer` now creates a single-use async `FrameHeadDraft` transaction.
  `finishFrame` consumes the draft and commits deferred side effects;
  `abortFrameHead` consumes the draft and restores the checkpoint.
- `ViewGraph`, `ViewNode`, `DependencyTracker`, and `FrameResolveState` expose
  package checkpoint/restore seams used by the abort path.
- Runtime registrations are staged in draft registries during frame-head
  preparation and restored into live registries only when the frame finishes.
- `AnimationController` frame-head transactions checkpoint animation state and
  defer completion closures until finish; abort discards deferred completions.
- Retained frame-tail state remains commit-only and is covered by an abort
  checkpoint seam for future tail cancellation.
- `AsyncFrameTailRenderingTests` covers normal committed scaffold effects,
  draft registration staging, graph/registration rollback after abort, and
  animation completion discard on abort.

## Post-mortem (2026-04-26)

**Status: reverted on `frame-head-wip`.** Two reverts (`56995ff` of `16e4917`,
then `263003f` of `40a17fc`) and a follow-up cleanup commit (`c30c5fe`) backed
this tranche out. Animation-completion deferral (`0cacb9e`) is kept; the
checkpoint scaffolding on `ViewGraph` / `ViewNode` / `DependencyTracker` /
`FrameResolveState` was deleted as dead code by the cleanup.

### What broke

Real-terminal scrolling and clicking regressed. Behavior was demonstrably
worse against the gallery example by hand. Reverting just the registration
staging restored expected behavior; keeping the abort scaffolding around the
revert was incompatible with the staging-removal because the abort path
depended on `FrameHeadDraft` being a class with consume/restore mechanics, so
the abort path had to come out too.

### Root cause (most likely)

The implementation of step 4 below diverged from the plan in one critical way:

- **The plan said**: at `finishFrame`, apply the recorded live mutation
  (`.resetAll` / `.removeSubtrees` / `.none`) and then **restore handlers from
  the committed graph** by walking `ResolvedNode`s and replaying each node's
  `NodeHandlers` into the live registries.
- **The implementation did**: apply the live mutation, then call
  `RuntimeRegistrationDraft.restoreAllIntoLive()` which merges the
  *per-frame draft registry snapshots* into live.

The two are not equivalent. The draft registries only contain what was
*touched during the current frame's resolve* — the dirty frontier's evaluator
plus any cache-hits restored via `ViewGraph.restoreRuntimeRegistrations(for:
into:)`. They omit:

- Subtrees outside the dirty frontier whose evaluators never ran.
- Alias-only nodes (e.g. ScrollView vertical/horizontal indicator identities)
  promoted out of the dirty frontier.
- Anything that exists in `nodesByIdentity` but whose evaluator chain wasn't
  walked this frame.

For `.removeSubtrees(roots)` the bug is mostly self-cancelling because the
mutation only clears live under `roots` and the draft contains exactly that
subtree's re-resolve output. For `.resetAll` the bug is direct: live is
wiped, but the draft only carries what `rootEvaluator?()` walked, and any
alias node that didn't sit on that walk silently disappears from the live
registry until the next full re-resolve.

The user-visible symptom is hard to predict from the model: scroll-indicator
clicks miss, drag-tracking fires against stale handlers, `keyCommand` /
`dropDestination` fall through to the wrong scope. Real terminal use trips it;
deterministic tests don't.

### Why the test suite didn't catch it

Documented for future-us so we don't relearn this:

- **Sync vs async paths**: most existing scroll/click tests
  (`InteractiveRuntimeTests`, the `runLoopBatchesQueuedScrollBursts` family)
  drive `runLoop.handleMouseEvent(...)` directly + `renderPendingFrames`
  (sync). They never enter `renderViewAsync` so they never exercise the
  staging code path.
- **Async-path coverage gap**: tests that *do* use the async path
  (`runTerminalInputHarness` → `runLoop.run()`, `realInputReader…` family)
  exercise it correctly under selective evaluation, but the scenarios they
  cover (a single ScrollView, a single Button) keep the dirty subtree's
  evaluator walking exactly the nodes whose handlers matter, so the
  staging-vs-graph divergence happens to produce the same registry contents.
- **No invariant test**: nothing asserted "live registries equal what
  `restoreRuntimeRegistrations(rootedAt: liveIdentities, into: live)` would
  build". A property of that shape would have caught it.

I attempted to write such an invariant test against a `bisect-staging-only`
branch (just `40a17fc` cherry-picked on top of `main`); the simple
"pointer routes don't disappear" formulation passed on both branches. The
failing-mode is more nuanced than the simple invariant captures.

### Guidance for the next attempt

When re-implementing step 4:

1. **Restore from the graph, not from the draft.** At `finishFrame`, after
   `runtimeRegistrationMutation.apply(to: live)`, walk the just-finalized
   `ResolvedNode` tree and call
   `viewGraph.restoreRuntimeRegistrations(for: resolved, into: live)` (the
   helper added in `40a17fc` is still useful — it walks `nodesByIdentity` and
   honors `registrationAliasesByIdentity`). This guarantees live is a
   superset of what the committed graph specifies, regardless of which
   evaluators actually ran.
2. **Keep the draft as a side-channel for `register()` calls during resolve.**
   Its only purpose is to capture *new* registrations from the dirty
   frontier's evaluator without contaminating live mid-frame. Do not use it
   as the source of truth at commit.
3. **Validate by hand, not by `swift test`.** Run `gallery-demo` interactively
   alongside `main` in another terminal. Scroll a tab. Click a button. Drag a
   slider. If it doesn't *feel* identical, do not merge.
4. **Add the invariant test once you can see the bug.** Easier to write a
   test that fails red against an observed symptom than to construct one
   blind.

The dead checkpoint scaffolding (`ViewGraph.Checkpoint`, `ViewNode.Checkpoint`,
`DependencyTracker.Checkpoint`) was deleted in `c30c5fe` so the next attempt
starts from a clean slate. Animation-completion deferral
(`AnimationController.Checkpoint`) survives because it's in active use and
its tests pass.

## Problem Frame

`prepareFrameHead` is not currently a pure draft builder. It mutates live
renderer state before the async tail starts:

- `ViewGraph.beginFrame()`, invalidation, dirty evaluation, and snapshot reads,
- `RuntimeRegistrationSet.resetAll()` / `removeSubtrees(...)` followed by
  direct registration into live registries,
- `AnimationController.beginTransitionCollection()`,
  `finishTransitionCollection()`, `processResolvedTree(...)`, and
  `applyInterpolations(...)`,
- retained frame-tail input capture.

Some of those effects are ordinary mutable state and can be checkpointed. Some
are not:

- runtime registry reset can tear down gesture recognizers and gesture-state
  bindings, so snapshotting after reset is too late,
- animation batch release can fire completion closures during interpolation, so
  a checkpoint cannot un-fire user code,
- `CommandRegistry` and `DropDestinationRegistry` are live runtime registries
  but are not currently recorded in `NodeHandlers`, so cache-hit restoration is
  incomplete for a draft-only registration model.

The next tranche therefore needs a hybrid design:

- checkpoint and restore graph-owned state,
- stage runtime registrations until frame finish,
- defer animation completion side effects until frame finish,
- keep tail-retained state unchanged until the frame actually commits.

## Goals

- Add an explicit `FrameHeadDraft.abort()` path.
- Preserve current ordered commit behavior.
- Leave the synchronous `render(...)` path behavior unchanged.
- Keep `View.body`, runtime registration, and animation controller ownership on
  the main actor.
- Do not expose new public API.
- Make abort idempotence impossible by construction: a draft can finish or
  abort exactly once.
- Prove abort safety for:
  - `ViewGraph` invalidation and lifecycle staging,
  - action/key/pointer/gesture/focus/scroll/lifecycle/task/preference/command/drop
    runtime registrations,
  - animation transition/interpolation state and completion closures,
  - retained layout/raster caches.

## Non-goals

- No worker cancellation in this tranche.
- No event-pump/tail-task race in this tranche.
- No completed-result dropping.
- No off-main resolve.
- No public renderer draft API.
- No broad locking around live registries.

## Design Direction

### 1. Use an explicit frame-head transaction

Introduce a package-internal frame-head transaction owned by `DefaultRenderer`.

```swift
@MainActor
package struct FrameHeadDraft {
  package let id: FrameHeadDraftID
  package let generation: RenderGeneration
  package let resolved: ResolvedNode
  package let frameTailInput: FrameTailInput
  package let commitInputs: FrameCommitInputs
}

@MainActor
private struct FrameHeadAbortCheckpoint {
  var viewGraph: ViewGraph.Checkpoint
  var runtimeRegistrations: RuntimeRegistrationDraft
  var animation: AnimationController.Checkpoint
  var tailRetained: FrameTailRetainedState.Checkpoint
}
```

The exact type names can change during implementation. The contract should not:
preparation starts a transaction, finishing consumes it, aborting consumes it,
and no transaction may be reused.

### 2. Checkpoint `ViewGraph`, not runtime registries

`ViewGraph` and `ViewNode` mutations are internal renderer state. Add
package-internal checkpoint/restore APIs:

```swift
extension ViewGraph {
  package struct Checkpoint { ... }
  package func makeCheckpoint() -> Checkpoint
  package func restore(_ checkpoint: Checkpoint)
}

extension ViewNode {
  package struct Checkpoint { ... }
  package func makeCheckpoint() -> Checkpoint
  package func restore(_ checkpoint: Checkpoint)
}
```

The checkpoint must include:

- graph root, evaluator identity, node index, frame order, invalidation sets,
  lifecycle staging arrays, live identity set, dependency indexes, alias maps,
  and current frame ID,
- each existing node's committed snapshot, child references, parent reference,
  state slots, dependencies, lifecycle state, registered handlers, dirty flags,
  evaluation counters, frame IDs, and evaluator closure.

It is acceptable for new nodes created during the draft to remain allocated
after restore as long as they are unreachable from `nodesByIdentity`, parent
links, and root.

### 3. Stage runtime registrations in draft registries

Do not call `RuntimeRegistrationSet.resetAll()` or `removeSubtrees(...)` on the
live registries during `prepareFrameHead` once abort is possible.

Instead:

1. Record the intended live mutation:
   - `.resetAll`
   - `.removeSubtrees([Identity])`
   - `.none`
2. Resolve into draft registries.
3. Record every registration on the corresponding `ViewNode` through
   `NodeHandlers`.
4. On `finishFrame`, apply the recorded live mutation and restore handlers from
   the committed graph.
5. On `abort`, discard draft registries and leave live registries untouched.

This preserves the old committed frame's input surface while the new frame is
only prepared. That is the desired behavior for future cancellation: until a
new frame commits and presents, event dispatch should still target the old
presented tree.

Required registry work:

- add snapshot/restore support where it is missing for tests,
- record `CommandRegistry` and `DropDestinationRegistry` registrations in
  `NodeHandlers`,
- teach `RuntimeRegistrationSet.restore(from:)` to restore command/drop
  handlers as well as the existing registries,
- add a helper that restores registrations for either the whole committed tree
  or a dirty frontier after the live mutation is applied.

Do not rely on snapshotting live registries after mutation. Gesture registries
can tear down recognizers and gesture-state bindings during reset/removal, and
those side effects are not safely reversible.

### 4. Defer animation completion side effects

`AnimationController.applyInterpolations(...)` and placed-overlay sampling can
release animation batches. Releasing a batch can fire a user completion closure.
For an abortable frame head, completion closures must not run until the frame
commits.

Add an animation transaction mode:

```swift
extension AnimationController {
  package struct Checkpoint { ... }
  package func beginFrameHeadTransaction() -> Checkpoint
  package func commitFrameHeadTransaction(_ checkpoint: Checkpoint)
  package func abortFrameHeadTransaction(_ checkpoint: Checkpoint)
}
```

During a frame-head transaction:

- internal animation maps may mutate,
- completed batch IDs are collected,
- completion closures are not invoked.

On finish:

- keep the mutated animation state,
- fire deferred completions after commit planning succeeds and before the run
  loop applies lifecycle/task effects.

On abort:

- restore the checkpointed animation maps,
- discard deferred completions.

The checkpoint must cover:

- previous resolved/placed snapshots and matched-geometry maps,
- active animations,
- registered animations,
- completion closures,
- batch ref counts,
- pending empty-batch completions,
- transitions by identity,
- pending transitions,
- removing identities,
- previous identity set,
- last tick result.

### 5. Keep tail-retained state commit-only

`FrameTailRenderer.retainedInput(...)` is a read-only snapshot for the frame
tail. The retained state is updated only in `storeCommittedFrame(...)`, which
already runs in `finishFrame`. The first implementation should still add a
small checkpoint or assertion seam around `FrameTailRetainedState` so tests can
prove abort does not alter retained layout/raster reuse.

### 6. Add a package-internal test seam

Tests need to prepare and abort a frame head without starting worker tail work.
Add a package-internal seam, not a public API:

```swift
extension DefaultRenderer {
  package func prepareFrameHeadForCancellationTesting<V: View>(...) -> FrameHeadDraft
  package func abortPreparedFrameHeadForCancellationTesting(_ draft: FrameHeadDraft)
}
```

If the implementation can expose the real future runtime methods at `package`
access instead, prefer that over test-only naming. Keep the public
`DefaultRenderer.render(...)` and `renderAsync(...)` surfaces unchanged.

## Implementation Plan

### Task 1: Add abort-safety test scaffolding

Files:

- `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift`
- new helper types in that test file if needed

Add reusable scaffolding for the exact abort contract without committing a red
suite:

- a view fixture with action, key-command, drop, lifecycle, task, preference,
  focus, scroll, and animation-completion hooks,
- assertion helpers that inspect which effects fired after a normal committed
  render,
- a package-internal renderer test seam if it is needed for later tasks.

Do not leave failing or disabled tests in the tree. Add the abort assertions in
the tasks that make each subsystem abort-safe.

Commit boundary:

```bash
git commit -m "test(renderer): add frame-head abort scaffolding"
```

Validation:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
```

### Task 2: Make runtime registrations draft-applied

Files:

- `Sources/Core/Graph/NodeHandlers.swift`
- `Sources/Core/Graph/ViewNode.swift`
- `Sources/Core/RuntimeRegistrationSet.swift`
- `Sources/Core/CommandRegistry.swift`
- `Sources/Core/DropDestinationRegistry.swift`
- `Sources/View/ActionScopes/KeyCommandModifier.swift`
- `Sources/View/ActionScopes/DropDestinationModifier.swift`
- `Sources/SwiftTUI/SwiftTUI.swift`
- focused Core and SwiftTUI tests

Work:

- add command/drop registration storage to `NodeHandlers`,
- add `ViewNode` record methods for command/drop handlers,
- have key-command and drop-destination modifiers record through
  `ViewNodeContext.current`,
- add draft registry creation in `prepareFrameHead`,
- replace live registry reset/removal during prepare with a recorded mutation,
- apply that mutation and restore graph handlers during `finishFrame`,
- discard draft registrations during abort.

Commit boundary:

```bash
git commit -m "refactor(renderer): stage runtime registrations for frame heads"
```

Validation:

```bash
swiftly run swift test --filter CoreTests.CommandRegistryTests
swiftly run swift test --filter CoreTests.DropDestinationRegistryTests
swiftly run swift test --filter SwiftTUITests.KeyCommandTests
swiftly run swift test --filter SwiftTUITests.DropDestinationDispatchTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
```

### Task 3: Add `ViewGraph` and `ViewNode` checkpoints

Files:

- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/Core/Graph/ViewNode.swift`
- `Sources/Core/Graph/DependencyTracker.swift`
- `Tests/CoreTests/Graph/ViewGraphTests.swift`

Work:

- add checkpoint structs,
- include dependency tracker state,
- include per-node registration capture/evaluation counters,
- restore parent/child links and graph indexes,
- prove dirty/invalidation/lifecycle staging rolls back,
- prove a fresh render after restore reuses the pre-abort committed tree.

Commit boundary:

```bash
git commit -m "refactor(core): checkpoint view graph frame-head state"
```

Validation:

```bash
swiftly run swift test --filter CoreTests.ViewGraphTests
swiftly run swift test --filter SwiftTUITests.ResolveReuseAncestorInvalidationTests
swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests
```

### Task 4: Add animation frame-head transactions

Files:

- `Sources/SwiftTUI/AnimationController.swift`
- `Tests/SwiftTUITests/AnimationControllerTests.swift`
- `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift`

Work:

- add animation checkpoint/restore,
- route batch completion firing through a deferrable helper,
- collect completions during a frame-head transaction,
- fire deferred completions only on finish,
- discard deferred completions on abort,
- prove active animations, removals, placed overlays, matched geometry, and
  pending empty-batch completions survive abort correctly.

Commit boundary:

```bash
git commit -m "refactor(animation): defer frame-head animation side effects"
```

Validation:

```bash
swiftly run swift test --filter SwiftTUITests.AnimationControllerTests
swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
```

### Task 5: Wire `FrameHeadDraft.abort()`

Files:

- `Sources/SwiftTUI/SwiftTUI.swift`
- `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift`

Work:

- create the abort checkpoint before the first frame-head mutation,
- attach it to `FrameHeadDraft`,
- make `finishFrame` consume and commit the draft,
- make `abortFrameHead` consume and restore the checkpoint,
- trap or precondition on double finish/abort in package-internal paths,
- keep `renderAsync` behavior unchanged by always finishing the draft.

Commit boundary:

```bash
git commit -m "refactor(renderer): abort uncommitted frame heads"
```

Validation:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.FocusTransitionTests
swiftly run swift test --filter SwiftTUITests.PreferenceSurfaceTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
```

### Task 6: Update docs and run full gates

Files:

- `docs/proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md`
- `docs/proposals/ASYNC_FRAME_STALE_POLICY.md`
- this plan

Work:

- mark Stage 3C complete,
- record the chosen abort strategy,
- leave Stage 3D blocked only on cancellable pre-start tail submission,
- add any new diagnostics/test names to the proposal.

Commit boundary:

```bash
git commit -m "docs(renderer): record frame-head abort design"
```

Final validation:

```bash
./Scripts/check_public_surface_policies.sh
./Scripts/check_concurrency_safety_policies.sh
swiftly run swift test
bun run test
```

## Stop Conditions

Stop and revise the design before implementation continues if any of these
happen:

- runtime registration staging requires public API changes,
- gesture recognizer or gesture-state rollback cannot be made non-destructive,
- animation completion deferral changes committed-frame completion ordering,
- `ViewGraph` checkpointing cannot restore state slots without leaking a
  user-visible mutation,
- package-internal draft APIs start escaping into public surface.

If `ViewGraph` checkpointing proves too fragile, pivot to a graph-forked draft
resolver: the live graph remains committed state, and frame-head preparation
writes to a draft graph that is applied on finish or discarded on abort.

## Acceptance Criteria

The tranche is complete when:

- a prepared frame head can be aborted and followed by a normal render with no
  stale registrations, lifecycle events, focus state, preference observation,
  animation completion, or retained-cache drift,
- the normal sync and async render paths remain artifact-equivalent where
  diagnostics are disabled,
- Stage 3D can add pre-start tail cancellation without inventing a new rollback
  mechanism,
- `bun run test` passes.

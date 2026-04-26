# Off-Main Pipeline Rendering

## Status

Proposal.

This document explores whether any part of the terminal render pipeline can run
off the main actor. It does not propose moving the whole pipeline in one step.
The viable first target is the deterministic frame tail:

```
measure -> place -> semantics -> draw -> raster
```

The initial cut should keep these phases on a single worker actor/queue, not
parallelize them internally. `resolve`, focus synchronization, lifecycle commit,
runtime registration mutation, and terminal presentation stay owned by the main
actor at first.

## Problem

The current interactive runtime renders frames on the main actor:

```
event -> state mutation -> resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

Async presentation already moved blocking terminal `write(2)` work off the main
actor. That helps slow terminal pipes, but it does not help frames where layout,
placement, draw extraction, or rasterization are the expensive part.

The obvious next question is whether the pipeline itself can move off the main
actor. The answer is: partially, but only after separating authored-view
evaluation and runtime side effects from pure frame-tail computation.

## Goals

- Identify which pipeline phases can realistically move off the main actor.
- Preserve the current seven-phase mental model.
- Keep authored SwiftUI-like view evaluation semantically main-actor-isolated.
- Keep runtime state mutations deterministic and ordered.
- Avoid introducing public API changes unless a later whole-pipeline migration
  requires them.
- Create a migration plan that can land in testable increments.

## Non-goals

- Parallelizing individual layout or raster subtrees.
- Running user-authored `body`, `@State`, `Binding`, gesture callbacks, command
  actions, or lifecycle handlers off the main actor.
- Making local registries thread-safe by adding locks everywhere.
- Replacing the retained tree, animation controller, or presentation planner.
- Process-level renderer isolation.

---

## Current architecture

### Core pipeline shape

`Sources/Core/Pipeline.swift` already defines a generic `Renderer<Root>` as
explicit closure composition:

```
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The artifacts are value-shaped (`ResolvedNode`, `MeasuredNode`, `PlacedNode`,
`SemanticSnapshot`, `DrawNode`, `RasterSurface`, `CommitPlan`,
`FrameArtifacts`). That is the right broad shape for off-main computation.

The interactive runtime, however, does not use this generic renderer directly.
It uses `DefaultRenderer`, which is richer and stateful.

### DefaultRenderer state

`DefaultRenderer.render(...)` is `@MainActor` and owns:

- `ViewGraph`
- `FrameResolveState`
- `PresentationHostState`
- `AnimationController`
- `RetainedFrameStore`
- `LayoutEngine` and its `MeasurementCache`
- `ImageAssetRepository` resolver

The current render method does more than pure pipeline evaluation:

1. Prepares a `ResolveContext`.
2. Mutates `FrameResolveState`.
3. Begins a `ViewGraph` frame.
4. Evaluates dirty authored view nodes.
5. Reconciles presentation host state.
6. Processes animation transitions and interpolation.
7. Measures and places.
8. Extracts semantics and draw tree.
9. Rasterizes with previous-surface and damage context.
10. Finalizes the `ViewGraph` frame.
11. Computes lifecycle commit plan.
12. Updates retained frame state.

Only steps 7-9 are clearly pure enough to move first. Steps 6 and 10-12 are
stateful and coupled to the main-actor renderer today.

### RunLoop integration

`RunLoop.renderPendingFrames(...)` is `@MainActor`. For each scheduled frame it:

- builds the resolve context,
- calls `renderer.render(...)`,
- uses the semantic snapshot to update focus, focused values, scroll position,
  and palette commands,
- may rerender for focus synchronization,
- presents the raster surface,
- applies lifecycle/task commits,
- applies preference observation changes,
- schedules animation deadlines,
- logs diagnostics.

This means an off-main frame tail cannot be a simple background fire-and-forget
task. The main actor still needs the result before it can commit focus,
registrations, presentation, lifecycle, and diagnostics for that frame.

---

## Main-actor constraints

### Authored view evaluation

Most of the View layer is explicitly `@MainActor`:

- `View.body`
- `ViewBuilder`
- `AnyView` / `ScopedBuilder` resolve closures
- collection content builders
- button/menu/link actions
- gesture recognizers and callbacks
- bindings
- dynamic-property support

This should remain true. User code expects SwiftUI-style main-actor authoring.
Moving `resolve` off-main would require a much larger authoring model change.

### Task-local context

Current authoring and animation context rely on main-actor task-local storage:

- `AuthoringContextStorage.current`
- `AnimationContextStorage.currentRequest`
- animation/transition/completion sinks
- `ViewNodeContext.current`

`docs/proposals/ARCHITECTURE_NOTES.md` already identifies explicit context
threading as the prerequisite for off-main rendering demand. That refactor is
still relevant, but it is too large to require for a first frame-tail offload.

### Runtime registrations

`ResolveContext` carries main-actor registries:

- local action handlers,
- key handlers,
- pointer handlers,
- gesture state,
- focus bindings,
- focused values,
- scroll position bridges,
- preference observation handlers,
- lifecycle/task registrations,
- command and drop-destination registries.

These are side-effectful and callback-oriented. They should not be mutated from
a worker. For a frame-tail offload, all registration mutation must finish during
main-actor resolve before the worker starts.

### Commit and lifecycle

`DefaultRenderer` currently calls `viewGraph.finalizeFrame(...)` during commit.
That is a main-actor operation because `ViewGraph` owns retained nodes,
evaluators, aliases, and lifecycle edges.

The worker can produce `measured`, `placed`, `semantics`, `draw`, `raster`, and
diagnostics. The main actor should still run `viewGraph.finalizeFrame(...)` and
`CommitPlanner.plan(...)` until lifecycle extraction is split from `ViewGraph`.

### Focus synchronization

The run loop may render repeatedly in one scheduled frame until focus bindings,
focused values, and scroll-position synchronization converge. Off-main tail
rendering must preserve that loop:

1. main actor resolves,
2. worker computes frame tail,
3. main actor syncs focus/focused values/scroll,
4. if sync changed runtime state, main actor resolves again and submits another
   tail job.

Skipping this loop would regress focus and scroll behavior.

---

## Viable migration shape

### Phase 1: Frame tail offload

Introduce a package-internal worker responsible for:

```
measure -> place -> semantics -> draw -> raster
```

The main actor still performs:

```
resolve -> animation capture/interpolation -> worker tail -> commit -> present
```

The worker should be a single serial actor or queue-owned object. A serial
worker keeps retained layout/raster caches coherent without broad locking and
preserves deterministic diagnostics.

Proposed type shape:

```swift
package struct FrameTailInput: Sendable {
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var environment: EnvironmentSnapshot
  var transaction: TransactionSnapshot
  var invalidatedIdentities: Set<Identity>
  var previousRasterSurface: RasterSurface?
  var retainedLayoutSnapshot: RetainedLayoutSnapshot?
  var collectsDiagnostics: Bool
}

package struct FrameTailOutput: Sendable {
  var measured: MeasuredNode
  var placed: PlacedNode
  var baselinePlaced: PlacedNode
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var raster: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var diagnostics: FrameTailDiagnostics
}

package actor FrameTailRenderer {
  private var layoutEngine: LayoutEngine
  private var semanticExtractor: SemanticExtractor
  private var drawExtractor: DrawExtractor
  private var rasterizer: Rasterizer
  private var retainedTailState: RetainedTailState

  package func render(_ input: FrameTailInput) -> FrameTailOutput
}
```

`RetainedTailState` should be owned by the worker. It replaces the parts of
`RetainedFrameStore` that only serve measurement reuse and previous-surface
raster reuse. Main-actor code should not read or mutate this state directly.

The first implementation can keep `LayoutEngine`, `SemanticExtractor`,
`DrawExtractor`, and `Rasterizer` as they are if they are `Sendable` enough for a
worker-owned instance. If strict concurrency rejects that, make the worker a
class isolated behind a serial `DispatchQueue` and keep the mutable components
private to that queue.

### Phase 1A: Main-actor orchestration

Split `DefaultRenderer.renderView(...)` into two methods:

```swift
@MainActor
func resolveFrameHead(...) -> FrameHeadOutput

@MainActor
func finishFrame(
  head: FrameHeadOutput,
  tail: FrameTailOutput
) -> FrameArtifacts
```

`resolveFrameHead(...)` performs current resolve, presentation host composition,
safe-area wrapping, animation processing, and animation interpolation. It returns
a fully prepared `ResolvedNode` plus the state needed for commit.

`finishFrame(...)` runs `viewGraph.finalizeFrame(...)`, plans commit, updates
animation placed-tree snapshots if still main-actor-owned, stores any
main-actor-retained artifacts, and constructs `FrameArtifacts`.

If animation removal overlays still require `capturePlacedTree(...)` and
`applyPlacedOverlays(...)`, Phase 1 has two options:

1. Keep placed-overlay animation on the main actor after the worker returns
   baseline placement, then run semantics/draw/raster on the worker in a second
   worker call. This is safer but adds another hop.
2. Move only the animation controller's placed-overlay data needed for this
   frame into `FrameTailInput`, letting the worker apply overlays before
   semantics/draw/raster. This is better long-term, but requires making that
   overlay state a value snapshot.

Recommendation: start with option 1 if implementation risk matters; move to
option 2 once parity tests are green.

### Phase 1B: Async run-loop boundary

`RunLoop.renderPendingFrames(...)` must become async or call an async helper:

```swift
package func renderPendingFrames(renderedFrames: inout Int) async throws
```

Awaiting the worker should suspend the main actor, allowing input and signal
handling to enqueue more work while the frame tail computes. The current frame
must still commit in order. Do not present newer frames before older committed
state has been finalized unless a later generation-dropping design explicitly
handles skipped commits.

At this phase, do not drop in-flight pipeline work. Let the first version be
correct and ordered. If background tail latency proves high enough to create
stale results, add generation cancellation later.

### Phase 1C: Diagnostics

Current diagnostics report per-phase timings and counts. The split should keep
those fields stable:

- main actor measures resolve and commit,
- worker measures measure/place/semantics/draw/raster,
- presentation timing remains measured around `terminalHost.present(...)`,
- total frame duration includes awaited worker time.

Add explicit worker queue latency once useful:

- time from submitting tail work to worker start,
- time spent computing tail work,
- time from worker completion to main-actor commit.

---

## Why not move the whole pipeline first?

Whole-pipeline off-main rendering means moving `resolve` off-main. That implies:

- user-authored `View.body` would run off-main,
- `@State` and `Binding` reads/writes would need a new actor contract,
- `ViewGraph` evaluators could no longer be `@MainActor` closures,
- authoring context task-locals would need explicit context passing,
- runtime registrations would need snapshot builders instead of direct mutation,
- observation tracking would need a non-main actor story,
- gesture, focus, scroll, lifecycle, task, and command registrations would need
  apply-on-main diffs.

That is an architectural migration, not a performance patch. It may be worth
doing eventually, but it should be justified by evidence that post-resolve
offload is insufficient.

---

## Later migration: snapshot-producing resolve

If Phase 1 is not enough, the next step is not "make registries thread-safe."
The next step is to make resolve produce side-effect snapshots:

```swift
package struct ResolveSideEffects: Sendable {
  var actionRegistrations: [ActionRegistrationSnapshot]
  var keyHandlerRegistrations: [KeyHandlerRegistrationSnapshot]
  var pointerRegistrations: [PointerRegistrationSnapshot]
  var gestureRegistrations: [GestureRegistrationSnapshot]
  var focusBindingRegistrations: [FocusBindingRegistrationSnapshot]
  var focusedValueRegistrations: [FocusedValueRegistrationSnapshot]
  var scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot]
  var preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot]
  var lifecycleRegistrations: [LifecycleRegistrationSnapshot]
  var taskRegistrations: [TaskRegistrationSnapshot]
  var commandRegistrations: [CommandRegistrationSnapshot]
  var dropDestinationRegistrations: [DropDestinationRegistrationSnapshot]
}
```

Resolve would fill a local snapshot builder. The main actor would apply the
diff to live registries after the worker returns. This preserves registry
ownership while making resolve less side-effectful.

This shape also makes it possible to test resolve output without installing live
runtime registries.

---

## Cancellation and ordering

Pipeline offload creates a new stale-result problem:

1. Frame A starts on the worker.
2. Input arrives and mutates state.
3. Frame B is scheduled before A finishes.
4. A finishes with artifacts for old state.

The first implementation should commit A in order, then render B. This preserves
today's semantics and avoids skipped lifecycle/focus transitions.

Only after that is correct should the runtime consider dropping stale tail
results. Dropping a computed frame is harder than dropping a presentation write
because commit has side effects:

- lifecycle appear/disappear edges,
- task starts/cancellations,
- focus binding sync,
- scroll-position sync,
- preference observation updates,
- animation controller state,
- retained layout/raster caches.

If frame dropping is introduced later, it must either:

- prove that skipped frames have not committed any side effects, or
- run a main-actor reconciliation pass that advances lifecycle and retained
  state safely to the newest frame.

Until that exists, ordered commit is the safer contract.

---

## Performance expectations

Moving the tail off-main does not make a single frame finish faster by itself.
The user-visible win is main-actor responsiveness while the tail computes:

- input bytes can be read and queued,
- timers/deadlines can be scheduled,
- host callbacks can run,
- terminal writes are already async.

The frame still cannot be presented until rasterization finishes.

This is likely worthwhile only if diagnostics show meaningful time in
measure/place/draw/raster on realistic workloads. If the hot path is resolve,
state mutation, focus sync, or commit, Phase 1 will not solve it.

Do not start implementation without first adding or using diagnostics that can
separate:

- resolve time,
- measure/place time,
- semantics/draw time,
- raster time,
- commit time,
- presentation submit time,
- input-to-commit latency.

---

## Implementation plan

### Step 0: Characterize

Use existing frame diagnostics on the gallery, layouts example, and at least one
large synthetic tree. Identify whether frame time is dominated by the tail.

Add a focused benchmark if current diagnostics do not expose enough:

- large `VStack`/`List` layout,
- styled text rasterization,
- image-heavy rasterization,
- animation tick with resolve reuse.

### Step 1: Extract a synchronous frame-tail function

Before adding concurrency, refactor `DefaultRenderer.renderView(...)` so the
tail is a separate synchronous helper:

```swift
func renderFrameTail(_ input: FrameTailInput) -> FrameTailOutput
```

Run existing tests. This proves the seam is correct before actor/queue concerns
enter the picture.

### Step 2: Move tail-owned retained state behind the seam

Move measurement-cache and previous-raster-surface ownership into the tail
object. Keep main-actor commit state in `DefaultRenderer`.

Tests to preserve:

- retained layout reuse,
- raster damage refinement,
- animation tick reuse,
- Kitty image replay behavior,
- focus-sync rerender behavior.

### Step 3: Add the worker

Introduce a serial `FrameTailRenderer` worker and call it from an async render
path. Keep a synchronous test-only path until the async runtime path is stable.

Use one worker per `DefaultRenderer`, not one global worker. Per-renderer workers
preserve cache locality and avoid cross-scene contention.

### Step 4: Convert run-loop rendering to async

Change the render loop boundary to await tail rendering. Preserve ordered frame
commit. Do not drop computed frames.

Regression tests should cover:

- input event can be queued while a tail job is blocked,
- focus-sync rerenders still converge,
- lifecycle events fire once and in order,
- animation deadlines still schedule after commit,
- diagnostics include worker phase durations.

### Step 5: Evaluate

Compare before/after:

- main-actor blocked time per frame,
- input-to-state-mutation latency under heavy raster/layout load,
- total frame time,
- animation smoothness,
- full `bun run test`.

If total frame time worsens and main-actor responsiveness does not improve in a
measurable way, stop. The seam may still be useful for testability, but it
should not be carried as runtime complexity without evidence.

---

## Open questions

- Should animation placed-overlay application move into the worker in Phase 1,
  or should the first cut split the tail into `measure/place` and
  `semantics/draw/raster` around main-actor animation overlay work?
- Are all `ResolvedNode`, `MeasuredNode`, `PlacedNode`, `DrawNode`,
  `RasterSurface`, and `PresentationDamage` members actually `Sendable` under
  strict checking once the worker boundary is real?
- Should the worker be a Swift actor or a serial `DispatchQueue`-backed class?
  Actor isolation is cleaner; a queue can be more pragmatic if existing mutable
  pipeline components do not satisfy `Sendable` cleanly.
- Should diagnostics expose main-actor blocked time separately from total frame
  latency?
- How much of `CommitPlanner.plan(...)` can become pure once
  `ViewGraph.finalizeFrame(...)` is split from commit planning?

## Recommendation

Do not attempt whole-pipeline off-main rendering first.

Start with a frame-tail seam, keep it synchronous until tests prove the split,
then move that tail behind a per-renderer serial worker. This targets the only
large region of the current runtime that is plausibly pure and expensive:

```
measure -> place -> semantics -> draw -> raster
```

Treat off-main `resolve` as a separate future project requiring explicit
authoring context, side-effect snapshots, and a main-actor registry apply phase.

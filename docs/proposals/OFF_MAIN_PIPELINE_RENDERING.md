# Off-Main Pipeline Rendering

## Status

Implemented in narrowed form.

For the consolidated async rendering status, see
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md). This file is the detailed
record for the initial guarded frame-tail worker.

This document explores whether any part of the terminal render pipeline can run
off the main actor. It does not propose moving the whole pipeline in one step.
The viable first target was originally evaluated as the deterministic frame
tail:

```
measure -> place -> semantics -> draw -> raster
```

Implementation proved that this target has to be conditional for the current
runtime. Ordinary authored custom-layout callbacks still use main-actor-isolated
`LayoutProxyBox` entry points, while `SendableLayout` opt-in and framework-owned
worker-safe layouts can avoid that bridge. The retained shape is:

```
main actor: resolve -> animation interpolation
worker when eligible: measure -> place
main actor fallback: ordinary custom Layout measure -> place
main actor: placed-animation overlay snapshot
worker: overlay application -> semantics -> draw -> raster
main actor: commit -> present -> lifecycle
```

The worker is a private per-renderer serial queue. `resolve`, ordinary custom
layout fallback, focus synchronization, lifecycle commit, runtime registration
mutation, and terminal presentation remain owned by the main actor. Built-in
layout, explicitly opted-in `SendableLayout` custom layout, framework-owned
`SendableLayout` containers, and snapshotted lazy indexed child sources can run
on the worker because they are value-shaped after resolve.

## Implementation result

The staged migration landed behind the existing public runtime surface:

- `DefaultRenderer` now has an async render entry point used by the interactive
  run loop.
- A private `FrameTailRenderer` owns built-in layout offload, worker-side
  placed-overlay application, semantic extraction, draw extraction,
  rasterization, previous-surface reuse, and worker timing diagnostics.
- The runtime awaits the worker and preserves ordered frame commit. It does not
  drop computed frames or present newer frames ahead of older side effects.
- Blocking-tail tests verify that input can be queued while async tail rendering
  is suspended, without committing or presenting out of order.
- Full repository validation passed with `bun run test` after the async runtime
  path and stress coverage were added.

Decision: keep the async runtime path, but treat it as a guarded frame-tail
offload. It is a correct suspension boundary for built-in layout and
semantics/draw/raster-heavy frames, and it gives ordinary custom layout an
explicit fallback boundary. Later `SendableLayout` work added an opt-in path for
worker-safe custom layout; it is not evidence that all custom layout measurement
and placement are ready to leave the main actor.

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
- `PresentationPortalState`
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

### Phase 1: Guarded frame tail offload

Introduce a package-internal worker responsible for the Sendable built-in
layout and post-layout tail:

```
built-in measure -> built-in place -> overlay application -> semantics -> draw -> raster
```

The main actor still performs resolve, animation interpolation, animation
snapshotting, custom-layout fallback, commit, and presentation:

```
resolve -> animation interpolation -> guarded worker tail -> commit -> present
```

The worker should be a single serial actor or queue-owned object. A serial
worker keeps retained layout/raster caches coherent without broad locking and
preserves deterministic diagnostics.

Proposed type shape:

```swift
package struct FrameTailInput: Sendable {
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var rootIdentity: Identity
  var retained: FrameTailRetainedInput
  var layoutPassContext: LayoutPassContext
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

package final class FrameTailRenderer: Sendable {
  private let semanticExtractor: SemanticExtractor
  private let drawExtractor: DrawExtractor
  private let rasterizer: Rasterizer
  private let retainedTailState: FrameTailRetainedState

  package func renderRasterAsync(
    _ input: FrameTailInput,
    placed: PlacedNode
  ) async -> FrameTailOutput
}
```

`RetainedTailState` should be split by actor ownership. Previous-surface raster
reuse and built-in retained-layout cache access can be worker-owned. Custom
layout measurement and placement remain main-actor-owned until custom layouts
have a non-main isolation model.

The first implementation can keep `LayoutEngine`, `SemanticExtractor`,
`DrawExtractor`, and `Rasterizer` as they are if they are `Sendable` enough for a
worker-owned instance. If strict concurrency rejects that, make the worker a
class isolated behind a serial `DispatchQueue` and keep the mutable components
private to that queue.

Implementation note: the landed version uses the pragmatic serial
`DispatchQueue` shape. Built-in layout jobs run on that queue; resolved trees
containing `.custom` layout fall back to inline main-actor layout because
authored custom-layout callbacks are still main-actor-isolated.

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

Implementation chose option 1's ownership model, with an additional narrowing:
layout also remains on the main actor. Move to option 2 only after removal
overlay state can be represented as a Sendable value snapshot.

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

Implementation status: the interactive run loop now uses an async helper and
awaits `DefaultRenderer.renderAsync(...)`. The synchronous render path remains
available for deterministic package tests.

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

Implementation status: `FrameDiagnostics.workerTimings` records enqueue,
compute, and completion-to-main-commit timings for the worker portions.
`FrameDiagnostics.mainActorTimings` records main-actor blocked render time and
async worker-suspension time. `FrameDiagnosticsLogger` also records
`input_events_during_render_suspension` so blocked-tail tests can prove input
was accepted while commit remained ordered.

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

See [`ASYNC_FRAME_STALE_POLICY.md`](ASYNC_FRAME_STALE_POLICY.md) for the
dedicated policy and migration gates for future generation cancellation or
stale-result dropping.

---

## Performance expectations

Moving the tail off-main does not make a single frame finish faster by itself.
The user-visible win is main-actor responsiveness while the tail computes:

- input bytes can be read and queued,
- timers/deadlines can be scheduled,
- host callbacks can run,
- terminal writes are already async.

The frame still cannot be presented until rasterization finishes.

This is likely worthwhile only if diagnostics show meaningful time in the
worker-owned tail on realistic workloads. In the implemented version that means
semantics, draw extraction, and rasterization. If the hot path is resolve,
layout, state mutation, focus sync, or commit, Phase 1 will not solve it.

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

- What custom-layout API or snapshot design would let measurement and placement
  run away from the main actor without `MainActor.assumeIsolated` traps? See
  [`CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md`](CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md).
- Can the placed-animation overlay snapshot be narrowed further so it is easier
  to inspect, diff, and fuzz independently of `AnimationController`?
- How much of `CommitPlanner.plan(...)` can become pure once
  `ViewGraph.finalizeFrame(...)` is split from commit planning?

## Recommendation

Do not attempt whole-pipeline off-main rendering first.

Keep the landed guarded frame-tail seam and continue measuring it on built-in
layout and semantics/draw/raster-heavy workloads. It targets the regions of the
current runtime that proved pure enough for a worker without changing the
authoring model:

```
built-in measure -> built-in place -> overlay application -> semantics -> draw -> raster
```

Treat ordinary public custom layout as a main-actor fallback unless it opts in
through the `SendableLayout` contract described in
[`CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md`](CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md).
Treat off-main `resolve` as a still larger future project requiring explicit
authoring context, side-effect snapshots, and a main-actor registry apply phase.

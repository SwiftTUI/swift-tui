# Animation Plan

**Date:** 2026-04-08  
**Status:** Proposed  
**Supersedes in part:** [docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md](docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md)

## Goal

Add a SwiftUI-shaped animation system to this terminal UI framework, with a
credible first implementation of:

- `withAnimation(_:_:)`
- `View.animation(_:value:)`
- `View.transition(_:)`

The design must be future-compatible with:

- built-in spring families such as `.smooth`, `.snappy`, and `.bouncy`
- `Binding.animation(_:)`
- transaction-scoped animation overrides
- custom transitions
- later phase-based and keyframe-based APIs such as `phaseAnimator` and
  `keyframeAnimator`

The design must also respect the realities of a terminal renderer:

- layout is cell-quantized
- presentation is incremental and idle frames should still converge to zero
  bytes written
- semantics, focus, lifecycle, and tasks remain driven by the committed tree,
  not by temporary animation overlays

## SwiftUI Findings That Shape The Design

SwiftUI’s animation model is more constrained and more structured than it first
appears:

1. `withAnimation`, `Binding.animation(_:)`, and `.animation(_:value:)` are all
   transaction-based APIs. They do not directly animate closures or views;
   they annotate a specific update with `Animation?` intent.
2. `Transaction` is per-update and ephemeral. It is propagated during one UI
   refresh, then discarded.
3. `.animation(_:value:)` is value-gated. It only writes animation into the
   transaction when the watched value changes.
4. Only animatable properties interpolate. Non-interpolable state changes still
   snap.
5. Structural transitions are distinct from ordinary property animation.
   `transition(_:)` applies when a view is inserted into or removed from the
   hierarchy.
6. Modern SwiftUI custom transitions are phase-based. The important mental model
   is `willAppear -> identity -> didDisappear`.
7. `phaseAnimator` is layered on top of ordinary animation. It advances through
   discrete phases and still uses normal `Animation` values between them.
8. `keyframeAnimator` is a different class of system. It defines a timeline of
   values directly and is not a good substitute for retargetable, interactive
   state animation.

These findings point to one architectural split that we should preserve:

- `Animation` decides how progress evolves over time.
- animatable surfaces decide what can interpolate.
- `TransactionSnapshot` scopes animation intent to a single update.
- transitions are structural visual effects layered on top of lifecycle and
  diffing, not a second kind of state invalidation.

## Design Principles

### 1. Keep SwiftUI’s Transaction Model

The system should feel SwiftUI-shaped because it uses the same conceptual flow:

- authored API writes animation intent into the current transaction
- resolve propagates transaction intent through the tree
- animatable runtime surfaces decide whether to interpolate

We should not build a parallel “global animator” API that bypasses
transactions.

### 2. Separate Animation From Transition

Animation and transition overlap, but they are not the same thing:

- ordinary animation applies to state changes on views that survive the update
- transition applies to insertion/removal of view identity

Internally they can share clocks, sampling, and scheduling, but they should not
collapse into one enum or one modifier type.

### 3. Preserve The Existing Pipeline

The current pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

should remain the mental model.

Animation should be introduced as:

```text
resolve -> measure -> place -> semantics -> draw -> animate/sample -> raster -> commit
```

where “animate/sample” is a package-only coordinator that can:

- animate surviving draw channels
- overlay disappearing transition snapshots
- transform entering draw nodes
- return the next wake deadline

### 4. Keep Time Out Of `TransactionSnapshot`

`TransactionSnapshot` should carry intent, not progress.

If frame time lives inside `TransactionSnapshot`, retained resolve reuse will
collapse because every animation frame would look like a new transaction even
when nothing else changed.

### 5. Be Honest About Terminal Limits

A terminal can render some kinds of animation convincingly and others poorly.

Good v1 fits:

- color interpolation
- opacity fades
- integer-cell offset and reveal/clipping transitions
- spring timing for interruptible value changes

Poor v1 fits:

- sub-cell transforms
- rotation
- blur
- arbitrary scale
- matched geometry

The public design should not imply broad visual capabilities that the renderer
cannot deliver.

## Proposed Public Surface

### Phase 1 Public Surface

The first user-facing slice should add the commonly expected state animation
APIs plus built-in transition attachment:

```swift
public struct Animation: Equatable, Sendable {
  public static let `default`: Animation

  public static func linear(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeIn(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeOut(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeInOut(duration: Duration = .milliseconds(200)) -> Animation

  public static func smooth(duration: Duration = .milliseconds(350)) -> Animation
  public static func bouncy(
    duration: Duration = .milliseconds(500),
    extraBounce: Double = 0
  ) -> Animation
  public static func snappy(
    duration: Duration = .milliseconds(350),
    extraBounce: Double = 0
  ) -> Animation

  public static func spring(
    duration: Duration = .milliseconds(350),
    bounce: Double = 0,
    blendDuration: Duration = .zero
  ) -> Animation
}

@MainActor
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  _ body: () throws -> Result
) rethrows -> Result

extension View {
  public func animation<Value: Equatable>(
    _ animation: Animation?,
    value: Value
  ) -> some View

  public func transition(_ transition: AnyTransition) -> some View
}

public struct AnyTransition: Equatable, Sendable {
  public static let identity: AnyTransition
  public static let opacity: AnyTransition
  public static let slide: AnyTransition

  public static func move(edge: Edge) -> AnyTransition
  public static func push(from edge: Edge) -> AnyTransition
  public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition

  public static func asymmetric(
    insertion: AnyTransition,
    removal: AnyTransition
  ) -> AnyTransition

  public func combined(with other: AnyTransition) -> AnyTransition
  public func animation(_ animation: Animation?) -> AnyTransition
}
```

### Why `AnyTransition` First

SwiftUI’s modern custom transition model is protocol-first, but this repo does
not yet have the machinery to re-evaluate arbitrary disappearing subtrees
through transition bodies after removal.

That makes a phase-based public `Transition` protocol a poor first landing
surface.

The recommended sequence is:

1. ship `transition(_:)` plus `AnyTransition` built-ins
2. implement a phase-aware internal transition runtime
3. then add a public `Transition` protocol once custom transition lowering is
   stable

This keeps the first public surface small and honest while still leaving the
internal architecture ready for SwiftUI’s `TransitionPhase` model.

### Deferred Public Surface

These should be explicitly out of scope for the first implementation, but the
architecture should not block them:

- `Binding.animation(_:)`
- `withAnimation(_:completionCriteria:_:completion:)`
- public `Transaction`
- public `TransactionKey`
- body-scoped `.animation(_:body:)`
- public `Transition` / `TransitionPhase`
- `contentTransition(_:)`
- `phaseAnimator`
- `keyframeAnimator`
- `CustomAnimation`
- `Animatable` / `VectorArithmetic`
- `matchedGeometryEffect`
- navigation and scroll transitions

## Internal Architecture

## 1. Core Animation Types

Add package-only animation descriptors in `Core` rather than storing authored
`View.Animation` values directly in runtime structures.

Suggested shape:

```swift
package enum AnimationDescriptor: Equatable, Sendable {
  case curve(
    curve: UnitCurveDescriptor,
    duration: Duration,
    delay: Duration
  )
  case spring(
    duration: Duration,
    bounce: Double,
    extraBounce: Double?,
    blendDuration: Duration,
    delay: Duration
  )
}

package enum AnimationRequest: Equatable, Sendable {
  case inherit
  case disabled
  case animate(AnimationDescriptor)
}
```

This keeps authored API in `View` and runtime intent in `Core`.

## 2. Extend `TransactionSnapshot`

`TransactionSnapshot` should stop being just a debug string carrier.

Suggested additions:

```swift
public struct TransactionSnapshot: Equatable, Sendable {
  public var debugSignature: String

  package var animation: AnimationRequest
  package var disablesAnimations: Bool
}
```

Important:

- add a dedicated “reuse equivalence” helper that ignores debug-only fields
- do not let `debugSignature` or future completion bookkeeping defeat resolve
  reuse

## 3. Mutation-Time Animation Plumbing

Adopt the pattern already outlined in
`docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md`:

- use a task-local to hold the current `AnimationRequest`
- let state mutations attach animation intent to the next invalidation
- keep `Invalidating` public protocol stable if possible
- add a package-only `AnimationAwareInvalidating` refinement

Suggested shape:

```swift
package enum AnimationContextStorage {
  @TaskLocal static var currentRequest: AnimationRequest = .inherit
}

package protocol AnimationAwareInvalidating: Invalidating {
  func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest
  )
}
```

`FrameScheduler` should coalesce the pending animation request for the next
frame using a simple rule:

- latest explicit request wins
- `.disabled` is explicit
- `.inherit` never overwrites an explicit pending request

## 4. Resolve-Time Value-Gated Animation

`.animation(_:value:)` should remain resolve-time plumbing, not mutation-time
plumbing.

It needs private modifier bookkeeping state:

- read previous watched value
- compare to current watched value
- if changed, override the child transaction
- store the new value without triggering another invalidation

That implies a new non-invalidating state-slot write path for modifier
bookkeeping.

This matches SwiftUI semantics more closely than trying to infer watched-value
changes from scheduler invalidations.

## 5. A Unified Presentation Animation Coordinator

The existing color plan proposed a `ColorAnimationCoordinator`.

For the broader feature set, the better long-term shape is a more general
package-only coordinator in `TerminalUI`, for example:

```swift
package final class PresentationAnimationCoordinator {
  func sample(
    current: DrawNode,
    previous: DrawNode?,
    frame: FrameContext,
    structuralDiff: StructuralAnimationContext
  ) -> PresentationAnimationResult
}

package struct PresentationAnimationResult {
  package var drawTree: DrawNode
  package var nextDeadline: MonotonicInstant?
}
```

Responsibilities:

- animate surviving draw channels like color and opacity
- create entering tracks for inserted nodes with transitions
- create disappearing overlay tracks for removed nodes
- sample all active tracks using the frame timestamp
- return the next wake deadline

This unifies ordinary animation and transition timing without conflating their
semantics.

## Transition Runtime Design

## 1. Structural Source Of Truth

Transitions should be driven by identity diffing from `ViewGraph`, not by ad hoc
view inspection.

The runtime already knows:

- which nodes appeared this frame
- which nodes disappeared this frame
- which nodes preserved identity

That is the right place to decide whether a transition track starts.

## 2. Entering And Exiting Tracks

We need two different runtime stories:

- entering view:
  - the node exists in the current tree
  - semantics/focus/lifecycle operate on the current tree immediately
  - the coordinator samples from `willAppear -> identity`

- exiting view:
  - the node no longer exists in the current tree
  - semantics/focus/tasks/lifecycle must already reflect removal
  - the coordinator retains a non-semantic visual snapshot and samples
    `identity -> didDisappear`

This is the most important transition design constraint in the repo.

Removed views cannot remain in the live semantic tree just because they are
still animating visually.

## 3. Snapshot Strategy For Removal

For disappearing transitions, retain the previous frame’s placed/draw data long
enough to animate it out.

Suggested retained track payload:

```swift
package struct ExitingTransitionTrack: Equatable, Sendable {
  package var identity: Identity
  package var drawSnapshot: DrawNode
  package var transition: ResolvedTransitionDescriptor
  package var start: MonotonicInstant
  package var end: MonotonicInstant
}
```

This avoids inventing fake lifecycle presence after removal.

## 4. `ResolvedTransitionDescriptor`

Built-in transitions should lower into a package-only descriptor model that the
coordinator can sample without re-resolving arbitrary view code.

Suggested shape:

```swift
package struct ResolvedTransitionDescriptor: Equatable, Sendable {
  package var insertion: TransitionEffectDescriptor
  package var removal: TransitionEffectDescriptor
  package var animationOverride: AnimationDescriptor?
}

package struct TransitionEffectDescriptor: Equatable, Sendable {
  package var opacity: Double?
  package var offsetX: Int
  package var offsetY: Int
  package var clipInsets: EdgeInsets?
  package var foregroundColor: Color?
  package var backgroundColor: Color?
  package var borderColor: Color?
}
```

The descriptor should be composable:

- `combined(with:)` merges effects
- `asymmetric` stores separate insertion/removal descriptors
- `.animation(_:)` overrides transition timing only

## 5. Supported Built-In Transition Set For v1

Because the renderer is cell-based, the recommended initial set is:

- `.identity`
- `.opacity`
- `.move(edge:)`
- `.push(from:)`
- `.slide`
- `.offset(x:y:)`
- `.combined(with:)`
- `.asymmetric(insertion:removal:)`

These can all be expressed with:

- opacity changes
- integer-cell offsets
- clipping/reveal masks

Do not promise these yet:

- `.scale`
- rotation-based transitions
- blur-based transitions
- transform-heavy custom transitions

Those effects are natural in SwiftUI, but they are not a good first fit for a
cell rasterizer.

## 6. Custom Transition Direction

The design should aim toward SwiftUI’s `TransitionPhase` model, but the public
custom-transition surface should wait until the runtime can lower phase-based
custom transition bodies safely.

That means:

- internal transition tracks should already think in
  `willAppear / identity / didDisappear`
- built-in `AnyTransition` should land first
- a public custom `Transition` protocol can follow once the lowerer can turn
  custom phase styling into a stable descriptor or a safely retained snapshot

In other words:

- phase-first internals now
- built-in/type-erased public surface first
- custom phase-authored public transitions second

## Animatable Surface Matrix

The first implementation should be explicit about what animates and what snaps.

### State changes on surviving nodes

Animate:

- text foreground color
- text background color when resolved to a single color
- background fill color
- border color
- opacity

Snap:

- layout position changes with stable identity
- size changes
- arbitrary shape geometry changes
- gradient interpolation
- terminal chrome interpolation
- text content replacement

### Structural insertion/removal

Animate when a transition is attached:

- fade
- integer-cell move/push/slide
- color/opacity changes included by the transition descriptor

Snap when unsupported:

- transform-heavy transitions
- transitions that require arbitrary sub-view re-layout during exit

This keeps the first implementation useful without pretending that terminal
layout animation already exists.

## Future Compatibility

### 1. `Binding.animation(_:)`

The mutation-time transaction plumbing should be built so bindings can reuse it
without touching the coordinator.

### 2. Body-Scoped Animation APIs

SwiftUI now has body-scoped animation and transaction modifiers. The internal
transaction override helpers added for `.animation(_:value:)` should be reusable
for these later surfaces.

### 3. `phaseAnimator`

`phaseAnimator` should be implemented as a separate higher-level engine that:

- drives a phase sequence
- selects an `Animation?` per phase edge
- delegates actual interpolation to the same base animation coordinator

The current work should therefore avoid baking “exactly one from/to state” too
deeply into runtime types.

### 4. `keyframeAnimator`

Keyframes should be a separate timeline/value engine. They should not reuse the
same internal type as transaction-carried state animation.

The scheduler and frame clock can be shared, but the sampled value generation
should be separate.

### 5. Completion Support

SwiftUI now exposes animation completion criteria. We do not need to implement
that in the first public slice, but we should not paint ourselves into a corner.

Recommendation:

- assign stable internal animation batch IDs when creating tracks
- keep coordinator-owned track groups explicit
- later add completion observers keyed by batch ID and completion criteria

## Repository-Grounded Implementation Plan

## Phase 0: Foundations And Reuse Fixes

Objectives:

- add package-only animation descriptors and requests
- extend `TransactionSnapshot`
- make deadline-only frames reuse-compatible
- stop debug-only transaction fields from defeating reuse

Primary files:

- `Sources/Core/EnvironmentAndNodeTypes.swift`
- new `Sources/Core/AnimationTypes.swift`
- `Sources/Core/Graph/ViewNode.swift`
- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/View/Foundation/ViewFoundation.swift`

Key repo-specific fix:

`ViewGraph.reusableSnapshot(...)` currently bails out when
`invalidatedIdentities` is empty. Animation frames and future timeline frames
need empty-invalidation reuse to be legal.

## Phase 1: Scheduler Wake Integration

Objectives:

- schedule and render deadline-only frames
- wake the run loop without synthetic input
- preserve input coalescing behavior

Primary files:

- `Sources/Core/Scheduler.swift`
- `Sources/Core/CommitAndFrameTypes.swift`
- `Sources/TerminalUI/RunLoop.swift`
- `Sources/TerminalUI/RunLoop+EventPump.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`

Key repo-specific constraint:

The event pump already supports scheduler wake callbacks through
`WakeNotifyingFrameScheduling`; the missing piece is carrying animation
requests and deadline work cleanly through scheduled frames.

## Phase 2: Mutation-Time Animation Plumbing

Objectives:

- let `withAnimation` annotate the next invalidation
- let state writes preserve explicit disable/override semantics

Primary files:

- `Sources/Core/Scheduler.swift`
- `Sources/Core/StateContainer.swift`
- `Sources/View/State/State.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`

Notes:

- reuse the task-local approach from the existing color plan
- keep public runtime protocols stable where possible

## Phase 3: Public Animation Surface

Objectives:

- add `Animation`
- add `withAnimation`
- add `.animation(_:value:)`
- store watched values without self-invalidating

Primary files:

- new `Sources/View/Animation.swift`
- `Sources/View/Modifiers/ViewModifiers.swift`
- `Sources/View/Environment/Environment.swift`
- `Sources/View/State/State.swift`

Acceptance focus:

- `.animation(_:value:)` only triggers when the value changes
- `.animation(nil, value:)` disables inherited animation for that subtree
- ordinary unanimated mutations behave exactly as before

## Phase 4: Extant-Node Animation Coordinator

Objectives:

- animate surviving draw channels such as color and opacity
- thread transaction data through to draw-time structures

Primary files:

- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/DrawExtractor.swift`
- new `Sources/TerminalUI/PresentationAnimationCoordinator.swift`
- `Sources/TerminalUI/TerminalUI.swift`

This phase is the natural evolution of
`docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md`.

## Phase 5: Built-In Transition Runtime

Objectives:

- add `AnyTransition`
- add `View.transition(_:)`
- create entering and exiting tracks
- overlay disappearing snapshots after removal

Primary files:

- new `Sources/View/Transition.swift`
- `Sources/View/Modifiers/ViewModifiers.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/Core/CommitAndFrameTypes.swift`
- `Sources/TerminalUI/PresentationAnimationCoordinator.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/TerminalUI/TerminalUI.swift`

Acceptance focus:

- insertion transition uses final layout and current semantics
- removal transition keeps rendering after semantic removal
- transition-specific animation override beats ambient transaction animation
- idle scheduling stops when tracks complete

## Phase 6: Custom Transition Surface

Objectives:

- expose a public custom transition story
- keep it aligned with SwiftUI’s phase model
- only ship it once built-in lowering is stable

Recommended public outcome:

- add `TransitionPhase`
- add `TransitionProperties`
- add a public `Transition` protocol
- keep `AnyTransition` as type erasure and storage surface

If this proves too large for the first post-built-in pass, ship a narrower
custom builder surface first and keep the internal runtime phase-based so the
later public `Transition` protocol remains additive.

## Testing Plan

### Core tests

- scheduler stores and coalesces animation requests correctly
- deadline-only frames are consumable without input
- transaction reuse equivalence ignores debug-only fields

Suggested locations:

- `Tests/CoreTests/Graph/ViewGraphTests.swift`
- new `Tests/CoreTests/AnimationSchedulerTests.swift`

### View-surface tests

- `Animation` factory defaults
- `.animation(_:value:)` gating
- `.animation(nil, value:)` disabling
- `transition(_:)` attachment and metadata lowering

Suggested locations:

- `Tests/ViewTests/ViewResolutionTests.swift`
- new `Tests/ViewTests/AnimationSurfaceTests.swift`

### Renderer/runtime tests

- color interpolation
- opacity interpolation
- entering transition sampling
- disappearing overlay tracks after removal
- animation deadlines stop once tracks finish
- run loop renders deadline-driven frames without input

Suggested locations:

- `Tests/TerminalUITests/Phase0FoundationTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- new `Tests/TerminalUITests/AnimationRuntimeTests.swift`

### Regression cases worth pinning

- interrupted spring retargeting starts from the current displayed value
- explicit `.animation(nil, value:)` beats inherited animation
- transitions do not keep removed views interactive
- focus/selection routes reflect only the committed tree, not disappearing
  overlays
- damage tracking still converges to zero bytes after animation completes

## Documentation Updates Required When Implementation Starts

- `docs/PUBLIC_API_INVENTORY.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/STATUS.md`
- `docs/ARCHITECTURE.md`
- `docs/RUNTIME.md`
- `docs/README.md`

The repo’s public-surface policy means these doc updates should ship in the
same changes that introduce the public APIs.

## Risks And Mitigations

### Risk: Deadline frames cause too much work

Mitigation:

- empty-invalidation resolve reuse
- debug-insensitive transaction reuse
- animate only draw-level channels in the first implementation

### Risk: Removal transitions fight lifecycle semantics

Mitigation:

- render exiting nodes only as non-semantic overlays
- keep lifecycle, tasks, focus, and interaction bound to the committed tree

### Risk: Transition API shape outruns runtime reality

Mitigation:

- ship built-in `AnyTransition` first
- keep internal transition runtime phase-based
- add public custom `Transition` only after lowering is proven

### Risk: Terminal visuals make some SwiftUI transitions look bad

Mitigation:

- constrain v1 built-ins to opacity, offset, push, slide, and reveal
- explicitly defer scale, blur, and rotation-based transitions

### Risk: Scheduler wake behavior regresses input responsiveness

Mitigation:

- keep wake notifications package-only
- preserve existing pointer event batching and coalescing
- add targeted runtime tests for mixed input and animation traffic

## Recommendation Summary

The best path for this repo is:

1. keep SwiftUI’s transaction-based animation model
2. turn the existing color-animation proposal into a general presentation
   animation coordinator
3. fix empty-invalidation reuse and scheduler wake handling first
4. ship `Animation`, `withAnimation`, and `.animation(_:value:)`
5. ship built-in `AnyTransition` plus `transition(_:)`
6. add public custom `Transition` support only after the phase-based transition
   runtime is stable

That gives the framework a coherent first animation system now, while leaving a
clean path to `Binding.animation(_:)`, body-scoped animation, custom
transitions, `phaseAnimator`, and `keyframeAnimator` later.

## References

### SwiftUI docs

- [Animations](https://developer.apple.com/documentation/swiftui/animations)
- [withAnimation(_:_:)](https://developer.apple.com/documentation/swiftui/withanimation%28_%3A_%3A%29/)
- [Transaction](https://developer.apple.com/documentation/swiftui/transaction)
- [Transition](https://developer.apple.com/documentation/swiftui/transition)
- [View.transition(_:)](https://developer.apple.com/documentation/SwiftUI/View/transition%28_%3A%29-5h5h0)

### WWDC sessions

- [Explore SwiftUI animation (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10156/)
- [Wind your way through advanced animations in SwiftUI (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10157/)
- [Animate with springs (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10158/)
- [Enhance your UI animations and transitions (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10145/)
- [Create custom visual effects with SwiftUI (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10151/)

### Repo context

- [docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md)
- [docs/ARCHITECTURE.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/ARCHITECTURE.md)
- [docs/RUNTIME.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/RUNTIME.md)
- [Sources/TerminalUI/TerminalUI.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalUI.swift)
- [Sources/TerminalUI/RunLoop+Rendering.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/RunLoop+Rendering.swift)
- [Sources/Core/Graph/ViewGraph.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/Core/Graph/ViewGraph.swift)

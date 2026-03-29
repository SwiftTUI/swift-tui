# Color Animation Implementation Plan

**Date:** 2026-03-26
**Status:** Proposed
**Scope:** Border, background, and text color animation using `Animation`,
`withAnimation`, and `.animation(_:value:)`

## Goal

Add a first-class animation subset that feels SwiftUI-shaped, preserves the
existing retained rendering model, and is well matched to terminal rendering.

The initial supported visual channels are:

- text foreground color
- background fill color
- border stroke color

Optional stretch support inside the same machinery:

- text background color
- per-edge border background colors when they resolve to single colors

## Why This Slice

Color animation is the best first subset for this codebase because it stays in
the draw and presentation layers. It does not require sub-cell geometry,
animatable layout, or general vector interpolation.

That makes it a strong fit for the current architecture:

- geometry is cell-quantized, so spatial animation would snap aggressively
- draw commands already carry identity and styling
- terminal presentation already understands concrete colors
- the runtime already has deadline concepts in the scheduler, even though they
  are not fully wired into the wait loop yet

## Non-Goals

This plan does not attempt to support:

- full SwiftUI `Animatable` or `VectorArithmetic`
- `AnimatableModifier`
- springs, repeaters, or repeat-forever APIs
- value-less `.animation(_:)`
- public `Transaction`
- layout, size, position, scale, rotation, or matched-geometry animation
- gradient interpolation
- `TerminalChromeStyle` interpolation
- opacity animation as part of this slice

Unsupported style transitions should snap immediately to their target values.

## Product Surface

The public API should stay intentionally small.

### Public API

Add a new public `Animation` type and the two canonical entry points:

```swift
public struct Animation: Equatable, Sendable {
  public enum Curve: String, Equatable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
  }

  public var curve: Curve
  public var duration: Duration
  public var delay: Duration

  public init(
    curve: Curve = .easeInOut,
    duration: Duration = .milliseconds(200),
    delay: Duration = .zero
  )

  public static let `default`: Animation
  public static func linear(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeIn(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeOut(duration: Duration = .milliseconds(200)) -> Animation
  public static func easeInOut(duration: Duration = .milliseconds(200)) -> Animation
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
}
```

### Public Semantics

- `withAnimation(animation)` animates eligible color changes caused by state
  writes inside the closure.
- `withAnimation(nil)` disables animation for those writes.
- `.animation(animation, value:)` animates eligible color changes in the
  modified subtree when `value` changes.
- `.animation(nil, value:)` disables inherited animation in the modified
  subtree when `value` changes.
- Only border, background, and text color changes participate in v1.
- Unsupported style changes fall back to snapping.

## Core Design Decisions

### 1. Animate Resolved Colors, Not `ShapeStyle`

The implementation should animate concrete resolved colors after draw
extraction, not authored `ShapeStyle` values.

Reasons:

- `AnyShapeStyle` includes semantic roles, gradients, and terminal chrome.
- interpolation is only well defined for single resolved colors in v1
- draw extraction is where the pipeline still has both identity and visual
  structure
- rasterization has already lost node identity, which makes subtree-scoped
  animation hard to reason about

Implication:

- styles that resolve to a single color are animatable
- styles that do not resolve to a single color snap

### 2. Keep Animation Intent in Transactions, But Keep Time Out of Transactions

Animation intent should flow through `TransactionSnapshot`, but per-frame time
or progress should not.

Reasons:

- subtree-scoped animation APIs need transaction-like inheritance and override
  semantics
- frame progress changes every tick and would destroy resolve reuse if it lived
  in `TransactionSnapshot`

Implication:

- `TransactionSnapshot` carries only animation intent
- active animation state and frame sampling live in a renderer-owned
  coordinator

### 3. Preserve Module Boundaries

`TransactionSnapshot` lives in `Core`, while the SwiftUI-shaped authoring API
belongs in `View`.

That means the implementation should separate:

- a public authored `Animation` type in `View`
- a package-only resolved animation descriptor in `Core`

Recommended shape:

```swift
package enum AnimationCurveDescriptor: UInt8, Equatable, Sendable {
  case linear
  case easeIn
  case easeOut
  case easeInOut
}

package struct AnimationDescriptor: Equatable, Sendable {
  package var curve: AnimationCurveDescriptor
  package var duration: Duration
  package var delay: Duration
}

package enum AnimationRequest: Equatable, Sendable {
  case inherit
  case disabled
  case animate(AnimationDescriptor)
}
```

`View.Animation` converts to `Core.AnimationDescriptor` through package-only
bridging, which keeps target layering intact.

### 4. Draw-Level Subtree Animation Requires Transaction Data To Reach Draw Nodes

`ResolvedNode` already stores `transactionSnapshot`, but `PlacedNode` and
`DrawNode` do not.

For subtree-scoped `.animation(_:value:)` and `.animation(nil, value:)` to work
at the draw stage, transaction information must survive to the draw tree.

Recommended change:

- add `transactionSnapshot` to `PlacedNode`
- add `transactionSnapshot` to `DrawNode`
- thread the value through layout placement and draw extraction unchanged

### 5. Deadline Frames Must Reuse Resolve Work

Today, deadline-only frames would be too expensive because retained resolve
reuse currently requires `invalidatedIdentities` to be non-empty. Animation
frames frequently have no invalidated identities.

Recommended fix:

- make resolve reuse treat an empty invalidation set as "nothing is invalidated"
- compare transactions for reuse using a dedicated equivalence that ignores
  debug-only fields

That work is required for animation, but it is also a general runtime
correctness improvement for deadline and externally scheduled frames.

### 6. The Scheduler Must Wake The Run Loop For Non-Input Work

The current run loop only wakes on input and signal streams. Animation,
external invalidation, lifecycle-driven invalidation, and deadlines need a
general scheduler-to-run-loop wake path.

Recommended direction:

- add a package-only wake stream or continuation-backed notifier to
  `FrameScheduler`
- merge scheduler wakes into the event pump
- render pending frames after any scheduler wake, even when there are no input
  events to drain

This solves both animation deadlines and existing background invalidation gaps.

## Supported Style Resolution Rules

The v1 coordinator should animate only when both the old and new endpoints
resolve to a single color without spatial sampling.

Animate:

- `.color(...)`
- semantic roles that resolve to a single color through the active theme or
  environment

Snap:

- `.linearGradient(...)`
- `.terminalChrome(...)`
- transitions where the command type, geometry, bounds, or stroke shape changed
  too much to pair safely

## Internal Runtime Model

### Animation Context At Mutation Time

`withAnimation` needs mutation-time plumbing so state changes can attach a root
animation request to the next invalidation.

Recommended internal helper in `Core`:

```swift
package enum AnimationContextStorage {
  @TaskLocal static var currentRequest: AnimationRequest = .inherit
}

package func withCurrentAnimationRequest<Result>(
  _ request: AnimationRequest,
  _ body: () throws -> Result
) rethrows -> Result

package func currentAnimationRequest() -> AnimationRequest
```

`View.withAnimation` becomes a thin wrapper over this task-local.

### Animation-Aware Invalidation

Do not widen the public `Invalidating` protocol unless necessary.

Instead, add a package-only refinement:

```swift
package protocol AnimationAwareInvalidating: Invalidating {
  func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest
  )
}
```

`FrameScheduler` adopts this package protocol. `StateContainer` and
`DynamicStateStore` attempt the animation-aware path first, then fall back to
plain invalidation when unavailable.

This keeps the authored API small and avoids turning animation internals into a
public runtime contract.

### Animation State At Resolve Time

`.animation(_:value:)` is resolve-time plumbing, not mutation-time plumbing.

Recommended behavior:

1. Store the last observed `value` for the modifier in dynamic state.
2. Compare the stored value to the current value during resolve.
3. If the value changed, override the child transaction animation request for
   that subtree.
4. Persist the new value without triggering another invalidation.

This requires a non-invalidating internal write path in `DynamicStateStore` for
modifier bookkeeping.

### Active Animation State At Draw Time

The renderer owns a stateful color animation coordinator.

Recommended internal types:

```swift
package enum ColorAnimationChannel: String, Sendable {
  case textForeground
  case textBackground
  case fillBackground
  case strokeForeground
  case strokeBackgroundTop
  case strokeBackgroundRight
  case strokeBackgroundBottom
  case strokeBackgroundLeft
}

package struct ColorAnimationKey: Hashable, Sendable {
  package var identity: Identity
  package var commandPath: [Int]
  package var channel: ColorAnimationChannel
}

package struct ActiveColorAnimation: Equatable, Sendable {
  package var key: ColorAnimationKey
  package var from: Color
  package var to: Color
  package var animation: AnimationDescriptor
  package var start: MonotonicInstant
  package var end: MonotonicInstant
}
```

Notes:

- use `commandPath` rather than a flat ordinal so nested group and clip command
  structures can be paired conservatively
- only create an animation when the previous and current endpoints have the same
  structural identity
- if an animation is interrupted, start the next animation from the currently
  displayed interpolated color, not the original source color

## Rendering Strategy

The animation coordinator should sit between draw extraction and rasterization.

Recommended per-frame flow:

1. Renderer resolves and lays out normally.
2. Draw extractor produces a `DrawNode` tree that now includes
   `transactionSnapshot`.
3. Coordinator walks the current draw tree and extracts animatable color
   endpoints.
4. Coordinator compares endpoints to the currently displayed values.
5. For eligible changes in animated transactions, coordinator creates or retargets
   `ActiveColorAnimation` entries.
6. Coordinator returns a draw tree with concrete interpolated colors substituted
   into the relevant commands.
7. Rasterizer rasterizes the adjusted draw tree.
8. Coordinator returns the next wake deadline if any animations remain active.
9. After presentation, the runtime requests that deadline from the scheduler.

## Frame Cadence

Use a fixed animation cadence in v1 rather than trying to approximate display
refresh.

Recommended default:

- 30 FPS target cadence
- `frameInterval = .milliseconds(33)`

Reasons:

- terminal UIs do not benefit much from 60 FPS color interpolation
- fewer frames reduce terminal writes and improve the odds of preserving the
  project's zero-byte idle goals outside active animation windows
- a fixed cadence is easy to reason about in tests

The next deadline should be:

- `min(animationEnd, now + frameInterval)` for each active animation
- the earliest of those deadlines across all active animations

## Implementation Phases

## Phase 0: Foundational Types And Reuse Semantics

### Objectives

- define package-only animation descriptors and requests
- make deadline-only frames compatible with resolve reuse
- ensure transaction debug info no longer defeats reuse

### Changes

1. Add package-only animation types in `Core`.
2. Extend `TransactionSnapshot` with package-only animation intent.
3. Add a dedicated reuse-equivalence helper for `TransactionSnapshot` that
   ignores debug-only fields.
4. Remove the retained-resolve requirement that invalidation sets be non-empty.

### Files

- `Sources/Core/EnvironmentAndNodeTypes.swift`
- `Sources/View/Environment.swift`
- optionally new `Sources/Core/AnimationTypes.swift`

### Acceptance Criteria

- deadline frames with no invalidated identities can reuse resolved subtrees
- transaction debug signatures do not break reuse
- no public API exposed yet

## Phase 1: Mutation-Time Animation Plumbing

### Objectives

- let `withAnimation` attach animation intent to invalidations
- keep public runtime protocols stable where possible

### Changes

1. Add Core task-local animation request helpers.
2. Add package-only `AnimationAwareInvalidating`.
3. Update `FrameScheduler` to store a pending coalesced animation request for
   the next frame.
4. Update `ScheduledFrame` to carry the coalesced animation request.
5. Update `StateContainer` to propagate the current animation request when
   invalidating.
6. Update `DynamicStateStore` to do the same for `@State` writes.
7. Update `RunLoop.resolveContext(for:)` so the scheduled frame's animation
   request becomes the root transaction animation request for that frame.

### Coalescing Rule

For v1, use a simple and explicit coalescing rule:

- latest explicit request wins
- `.disabled` is explicit
- `.inherit` never overrides an explicit pending request

This is easy to implement and predictable enough for the initial subset.

### Files

- `Sources/Core/Scheduler.swift`
- `Sources/Core/StateContainer.swift`
- `Sources/View/State.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/Core/CommitAndFrameTypes.swift` if `ScheduledFrame` stays there in the
  future, otherwise `Sources/Core/Scheduler.swift`

### Acceptance Criteria

- state writes inside `withAnimation` reach the next frame as animation intent
- state writes inside `withAnimation(nil)` explicitly disable animation
- plain mutations still behave exactly as before

## Phase 2: Public View API And Resolve-Time Modifiers

### Objectives

- expose the authored API
- implement subtree-scoped `.animation(_:value:)`

### Changes

1. Add public `Animation` and `withAnimation` in `View`.
2. Add `View.animation(_:value:)`.
3. Add package-only transaction transformation helpers on `ResolveContext`.
4. Add a dedicated animation modifier view in `ViewModifiers`.
5. Add a non-invalidating dynamic-state write path so the modifier can store its
   last observed `value`.

### Suggested Modifier Shape

```swift
package struct ValueAnimationModifier<Content: View, Value: Equatable>: View, ResolvableView {
  package var content: Content
  package var animationRequest: AnimationRequest
  package var value: Value
  package var sourceLocation: String
}
```

During resolve, the modifier:

- reads the previous `value`
- determines whether the subtree should animate or disable animation
- resolves the child with an overridden transaction when appropriate
- stores the current `value` without invalidating

### Files

- new `Sources/View/Animation.swift`
- `Sources/View/Environment.swift`
- `Sources/View/ViewModifiers.swift`
- `Sources/View/State.swift`

### Acceptance Criteria

- `.animation(_:value:)` only fires when `value` changes
- `.animation(nil, value:)` disables inherited animation for that subtree
- no value-less `.animation(_:)` surface is added

## Phase 3: Scheduler Wake Integration

### Objectives

- wake the run loop for deadlines and background invalidations
- keep input and signal handling intact

### Changes

1. Add a scheduler wake stream or notifier to `FrameScheduler`.
2. Merge that stream into `RunLoop.EventPump`.
3. Update the run loop to render pending frames even when a wake arrives with no
   runtime events to drain.
4. Preserve mouse coalescing behavior for input batches.

### Important Behavioral Fix

This phase should fix more than animation:

- lifecycle or task-driven invalidations should wake the run loop
- external scheduler wakes should no longer depend on input or signals
- deadline frames should render without synthetic input

### Files

- `Sources/Core/Scheduler.swift`
- `Sources/TerminalUI/RunLoop.swift`
- `Sources/TerminalUI/RunLoop+EventPump.swift`

### Acceptance Criteria

- a scheduled deadline triggers rendering without input
- a background invalidation triggers rendering without input
- existing input and signal behavior remains unchanged

## Phase 4: Draw-Level Color Animation Coordinator

### Objectives

- animate eligible color endpoints at the draw layer
- leave layout and semantics untouched

### Changes

1. Thread `transactionSnapshot` through `PlacedNode` and `DrawNode`.
2. Add a new package-only `ColorAnimationCoordinator` in `TerminalUI`.
3. Have `DefaultRenderer` consult the coordinator between draw extraction and
   rasterization.
4. Extract animatable color endpoints from text, fill, and stroke commands.
5. Resolve animatable endpoints to concrete single colors.
6. Start, retarget, sample, and retire active animations.
7. Sample using the existing `FrameContext.timestamp` rather than introducing a
   second clock source.
8. Return the earliest next animation deadline to the runtime.
9. After presentation, have the runtime request that deadline from the
   scheduler.

### Pairing Rules

Conservatively pair old and new endpoints only when all of the following are
true:

- same `DrawNode.identity`
- same `commandPath`
- same command kind
- same relevant geometry and bounds
- same channel

If pairing fails, snap.

### Sampling Rules

- use the frame timestamp as the source of truth
- apply delay before interpolation begins
- clamp progress to `[0, 1]`
- use existing `mix(_:_:amount:)` for color interpolation

### Files

- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/LayoutEngine.swift` or the placement helpers that construct
  `PlacedNode`
- `Sources/Core/DrawExtractor.swift`
- new `Sources/TerminalUI/ColorAnimationCoordinator.swift`
- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`

### Acceptance Criteria

- text foreground color animates
- background fill color animates
- border stroke color animates
- unsupported styles snap immediately
- interrupted animations retarget smoothly from the current displayed color

## Phase 5: Testing, Diagnostics, And Docs

### Objectives

- lock the behavior down with deterministic tests
- satisfy repo policy hooks for new public surface

### Tests

1. Core scheduler tests:
   - coalesced animation request storage
   - deadline wake stream behavior
   - latest-explicit-request-wins semantics
2. Resolve/runtime tests:
   - deadline-only frames reuse resolve work
   - debug signature changes do not defeat reuse
3. Public API surface tests:
   - `Animation` factory defaults
   - `withAnimation(nil)` disables animation
   - `.animation(_:value:)` only triggers on value change
4. Renderer tests:
   - text foreground color interpolation
   - background fill interpolation
   - border stroke interpolation
   - unsupported gradients and terminal chrome snapping
   - subtree `.animation(nil, value:)` overriding inherited animation
5. Interactive runtime tests:
   - render progresses over scheduler deadlines with no input
   - animation stops scheduling frames after completion

### Suggested Test Locations

- `Tests/TerminalUITests/Phase0FoundationTests.swift`
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- optionally a dedicated `Tests/TerminalUITests/AnimationTests.swift`

### Docs And Policy Updates

Implementation of the public API will likely need the companion docs updates
required by the repo's public-surface guardrails:

- `docs/PUBLIC_API_INVENTORY.md`
- `docs/SOURCE_LAYOUT.md` if new source files are introduced as canonical seams

## File-Level Change List

Expected primary implementation touch points:

- new `Sources/View/Animation.swift`
- `Sources/View/Environment.swift`
- `Sources/View/ViewModifiers.swift`
- `Sources/View/State.swift`
- `Sources/Core/EnvironmentAndNodeTypes.swift`
- `Sources/Core/Scheduler.swift`
- `Sources/Core/StateContainer.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/LayoutEngine.swift` or extracted placement helpers
- `Sources/Core/DrawExtractor.swift`
- new `Sources/TerminalUI/ColorAnimationCoordinator.swift`
- `Sources/TerminalUI/RunLoop.swift`
- `Sources/TerminalUI/RunLoop+EventPump.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/TerminalUI/TerminalUI.swift`
- `Tests/TerminalUITests/...`
- `docs/PUBLIC_API_INVENTORY.md`
- `docs/SOURCE_LAYOUT.md` if needed

## Risks And Mitigations

### Risk: Deadline frames trigger too much work

Mitigation:

- fix resolve reuse for empty invalidation sets
- ignore debug-only transaction fields for reuse
- animate only draw-level color channels

### Risk: Scheduler wake integration changes runtime behavior broadly

Mitigation:

- add targeted tests for background invalidation and input handling
- keep event coalescing behavior for pointer streams
- keep scheduler wake notifications package-only

### Risk: Command pairing is brittle

Mitigation:

- use conservative pairing rules
- snap whenever structure changes
- start with a small set of supported channels

### Risk: `.animation(_:value:)` needs stored previous values during resolve

Mitigation:

- add an explicit non-invalidating state-store path for modifier bookkeeping
- keep the behavior local to the modifier rather than making transactions stateful

### Risk: Public API expansion triggers policy hooks

Mitigation:

- ship docs updates in the same change as the public API
- classify the new animation surface explicitly in the public API inventory

## Rollout Recommendation

Implement this plan as two reviewable PRs instead of one large drop.

### PR 1

- foundational types
- mutation plumbing
- scheduler wakes
- resolve reuse fix for deadline frames
- tests for scheduling and reuse

### PR 2

- public `Animation` API
- `.animation(_:value:)`
- draw-level coordinator
- renderer integration
- interpolation and runtime tests
- public API docs updates

This sequencing reduces integration risk because the runtime can first prove
that deadline wakes and background invalidation work correctly before any
authored animation API depends on them.

## Recommendation Summary

The most important implementation choices are:

1. represent animation intent in transactions, but keep time and progress out of
   transactions
2. resolve authored animation requests into package-only Core descriptors
3. animate concrete colors between draw extraction and rasterization
4. add a real scheduler wake path to the run loop
5. make deadline-only frames compatible with retained resolve reuse

If those five choices hold, this feature can land as a small and coherent
animation subset instead of becoming the start of a full SwiftUI animation
reimplementation.

# Animation Implementation Plan

**Date:** 2026-04-08
**Status:** Approved
**Branch:** `animation`
**Supersedes:** `docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md`

## Goal

Add a faithful SwiftUI-shaped animation system to the terminal UI framework.
"Faithful" means matching SwiftUI's internal architecture — Transaction
propagation, Animatable/VectorArithmetic protocols, spring physics solver,
CustomAnimation protocol — for the subset of properties that can be meaningfully
represented in a terminal.

This is **not** API-surface mimicry. The internal model (resolve-once,
animate-through-pipeline, identity-keyed animation state) matches SwiftUI's
approach, scoped to terminal-representable properties.

## Design Decisions

These were settled during the brainstorming conversation:

1. **Approach A — Faithful implementation for the chosen subset.** Match SwiftUI
   internals, not just naming. Overdoing internal fidelity where it matters;
   excluding properties that can never be properly represented in a terminal.

2. **Resolve-Once, Animate-Through-Pipeline.** Resolve runs once with the new
   "to" values. The animation controller captures (from, to, animation, start)
   per changed property. On tick frames, interpolated values are injected before
   Measure. Resolve is NOT re-run on tick frames.

3. **Full spring physics.** Real damped harmonic oscillator solver, not preset
   bezier approximations. Plus cubic bezier timing curves and the
   CustomAnimation protocol.

4. **Modern Transition protocol only.** iOS 17+ `Transition` protocol with
   `TransitionPhase`, not the legacy `AnyTransition.modifier(active:identity:)`.

## Animatable Properties

### Strong candidates (look good in terminal)

| Property | Notes |
|----------|-------|
| Foreground color | Oklab interpolation pipeline already exists |
| Background color | Same |
| Border color | Same |
| Opacity | Via color pre-blending against background |

### Viable but coarser

| Property | Notes |
|----------|-------|
| Position / offset | Integer-stepped, decent at 30fps for small moves |
| Size (width/height) | Triggers relayout, works |
| Padding | Same mechanism as size |

### Not representable (excluded)

Rotation, scale, blur, 3D transforms — no terminal equivalent.

## Built-in Transitions

| Transition | Viability |
|------------|-----------|
| `.opacity` | Fade in/out via color blending |
| `.move(edge:)` | Slide from an edge |
| `.slide` | Leading in, trailing out |
| `.offset(x:y:)` | Shift by fixed amount |
| `.push(from:)` | Push old view out, new in |
| `.identity` | Instant, no visual change |

Plus combinators: `.combined(with:)` and `.asymmetric(insertion:removal:)`.

Excluded: `.scale` (no sub-cell scaling), `.blurReplace` (not possible).

---

## Layer 1: Foundation Protocols

Lives in `Core` (protocols) with conformances in both `Core` and `View`.

### VectorArithmetic

```swift
// Core module
public protocol VectorArithmetic: AdditiveArithmetic, Sendable {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}
```

Conformances: `Double`, `Int` (terminal coordinates are integers — interpolation
truncates: `from + Int(Double(to - from) * progress)`), `AnimatablePair<First,
Second>`, `EmptyAnimatableData`.

### Animatable

```swift
// Core module
public protocol Animatable: Sendable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: AnimatableData { get set }
}
```

Key conformances:

- **DrawMetadata** — exposes `opacity` as animatable data
- **EdgeInsets** — via `AnimatablePair<AnimatablePair<Int,Int>,
  AnimatablePair<Int,Int>>`
- **Color** — wraps `Color.interpolated(to:progress:method:)` via a
  `ColorAnimatableData` adapter rather than raw VectorArithmetic

### Animation

```swift
// View module (public)
public struct Animation: Equatable, Hashable, Sendable {
    // Timing curves
    public static let `default`: Animation  // = .easeInOut
    public static func linear(duration: Duration = .milliseconds(200)) -> Animation
    public static func easeIn(duration: Duration = .milliseconds(200)) -> Animation
    public static func easeOut(duration: Duration = .milliseconds(200)) -> Animation
    public static func easeInOut(duration: Duration = .milliseconds(200)) -> Animation
    public static func timingCurve(_ c0x: Double, _ c0y: Double,
                                    _ c1x: Double, _ c1y: Double,
                                    duration: Duration = .milliseconds(200)) -> Animation

    // Spring physics
    public static func spring(duration: Duration = .milliseconds(500),
                               bounce: Double = 0.0) -> Animation
    public static var smooth: Animation      // spring(bounce: 0.0)
    public static var snappy: Animation      // spring(bounce: 0.15)
    public static var bouncy: Animation      // spring(bounce: 0.3)
    public static func smooth(duration: Duration, extraBounce: Double = 0.0) -> Animation
    public static func snappy(duration: Duration, extraBounce: Double = 0.0) -> Animation
    public static func bouncy(duration: Duration, extraBounce: Double = 0.0) -> Animation
    public static func interpolatingSpring(mass: Double, stiffness: Double,
                                            damping: Double,
                                            initialVelocity: Double = 0.0) -> Animation

    // Modifiers
    public func delay(_ delay: Duration) -> Animation
    public func speed(_ speed: Double) -> Animation
    public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation
    public func repeatForever(autoreverses: Bool = true) -> Animation

    // Custom animation
    public init<A: CustomAnimation>(_ base: A)
}
```

### CustomAnimation

```swift
// View module (public)
public protocol CustomAnimation: Hashable, Sendable {
    func animate<V: VectorArithmetic>(
        value: V, time: Duration, context: inout AnimationContext<V>
    ) -> V?  // nil = animation complete

    func shouldMerge<V: VectorArithmetic>(
        previous: Animation, value: V, time: Duration,
        context: inout AnimationContext<V>
    ) -> Bool  // default: false

    func velocity<V: VectorArithmetic>(
        value: V, time: Duration, context: AnimationContext<V>
    ) -> V?  // for interrupted animation handoff
}

public struct AnimationContext<Value: VectorArithmetic>: Sendable {
    public var state: AnimationState  // keyed storage for custom state
    public var environment: EnvironmentSnapshot
}
```

### Spring Solver

~50 lines of math. Solves the damped harmonic oscillator equation:

```
x(t) = e^(-ζωt) * (A·cos(ωd·t) + B·sin(ωd·t))
```

Where `ζ` = damping ratio (derived from `bounce`), `ω` = natural frequency
(derived from `duration`), `ωd` = damped frequency.

The `bounce` parameter maps to damping:
- `0` = critically damped
- `> 0` = underdamped (bouncy)
- `< 0` = overdamped

The cubic bezier solver uses De Casteljau's algorithm to find `t` for a given
`x`, then evaluates `y(t)`.

---

## Layer 2: Transaction + Mutation/Resolve Plumbing

### TransactionSnapshot Enhancement

The current stub (`Sources/Core/EnvironmentAndNodeTypes.swift:80`) gets real
animation data:

```swift
// Core module
public struct TransactionSnapshot: Equatable, Sendable {
    public var debugSignature: String
    package var animationRequest: AnimationRequest = .inherit

    package func isReuseEquivalent(to other: Self) -> Bool {
        animationRequest == other.animationRequest
    }
}

package enum AnimationRequest: Equatable, Sendable {
    case inherit          // use whatever the parent transaction says
    case disabled         // explicitly suppress animation in this subtree
    case animate(Animation)  // animate with this curve
}
```

### withAnimation — Mutation-Time Plumbing

```swift
// View module (public)
@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result

// With completion (matches SwiftUI iOS 17+)
@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping @Sendable () -> Void
) rethrows -> Result
```

Internal mechanism — three pieces:

**1. Task-local animation context** (Core, package-only):

```swift
package enum AnimationContextStorage {
    @TaskLocal static var currentRequest: AnimationRequest = .inherit
}
```

**2. Animation-aware invalidation** (Core, package-only):

```swift
package protocol AnimationAwareInvalidating: Invalidating {
    func requestInvalidation(
        of identities: Set<Identity>,
        animation: AnimationRequest
    )
}
```

`FrameScheduler` conforms. Stores a pending coalesced animation request on
`ScheduledFrame`. Coalescing rule: latest explicit request wins; `.inherit`
never overrides an explicit pending request.

**3. State write propagation:** `StateContainer` and `DynamicStateStore` read
the task-local, attempt the animation-aware invalidation path.
`withAnimation` sets the task-local, executes the body, state writes carry the
animation request through to the scheduler, and the next `ScheduledFrame`
carries it into `FrameContext.transaction.animationRequest`.

### .animation(\_:value:) — Resolve-Time Plumbing

```swift
// View module (public)
extension View {
    public func animation<V: Equatable>(
        _ animation: Animation?, value: V
    ) -> some View
}
```

Internal modifier (View module, package-only):

```swift
package struct ValueAnimationModifier<Content: View, Value: Equatable & Sendable>:
    View, ResolvableView
{
    var content: Content
    var animation: Animation?
    var value: Value
}
```

During resolve:

1. Reads previous value from a non-invalidating state slot
2. Compares previous vs current
3. If changed and `animation != nil`: overrides child transaction to
   `.animate(animation)`
4. If changed and `animation == nil`: overrides child transaction to `.disabled`
5. If unchanged: passes through parent transaction (`.inherit`)
6. Stores current value without invalidating

**Non-invalidating state slot** — the modifier must remember the previous value
but writing it must not cause re-resolve. New capability on `ViewNode`:
`setStateSlotSilently(ordinal:value:)` that skips the invalidation path.

### .transaction() Modifier

```swift
// View module (public)
extension View {
    public func transaction(
        _ transform: @escaping @Sendable (inout TransactionSnapshot) -> Void
    ) -> some View
}
```

Allows stripping animation from a subtree:
`.transaction { $0.animationRequest = .disabled }`.

---

## Layer 3: Animation Controller + Pipeline Integration

### AnimationController

Renderer-owned, stateful. Lives in `TerminalUI` module (package-only).

```swift
@MainActor
package final class AnimationController {
    // Active animations keyed by (identity, property path)
    private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]

    // Previous frame's resolved property snapshots for diffing
    private var previousSnapshots: [Identity: AnimatableSnapshot] = [:]

    // Completion callbacks
    private var pendingCompletions: [AnimationKey: () -> Void] = [:]
}

package struct AnimationKey: Hashable, Sendable {
    var identity: Identity
    var property: AnimatableProperty
}

package enum AnimatableProperty: Hashable, Sendable {
    case opacity
    case foregroundColor
    case backgroundColor
    case borderColor
    case paddingTop, paddingLeading, paddingBottom, paddingTrailing
    case offsetX, offsetY
    case frameWidth, frameHeight
}

package struct ActiveAnimation: Sendable {
    var from: AnimatableValue
    var to: AnimatableValue
    var animation: Animation
    var startTime: MonotonicInstant
    var retargetedFrom: AnimatableValue?  // for interrupted animation handoff
}

package enum AnimatableValue: Sendable {
    case double(Double)         // opacity
    case integer(Int)           // padding, offset, size
    case color(Color)           // fg/bg/border colors
}
```

### AnimatableSnapshot

Captured per-identity after resolve, before diffing:

```swift
package struct AnimatableSnapshot: Equatable, Sendable {
    var opacity: Double?
    var foregroundColor: Color?
    var backgroundColor: Color?
    var borderColor: Color?
    var padding: EdgeInsets?
    var offset: (x: Int, y: Int)?
    var frameSize: (width: Int?, height: Int?)?
}
```

Extracted from `ResolvedNode.drawMetadata` + `ResolvedNode.layoutBehavior` for
each identity.

### Per-Frame Flow

The animation controller has two entry points per frame:

**1. `processResolvedTree(_:transaction:timestamp:)`** — called after Resolve,
before Measure.

For each identity in the new resolved tree:

1. Extract `AnimatableSnapshot` from resolved node
2. Compare with `previousSnapshots[identity]`
3. For each property that changed:
   - If transaction is `.animate(anim)`: create
     `ActiveAnimation(from: previous, to: new, animation: anim, startTime: now)`.
     If an animation for this key already exists, **retarget**: sample current
     interpolated value as new `from`.
   - If `.disabled` or `.inherit` with no parent animation: snap immediately
4. Store new snapshot in `previousSnapshots`

**2. `applyInterpolations(to:at:)`** — mutates the resolved tree with
interpolated values.

For each active animation:

1. Compute `elapsed = timestamp - startTime`
2. Apply delay (skip if `elapsed < delay`)
3. Evaluate animation curve → progress (may overshoot for springs)
4. Interpolate: `current = from + (to - from) * progress`
   - For colors: use `Color.interpolated(to:progress:method: .perceptual)`
   - For integers: truncate interpolated Double to Int
   - For doubles: direct interpolation
5. Override the resolved node's property with interpolated value
6. If animation curve returns nil (complete): remove from `activeAnimations`,
   fire completion callback

Returns:

```swift
package struct AnimationTickResult: Sendable {
    var hasActiveAnimations: Bool
    var nextDeadline: MonotonicInstant?
    var affectedIdentities: Set<Identity>  // for damage tracking
}
```

### Pipeline Integration Point

In `RunLoop+Rendering.swift`, the frame rendering flow becomes:

```
 1. Resolve (unchanged)
 2. → animationController.processResolvedTree(resolved, transaction, timestamp)
 3. → animationController.applyInterpolations(to: &resolved, at: timestamp)
 4. Measure (uses interpolated values — layout sees intermediate padding/size)
 5. Place (uses interpolated values — positions reflect intermediate state)
 6. Semantics (unchanged)
 7. Draw (uses interpolated values — colors/opacity are intermediate)
 8. Raster (unchanged)
 9. Commit (unchanged)
10. → if tickResult.hasActiveAnimations:
       scheduler.requestDeadline(tickResult.nextDeadline)
```

Steps 2–3 are the only new insertions. The rest of the pipeline is untouched.

### Frame Cadence

- **30 FPS** target during active animation (`frameInterval = .milliseconds(33)`)
- Next deadline: `min(earliestAnimationEnd, now + frameInterval)` across all
  active animations
- When all animations complete, no more deadlines are requested → runtime
  returns to idle event-driven mode (zero-cost when not animating)

### Interrupted Animation Retargeting

When a new animation starts for a key that already has an active animation:

1. Sample the currently displayed interpolated value
2. Start the new animation from that value (not from the original `from`)
3. This produces smooth retargeting — no visual discontinuity

### View Insertion/Removal Tracking

The controller tracks which identities are new (inserted) vs removed by
comparing the identity set between frames. This feeds into the transition
system (Layer 4). Removed identities keep their animations alive until
transitions complete.

---

## Layer 4: Transition System

### Transition Protocol

Modern API only, matching SwiftUI iOS 17+:

```swift
// View module (public)
public protocol Transition: Sendable {
    associatedtype Body: View

    @ViewBuilder
    func body(content: TransitionContent<Self>, phase: TransitionPhase) -> Body

    static var properties: TransitionProperties { get }
}

public enum TransitionPhase: Hashable, Sendable {
    case willAppear     // view is being inserted
    case identity       // view is fully present (normal state)
    case didDisappear   // view is being removed

    public var isIdentity: Bool { self == .identity }
}

public struct TransitionProperties: Sendable {
    public var hasMotion: Bool = true
}
```

`TransitionContent<T>` is a placeholder view that represents the content being
transitioned — the transition's `body` wraps it with modifiers that vary by
phase.

### AnyTransition — Type-Erased Wrapper

```swift
// View module (public)
public struct AnyTransition: Sendable {
    private var _apply: @Sendable (TransitionPhase) -> TransitionModifiers
}

// Package-only property effects for a phase
package struct TransitionModifiers: Sendable {
    var opacity: Double?
    var offsetX: Int?
    var offsetY: Int?
}
```

The type erasure resolves transitions down to their concrete property effects.
The `Transition` protocol's `body` method is the authoring surface;
`AnyTransition` flattens it into property deltas.

### Built-in Transitions

```swift
extension AnyTransition {
    /// Fades in/out
    public static var opacity: AnyTransition
    // willAppear: opacity = 0 → 1
    // didDisappear: opacity = 1 → 0

    /// Slides from a specific edge
    public static func move(edge: Edge) -> AnyTransition
    // willAppear: offset from edge → origin
    // didDisappear: origin → offset to edge

    /// Leading in, trailing out
    public static var slide: AnyTransition
    // asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))

    /// Fixed offset shift
    public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition
    // willAppear: offset(x,y) → (0,0)
    // didDisappear: (0,0) → offset(x,y)

    /// Push: old exits one way, new enters from same direction
    public static func push(from edge: Edge) -> AnyTransition
    // Asymmetric: insertion moves from edge, removal moves to opposite edge

    /// No visual change — instant
    public static var identity: AnyTransition

    // Combinators
    public func combined(with other: AnyTransition) -> AnyTransition
    public static func asymmetric(
        insertion: AnyTransition,
        removal: AnyTransition
    ) -> AnyTransition
}
```

### .transition() View Modifier

```swift
extension View {
    public func transition(_ t: AnyTransition) -> some View
}
```

Stores the transition in draw metadata so the animation controller can read it
during insertion/removal processing.

### Custom Transition Authoring

```swift
// Example: a custom "wipe" transition
struct WipeTransition: Transition {
    var edge: Edge

    func body(content: TransitionContent<Self>, phase: TransitionPhase) -> some View {
        content
            .offset(
                x: phase == .willAppear ? (edge == .leading ? -20 : 20) :
                   phase == .didDisappear ? (edge == .leading ? -20 : 20) : 0,
                y: 0
            )
            .opacity(phase.isIdentity ? 1.0 : 0.3)
    }
}

// Usage:
.transition(AnyTransition(WipeTransition(edge: .leading)))
```

### Lifecycle Integration with AnimationController

**Insertion:**

1. A new identity appears in the resolved tree that wasn't in the previous frame
2. Controller checks if the node has a `.transition()` modifier
3. If yes: starts animation from `willAppear` phase modifiers → `identity`
   phase modifiers
4. The transition's property deltas (opacity, offset) become the `from` values;
   identity values are the `to` values
5. Normal animation curve applies (from the active transaction)

**Removal:**

1. An identity from the previous frame is absent in the new resolved tree
2. Controller checks if the node had a `.transition()` modifier
3. If yes: the node is **kept alive** in the resolved tree during the animation
4. Starts animation from `identity` phase modifiers → `didDisappear` phase
   modifiers
5. When animation completes, the node is truly removed from the tree
6. During the animation, the node continues to participate in draw + raster
   but **not** in layout (it occupies no space — same as SwiftUI)

**Kept-alive nodes** — the key complexity:

```swift
package struct RemovalEntry: Sendable {
    var snapshot: ResolvedNode      // frozen at removal time
    var placedBounds: Rect          // last known position
    var transition: AnyTransition
    var animation: Animation
    var startTime: MonotonicInstant
}
```

- `removingNodes: [Identity: RemovalEntry]` dictionary on the controller
- During measure/place, removing nodes are excluded
- During draw, removing nodes are included at their last placed position with
  interpolated transition properties
- When the removal animation completes, the entry is purged

**Default transition:** When no `.transition()` modifier is present,
insertion/removal snaps immediately (equivalent to `.transition(.identity)`).
Matches SwiftUI behavior.

---

## Layer 5: Scheduler Wake Integration

### The Problem

The current run loop only wakes on two streams: input events and signals. The
event pump merges these into an `AsyncSequence`. When no input arrives and no
signal fires, the loop sleeps — even if `requestDeadline()` was called.
Animation frames need to render on a timer with no user interaction.

### Wake Stream on FrameScheduler

```swift
// Core module (Scheduler.swift)
package final class FrameScheduler: FrameScheduling, AnimationAwareInvalidating {
    // Existing fields...

    // NEW: continuation-backed wake notifier
    private var wakeContinuation: AsyncStream<Void>.Continuation?
    package var wakeStream: AsyncStream<Void>  // vended once to the run loop

    private func notifyWake() {
        wakeContinuation?.yield()
    }
}
```

`requestDeadline()` and `requestInvalidation()` both call `notifyWake()`. This
wakes the run loop even when there's no input.

### Event Pump Merge

In `RunLoop+EventPump.swift`, the event pump currently merges input + signals.
Add the scheduler wake as a third stream:

```swift
// TerminalUI module (RunLoop+EventPump.swift)
let merged = merge(
    inputEvents,        // keyboard, mouse
    signalEvents,       // SIGWINCH, etc.
    schedulerWakes      // deadline reached, background invalidation
)
```

### Run Loop Changes

In `RunLoop.swift`, the main loop body adds one check:

```swift
// After draining pending events:
if pendingEvents.isEmpty {
    // Woke from scheduler (deadline or background invalidation)
    if scheduler.hasPendingFrame(at: .now()) {
        try renderPendingFrames(renderedFrames: &renderedFrames)
    }
    continue
}
```

This is already partially there in the existing code — it checks
`hasPendingFrame` when events are empty. The missing piece is the wake stream
that causes the loop to actually wake up when a deadline arrives.

### Deadline-Only Frame Reuse

A tick frame typically has no invalidated identities — only active animations
need re-rendering. Two changes needed:

1. **Resolve reuse with empty invalidation set:** Currently the reuse check
   requires `invalidatedIdentities` to be non-empty. For animation frames,
   empty means "nothing re-resolved, just re-interpolate." Fix: treat empty
   invalidation set as "nothing is dirty" → full resolve reuse.

2. **Transaction reuse equivalence:** Use `isReuseEquivalent(to:)` instead of
   `==` for transaction comparison during resolve reuse. This ignores
   `debugSignature` changes that would otherwise defeat reuse.

Together, these mean animation tick frames are cheap: resolve is fully reused,
only the animation controller's interpolation + measure/place/draw/raster run.

### Animation Lifecycle

```
State change inside withAnimation
  → invalidation with animation request
  → scheduler.requestInvalidation() + notifyWake()
  → run loop wakes
  → frame renders (resolve runs, animation controller captures from/to)
  → animation controller returns nextDeadline
  → scheduler.requestDeadline(nextDeadline)
  → notifyWake() (for the NEXT tick)
  → run loop wakes at deadline
  → frame renders (resolve REUSED, interpolation runs, measure/place/draw/raster)
  → repeat until all animations complete
  → no more deadlines requested
  → run loop returns to idle (zero cost)
```

### Broader Fix

This wake integration also fixes existing gaps unrelated to animation:

- Lifecycle-driven invalidations (`onAppear` tasks that mutate state) now wake
  the loop
- External invalidation via `requestExternalWake()` now actually wakes
- Background `@Observable` changes propagate without waiting for input

---

## Implementation Phases

### Phase 0: Foundation Types + Reuse Semantics

**Objectives:** Define core protocols, make deadline frames work with resolve
reuse.

**Changes:**

1. Add `VectorArithmetic`, `Animatable`, `AnimatablePair`, `EmptyAnimatableData`
   protocols and types in `Core`
2. Add `Int` and `Double` conformances to `VectorArithmetic`
3. Extend `TransactionSnapshot` with `package var animationRequest:
   AnimationRequest`
4. Add `isReuseEquivalent(to:)` to `TransactionSnapshot`
5. Remove retained-resolve requirement that invalidation sets be non-empty
6. Add `AnimationRequest` enum in `Core`

**Files:**

- New `Sources/Core/AnimationProtocols.swift`
- `Sources/Core/EnvironmentAndNodeTypes.swift`
- `Sources/Core/CommitPlanner.swift` (reuse predicate)

**Acceptance criteria:**

- Deadline frames with no invalidated identities reuse resolved subtrees
- Transaction debug signatures do not break reuse
- No public animation API exposed yet

### Phase 1: Animation Type System

**Objectives:** Build the `Animation` type, spring solver, bezier solver,
`CustomAnimation` protocol.

**Changes:**

1. Add spring solver (damped harmonic oscillator)
2. Add cubic bezier solver (De Casteljau)
3. Add `Animation` struct with all factory methods and modifiers
4. Add `CustomAnimation` protocol and `AnimationContext`
5. Add `Animatable` conformances for `DrawMetadata`, `EdgeInsets`
6. Add `ColorAnimatableData` wrapper for color interpolation

**Files:**

- New `Sources/View/Animation/Animation.swift`
- New `Sources/View/Animation/CustomAnimation.swift`
- New `Sources/View/Animation/SpringSolver.swift`
- New `Sources/View/Animation/BezierSolver.swift`
- `Sources/Core/AnimationProtocols.swift` (Animatable conformances)

**Acceptance criteria:**

- Spring solver produces correct output for critically damped, underdamped, and
  overdamped configurations
- Bezier solver matches standard easeInOut/easeIn/easeOut curves
- `Animation.smooth`, `.snappy`, `.bouncy` produce distinct spring behaviors
- `CustomAnimation` protocol allows user-defined animation curves

### Phase 2: Mutation-Time Plumbing

**Objectives:** Let `withAnimation` attach animation intent to invalidations.

**Changes:**

1. Add Core task-local animation request helpers
2. Add `AnimationAwareInvalidating` protocol
3. Update `FrameScheduler` to store coalesced animation request
4. Update `ScheduledFrame` to carry animation request
5. Update `StateContainer` to propagate animation request when invalidating
6. Update `DynamicStateStore` to do the same for `@State` writes
7. Update `RunLoop.resolveContext(for:)` so scheduled frame's animation request
   becomes root transaction animation request

**Coalescing rule:** Latest explicit request wins. `.disabled` is explicit.
`.inherit` never overrides an explicit pending request.

**Files:**

- `Sources/Core/Scheduler.swift`
- `Sources/Core/StateContainer.swift`
- `Sources/View/State.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/Core/CommitAndFrameTypes.swift`

**Acceptance criteria:**

- State writes inside `withAnimation` reach the next frame as animation intent
- State writes inside `withAnimation(nil)` explicitly disable animation
- Plain mutations behave exactly as before

### Phase 3: Public View API + Resolve-Time Modifiers

**Objectives:** Expose the authored API, implement subtree-scoped
`.animation(_:value:)`.

**Changes:**

1. Add public `withAnimation` in `View`
2. Add `View.animation(_:value:)`
3. Add `View.transaction(_:)`
4. Add `ValueAnimationModifier` view
5. Add non-invalidating dynamic-state write path
   (`setStateSlotSilently(ordinal:value:)`)
6. Add transaction transformation helpers on `ResolveContext`

**Files:**

- `Sources/View/Animation/AnimationModifiers.swift`
- `Sources/View/Environment/FrameResolveState.swift`
- `Sources/Core/Graph/ViewNode.swift`

**Acceptance criteria:**

- `.animation(_:value:)` only fires when `value` changes
- `.animation(nil, value:)` disables inherited animation for that subtree
- `.transaction()` can strip animation from a subtree
- No value-less `.animation(_:)` surface is added

### Phase 4: Animation Controller

**Objectives:** Build the stateful animation engine.

**Changes:**

1. Add `AnimationController` class
2. Add `AnimatableSnapshot` extraction from resolved nodes
3. Add `processResolvedTree()` for from/to capture
4. Add `applyInterpolations()` for per-tick interpolation
5. Add `AnimationTickResult` for frame cadence feedback
6. Add interrupted animation retargeting
7. Integrate into `DefaultRenderer` between resolve and measure

**Files:**

- New `Sources/TerminalUI/AnimationController.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`

**Acceptance criteria:**

- Color transitions interpolate smoothly via Oklab
- Opacity fades via color pre-blending
- Position, size, padding animate (integer-stepped)
- Interrupted animations retarget from current displayed value
- Animations complete and stop requesting frames

### Phase 5: Transition System

**Objectives:** Implement the modern `Transition` protocol and built-in
transitions.

**Changes:**

1. Add `Transition` protocol and `TransitionPhase`
2. Add `AnyTransition` with type erasure
3. Add built-in transitions: opacity, move, slide, offset, push, identity
4. Add combinators: `combined(with:)`, `asymmetric(insertion:removal:)`
5. Add `.transition()` view modifier
6. Add insertion/removal tracking to `AnimationController`
7. Add kept-alive node support for removal animations

**Files:**

- New `Sources/View/Animation/Transition.swift`
- New `Sources/View/Animation/AnyTransition.swift`
- `Sources/TerminalUI/AnimationController.swift`

**Acceptance criteria:**

- New views fade in with `.transition(.opacity)`
- Removed views animate out before being removed from draw tree
- `.asymmetric()` uses different transitions for insertion and removal
- Custom transitions via the `Transition` protocol work
- Views without `.transition()` snap immediately

### Phase 6: Scheduler Wake Integration

**Objectives:** Wire deadline wakes into the run loop event pump.

**Changes:**

1. Add wake stream (`AsyncStream<Void>`) to `FrameScheduler`
2. Merge wake stream into `RunLoop.EventPump`
3. Update run loop to render on scheduler wake with no input events
4. Preserve mouse coalescing for input batches
5. Fix resolve reuse for empty invalidation sets (if not done in Phase 0)

**Files:**

- `Sources/Core/Scheduler.swift`
- `Sources/TerminalUI/RunLoop.swift`
- `Sources/TerminalUI/RunLoop+EventPump.swift`

**Acceptance criteria:**

- Scheduled deadlines trigger rendering without user input
- Background invalidations trigger rendering without input
- Existing input and signal behavior unchanged
- Lifecycle-driven invalidations wake the loop

### Phase 7: Testing + Docs

**Objectives:** Lock behavior down with deterministic tests, update docs.

**Tests:**

1. **Spring solver** — critically damped, underdamped, overdamped convergence
2. **Bezier solver** — standard curves match expected output at sample points
3. **Transaction propagation** — `withAnimation` sets animation request,
   `withAnimation(nil)` disables, plain writes have no animation intent
4. **Resolve reuse** — deadline-only frames reuse resolve, debug signature
   changes don't defeat reuse
5. **Animation controller** — color interpolation, opacity fade, integer
   truncation for position, retargeting from interrupted state
6. **Transitions** — insertion/removal lifecycle, kept-alive nodes during
   removal, combinators, custom transitions
7. **Scheduler wake** — deadline wakes, background invalidation wakes
8. **Interactive runtime** — animation progresses over deadlines without input,
   stops scheduling after completion

**Suggested test files:**

- `Tests/TerminalUITests/AnimationSolverTests.swift`
- `Tests/TerminalUITests/AnimationControllerTests.swift`
- `Tests/TerminalUITests/TransitionTests.swift`
- `Tests/TerminalUITests/AnimationPipelineTests.swift`

**Docs updates:**

- `docs/PUBLIC_API_INVENTORY.md`
- `docs/SOURCE_LAYOUT.md`

---

## File-Level Change Summary

### New files

| File | Module | Contents |
|------|--------|----------|
| `Sources/Core/AnimationProtocols.swift` | Core | VectorArithmetic, Animatable, AnimatablePair, conformances |
| `Sources/View/Animation/Animation.swift` | View | Animation struct, factory methods, modifiers |
| `Sources/View/Animation/CustomAnimation.swift` | View | CustomAnimation protocol, AnimationContext |
| `Sources/View/Animation/SpringSolver.swift` | View | Damped harmonic oscillator solver |
| `Sources/View/Animation/BezierSolver.swift` | View | Cubic bezier timing curve solver |
| `Sources/View/Animation/AnimationModifiers.swift` | View | ValueAnimationModifier, .transition(), .transaction() |
| `Sources/View/Animation/Transition.swift` | View | Transition protocol, TransitionPhase |
| `Sources/View/Animation/AnyTransition.swift` | View | AnyTransition, built-ins, combinators |
| `Sources/TerminalUI/AnimationController.swift` | TerminalUI | AnimationController, snapshots, tick logic |

### Modified files

| File | Module | Changes |
|------|--------|---------|
| `Sources/Core/EnvironmentAndNodeTypes.swift` | Core | AnimationRequest on TransactionSnapshot |
| `Sources/Core/Scheduler.swift` | Core | AnimationAwareInvalidating, wake stream |
| `Sources/Core/StateContainer.swift` | Core | Animation-aware invalidation path |
| `Sources/Core/CommitAndFrameTypes.swift` | Core | Animation request on ScheduledFrame/FrameContext |
| `Sources/Core/CommitPlanner.swift` | Core | Reuse predicate for empty invalidation sets |
| `Sources/Core/Graph/ViewNode.swift` | Core | setStateSlotSilently for non-invalidating writes |
| `Sources/View/State.swift` | View | Propagate animation request from task-local |
| `Sources/View/Environment/FrameResolveState.swift` | View | Transaction transformation helpers |
| `Sources/TerminalUI/RunLoop.swift` | TerminalUI | Scheduler wake handling |
| `Sources/TerminalUI/RunLoop+EventPump.swift` | TerminalUI | Merge wake stream |
| `Sources/TerminalUI/RunLoop+Rendering.swift` | TerminalUI | Animation controller integration |

---

## Risks and Mitigations

### Risk: Tick frames trigger too much work

**Mitigation:** Fix resolve reuse for empty invalidation sets. Ignore
debug-only transaction fields for reuse. Animation tick frames skip resolve
entirely — only interpolation + measure/place/draw/raster run.

### Risk: Scheduler wake integration changes runtime behavior broadly

**Mitigation:** Targeted tests for background invalidation and input handling.
Keep event coalescing for pointer streams. Keep scheduler wake notifications
package-only.

### Risk: Kept-alive removal nodes create complexity

**Mitigation:** Removal nodes are frozen snapshots placed at their last known
position. They participate in draw but not layout. Clear ownership: the
`AnimationController.removingNodes` dictionary manages their lifecycle.

### Risk: Integer-stepped position animations look bad

**Mitigation:** 30fps cadence smooths small movements. Position animation is
opt-in (only happens when the user applies `.animation()` to position-affecting
properties). Most terminal UIs will primarily use color/opacity transitions.

### Risk: CustomAnimation protocol adds surface area too early

**Mitigation:** The protocol is needed for future `keyframeAnimator` and
`phaseAnimator` support. The internal spring and bezier animations are
implemented as `CustomAnimation` conformances, so the protocol is validated by
its own built-in usage.

### Risk: `.animation(_:value:)` needs stored previous values during resolve

**Mitigation:** Explicit non-invalidating state-store path for modifier
bookkeeping (`setStateSlotSilently`). Behavior stays local to the modifier.

---

## Rollout Recommendation

### PR 1: Foundation + Plumbing

- Phase 0 (foundation types, reuse semantics)
- Phase 1 (animation type system, solvers)
- Phase 2 (mutation-time plumbing)
- Phase 6 (scheduler wake integration)
- Tests for scheduling, reuse, and solver correctness

This PR proves the runtime can handle deadline wakes and animation-aware
transactions before any user-facing animation API depends on them.

### PR 2: Public API + Controller

- Phase 3 (public view API, resolve-time modifiers)
- Phase 4 (animation controller)
- Phase 7 (controller tests, interpolation tests)

### PR 3: Transitions

- Phase 5 (transition system)
- Phase 7 (transition tests, integration tests, docs)

This sequencing reduces integration risk: the runtime proves itself first, then
the animation engine, then the transition lifecycle.

---

## Future Work (Out of Scope)

These are enabled by this architecture but not part of this plan:

- `keyframeAnimator(initialValue:repeating:content:keyframes:)`
- `phaseAnimator(_:content:animation:)`
- `matchedGeometryEffect`
- Gradient interpolation
- `TerminalChromeStyle` interpolation
- 60fps mode (if terminal I/O permits)

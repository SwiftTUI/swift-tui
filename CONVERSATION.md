❯ I want to add animation support to this SwiftUI mimicking TUI framework.

  Please investigate and plan how to add withAnimation(_:_:) and animation(_:value:) and transition(_:) APIs.

  * Design with the awareness of other SwiftUI animation methods (like keyframeAnimator(initialValue:repeating:content:keyframes:) and
  phaseAnimator(_:content:animation:)) that will be implemented in future.
  * Allow for custom Transitions
  * Provide common animations like easeInOut, bouncy, and smooth

  This will be a signficant undertaking. Investigate the swiftui apis deeply, using sub-agents to gather information and to specialize on
   domain problems.

  Write a design document and plan out to ANIMATION_PLAN.md

⏺ Skill(superpowers:brainstorming)
  ⎿  Successfully loaded skill

⏺ Let me explore the codebase and research SwiftUI animation APIs in parallel.

⏺ 3 agents finished (ctrl+o to expand)
   ├─ Explore (Explore TUI framework codebase) · 0 tool uses
   │  ⎿  Done
   ├─ Agent (Research SwiftUI animation internals) · 0 tool uses
   │  ⎿  Done
   └─ Agent (Research terminal animation constraints) · 0 tool uses
      ⎿  Done

⏺ Good — I now have a deep picture of both the codebase and SwiftUI's animation model. Here's what I've learned:

  Your framework already has strong foundations for animation:
  - 7-phase render pipeline (Resolve → Measure → Place → Semantics → Draw → Raster → Commit)
  - Identity-based view tracking that persists across frames
  - FrameScheduler.requestDeadline() for scheduling future frame wakes
  - Sophisticated color interpolation (Oklab, Oklch, linear RGB, etc.)
  - Opacity property on DrawMetadata (currently mapped to binary SGR faint)
  - Incremental damage-based terminal updates

  SwiftUI's animation model boils down to:
  - Transaction carries an Animation through the view tree
  - Animatable protocol + VectorArithmetic enables value interpolation
  - withAnimation sets a transaction at the root (explicit)
  - .animation(_:value:) intercepts and replaces the transaction at a subtree (implicit)
  - .transition() controls insertion/removal via TransitionPhase
  - Future APIs (keyframeAnimator, phaseAnimator) are higher-level choreography built on the same Transaction/Animatable infrastructure

  Now for the first clarifying question:

  In a terminal, positions are integers (character cells) and there's no true alpha compositing. This constrains what "animation" means
  compared to SwiftUI. Which of these describes your priority?

  - (A) Faithful API mirroring — Match SwiftUI's API surface as closely as possible (Transaction, Animatable, VectorArithmetic, etc.),
  even if some animations look coarse at terminal resolution. Users who know SwiftUI should feel at home.
  - (B) Terminal-optimized with SwiftUI flavor — Use SwiftUI naming and patterns (withAnimation, .animation(), .transition()) but adapt
  the internals for terminal realities. For example, color interpolation via your existing Oklab pipeline, smooth opacity via color
  pre-blending rather than SGR faint, and accepting that position animations are integer-stepped.
  - (C) Practical subset — Focus on what looks good in a terminal (color transitions, opacity fades, transitions for view
  insertion/removal) and skip things that would look bad (position animations in a character grid).

  My recommendation is (B) — the framework clearly aims for SwiftUI API parity, but animations should be tuned for what actually looks
  good in a terminal.

✻ Cogitated for 5m 40s

❯ What i'm looking for is closer to A: faithful implementation for the subset that we choose to implement, with faithful API for the
  subset we choose to implement.
  This means overdoing the implementation to match swiftui's methodology in some places, but not in places that can be excluded because
  they can never be properly represented in a terminal.

  We're aiming for parity of implementation for the subset of the API that we implement.

⏺ Clear — faithful internals for what we implement, not just API surface matching. The Transaction propagation model,
  Animatable/VectorArithmetic protocols, the distinction between implicit and explicit animations — all of that done properly, just scoped
   to terminal-representable properties.

  Next question: Which animatable properties should be in scope for this initial implementation?

  Here's my assessment of what's viable in a terminal:

  Strong candidates (look good):
  - Color transitions (fg/bg/border) — your Oklab interpolation pipeline is already excellent
  - Opacity — via color pre-blending against background (upgrade from binary SGR faint)
  - View insertion/removal transitions (opacity, slide, move)

  Viable but coarser:
  - Position/offset — integer-stepped, but decent at 30fps for small movements
  - Size (width/height) — triggers relayout, works
  - Padding — same mechanism as size

  Not representable (skip):
  - Rotation, scale, blur, 3D transforms — no terminal equivalent

  Would you include position/size/padding animations in the initial scope, or keep the first pass to color, opacity, and transitions?

❯ This is a reasonable grouping. include the viable but coarser set.

⏺ Good. Full property set: colors, opacity, position/offset, size, padding, plus insertion/removal transitions.

  Next question: How deep should the Animation type system go?

  SwiftUI's bouncy and smooth aren't just timing curves — they're spring physics simulations (damped harmonic oscillator). A faithful
  implementation means:

  - (A) Full spring physics — Implement the actual spring solver (mass, stiffness, damping, initialVelocity). This gives you
  spring(duration:bounce:), smooth, snappy, bouncy as SwiftUI defines them, plus interpolatingSpring. Also implement cubic bezier timing
  curves for easeInOut, easeIn, easeOut, linear. And the CustomAnimation protocol so users can define their own.
  - (B) Spring presets + timing curves — Implement the spring solver and cubic bezier curves, but skip CustomAnimation protocol for now.
  Users get all the built-in animations but can't define custom ones yet.
  - (C) Timing curves only — Just cubic bezier for easeInOut/linear/etc, and approximate bouncy/smooth as preset bezier curves rather than
   true spring physics. Simpler but not faithful.

  My recommendation is (A) — the spring solver is ~50 lines of math, and CustomAnimation is what enables future
  keyframeAnimator/phaseAnimator to be built cleanly on top. It's the right foundation for your "faithful implementation" goal.

❯ full spring physics.

⏺ Next question: Which built-in transitions should ship, and which Transition API model?

  SwiftUI has two transition APIs:
  - Legacy: AnyTransition with .modifier(active:identity:) — type-erased, combinable
  - Modern (iOS 17+): Transition protocol with TransitionPhase enum (.willAppear, .identity, .didDisappear)

  For a new implementation targeting custom transitions, the modern Transition protocol is cleaner. I'd recommend implementing that, with
  AnyTransition as the type-erased wrapper.

  For built-in transitions, which of these do you want in the initial set?

  ┌───────────────┬────────────────────────────────────────────┐
  │  Transition   │             Terminal viability             │
  ├───────────────┼────────────────────────────────────────────┤
  │ .opacity      │ Excellent — fade in/out via color blending │
  ├───────────────┼────────────────────────────────────────────┤
  │ .move(edge:)  │ Good — slide from an edge                  │
  ├───────────────┼────────────────────────────────────────────┤
  │ .slide        │ Good — leading in, trailing out            │
  ├───────────────┼────────────────────────────────────────────┤
  │ .offset(x:y:) │ Good — shift by fixed amount               │
  ├───────────────┼────────────────────────────────────────────┤
  │ .push(from:)  │ Good — push old view out, new in           │
  ├───────────────┼────────────────────────────────────────────┤
  │ .scale        │ Poor — no sub-cell scaling in terminal     │
  ├───────────────┼────────────────────────────────────────────┤
  │ .blurReplace  │ Not possible                               │
  ├───────────────┼────────────────────────────────────────────┤
  │ .identity     │ Trivial — instant, no visual change        │
  └───────────────┴────────────────────────────────────────────┘

  My recommendation: .opacity, .move(edge:), .slide, .offset, .push(from:), .identity, plus .combined(with:) and
  .asymmetric(insertion:removal:) combinators. Skip .scale and .blurReplace.

❯ We want to implement only the modern transition API. your list of transitions is acceptable.

⏺ Good. Modern Transition protocol only, with opacity, move, slide, offset, push, identity, plus combinators.

  I think I have enough to propose approaches. Let me move to that.

⏺ Let me read a few critical files to ground the proposal in the actual code before presenting.

⏺ Explore(Read core pipeline and scheduler)
  ⎿  Done (8 tool uses · 144.1k tokens · 32s)
  (ctrl+o to expand)

⏺ Critical finding — ResolveContext already has a transaction: TransactionSnapshot field. Let me check what that contains.

  Searched for 4 patterns, read 1 file (ctrl+o to expand)

⏺ There's already an existing COLOR_ANIMATION_IMPLEMENTATION_PLAN.md — our plan supersedes this with a full animation system. Let me check
   what's already been implemented from it and understand the current TransactionSnapshot.

  Searched for 2 patterns, read 1 file (ctrl+o to expand)

⏺ Now I have the full picture. TransactionSnapshot is currently a stub (just debugSignature: String). The prior
  COLOR_ANIMATION_IMPLEMENTATION_PLAN.md was never implemented — no AnimationRequest, AnimationDescriptor, or coordinator code exists. Our
   plan supersedes it entirely.

  Here are the three architectural approaches:

  ---
  Approach A: Resolve-Once, Animate-Through-Pipeline (Recommended)

  Faithful to SwiftUI's model. When a state change happens inside withAnimation:

  1. Resolve runs once with the new "to" values (body evaluates once)
  2. Animation controller captures (from, to, animation, startTime) for each changed Animatable property
  3. On each tick frame (driven by requestDeadline): compute interpolated values → inject before Measure → run Measure → Place → Draw →
  Raster with interpolated values
  4. Resolve is NOT re-run on tick frames — only the downstream pipeline runs with overridden values

  This handles layout-affecting animations (position, size, padding) naturally because the layout engine sees intermediate values. Full
  Transaction propagation, Animatable/VectorArithmetic protocols, CustomAnimation protocol.

  Pros: Faithful to SwiftUI internals. Layout-affecting animations work correctly. Single animation code path.
  Cons: Tick frames run measure+place+draw (more work than post-processing draws only). But the existing measurement cache and damage
  tracking mitigate this.

  Approach B: Dual-Layer Animation

  Same as A for layout-affecting properties (position, size, padding). But color/opacity animation bypasses measure/place and interpolates
   at the draw level (like the prior color animation plan). Two animation code paths optimized for their domain.

  Pros: More efficient for visual-only animations (no re-layout).
  Cons: Two systems to maintain. Inconsistent behavior edge cases. Not faithful.

  Approach C: Draw-Post-Process Only

  All interpolation happens between draw and raster. Generalizes the prior color plan to opacity. Cannot animate position/size/padding
  (they would snap).

  Pros: Simplest implementation.
  Cons: Contradicts your requirements — no layout animation.

  ---
  My recommendation is Approach A. It's the faithful model, and the existing measurement cache + selective evaluation + damage tracking
  make the per-tick cost manageable. Approach B could be a future optimization if profiling shows hot spots, but starting with a single
  uniform path is architecturally cleaner.

  Does this match your thinking?

✻ Cooked for 3m 33s

❯ Yes. Approach A.

⏺ Let me read a few more files to ground the design precisely before presenting it.

⏺ Explore(Read pipeline integration points)
  ⎿  Done (19 tool uses · 158.6k tokens · 1m 9s)
  (ctrl+o to expand)

⏺ Now I have everything needed. Let me present the design section by section.

  ---
  Design Section 1: Foundation Protocols

  This layer lives in Core (protocols) with conformances in both Core and View.

  VectorArithmetic

  // Core module
  public protocol VectorArithmetic: AdditiveArithmetic, Sendable {
      mutating func scale(by rhs: Double)
      var magnitudeSquared: Double { get }
  }

  Conformances: Double, Int (for cell-grid positions), AnimatablePair<First, Second>, EmptyAnimatableData.

  Int conformance is non-standard vs SwiftUI (which uses CGFloat), but required since all terminal coordinates are integers. Interpolation
   truncates: from + Int(Double(to - from) * progress).

  Animatable

  // Core module
  public protocol Animatable: Sendable {
      associatedtype AnimatableData: VectorArithmetic
      var animatableData: AnimatableData { get set }
  }

  Key conformances:
  - DrawMetadata — exposes opacity as animatable data
  - EdgeInsets — animatable via AnimatablePair<AnimatablePair<Int,Int>, AnimatablePair<Int,Int>>
  - Color — uses your existing Oklab interpolation pipeline rather than raw VectorArithmetic (a ColorAnimatableData wrapper that delegates
   to Color.interpolated(to:progress:method:))

  Animation type + curves

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

  CustomAnimation protocol

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

  Spring solver

  ~50 lines of math. Solves the damped harmonic oscillator equation:

  x(t) = e^(-ζωt) * (A*cos(ωd*t) + B*sin(ωd*t))

  Where ζ = damping ratio (derived from bounce), ω = natural frequency (derived from duration), ωd = damped frequency. The bounce
  parameter maps to damping: 0 = critically damped, >0 = underdamped (bouncy), <0 = overdamped.

  The cubic bezier solver uses De Casteljau's algorithm to find t for a given x, then evaluates y(t).

  ---
  Does this foundation layer look right before I continue to the Transaction and plumbing section?

✻ Crunched for 2m 44s

❯ this look sright. please continue

⏺ Design Section 2: Transaction + Mutation/Resolve Plumbing

  TransactionSnapshot enhancement

  The current stub gets real animation data:

  // Core module (EnvironmentAndNodeTypes.swift)
  public struct TransactionSnapshot: Equatable, Sendable {
      public var debugSignature: String
      package var animationRequest: AnimationRequest = .inherit

      // Reuse check ignores debugSignature — animation intent matters for reuse,
      // debug labels don't
      package func isReuseEquivalent(to other: Self) -> Bool {
          animationRequest == other.animationRequest
      }
  }

  package enum AnimationRequest: Equatable, Sendable {
      case inherit          // use whatever the parent transaction says
      case disabled         // explicitly suppress animation in this subtree
      case animate(Animation)  // animate with this curve
  }

  withAnimation — mutation-time plumbing

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

  Internal mechanism — three pieces:

  1. Task-local animation context (Core, package-only):
  package enum AnimationContextStorage {
      @TaskLocal static var currentRequest: AnimationRequest = .inherit
  }

  2. Animation-aware invalidation (Core, package-only):
  package protocol AnimationAwareInvalidating: Invalidating {
      func requestInvalidation(
          of identities: Set<Identity>,
          animation: AnimationRequest
      )
  }

  FrameScheduler conforms. Stores a pending coalesced animation request on ScheduledFrame. Coalescing rule: latest explicit request wins;
  .inherit never overrides an explicit pending request.

  3. State write propagation: StateContainer and DynamicStateStore read the task-local, attempt the animation-aware invalidation path.
  withAnimation sets the task-local, executes the body, state writes carry the animation request through to the scheduler, and the next
  ScheduledFrame carries it into FrameContext.transaction.animationRequest.

  .animation(_:value:) — resolve-time plumbing

  // View module (public)
  extension View {
      public func animation<V: Equatable>(
          _ animation: Animation?, value: V
      ) -> some View
  }

  Internal modifier (View module, package-only):

  package struct ValueAnimationModifier<Content: View, Value: Equatable & Sendable>:
      View, ResolvableView
  {
      var content: Content
      var animation: Animation?
      var value: Value
  }

  During resolve:
  1. Reads previous value from a non-invalidating state slot (new capability — a state write that updates stored value without triggering
  invalidation)
  2. Compares previous vs current
  3. If changed and animation != nil: overrides child transaction to .animate(animation)
  4. If changed and animation == nil: overrides child transaction to .disabled
  5. If unchanged: passes through parent transaction (.inherit)
  6. Stores current value without invalidating

  Non-invalidating state slot — needed because the modifier must remember the previous value but writing it shouldn't cause re-resolve.
  This is a small addition to ViewNode: setStateSlotSilently(ordinal:value:) that skips the invalidation path.

  .transaction() modifier

  // View module (public)
  extension View {
      public func transaction(
          _ transform: @escaping @Sendable (inout TransactionSnapshot) -> Void
      ) -> some View
  }

  Allows stripping animation from a subtree: .transaction { $0.animationRequest = .disabled }.

  ---
  Does the transaction and plumbing design look right? Next up would be the Animation Controller and pipeline integration.

❯ this looks good

⏺ Design Section 3: Animation Controller + Pipeline Integration

  AnimationController

  Renderer-owned, stateful. Lives in TerminalUI module (package-only).

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
      var from: AnimatableValue       // captured at animation start
      var to: AnimatableValue         // target value
      var animation: Animation
      var startTime: MonotonicInstant
      var retargetedFrom: AnimatableValue?  // for interrupted animation handoff
  }

  AnimatableValue is an enum that wraps the concrete types:
  package enum AnimatableValue: Sendable {
      case double(Double)         // opacity
      case integer(Int)           // padding, offset, size
      case color(Color)           // fg/bg/border colors
  }

  AnimatableSnapshot

  Captured per-identity after resolve, before diffing:

  package struct AnimatableSnapshot: Equatable, Sendable {
      var opacity: Double?
      var foregroundColor: Color?
      var backgroundColor: Color?
      var borderColor: Color?
      var padding: EdgeInsets?
      var offset: (x: Int, y: Int)?
      var frameSize: (width: Int?, height: Int?)?
  }

  Extracted from ResolvedNode.drawMetadata + ResolvedNode.layoutBehavior for each identity.

  Per-frame flow

  The animation controller has two entry points per frame:

  1. processResolvedTree(_:transaction:timestamp:) — called after Resolve, before Measure

  For each identity in the new resolved tree:
    1. Extract AnimatableSnapshot from resolved node
    2. Compare with previousSnapshots[identity]
    3. For each property that changed:
       a. If transaction.animationRequest is .animate(anim):
          - Create ActiveAnimation(from: previous, to: new, animation: anim, startTime: now)
          - If an animation for this key already exists, retarget:
            sample current interpolated value as new "from"
       b. If .disabled or .inherit with no parent animation:
          - Snap immediately (no animation entry)
    4. Store new snapshot in previousSnapshots

  2. applyInterpolations(to:at:) — mutates the resolved tree with interpolated values

  For each active animation:
    1. Compute elapsed = timestamp - startTime
    2. Apply delay (skip if elapsed < delay)
    3. Evaluate animation curve → progress (may overshoot for springs)
    4. Interpolate: current = from + (to - from) * progress
       - For colors: use Color.interpolated(to:progress:method: .perceptual)
       - For integers: truncate interpolated Double to Int
       - For doubles: direct interpolation
    5. Override the resolved node's property with interpolated value
    6. If animation curve returns nil (complete):
       - Remove from activeAnimations
       - Fire completion callback if any

  Returns: AnimationTickResult
  package struct AnimationTickResult: Sendable {
      var hasActiveAnimations: Bool
      var nextDeadline: MonotonicInstant?  // earliest next tick needed
      var affectedIdentities: Set<Identity>  // for damage tracking
  }

  Pipeline integration point

  In RunLoop+Rendering.swift, the frame rendering flow becomes:

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

  Steps 2-3 are the only new insertions. The rest of the pipeline is untouched.

  Frame cadence

  - 30 FPS target during active animation (frameInterval = .milliseconds(33))
  - Next deadline: min(earliestAnimationEnd, now + frameInterval) across all active animations
  - When all animations complete, no more deadlines are requested → runtime returns to idle event-driven mode (zero-cost when not
  animating)

  Interrupted animation retargeting

  When a new animation starts for a key that already has an active animation:
  1. Sample the currently displayed interpolated value
  2. Start the new animation from that value (not from the original "from")
  3. This produces smooth retargeting — no visual discontinuity

  View insertion/removal tracking

  The controller tracks which identities are new (inserted) vs removed by comparing the identity set between frames. This feeds into the
  transition system (Section 4). Removed identities keep their animations alive until transitions complete.

  ---
  Does this look right? Next is the Transition system.

✻ Baked for 35s

❯ yes. continue

⏺ Design Section 4: Transition System

  Transition protocol

  Modern API only, matching SwiftUI iOS 17+:

  // View module (public)
  public protocol Transition: Sendable {
      associatedtype Body: View

      @ViewBuilder
      func body(content: TransitionContent<Self>, phase: TransitionPhase) -> Body

      // Default: uses body() for both. Override for static optimization.
      static var properties: TransitionProperties { get }
  }

  public enum TransitionPhase: Hashable, Sendable {
      case willAppear     // view is being inserted
      case identity       // view is fully present (normal state)
      case didDisappear   // view is being removed

      public var isIdentity: Bool { self == .identity }
  }

  public struct TransitionProperties: Sendable {
      // Hints to the system about what the transition affects
      public var hasMotion: Bool = true
  }

  TransitionContent<T> is a placeholder view that represents the content being transitioned — the transition's body wraps it with
  modifiers that vary by phase.

  AnyTransition — type-erased wrapper

  // View module (public)
  public struct AnyTransition: Sendable {
      // Store the type-erased transition
      private var _apply: @Sendable (TransitionPhase) -> TransitionModifiers
  }

  // TransitionModifiers — the concrete property changes for a phase
  package struct TransitionModifiers: Sendable {
      var opacity: Double?
      var offsetX: Int?
      var offsetY: Int?
  }

  The type erasure resolves transitions down to their concrete property effects. This is simpler than full view-wrapping because terminal
  animations operate on a fixed set of animatable properties. The Transition protocol's body method is the authoring surface;
  AnyTransition flattens it into property deltas.

  Built-in transitions

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

  .transition() view modifier

  extension View {
      public func transition(_ t: AnyTransition) -> some View
  }

  Stores the transition in DrawMetadata or a dedicated metadata field so the animation controller can read it during insertion/removal
  processing.

  Custom transition authoring

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

  Lifecycle integration with AnimationController

  The animation controller already tracks identity sets between frames. Transition integration adds:

  Insertion:
  1. A new identity appears in the resolved tree that wasn't in the previous frame
  2. Controller checks if the node has a .transition() modifier
  3. If yes: starts animation from willAppear phase modifiers → identity phase modifiers
  4. The transition's property deltas (opacity, offset) become the from values; identity values are the to values
  5. Normal animation curve applies (from the active transaction)

  Removal:
  1. An identity from the previous frame is absent in the new resolved tree
  2. Controller checks if the node had a .transition() modifier
  3. If yes: the node is kept alive in the resolved tree during the animation
  4. Starts animation from identity phase modifiers → didDisappear phase modifiers
  5. When animation completes, the node is truly removed from the tree
  6. During the animation, the node continues to participate in draw + raster but NOT in layout (it occupies no space — same as SwiftUI)

  Kept-alive nodes — the key complexity:
  - The controller maintains a removingNodes: [Identity: RemovalEntry] dictionary
  - Each entry holds the last resolved snapshot + transition + animation
  - During measure/place, removing nodes are excluded
  - During draw, removing nodes are included at their last placed position with interpolated transition properties
  - When the removal animation completes, the entry is purged

  package struct RemovalEntry: Sendable {
      var snapshot: ResolvedNode      // frozen at removal time
      var placedBounds: Rect          // last known position
      var transition: AnyTransition
      var animation: Animation
      var startTime: MonotonicInstant
  }

  Default transition

  When no .transition() modifier is present, insertion/removal snaps immediately (equivalent to .transition(.identity)). This matches
  SwiftUI behavior.

  ---
  Does the transition system look right? I have one more section — the scheduler wake integration that makes the whole thing tick.

✻ Crunched for 37s

❯ This looks good.

⏺ Design Section 5: Scheduler Wake Integration

  This is the infrastructure that makes animation frames fire without user input.

  The problem

  The current run loop only wakes on two streams: input events and signals. The event pump merges these into an AsyncSequence. When no
  input arrives and no signal fires, the loop sleeps — even if requestDeadline() was called. Animation frames need to render on a timer
  with no user interaction.

  Wake stream on FrameScheduler

  // Core module (Scheduler.swift)
  package final class FrameScheduler: FrameScheduling, AnimationAwareInvalidating {
      // Existing fields...

      // NEW: continuation-backed wake notifier
      private var wakeContinuation: AsyncStream<Void>.Continuation?
      package var wakeStream: AsyncStream<Void>  // vended once to the run loop

      // When requestDeadline or requestInvalidation is called,
      // signal the wake stream:
      private func notifyWake() {
          wakeContinuation?.yield()
      }
  }

  requestDeadline() and requestInvalidation() both call notifyWake(). This wakes the run loop even when there's no input.

  Event pump merge

  In RunLoop+EventPump.swift, the event pump currently merges input + signals. Add the scheduler wake as a third stream:

  // TerminalUI module (RunLoop+EventPump.swift)
  // Conceptually:
  let merged = merge(
      inputEvents,        // keyboard, mouse
      signalEvents,       // SIGWINCH, etc.
      schedulerWakes      // deadline reached, background invalidation
  )

  When a scheduler wake arrives, the run loop checks scheduler.hasPendingFrame(at: .now()) and renders if true. No synthetic input event
  needed.

  Run loop changes

  In RunLoop.swift, the main loop body adds one check:

  // After draining pending events:
  if pendingEvents.isEmpty {
      // Woke from scheduler (deadline or background invalidation)
      if scheduler.hasPendingFrame(at: .now()) {
          try renderPendingFrames(renderedFrames: &renderedFrames)
      }
      continue
  }

  This is already partially there in the existing code — it checks hasPendingFrame when events are empty. The missing piece is the wake
  stream that causes the loop to actually wake up when a deadline arrives.

  Deadline-only frame reuse

  A tick frame typically has no invalidated identities — only active animations need re-rendering. Two changes needed:

  1. Resolve reuse with empty invalidation set: Currently the reuse check requires invalidatedIdentities to be non-empty. For animation
  frames, empty means "nothing re-resolved, just re-interpolate." Fix: treat empty invalidation set as "nothing is dirty" → full resolve
  reuse.
  2. Transaction reuse equivalence: Use isReuseEquivalent(to:) instead of == for transaction comparison during resolve reuse. This ignores
   debugSignature changes that would otherwise defeat reuse.

  Together, these mean animation tick frames are cheap: resolve is fully reused, only the animation controller's interpolation +
  measure/place/draw/raster run.

  Animation lifecycle

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

  Broader fix

  This wake integration also fixes existing gaps unrelated to animation:
  - Lifecycle-driven invalidations (onAppear tasks that mutate state) now wake the loop
  - External invalidation via requestExternalWake() now actually wakes
  - Background @Observable changes propagate without waiting for input

  ---
  That completes the design. To summarize the five layers:

  1. Foundation: VectorArithmetic, Animatable, AnimatablePair, conformances
  2. Animation types: Animation, CustomAnimation, timing curves, spring solver
  3. Transaction + plumbing: TransactionSnapshot enhancement, withAnimation, .animation(_:value:), .transaction()
  4. Animation controller: Stateful engine tracking active animations, interpolation, retargeting, insertion/removal lifecycle
  5. Scheduler wake: Wake stream, deadline-only frame reuse, event pump merge

  Does the full design look complete and correct? If so, I'll write it up as ANIMATION_PLAN.md.
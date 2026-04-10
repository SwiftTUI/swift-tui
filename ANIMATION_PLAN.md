# Animation Implementation Plan

**Date:** 2026-04-08 (plan) / 2026-04-10 (status update)
**Status:** Phase 0–6 shipped and verified in the gallery demo; follow-up work in the "What's Next" section below
**Branch:** `animation` (merged; development continues on `main`)
**Supersedes:** `docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md`

---

## Current Status (2026-04-10)

Phases 0–6 of the original plan are shipped and green. The full package test
suite is 682/682 passing; `swift test --filter Animation` runs 20 animation-
scoped tests across 5 suites, zero regressions. The gallery demo
(`Examples/gallery`) exercises both `withAnimation` color animation
(`color = color.rotatedHue(by:)`) and `.transition(.opacity)` insertion +
removal of a wrapped `TextFigure`. Fades are smooth on truecolor terminals.

> **Post-graph-refactor caveat:** the gallery verification predates
> commit `d8d0a80` (2026-04-10, "fold ResolvedNode into ViewNode as single
> source of truth"), which collapsed ViewNode's 14 mirror fields onto a
> single `committed: ResolvedNode`. The animation controller still operates
> on a local `ResolvedNode` returned by `viewGraph.snapshot()` and the
> `Boxed<DrawMetadata>` copy-on-write wrapper protects the cached tree from
> tick-frame mutation, so nothing should be broken — but the integration
> has not been re-verified against the new graph architecture. See
> "What's next → P0 post-refactor verification" below.

### What ships today

**Foundation protocols** — `Sources/Core/AnimationProtocols.swift`
- `VectorArithmetic`, `Animatable`, `AnimatablePair`, `EmptyAnimatableData`
- `Double`/`Int` conformances (integer interpolation truncates)
- `AnimationRequest` enum (`.inherit` / `.disabled` / `.animate(AnimationBox)`)
- `AnimationBox` — type-erased `Hashable & Sendable` wrapper for Core ↔ View
  decoupling
- `AnimationAwareInvalidating` protocol extending `Invalidating` with an
  animation-request parameter

**Transaction plumbing** — `Sources/Core/EnvironmentAndNodeTypes.swift`,
`Sources/Core/AnimationContextStorage.swift`
- `TransactionSnapshot.animationRequest` (package) with
  `isReuseEquivalent(to:)` so debug-only fields don't defeat retained reuse
- `@TaskLocal AnimationContextStorage.currentRequest` as the bridge between
  `withAnimation` and state writes
- `AnimationRegistrationSink` + `TransitionRegistrationSink` protocols: the
  `RunLoop` installs the renderer-owned `AnimationController` as the active
  sink for both so the View layer can hand concrete `Animation` and
  `AnyTransition` instances off without introducing a direct module
  dependency

**Scheduler + wake integration** — `Sources/Core/Scheduler.swift`,
`Sources/TerminalUI/RunLoop+EventPump.swift`, `RunLoop.swift`
- `FrameScheduler.requestDeadline(_:)` now fires the wake handler (previously
  stored deadlines silently, so animation ticks could be missed)
- `ScheduledFrame.animationRequest` carries animation intent through to the
  frame pipeline
- `FrameScheduler` conforms to `AnimationAwareInvalidating`; coalescing rule is
  "latest explicit request wins; `.inherit` never overrides an explicit
  pending request"
- `EventPump.scheduleDeadlineWake(_:)` — a cancellable `Task.sleep` that yields
  into the pump stream at the deadline, so animation tick frames fire without
  external input
- `RunLoop+Rendering.swift` threads the scheduled frame's animation request
  into `TransactionSnapshot` on `ResolveContext`, and requests the next
  deadline from `AnimationController.lastTickResult` after each render

**Animation type system** — `Sources/View/Animation/`
- `SpringSolver` — full damped harmonic oscillator with under/over/critically
  damped regimes. Constructors: `init(duration:bounce:)` and
  `init(mass:stiffness:damping:)`. Initial conditions (`x(0)=1`, `v(0)=0`)
  are correctly enforced in all three regimes.
- `BezierSolver` — cubic bezier timing curves via Newton-Raphson with a
  bisection fallback. Presets: `.linear`, `.easeIn`, `.easeOut`, `.easeInOut`.
- `CustomAnimation` protocol with `AnimationState` (keyed Sendable storage)
  and `AnimationContext<V: VectorArithmetic>`. **Note:** declared but not yet
  evaluated by the controller — see "Gaps" below.
- `Animation` struct with:
  - Timing curves: `.default`, `.linear`, `.easeIn`, `.easeOut`, `.easeInOut`,
    `.timingCurve(...)`
  - Springs: `.spring(duration:bounce:)`, `.smooth`, `.snappy`, `.bouncy`,
    `.smooth(duration:extraBounce:)` and friends,
    `.interpolatingSpring(mass:stiffness:damping:initialVelocity:)`
  - Modifiers: `.delay(_:)`, `.speed(_:)`, `.repeatCount(_:autoreverses:)`,
    `.repeatForever(autoreverses:)`
  - Custom wrapping: `Animation.init<A: CustomAnimation>(_:)`
  - Package-level `evaluate(elapsed:) -> Double?` used by the controller

**Mutation-time plumbing**
- `StateContainer.mutate` / `.replace` read the task-local animation request
  and forward through `AnimationAwareInvalidating` when present
- `ViewNode.setStateSlot` does the same for `@State`-backed writes
- `ViewNode.setStateSlotSilently` — new non-invalidating write path for
  modifier-internal bookkeeping (used by `ValueAnimationModifier`)
- `ViewGraph.nodeForIdentity(_:)` — new package accessor

**Public view surface** — `Sources/View/Animation/`
- `withAnimation(_:_:)` — registers the animation with the renderer-owned
  sink and sets the task-local for the body's scope
- `withAnimation(_:completionCriteria:_:completion:)` — public for API
  parity; completion closure is accepted but **not yet wired through the
  controller** (see "Gaps")
- `View.animation(_:value:)` → `ValueAnimationModifier` — value-gated with
  non-invalidating previous-value storage via `setStateSlotSilently`
- `View.transaction(_:)` with a public `Transaction` shim exposing
  `animation: Animation?` (setter works; getter returns nil because the
  `AnimationBox` is hash-only — see "Gaps")

**AnimationController** — `Sources/TerminalUI/AnimationController.swift`
- Stateful per-renderer engine wired between resolve and measure in
  `DefaultRenderer.render`
- **Snapshot extraction** via `AnimatableSnapshot`:
  - Opacity (from `drawMetadata.baseStyle.explicitOpacity`)
  - Foreground/background colors — extractor **prefers local draw metadata,
    falls back to `environmentSnapshot.style.foregroundStyle`**. This is
    critical: `.foregroundStyle(color)` on a generic view writes to the
    environment, not to the local draw metadata, so the naive extractor
    would never animate colors applied that way.
  - Layout-derived: offset, frame width/height. Padding and border color are
    reserved in `AnimatableProperty` but not yet extracted or applied (see
    "Gaps").
- **Diff + enqueue** per `(identity, property)` key with effective-request
  resolution (child transaction overrides parent; `.inherit` walks up)
- **Retargeting** on the value-change path: samples the current interpolated
  value from the existing animation and uses it as the new `from`, producing
  smooth retargeting under interruption
- **Interpolation** via `Color.interpolated(to:progress:method:.perceptual)`
  for colors, direct lerp for doubles, truncated lerp for integers
- **Write-back** to a local copy of the resolved tree; the viewGraph cache is
  never mutated — that means tick frames can skip resolve entirely via the
  existing `canUseSelectiveEvaluation && !viewGraph.hasDirtyWork` pipeline
  shortcut

**Transition system**
- `Transition` protocol + `TransitionPhase` (`willAppear`/`identity`/
  `didDisappear`), `TransitionProperties`, `TransitionContent<T>`
- `AnyTransition` with built-ins: `.opacity`, `.move(edge:)`, `.slide`,
  `.offset(x:y:)`, `.push(from:)`, `.identity`
- Combinators: `.combined(with:)`, `.asymmetric(insertion:removal:)`
- `View.transition(_:)` modifier → `TransitionViewModifier` registers per
  identity via the controller sink at resolve time
- **Insertion animations**: detected by identity-set diffing; `willAppear`
  modifiers → `identity` values using the active `withAnimation` curve
- **Removal animations** — the hard case, now working:
  - The full previous tree root is retained so removed subtrees can be
    captured with their complete descendant trees
  - Previous parent identity + child index are tracked per identity
  - **Ancestor walk-up**: when a transition-marked identity AND its parent
    are both removed in the same frame (which is the common case — e.g.
    `.transition(.opacity).padding(1)` where `PaddingView` wraps the text
    with its own identity), the controller walks up disappearing ancestors
    until it finds the first surviving one. The deepest disappearing
    ancestor becomes the injection target; the first surviving ancestor
    becomes the injection parent. This injects the whole padding+text unit
    as a single fading overlay.
  - **Cross-frame transition registration**: the registration map is split
    into `transitionsByIdentity` (current frame, for insertions) and
    `previousTransitionsByIdentity` (last frame, for removals). The
    disappearing branch doesn't re-register on its removal frame because
    `TransitionViewModifier.resolveElements` never runs, so the removal
    lookup uses the previous frame's snapshot.
  - **Re-injection** happens each tick in `applyInterpolations`, with
    interpolated transition modifiers applied via
    `interpolateRemovalModifiers` and cascaded recursively through the
    subtree (opacity cascades to every descendant so leaf text fades;
    offset applies only at the subtree root).
  - **Purge on completion** when the animation curve returns nil

**Smooth opacity rendering** — `Sources/Core/Rasterizer.swift`
- Before this fix, `TerminalPresentation.swift:636` mapped any fractional
  `style.opacity < 1` to the binary SGR "faint" attribute — so a 90-frame
  fade had exactly 2 visible states (normal, faint). Users saw ~3 "stages"
  total (in, faint, out).
- `resolveTextStyle` now bakes fractional opacity into the foreground color
  via `Color.mixed(with:amount:)`. Blend target priority:
  1. Explicit `style.backgroundColor` if set
  2. Otherwise `environment.theme.background`
- After baking, `ResolvedTextStyle.opacity` is normalized to 1.0 so
  presentation doesn't additionally emit SGR "faint" on top of the blended
  color
- Result: continuously smooth fades on truecolor terminals; nearest-palette
  shades on 256-color terminals

### Tests (20 animation-scoped under `--filter Animation`, 682 total passing)

| File | Tests | Scope |
|---|---|---|
| `Tests/CoreTests/AnimationSchedulerTests.swift` | 5 | `requestDeadline` wake, coalesced earlier deadline re-wake, animation request propagation, post-consume reset, explicit-beats-inherit coalescing |
| `Tests/ViewTests/AnimationSolverTests.swift` | 9 | Spring under/over/critically damped, bezier linear/easeInOut S-curve/endpoints, linear animation evaluation, preset distinctness, delay postponement |
| `Tests/TerminalUITests/AnimationControllerTests.swift` | 6 | Snapshot extraction (local, env fallback, priority); removal injection (direct parent, ancestor walk-up, purge-on-completion) |
| `Tests/TerminalUITests/TextFigureSurfaceTests.swift` | +1 | `fractionalOpacityProducesDistinctForegroundColors` — regression guard against the binary-faint regression (not matched by `--filter Animation`; counted separately) |

Three pre-existing tests were updated to reflect the new smooth-opacity
semantics (opacity is baked into the color and normalized to 1.0 on raster
style runs): `TextFigureSurfaceTests.genericViewStylingPropagatesToTextFigureOutput`,
`SwiftUISurfaceTests.textStylingSurvivesDrawAndRaster`, and
`InteractiveRuntimeTests.interactiveDemoSceneExercisesTruncationClippingWideGlyphsAndStyledText`.

### Gaps and known limitations

**Rendering + architectural**

1. **Removal overlays participate in layout.** The original plan's ideal
   (render exiting nodes as non-semantic draw-only overlays at their last
   *placed* bounds) is not implemented. Instead, removal subtrees are
   re-injected into the resolved tree at their previous child index and
   flow through measure/place/draw normally. For simple cases (overlay
   with one child, the gallery's usage) this is visually correct. For a
   `VStack` where a sibling is removed, other siblings may briefly shift
   during the exit animation because the re-injected child reserves layout
   space. A proper fix hoists removals into a dedicated draw-only overlay
   layer with frozen `PlacedNode` bounds from the previous frame.
2. **Removal overlays are technically in the resolved tree.** Semantics,
   focus, lifecycle, and interaction already ignore them because the
   resolver didn't emit them in the live pass, but any new pipeline code
   that walks the resolved tree after `applyInterpolations` without
   knowing about removal injection would treat them as live. A per-node
   "transient overlay" flag or a separate injection channel would make
   this explicit.
3. **Opacity blend target is a theme default.** The rasterizer blends toward
   the explicit `backgroundColor` if set, else `environment.theme.background`.
   If text is rendered over another opaque container (e.g. a colored
   rectangle behind a label) without the text style carrying its own
   background, the fade passes through the theme background instead of the
   actual rendered background beneath the cell. Proper fix: pre-composite
   against the *cell's current background* at raster time.
4. **Custom `Transition` authoring only supports the built-in effect
   palette.** `AnyTransition.init<T: Transition>(_:)` calls
   `extractModifiers(from: view)` which is a placeholder returning identity
   modifiers. User-authored `Transition` conformances whose body uses
   anything beyond the primitive effects the controller already understands
   will have their effects silently ignored. To make custom transitions
   real, either (a) walk the authored body's view tree at registration time
   to surface opacity/offset effects, or (b) expand `TransitionModifiers`
   and rebuild custom transitions from a richer effect palette.
5. **Transition offset effects are applied to the subtree root only, and
   are dropped when the root carries a non-intrinsic layout behavior.**
   `applyTransitionModifiersRecursively` cascades opacity through every
   descendant but applies offset only at the root. Nested offset-based
   transitions on children of an outer offset transition don't compose.
   Additionally, the offset write only triggers when the removed subtree
   root matches `case .intrinsic = node.layoutBehavior`
   (`AnimationController.swift:763-767`); if the root already carries a
   `.frame`, `.padding`, `.offset`, or `.flexibleFrame` layout behavior
   the offset is silently dropped to avoid clobbering authored layout,
   which means `.transition(.move(edge:))` on any view that is also
   sized, padded, or offset will fall back to a snap instead of a slide.

**API parity, not wired through**

6. **`withAnimation` completion callbacks.** The
   `AnimationCompletionCriteria`-accepting overload is public but its
   completion closure is ignored. Implementing it requires: (a) assigning
   stable batch IDs when creating animation tracks, (b) registering
   observers keyed by `(batchID, criteria)`, (c) firing after logically
   complete (curve returns nil) or after the removal overlay is purged.
7. **`Transaction.animation` getter.** Returns nil because the
   `AnimationBox` is hash-only and can't round-trip back to a concrete
   `Animation`. Setter works (`t.animation = .easeInOut`) because writes go
   through the box directly. Fix: keep a concrete `Animation` reference
   alongside the hash-based key, or add a controller-backed lookup
   registry.

**Animation features**

8. **`CustomAnimation` evaluation is a stub.** The protocol is public, but
   the controller evaluates animations via `Animation.evaluate(elapsed:)`,
   which handles `.bezier` and `.spring` curves only. Custom animations
   fall through to a linear fallback. To enable user-authored curves, the
   controller needs to call the protocol's `animate(value:time:context:)`
   at tick time with a per-key `AnimationState`, and honor the
   return-nil-means-complete contract.
9. **`repeatCount` and `repeatForever` are no-ops.** `delay` and `speed`
   both work — `Animation.evaluate` runs elapsed time through
   `adjustedTime(_:)` which applies `speedMultiplier` as a time scalar
   (`Animation.swift:185-190`). What's still missing: `repeatBehavior`
   is stored on the `Animation` struct but `evaluate` never consults it,
   so `.repeatCount(_:autoreverses:)` and `.repeatForever()` complete
   exactly once and then stop. Fix: the evaluator needs to track a
   repeat index, optionally mirror `progress` for autoreverse, and
   return `nil` only after the final iteration.
10. **Insertion-path retargeting restarts from the declared `willAppear`
    values** instead of the currently displayed interpolated value, if the
    insertion is interrupted by an opposite toggle mid-fade. The
    property-value-change path already retargets correctly; only the
    transition-driven insertion/removal paths need the same treatment.

**Animatable property surface — declared but not finished**

11. **`AnimatableProperty.borderColor`** is in the enum but
    `AnimatableSnapshot.extract` doesn't read
    `drawMetadata.baseStyle.borderShapeStyle`, and `applyValue` has no
    case for it. Easy finish.
12. **Padding animation** is declared
    (`paddingTop`/`paddingLeading`/`paddingBottom`/`paddingTrailing`).
    `AnimatableSnapshot.padding` is captured, but `diffAndEnqueue` never
    enqueues padding edges, and `applyValue` has no padding case.
13. **Frame size extraction only handles
    `.frame(width:height:alignment:)`**, not `.flexibleFrame(...)`. Most
    real view trees use the flexible variant. The extractor would need a
    second case.

**Scheduler**

14. **Tick frames do not re-propagate the active animation request on
    `ScheduledFrame`.** Currently the `animationRequest` on a deadline-only
    frame defaults to `.inherit`. That's correct in practice because tick
    frames carry no new state-change intent, and the controller's active
    animations persist across tick frames regardless. But if resolve ever
    runs on a tick frame (e.g. due to a background `@Observable` change
    that coincides with the deadline), value-change diffs would snap
    instead of retargeting the in-flight animation. Fix: the controller
    should inject its current dominant active request into the frame's
    transaction when there are active animations.

**Testing**

15. **No end-to-end integration test** for the full
    `withAnimation { state = newValue } → scheduler → tick frame →
    controller → raster` path. Unit tests cover each piece in isolation,
    but drive-and-inspect across the tick sequence is missing. A harness
    exists in `InteractiveRuntimeTests` and could be extended.

**State hygiene + performance (discovered during 2026-04-10 audit)**

16. **`AnimationController.reset()` is incomplete.**
    (`AnimationController.swift:899-904`.) It clears `previousSnapshots`,
    `activeAnimations`, `registeredAnimations`, and `lastTickResult`, but
    leaves nine other stored fields alive: `previousTreeRoot`,
    `previousParentByIdentity`, `previousChildIndexByIdentity`,
    `transitionsByIdentity`, `previousTransitionsByIdentity`,
    `pendingTransitionsByIdentity`, `removingIdentities`, and
    `previousIdentities`. Latent bug: if a renderer is reset while a
    removal animation is mid-flight, the stale `removingIdentities`
    entries will try to re-inject a subtree from the previous (now-stale)
    `previousTreeRoot` on the next tick. Fix is one line per field.

17. **Interpolation tick frames fire `didSet` hooks on every mutation.**
    `ResolvedNode.children` and `.layoutBehavior` carry `didSet` hooks
    (`RenderTreeAndSemanticsTypes.swift:195, :203`) that recompute
    `subtreeNodeCount`, `preferenceValues`, and `supportsRetainedReuse`.
    `AnimationController.applyValue` mutates `layoutBehavior` for
    offset/frame animations, and `applyTransitionModifiersRecursively`
    reassigns `node.children` on the removed subtree, so these
    recomputes run on every single tick frame for any animation that
    touches layout. For 30 FPS animation of a non-trivial subtree this
    is pure waste. Not a correctness bug, but worth fixing before
    landing items 12–13 (padding + flexibleFrame), which would make it
    the common path instead of the edge case.

18. **Post-graph-refactor verification has not been run.**
    Commit `d8d0a80` (2026-04-10) landed *after* the gallery demo
    verification the plan claims. The animation controller still
    operates on a local `ResolvedNode` from `viewGraph.snapshot()` and
    the `Boxed<DrawMetadata>` CoW wrapper protects the cached tree from
    tick-frame mutation, so nothing should be broken — but the full
    pipeline (`withAnimation { … }` → tick → raster bytes on the wire)
    has not been re-exercised against the new graph architecture. This
    is a verification gap, not a known regression.

### What's next — prioritized

**P0 — post-refactor verification**
- Item 18: re-run the gallery demo and the full animation test sweep
  against the post-`d8d0a80` graph architecture; confirm tick-frame
  mutation paths still allocate sanely and the Boxed CoW protects the
  cached tree in practice, not just in principle

**P0 — latent state hygiene**
- Item 16: extend `AnimationController.reset()` to clear all stored
  state (nine fields currently left alive)

**P0 — finish what's declared**
- Item 11: extract + apply `borderColor` animations
- Item 12: extract + apply `padding` edge animations
- Item 13: extract `.flexibleFrame` width/height
- Item 17: address the `didSet` recompute overhead on layout-touching
  tick frames *before* items 12–13 make it the common path

These are small finishes that turn public-looking API into real features.

**P0 — make custom transitions work**
- Item 4: walk the `Transition.body` output tree at registration time to
  extract opacity/offset effects for the current palette, OR expand the
  palette and re-wire `extractModifiers(from:)`

**P1 — animation features**
- Item 8: evaluate `CustomAnimation` conformances in the controller
- Item 9: honor `repeatCount` / `repeatForever` in `evaluate` (`speed`
  and `delay` already work)
- Item 10: insertion/removal retargeting from the displayed value

**P1 — API completeness**
- Item 6: `withAnimation` completion callbacks (batch ID + observer
  registry)
- Item 7: readable `Transaction.animation` via a concrete-animation
  registry

**P2 — architectural cleanup + fidelity**
- Item 1: removals as draw-only overlays with frozen placed bounds
- Item 2: per-node transient flag or separate overlay channel
- Item 3: per-cell blend target at raster time
- Item 5: composable nested offset transitions + offset on non-intrinsic
  roots (slide + frame/padding/offset compositions)
- Item 14: scheduler propagates active animation request on tick frames

**P2 — testing**
- Item 15: end-to-end integration test driving an animation through the
  real runtime and inspecting frame contents across the tick sequence

### SwiftUI parity items the current code *does not* attempt

The original plan explicitly deferred these; noting them here for
completeness so nobody gets surprised:

- `Binding.animation(_:)` — can be layered on top of the existing
  mutation-time plumbing without touching the controller
- Body-scoped `.animation(_:body:)` — uses the same transaction plumbing
- `contentTransition(_:)` — a distinct effect with its own runtime needs
- `phaseAnimator(_:content:animation:)` — requires a separate driving engine
  that sequences discrete phases on top of the base animation controller
- `keyframeAnimator(...)` — a different class of engine with its own
  timeline and value generation; explicitly not a reuse of
  `AnimationController`
- `matchedGeometryEffect` — requires cross-identity placement tracking that
  the current runtime doesn't carry
- Gradient / `TerminalChromeStyle` color interpolation
- 60fps mode (current target is 30fps via a fixed 33ms `frameInterval`)

---

## Goal

Add a faithful SwiftUI-shaped animation system to the terminal UI framework.
"Faithful" means matching SwiftUI's internal architecture — Transaction
propagation, Animatable/VectorArithmetic protocols, spring physics solver,
CustomAnimation protocol — for the subset of properties that can be meaningfully
represented in a terminal.

This is **not** API-surface mimicry. The internal model (resolve-once,
animate-through-pipeline, identity-keyed animation state) matches SwiftUI's
approach, scoped to terminal-representable properties.

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

SwiftUI's animation model is more constrained and more structured than it first
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

### 1. Keep SwiftUI's Transaction Model

The system should feel SwiftUI-shaped because it uses the same conceptual flow:

- authored API writes animation intent into the current transaction
- resolve propagates transaction intent through the tree
- animatable runtime surfaces decide whether to interpolate

We should not build a parallel "global animator" API that bypasses
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
resolve -> animate/sample -> measure -> place -> semantics -> draw -> raster -> commit
```

where "animate/sample" is a package-only controller that can:

- capture from/to snapshots for changed animatable properties
- inject interpolated values before measure (so layout sees intermediate state)
- overlay disappearing transition snapshots during draw
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
3. Evaluate animation curve -> progress (may overshoot for springs)
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
 2. -> animationController.processResolvedTree(resolved, transaction, timestamp)
 3. -> animationController.applyInterpolations(to: &resolved, at: timestamp)
 4. Measure (uses interpolated values — layout sees intermediate padding/size)
 5. Place (uses interpolated values — positions reflect intermediate state)
 6. Semantics (unchanged)
 7. Draw (uses interpolated values — colors/opacity are intermediate)
 8. Raster (unchanged)
 9. Commit (unchanged)
10. -> if tickResult.hasActiveAnimations:
       scheduler.requestDeadline(tickResult.nextDeadline)
```

Steps 2-3 are the only new insertions. The rest of the pipeline is untouched.

### Frame Cadence

- **30 FPS** target during active animation (`frameInterval = .milliseconds(33)`)
- Next deadline: `min(earliestAnimationEnd, now + frameInterval)` across all
  active animations
- When all animations complete, no more deadlines are requested -> runtime
  returns to idle event-driven mode (zero-cost when not animating)

### Interrupted Animation Retargeting

When a new animation starts for a key that already has an active animation:

1. Sample the currently displayed interpolated value
2. Start the new animation from that value (not from the original `from`)
3. This produces smooth retargeting — no visual discontinuity

### View Insertion/Removal Tracking

The controller tracks which identities are new (inserted) vs removed by
comparing the identity set between frames. This feeds into the transition
system (Layer 4).

Removed identities are retained as non-semantic visual overlays — they
participate only in draw/raster for the duration of the removal animation
(see Layer 4). They do not remain in the live semantic tree.

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

**Known limitation:** `TransitionModifiers` currently supports only opacity and
offset effects. Custom transitions that use other modifiers in their `body` will
have those effects silently ignored until the effect palette is expanded. This
is an intentional constraint — the internal runtime is phase-based and ready for
a wider effect set, but the renderer should only promise what it can deliver.

### Built-in Transitions

```swift
extension AnyTransition {
    /// Fades in/out
    public static var opacity: AnyTransition
    // willAppear: opacity = 0 -> 1
    // didDisappear: opacity = 1 -> 0

    /// Slides from a specific edge
    public static func move(edge: Edge) -> AnyTransition
    // willAppear: offset from edge -> origin
    // didDisappear: origin -> offset to edge

    /// Leading in, trailing out
    public static var slide: AnyTransition
    // asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))

    /// Fixed offset shift
    public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition
    // willAppear: offset(x,y) -> (0,0)
    // didDisappear: (0,0) -> offset(x,y)

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

Do not promise these yet:

- `.scale` — no sub-cell scaling
- rotation-based transitions
- blur-based transitions
- transform-heavy custom transitions

Those effects are natural in SwiftUI, but they are not a good first fit for a
cell rasterizer.

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

Transitions are driven by identity diffing from `ViewGraph`. The runtime
already knows which nodes appeared, disappeared, and preserved identity each
frame. That is the right place to decide whether a transition track starts.

**Insertion:**

1. A new identity appears in the resolved tree that wasn't in the previous frame
2. Controller checks if the node has a `.transition()` modifier
3. If yes: starts animation from `willAppear` phase modifiers -> `identity`
   phase modifiers
4. The transition's property deltas (opacity, offset) become the `from` values;
   identity values are the `to` values
5. Normal animation curve applies (from the active transaction)

**Removal:**

This is the most important transition design constraint in the repo:

**Removed views cannot remain in the live semantic tree just because they are
still animating visually.** Semantics, focus, tasks, lifecycle, and interaction
must already reflect removal. The animation controller retains only a
non-semantic visual snapshot.

1. An identity from the previous frame is absent in the new resolved tree
2. Controller checks if the node had a `.transition()` modifier
3. If yes: the controller retains a non-semantic visual snapshot at the node's
   last placed position
4. Starts animation from `identity` phase modifiers -> `didDisappear` phase
   modifiers
5. The snapshot participates only in draw/raster — not in layout, focus,
   semantics, or interaction
6. When the removal animation completes, the snapshot is purged

**Removal snapshot structure:**

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

### Existing Infrastructure

The repo already has wake-notification plumbing. No new stream or protocol is
needed — the existing mechanism must be extended to cover deadline-driven wakes.

**What exists today:**

- `WakeNotifyingFrameScheduling` protocol
  (`Sources/Core/Scheduler.swift:41`) with
  `setWakeHandler(_ handler: (@Sendable () -> Void)?)`.

- `FrameScheduler` conforms, storing the handler behind
  `wakeHandlerLock: OSAllocatedUnfairLock`.

- `requestInvalidation(of:)` and `requestExternalWake(reason:)` already call
  the wake handler after mutating pending state.

- The event pump (`RunLoop+EventPump.swift:113`) already wires the wake handler
  into the unified `AsyncStream<Void>` that input and signal tasks also yield
  into:

  ```swift
  wakeNotifyingScheduler?.setWakeHandler {
      continuation.yield()
  }
  ```

- The run loop (`RunLoop.swift:311`) already handles wake-without-events:

  ```swift
  guard !pendingEvents.isEmpty else {
      if scheduler.hasPendingFrame(at: .now()) {
          try renderPendingFrames(renderedFrames: &renderedFrames)
      }
      continue
  }
  ```

- `ScheduledFrame` already carries `triggeredDeadline`, `nextDeadline`, and
  `.deadline` as a `WakeCause`.

### The Gaps

**1. `requestDeadline` does not call the wake handler.**
(`Scheduler.swift:89-95`) It stores the deadline but never fires the handler.
If animation requests a future deadline and nothing else wakes the loop, the
loop sleeps through it.

**2. The coalesce path silently drops the wake.** When `requestDeadline` is
called with a deadline earlier than the existing one, it updates the stored
value but the early-return path (line 90-92) never notifies.

**3. No timed-wait for future deadlines.** Even if `requestDeadline` called the
wake handler immediately, the loop would wake, find
`hasPendingFrame(at: .now()) == false` (because the deadline is in the future),
and go back to sleep with no mechanism to wake again at the right time. The
event pump needs the ability to sleep until a specific deadline rather than
blocking indefinitely on the next yield.

### Required Changes

**Fix 1 — `requestDeadline` must notify:**

```swift
public func requestDeadline(_ deadline: MonotonicInstant) {
    if let existing = nextDeadline {
        nextDeadline = min(existing, deadline)
    } else {
        nextDeadline = deadline
    }
    wakeHandlerLock.withLockUnchecked { $0 }?()
}
```

**Fix 2 — Timed wake for future deadlines:**

The event pump or run loop must be able to sleep until the next deadline
instead of waiting indefinitely for a yield. Implementation options include a
delayed `Task.sleep`-then-yield in the scheduler, a timed `AsyncStream`
iteration in the event pump, or a racing `select`-style wait. The specific
mechanism should be chosen during implementation; the requirement is: when a
future deadline is the only pending wake source, the loop must wake at (or
shortly after) that instant without requiring external input or a second
`requestDeadline` call.

**Fix 3 — Carry animation request on `ScheduledFrame`:**

Add `package var animationRequest: AnimationRequest` to `ScheduledFrame` and
`FrameContext` so the animation controller can read the transaction's animation
intent.

### Deadline-Only Frame Reuse

A tick frame typically has no invalidated identities — only active animations
need re-rendering. Two changes needed:

1. **Resolve reuse with empty invalidation set:** Currently the reuse check
   requires `invalidatedIdentities` to be non-empty. For animation frames,
   empty means "nothing re-resolved, just re-interpolate." Fix: treat empty
   invalidation set as "nothing is dirty" -> full resolve reuse.

2. **Transaction reuse equivalence:** Use `isReuseEquivalent(to:)` instead of
   `==` for transaction comparison during resolve reuse. This ignores
   `debugSignature` changes that would otherwise defeat reuse.

Together, these mean animation tick frames are cheap: resolve is fully reused,
only the animation controller's interpolation + measure/place/draw/raster run.

### Animation Lifecycle

```
State change inside withAnimation
  -> invalidation with animation request
  -> scheduler.requestInvalidation() (calls wake handler)
  -> run loop wakes
  -> frame renders (resolve runs, animation controller captures from/to)
  -> animation controller returns nextDeadline
  -> scheduler.requestDeadline(nextDeadline) (calls wake handler)
  -> run loop sleeps until deadline
  -> run loop wakes at deadline
  -> frame renders (resolve REUSED, interpolation runs, measure/place/draw/raster)
  -> repeat until all animations complete
  -> no more deadlines requested
  -> run loop returns to idle (zero cost)
```

### Broader Fix

This wake integration also fixes existing gaps unrelated to animation:

- Lifecycle-driven invalidations (`onAppear` tasks that mutate state) now wake
  the loop
- External invalidation via `requestExternalWake()` already wakes (this is
  working today)
- Background `@Observable` changes propagate without waiting for input

---

## Future Compatibility

### 1. `Binding.animation(_:)`

The mutation-time transaction plumbing should be built so bindings can reuse it
without touching the animation controller.

### 2. Body-Scoped Animation APIs

SwiftUI now has body-scoped animation and transaction modifiers. The internal
transaction override helpers added for `.animation(_:value:)` should be reusable
for these later surfaces.

### 3. `phaseAnimator`

`phaseAnimator` should be implemented as a separate higher-level engine that:

- drives a phase sequence
- selects an `Animation?` per phase edge
- delegates actual interpolation to the same base animation controller

The current work should therefore avoid baking "exactly one from/to state" too
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
- keep controller-owned track groups explicit
- later add completion observers keyed by batch ID and completion criteria

---

## Implementation Phases

### Phase 0: Foundation Types + Reuse Semantics — ✅ shipped

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

**Key repo-specific fix:**

`ViewGraph.reusableSnapshot(...)` currently bails out when
`invalidatedIdentities` is empty. Animation frames and future timeline frames
need empty-invalidation reuse to be legal.

**Acceptance criteria:**

- Deadline frames with no invalidated identities reuse resolved subtrees
- Transaction debug signatures do not break reuse
- No public animation API exposed yet

### Phase 1: Scheduler Wake Integration — ✅ shipped

**Objectives:** Wire deadline wakes into the existing run loop infrastructure so
deadline-only frames can render without user input.

**Changes:**

1. Fix `requestDeadline` to call the wake handler after storing the deadline
2. Add timed-wait support so the loop sleeps until a future deadline rather
   than blocking indefinitely
3. Fix the deadline coalesce path to wake when a new deadline is earlier than
   the existing one
4. Preserve mouse coalescing for input batches
5. Carry animation request on `ScheduledFrame` and `FrameContext`

**Files:**

- `Sources/Core/Scheduler.swift`
- `Sources/Core/CommitAndFrameTypes.swift`
- `Sources/TerminalUI/RunLoop.swift`
- `Sources/TerminalUI/RunLoop+EventPump.swift`

**Key repo-specific constraint:**

The event pump already supports scheduler wake callbacks through
`WakeNotifyingFrameScheduling`; the missing pieces are (a) `requestDeadline`
calling the wake handler, (b) timed-wait for future deadlines, and (c) carrying
animation requests through scheduled frames.

**Acceptance criteria:**

- Scheduled deadlines trigger rendering without user input
- Background invalidations trigger rendering without input
- Existing input and signal behavior unchanged
- Lifecycle-driven invalidations wake the loop

### Phase 2: Animation Type System — ✅ shipped (CustomAnimation protocol public but evaluation is a stub — see Current Status § Gaps item 8)

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

### Phase 3: Mutation-Time Plumbing — ✅ shipped

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

### Phase 4: Public View API + Resolve-Time Modifiers — ✅ shipped (`Transaction.animation` getter returns nil — see Current Status § Gaps item 7)

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

### Phase 5: Animation Controller — ✅ shipped (declared animatable properties padding/borderColor/flexibleFrame not yet extracted — see Current Status § Gaps items 11–13)

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

### Phase 6: Transition System — ✅ shipped with caveats (removal overlays participate in layout rather than being draw-only; custom Transition authoring is limited to the built-in effect palette — see Current Status § Gaps items 1, 2, 4)

**Objectives:** Implement the modern `Transition` protocol and built-in
transitions.

**Changes:**

1. Add `Transition` protocol and `TransitionPhase`
2. Add `AnyTransition` with type erasure
3. Add built-in transitions: opacity, move, slide, offset, push, identity
4. Add combinators: `combined(with:)`, `asymmetric(insertion:removal:)`
5. Add `.transition()` view modifier
6. Add insertion/removal tracking to `AnimationController`
7. Add non-semantic removal snapshot support for exit animations

**Files:**

- New `Sources/View/Animation/Transition.swift`
- New `Sources/View/Animation/AnyTransition.swift`
- `Sources/TerminalUI/AnimationController.swift`

**Acceptance criteria:**

- New views fade in with `.transition(.opacity)`
- Removed views animate out as non-semantic overlays before being purged
- `.asymmetric()` uses different transitions for insertion and removal
- Custom transitions via the `Transition` protocol work
- Views without `.transition()` snap immediately
- Removal overlays do not participate in layout, focus, semantics, or
  interaction

### Phase 7: Testing + Docs — ⚠️ partial (unit tests shipped; integration test and doc updates still pending — see Current Status § Gaps item 15)

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
6. **Transitions** — insertion/removal lifecycle, non-semantic removal overlays,
   combinators, custom transitions
7. **Scheduler wake** — deadline wakes, background invalidation wakes,
   timed-wait for future deadlines
8. **Interactive runtime** — animation progresses over deadlines without input,
   stops scheduling after completion

**Regression cases worth pinning:**

- interrupted spring retargeting starts from the current displayed value
- explicit `.animation(nil, value:)` beats inherited animation
- transitions do not keep removed views interactive
- focus/selection routes reflect only the committed tree, not disappearing
  overlays
- damage tracking still converges to zero bytes after animation completes

**Suggested test files:**

- `Tests/CoreTests/Graph/ViewGraphTests.swift`
- New `Tests/CoreTests/AnimationSchedulerTests.swift`
- New `Tests/ViewTests/AnimationSurfaceTests.swift`
- New `Tests/TerminalUITests/AnimationSolverTests.swift`
- New `Tests/TerminalUITests/AnimationControllerTests.swift`
- New `Tests/TerminalUITests/TransitionTests.swift`
- New `Tests/TerminalUITests/AnimationPipelineTests.swift`

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
| `Sources/Core/Scheduler.swift` | Core | AnimationAwareInvalidating, requestDeadline wake fix, timed-wait support |
| `Sources/Core/StateContainer.swift` | Core | Animation-aware invalidation path |
| `Sources/Core/CommitAndFrameTypes.swift` | Core | Animation request on ScheduledFrame/FrameContext |
| `Sources/Core/CommitPlanner.swift` | Core | Reuse predicate for empty invalidation sets |
| `Sources/Core/Graph/ViewNode.swift` | Core | setStateSlotSilently for non-invalidating writes |
| `Sources/View/State.swift` | View | Propagate animation request from task-local |
| `Sources/View/Environment/FrameResolveState.swift` | View | Transaction transformation helpers |
| `Sources/TerminalUI/RunLoop.swift` | TerminalUI | Timed-wait for future deadlines |
| `Sources/TerminalUI/RunLoop+EventPump.swift` | TerminalUI | Timed-wait integration (if needed at pump level) |
| `Sources/TerminalUI/RunLoop+Rendering.swift` | TerminalUI | Animation controller integration |

---

## Rollout Recommendation

### PR 1: Foundation + Plumbing

- Phase 0 (foundation types, reuse semantics)
- Phase 1 (scheduler wake integration)
- Phase 2 (animation type system, solvers)
- Phase 3 (mutation-time plumbing)
- Tests for scheduling, reuse, wake behavior, and solver correctness

This PR proves the runtime can handle deadline wakes and animation-aware
transactions before any user-facing animation API depends on them.

### PR 2: Public API + Controller

- Phase 4 (public view API, resolve-time modifiers)
- Phase 5 (animation controller)
- Phase 7 partial (controller tests, interpolation tests)

### PR 3: Transitions

- Phase 6 (transition system)
- Phase 7 partial (transition tests, integration tests, docs)

This sequencing reduces integration risk: the runtime proves itself first, then
the animation engine, then the transition lifecycle.

---

## Risks and Mitigations

### Risk: Tick frames trigger too much work

**Mitigation:** Fix resolve reuse for empty invalidation sets. Ignore
debug-only transaction fields for reuse. Animation tick frames skip resolve
entirely — only interpolation + measure/place/draw/raster run.

### Risk: Scheduler wake integration changes runtime behavior broadly

**Mitigation:** The changes are minimal — `requestDeadline` calling the
existing wake handler, plus timed-wait support. Targeted tests for background
invalidation and input handling. Keep event coalescing for pointer streams.
Keep scheduler wake notifications package-only.

### Risk: Removal transitions fight lifecycle semantics

**Mitigation:** Render exiting nodes only as non-semantic visual overlays.
Keep lifecycle, tasks, focus, and interaction bound to the committed tree.

### Risk: Transition API shape outruns runtime reality

**Mitigation:** `AnyTransition` flattens custom transitions into a fixed
property-effect palette (`TransitionModifiers`: opacity + offset). The
`Transition` protocol is the correct authoring surface, but the renderer only
promises effects it can deliver. Document the limitation; expand the palette
incrementally.

### Risk: Terminal visuals make some SwiftUI transitions look bad

**Mitigation:** Constrain v1 built-ins to opacity, offset, push, slide, and
reveal. Explicitly defer scale, blur, and rotation-based transitions.

### Risk: Integer-stepped position animations look bad

**Mitigation:** 30fps cadence smooths small movements. Position animation is
opt-in (only happens when the user applies `.animation()` to position-affecting
properties). Most terminal UIs will primarily use color/opacity transitions.

### Risk: `.animation(_:value:)` needs stored previous values during resolve

**Mitigation:** Explicit non-invalidating state-store path for modifier
bookkeeping (`setStateSlotSilently`). Behavior stays local to the modifier.

### Risk: CustomAnimation protocol adds surface area too early

**Mitigation:** The protocol is needed for future `keyframeAnimator` and
`phaseAnimator` support. The internal spring and bezier animations are
implemented as `CustomAnimation` conformances, so the protocol is validated by
its own built-in usage.

---

## Documentation Updates

These doc updates should ship in the same changes that introduce the public
APIs:

- `docs/PUBLIC_API_INVENTORY.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/STATUS.md`
- `docs/ARCHITECTURE.md`
- `docs/RUNTIME.md`
- `docs/README.md`

---

## Future Work (Out of Scope)

These are enabled by this architecture but not part of this plan:

- `Binding.animation(_:)`
- public `Transaction` / `TransactionKey`
- body-scoped `.animation(_:body:)`
- `contentTransition(_:)`
- `phaseAnimator(_:content:animation:)`
- `keyframeAnimator(initialValue:repeating:content:keyframes:)`
- `matchedGeometryEffect`
- Gradient interpolation
- `TerminalChromeStyle` interpolation
- Navigation and scroll transitions
- 60fps mode (if terminal I/O permits)

---

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

- [docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md](docs/COLOR_ANIMATION_IMPLEMENTATION_PLAN.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/RUNTIME.md](docs/RUNTIME.md)
- [Sources/TerminalUI/TerminalUI.swift](Sources/TerminalUI/TerminalUI.swift)
- [Sources/TerminalUI/RunLoop+Rendering.swift](Sources/TerminalUI/RunLoop+Rendering.swift)
- [Sources/Core/Graph/ViewGraph.swift](Sources/Core/Graph/ViewGraph.swift)
- [Sources/Core/Scheduler.swift](Sources/Core/Scheduler.swift)

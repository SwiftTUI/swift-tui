# Animating Views

Animate state changes, insertions, and removals on the terminal's cell grid,
and keep every animation meaningful under reduce motion.

## Overview

SwiftTUI animates the way SwiftUI does: change state inside an animation
scope, and the framework interpolates every affected view from its old value
to its new one over time. Colors, offsets, positions, frame sizes, opacity,
and gradients all animate. Two terminal realities shape the result:

- The drawing unit is a character cell. Animated values interpolate
  continuously, but each drawn frame snaps to whole cells, so a short
  movement passes through only a few visible steps. Prefer longer durations
  and larger movements than you would use in a pixel UI so the interpolation
  reads clearly.
- Each frame rewrites only the cells whose contents changed. An animation
  that touches a small region stays cheap no matter how large the screen is.

One deliberate API divergence from SwiftUI: durations are Swift `Duration`
values, such as `.milliseconds(400)` or `.seconds(2)`, not floating-point
seconds.

The examples below use the composition basics from <doc:Authoring-Views>.

## Animate A State Change

Wrap a state write in ``withAnimation(_:_:)``. Every view the change touches
animates:

```swift
struct Pulse: View {
  @State private var isBlue = false

  var body: some View {
    VStack(spacing: 1) {
      Text("████████████████")
        .foregroundStyle(isBlue ? Color.blue : Color.red)
      Button("Animate") {
        withAnimation(.easeInOut(duration: .milliseconds(1500))) {
          isBlue.toggle()
        }
      }
    }
  }
}
```

``Animation`` offers timing curves — `.linear(duration:)`,
`.easeIn(duration:)`, `.easeOut(duration:)`, `.easeInOut(duration:)`, and a
cubic Bezier via `.timingCurve(_:_:_:_:duration:)` — and springs:
`.spring(duration:bounce:)`, the presets `.smooth`, `.snappy`, and `.bouncy`
(each also available as `(duration:extraBounce:)`), and the physics-based
`.interpolatingSpring(mass:stiffness:damping:initialVelocity:)`. The
`.default` animation is `.easeInOut`. Shape any curve with `.delay(_:)`,
`.speed(_:)`, `.repeatCount(_:autoreverses:)`, and
`.repeatForever(autoreverses:)`:

```swift
withAnimation(.spring(duration: .milliseconds(1500), bounce: 0.3)) {
  offsetX = 0
}
withAnimation(.bouncy) { offsetX = 15 }
withAnimation(.easeOut(duration: .seconds(1)).delay(.milliseconds(300))) {
  offsetX = 30
}
```

For a fully custom curve, conform a type to ``CustomAnimation`` and wrap it
with ``Animation/init(_:)``.

## Animate When A Value Changes

``View/animation(_:value:)`` attaches an implicit animation to one value.
Whenever `value` changes, the modified subtree animates; unrelated updates
pass through without animation. Passing `nil` suppresses any inherited
animation for that subtree when the value changes.

```swift
struct Meter: View {
  var level: Int

  var body: some View {
    Text(String(repeating: "█", count: level))
      .foregroundStyle(level > 6 ? Color.red : Color.green)
      .animation(.easeInOut, value: level)
  }
}
```

For finer control, ``withTransaction(_:_:)`` runs a body under a
``Transaction`` — set ``Transaction/disablesAnimations`` to suppress an
inherited animation for one write, or change one field with the key-path
form, `withTransaction(\.disablesAnimations, true) { count += 1 }`, which
keeps everything else about the enclosing scope. ``View/transaction(_:)``
edits the transaction seen by a subtree, ``View/transaction(value:_:)`` does
so only when a value changes (the whole-transaction sibling of
``View/animation(_:value:)``), and ``Binding/animation(_:)`` returns a
binding whose writes animate, so a control can animate the state it sets:
`Toggle("Wide", isOn: $wide.animation(.snappy))`.

The scoped forms narrow an animation to the modifiers inside a closure.
``View/animation(_:body:)`` hands the closure a ``PlaceholderContentView``
standing in for the modified view; modifiers applied to it animate, while
the view itself keeps the transaction in effect outside, so its own changes
snap:

```swift
Text(label)
  .foregroundStyle(color)              // snaps
  .animation(.easeInOut) { text in
    text.offset(x: offsetX, y: 0)      // animates whenever offsetX changes
  }
```

``View/transaction(_:body:)`` is the same shape with a transaction
transform, for example `{ $0.disablesAnimations = true }` to hold one
modifier still inside an animated scope.

## Transitions On Insertion And Removal

``View/transition(_:)`` describes how a view enters and leaves when a
condition adds or removes it. The change still needs an animation scope:

```swift
struct SavedBanner: View {
  @State private var show = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button(show ? "Hide" : "Show") {
        withAnimation(.easeInOut(duration: .milliseconds(1200))) {
          show.toggle()
        }
      }
      if show {
        Text("Saved!")
          .foregroundStyle(Color.cyan)
          .transition(.move(edge: .leading).combined(with: .opacity))
      }
    }
  }
}
```

``AnyTransition`` ships `.opacity`, `.move(edge:)`, `.slide`,
`.offset(x:y:)`, `.push(from:)`, and `.identity`. Compose them with
``AnyTransition/combined(with:)`` and, for different enter and exit
behavior, ``AnyTransition/asymmetric(insertion:removal:)``. The built-in
surface is intentionally opacity- and offset-based — scaling glyphs has no
meaning on a cell grid. While a removal transition plays, the departing view
is display-only: it no longer participates in layout, focus, or input.

## Run Code When An Animation Finishes

``withAnimation(_:completionCriteria:_:completion:)`` fires a closure after
the animations started in its scope finish:

```swift
Button("Run") {
  withAnimation(.easeInOut(duration: .milliseconds(1200))) {
    accent.toggle()
  } completion: {
    completedRuns += 1
  }
}
```

``AnimationCompletionCriteria`` picks the moment: `.logicallyComplete` (the
default) fires when the animation reaches its final value even if visual
overshoot is still settling, and `.removed` fires only after the animation
is fully removed. The completion closure is main-actor isolated and can
write `@State` directly. Under reduce motion the state change applies
instantly and the completion still fires, so completion-driven logic keeps
working when no motion is drawn.

A ``Transaction`` carries any number of completions, each with its own
criteria, through ``Transaction/addAnimationCompletion(criteria:_:)``; every
animation the scope starts reports to all of them:

```swift
var transaction = Transaction(animation: .bouncy)
transaction.addAnimationCompletion { logicalRuns += 1 }
transaction.addAnimationCompletion(criteria: .removed) { settledRuns += 1 }
withTransaction(transaction) { isExpanded.toggle() }
```

A binding that stores such a transaction (``Binding/transaction(_:)``) fires
the completions once per write made outside any enclosing `withAnimation`
or `withTransaction` scope; a write inside one never sees the stored
transaction. ``Animation/logicallyComplete(after:)`` moves the
`.logicallyComplete` instant earlier than the curve's end, so a spring's
settling tail does not hold up dependent logic while `.removed` still waits
for the visual to finish.

## Carry Gesture Velocity Into A Spring

Set ``Transaction/tracksVelocity`` on the writes a drag makes and the
spring that runs when the drag ends starts with the release velocity, so a
fast fling overshoots in the drag direction before settling:

```swift
struct Fling: View {
  @State private var offsetX = 0

  var body: some View {
    Text("◆")
      .offset(x: offsetX, y: 0)
      .gesture(
        DragGesture()
          .onChanged { value in
            withTransaction(\.tracksVelocity, true) {
              offsetX = Int(value.translation.width)
            }
          }
          .onEnded { _ in
            withAnimation(.spring(duration: .milliseconds(600), bounce: 0.2)) {
              offsetX = 0
            }
          }
      )
  }
}
```

The framework samples each tracked write with its timestamp over a short
window and seeds the next spring on the same value; two or more tracked
writes are needed before a release carries velocity. A spring retargeted
mid-flight carries its current velocity the same way. Both are behind the
`SWIFTTUI_ANIMATION_VELOCITY` kill switch (default on).

## Cycle Through Phases

``PhaseAnimator`` steps through a phase sequence, animating each step. With
a `trigger:` it runs one full cycle back to the first phase per trigger
change; without one it loops forever:

```swift
enum Bounce: Equatable, Sendable {
  case rest, up, down

  var offsetY: Int {
    switch self {
    case .rest: 0
    case .up: -1
    case .down: 1
    }
  }
}

struct BounceBadge: View {
  @State private var taps = 0

  var body: some View {
    VStack(spacing: 1) {
      Button("Bounce") { taps += 1 }
      PhaseAnimator([Bounce.rest, .up, .down], trigger: taps) { phase in
        Text("★").offset(x: 0, y: phase.offsetY)
      } animation: { _ in
        .spring(duration: .milliseconds(500), bounce: 0.4)
      }
    }
  }
}
```

## Animate Along Keyframes

``KeyframeAnimator`` interpolates a value along keyframe tracks and re-renders
its content with each sample, about twenty times a second. Each
``KeyframeTrack`` addresses one ``Animatable`` property of the value by key
path and lists its keyframes: ``LinearKeyframe`` eases to a value along a
``UnitCurve``, ``CubicKeyframe`` passes through values smoothly,
``SpringKeyframe`` moves with a ``Spring``, and ``MoveKeyframe`` jumps. Tracks
run independently; the animation lasts as long as the longest track and a
shorter track holds its last keyframe.

With a `trigger:`, the keyframes run once per trigger change, starting from
the current value if a run is still in flight:

```swift
struct Marker {
  var y = 0.0
  var opacity = 1.0
}

struct BounceStar: View {
  @State private var taps = 0

  var body: some View {
    VStack(spacing: 1) {
      Button("Bounce") { taps += 1 }
      KeyframeAnimator(initialValue: Marker(), trigger: taps) { marker in
        Text("★")
          .offset(x: 0, y: Int(marker.y.rounded()))
          .opacity(marker.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.y) {
          CubicKeyframe(-3, duration: .milliseconds(400))
          CubicKeyframe(1, duration: .milliseconds(300))
          SpringKeyframe(0, spring: .bouncy)
        }
        KeyframeTrack(\.opacity) {
          LinearKeyframe(0.4, duration: .milliseconds(200))
          LinearKeyframe(1, duration: .milliseconds(600), timingCurve: .easeOut)
        }
      }
    }
  }
}
```

`init(initialValue:repeating:content:keyframes:)` starts on appearance and,
by default, loops. When the value is itself ``Animatable``, list bare
keyframes and skip the track:

```swift
Text("▮")
  .keyframeAnimator(initialValue: 8.0, repeating: true) { bar, width in
    bar.frame(width: Int(width.rounded()))
  } keyframes: { _ in
    LinearKeyframe(24, duration: .milliseconds(800), timingCurve: .easeInOut)
    SpringKeyframe(8, spring: .snappy)
  }
```

The modifier forms hand the closure a ``PlaceholderContentView`` standing in
for the modified view. ``KeyframeTimeline`` is the same interpolation as a
plain value, `KeyframeTimeline(initialValue:content:)` with
``KeyframeTimeline/value(time:)`` and ``KeyframeTimeline/value(progress:)``,
for charts and tests. Two things to know:

- Keyframe content does not animate implicitly. The animator writes every
  sample under a transaction that disables animation, so a surrounding
  `withAnimation` scope or ``View/animation(_:value:)`` cannot layer a curve
  on top of the keyframe values, and transitions inside the content are
  suppressed. Keep the content cheap; it runs on every tick.
- `Int` properties step, because integer ``VectorArithmetic`` scaling
  truncates. Use `Double` tracks and round in the content closure.

Under reduce motion a trigger change writes the end value at once and
repeating mode rests at its initial value.

## Redraw On A Schedule

``TimelineView`` re-evaluates its content at instants supplied by a
``TimelineSchedule`` — `.periodic(from:by:)` for clocks and status lines,
`.animation` (about 20 updates per second) for shimmer or marquee effects —
with no hand-rolled tick loop. The updates stop automatically when the view
leaves the screen:

```swift
struct Shimmer: View {
  @State private var origin: MonotonicInstant = .now()

  var body: some View {
    TimelineView(.animation) { context in
      let t = origin.duration(to: context.instant).totalSeconds
      Text("Loading…")
        .foregroundStyle(
          Color.cyan.interpolated(to: .blue, progress: 0.5 + 0.5 * sin(t * 2))
        )
    }
  }
}
```

Use `.animation(minimumInterval:paused:)` to cap the cadence, or conform
your own type to ``TimelineSchedule`` for custom timing.

## Move A View Between Positions

``View/matchedGeometryEffect(id:in:properties:anchor:isSource:)`` identifies
the same logical view at two places in the tree, so swapping which branch
renders animates a slide between the two slots. Scope the shared ID with
``Namespace``:

```swift
struct HeroRow: View {
  @State private var onRight = false
  @Namespace private var heroSpace

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Swap") {
        withAnimation(.easeInOut(duration: .milliseconds(1500))) {
          onRight.toggle()
        }
      }
      HStack(spacing: 3) {
        if !onRight {
          Text("★ hero").matchedGeometryEffect(id: "hero", in: heroSpace)
          Text("(empty)")
        } else {
          Text("(empty)")
          Text("★ hero").matchedGeometryEffect(id: "hero", in: heroSpace)
        }
      }
    }
  }
}
```

`properties:` selects what interpolates. The default, `.frame`, slides the
view's `anchor:` point (`.center` by default) from the source's to the
destination's and resizes its bounds between the two sizes; `.position`
only slides, and `.size` only resizes in place around the anchor. Size
interpolates at the placed level, by bounds and clip rather than by
re-layout: the content lays out once at its destination size and is clipped
to the interpolated rect while the box grows or shrinks, so text never
re-wraps mid-animation, and every descendant whose bounds coincide with the
matched node's (a `.background`, an overlay, full-frame chrome) resizes with
it. Because the modifier tags its content, tag the outermost node whose
chrome should follow: `.background(...).border(...).matchedGeometryEffect(...)`,
not the reverse.

Add ``View/transition(_:)`` to both instances and the swap cross-fades along
one path: the departing instance's exit overlay travels to the destination
rect while its removal phase plays, and the arriving instance fades in from
the source rect while its insertion phase plays, so a change of colour or
content between the two reads as a blend rather than a cut.

```swift
Text("ONE").padding(3).background(Color.red)
  .transition(.opacity)
  .matchedGeometryEffect(id: "hero", in: heroSpace)
// … and in the other branch:
Text("TWO").background(Color.blue)
  .transition(.opacity)
  .matchedGeometryEffect(id: "hero", in: heroSpace)
```

Only registered transitions play — a swap without `.transition` cuts the
departing instance on the swap frame, as it does outside a match. An offset
transition (`.move`, `.offset`, `.slide`) composes additively with the
matched translation, as in SwiftUI when the transition is applied inside
the effect.

### Position a view onto another

An `isSource: false` instance that shares a key with a source on the same
screen is laid out at its own slot but *rendered* at the source's frame,
every frame and without an animation — SwiftUI's co-present rule. A badge
declared elsewhere in the tree sticks to the card it names, follows the card
when the card animates, and stays interactive where it is drawn:

```swift
VStack(alignment: .leading, spacing: 1) {
  HStack(spacing: 2) {
    if cardOnRight { Spacer() }
    Text("Card").padding(1).border()
      .matchedGeometryEffect(id: "card", in: heroSpace)
    if !cardOnRight { Spacer() }
  }
  Button("NEW") { … }
    .matchedGeometryEffect(id: "card", in: heroSpace, properties: .position,
                           anchor: .topTrailing, isSource: false)
}
```

`properties:` and `anchor:` on the non-source govern the adoption:
`.position` tracks the source's anchor point at the badge's own size (the
example pins the badge's top-trailing corner to the card's), `.size` takes
the source's size around the badge's own anchor, and `.frame` takes both.
Adoption needs exactly one source per key — with none the badge stays at
its slot, with several nothing moves. Layout is untouched (the badge's slot
still takes space; hide it with `.hidden()` or a zero frame if it should
not), reduce motion leaves adoption on, and when the source leaves inside
an animated transaction the badge slides home from where it was drawn.

## Reduce Motion

Users opt out of animation by launching your app with `--reduce-motion` or
`SWIFTTUI_REDUCE_MOTION=1` (the accessibility bundle `--accessible` /
`SWIFTTUI_ACCESSIBLE=1` implies it); see the
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables)
reference. Every built-in animation then renders in static form:

- Animated state changes apply instantly at their final value, and
  `withAnimation` completions still fire.
- ``PhaseAnimator`` rests at its first phase instead of cycling.
- ``TimelineView`` schedules run at a low cadence — the `.animation`
  schedule drops to about four updates per second, and periodic schedules
  fire at most once per second.

The same settled rendering applies when output is not an interactive
terminal (piped output, CI), keeping captured output deterministic. Read
``EnvironmentValues/accessibilityReduceMotion`` in your own views to swap
decorative motion for a static equivalent, exactly as the built-in views do.

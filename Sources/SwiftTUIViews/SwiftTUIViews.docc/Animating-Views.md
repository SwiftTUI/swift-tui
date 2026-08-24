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
inherited animation for one write. ``View/transaction(_:)`` edits the
transaction seen by a subtree, and ``Binding/animation(_:)`` returns a
binding whose writes animate, so a control can animate the state it sets:
`Toggle("Wide", isOn: $wide.animation(.snappy))`.

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

``View/matchedGeometryEffect(id:in:isSource:)`` identifies the same logical
view at two places in the tree, so swapping which branch renders animates a
slide between the two slots. Scope the shared ID with ``Namespace``:

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

The effect interpolates position only: a view whose size differs between
its two slots renders at its destination size while its origin slides.

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

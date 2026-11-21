# Animating Views

Animate state changes, insertions, and removals on the terminal's cell grid,
and keep every animation meaningful under reduce motion.

## Overview

SwiftTUI animates the way SwiftUI does: change state inside an animation
scope, and the framework interpolates every affected view from its old value
to its new one over time. Colors, offsets, positions, frame sizes, opacity,
and gradients all animate, and a `Text` can roll its digits when its string
changes. Two terminal realities shape the result:

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

A transaction modifier covers only the modifiers inside it. In
`content.transaction { $0.disablesAnimations = true }.opacity(level)`, the
opacity, like an `offset(x:y:)` or `clipShape(_:)` added after the
transaction modifier, animates under the transaction outside it, while
`content` snaps. Environment styles such as `foregroundStyle(_:)` added
after it are read by the content inside, so they follow the edited
transaction.

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

The scoped forms also include `foregroundStyle` and `tint` applied inside
the closure. These styles keep their scoped timing when they flow into the
wrapped view. A closer style modifier on the wrapped view still overrides
the inherited style and uses the outer transaction.

## Animate Your Own Views, Modifiers And Shapes

The framework interpolates the values it knows: an opacity, an offset, a
color. For anything else, conform a view, a view modifier or a shape to
`Animatable` and expose the value as `animatableData`. While an animation
runs, SwiftTUI evaluates the conformer again on every frame with interpolated
data, so anything you can compute from a number animates: how many
characters of a line are typed, which cells of a dissolve are shown, how far
a wedge has opened.

```swift
struct Typewriter: View, Animatable {
  var text: String
  var revealed: Double

  nonisolated var animatableData: Double {
    get { revealed }
    set { revealed = newValue }
  }

  var body: some View {
    Text(String(text.prefix(max(0, Int(revealed.rounded())))))
  }
}

struct Greeting: View {
  @State private var typed = false
  private let line = "Hello, terminal."

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Typewriter(text: line, revealed: typed ? Double(line.count) : 0)
      Button("Type") {
        withAnimation(.linear(duration: .milliseconds(1200))) { typed.toggle() }
      }
    }
  }
}
```

`body` runs once for each frame of the animation, with `revealed` moving
from its old value to its new one, and once more at exactly the new value.
The same holds for a modifier's `body(content:)`. ``withAnimation(_:_:)`` and
``View/animation(_:value:)`` both drive it, and the completion of
`withAnimation` fires when the value arrives. Use `AnimatablePair` to animate
two values together.

A few rules follow from how this works:

- **Declare `animatableData` as `nonisolated`.** A view and a modifier are
  main-actor types, and `Animatable` is not. The property reads and writes
  stored properties that are `Sendable`, as numbers are. See
  <doc:Coming-From-SwiftUI>.
- **A spring gives you values beyond your two ends.** A spring with bounce
  passes its target and comes back, so a value that goes from 0 to 1 is also
  1.08 for a few frames, and can drop below 0 on the way back. The body gets
  the values as they are. Clamp what must stay in range, as `Typewriter`
  does with `max` and `prefix`.
- **A change with no animation evaluates the body once.** A plain state
  write, `withAnimation(nil)`, a transaction that disables animations, and
  reduce motion all give the body its new value at once. Reduce motion that
  turns on while an animation runs ends it: the body gets its new value on
  that frame.
- **A new target in flight continues from the value on screen.** The
  animation toward the new target starts from the current sample, and a
  spring keeps its velocity.
- **When a view and the modifier on it both conform, they animate as one
  value.** `Gauge(level: x).modifier(Fade(progress: y))` is a
  ``ModifiedContent`` whose `animatableData` pairs the two.
- **A type with nothing to animate needs no `animatableData`.** A conformer
  whose data is `EmptyAnimatableData` gets the property for free and starts
  no animation.

A shape animates the same way. Conform it to `Animatable` and its
`path(in:)` is evaluated with interpolated data on every frame, wherever the
shape is used: in ``Shape/fill(_:)``, in a stroke, and in
``View/clipShape(_:)``. A trim or an inset of such a shape animates with it.

```swift
struct Wedge: Shape, Animatable {
  var open: Double

  nonisolated var animatableData: Double {
    get { open }
    set { open = newValue }
  }

  func path(in rect: Rect) -> Path {
    Path(Rect(
      origin: rect.origin,
      size: Size(width: rect.size.width * open * open, height: rect.size.height)))
  }
}

Text(report).clipShape(Wedge(open: isOpen ? 1 : 0))
```

A shape that does not conform keeps the earlier behavior: its path morphs
point by point between the old outline and the new one, when the two have
the same elements. `Wedge` without the conformance would open at a constant
rate. With it, the shape decides what each frame looks like.

The two forms cost differently, and on a terminal the difference shows:

- An `Animatable` view or modifier evaluates its body, and every view that
  body builds, about thirty times a second for the length of the animation.
  For a modifier that includes the content it wraps. Only that subtree runs
  again: the views beside it and above it are not evaluated. Keep such a
  view small, and put it on the content that changes rather than around a
  whole screen.
- An `Animatable` shape costs one call of `path(in:)` a frame and evaluates
  no view at all. So do the modifiers the framework interpolates itself,
  such as `opacity`, `offset`, `padding`, `frame`, and the styles.

Prefer an `Animatable` shape, or the interpolating modifiers, for large
content. A view inside the rows of a lazy stack is evaluated while the stack
lays out, and does not animate this way yet: it gets its new value at once.

## Transitions On Insertion And Removal

``View/transition(_:)-(AnyTransition)`` describes how a view enters and
leaves when a condition adds or removes it. The change still needs an
animation scope:

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

``AnyTransition`` ships `.opacity`, `.move(edge:)`, `.slide`, `.scale`,
`.scale(scale:anchor:)`, `.offset(x:y:)`, `.push(from:)`, and `.identity`.
An edge-relative move is measured against the moving view's own frame, as in
SwiftUI: a view entering from `.leading` starts exactly its own width to the
left of the slot it is about to occupy, so the travel reads as a slide inside
whatever clips it rather than a jump across the screen. A scale transition
preserves layout while its placed frame grows from or shrinks toward the
specified factor around its `UnitPoint` anchor; the parameterless form uses
SwiftUI's near-zero centered factor. On the cell grid the interpolated frame
rounds to whole cells and clips the content already laid out inside it.
Compose transitions with ``AnyTransition/combined(with:)`` and, for different
enter and exit behavior, ``AnyTransition/asymmetric(insertion:removal:)``.
While a removal transition plays, the departing view is display-only: it no
longer participates in layout, focus, or input.

Insertion and removal inside an animation scope use an opacity
transition when no explicit transition is attached. Use `.transition(.identity)`
to suppress that fade on the corresponding insertion or removal. Reinserting a
view while its removal fade is still running continues from its displayed
opacity, avoiding a flash back to full opacity.

### Give A Transition Its Own Animation

``AnyTransition/animation(_:)`` attaches an animation to a transition. That
animation replaces the animation of the surrounding scope for the transition,
on insertion and on removal:

```swift
Text("Saved!")
  .transition(.opacity.animation(.linear(duration: .milliseconds(400))))
```

The banner now fades for 400 ms whatever the duration of the `withAnimation`
scope is, and it also fades when the state changes with no animation scope at
all. Pass `nil` to make the transition snap inside an animated scope. A
`withAnimation` completion still waits for the transition's own animation.
`withAnimation(nil)` and Reduce Motion disable the transition as they disable
every animation. In ``AnyTransition/asymmetric(insertion:removal:)`` each side
keeps its own animation. In a combination, one animation drives the whole
transition: the first part that carries one decides.

### Write Your Own Transition

``Transition`` is the protocol behind the built-in transitions. A conforming
type returns a view from ``Transition/body(content:phase:)``. `content` stands
for the view the transition is attached to, and `phase` is a
``TransitionPhase``: ``TransitionPhase/willAppear`` before the view appears,
``TransitionPhase/identity`` while it is present, and
``TransitionPhase/didDisappear`` after it has gone.

```swift
struct Spotlight: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .padding(.horizontal, 1)
      .background(phase.isIdentity ? Color.blue : Color.gray)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

Text("Saved!").transition(Spotlight())
```

Pass the value to ``View/transition(_:)-(T)``, or erase it with
``AnyTransition/init(_:)`` to store it or to combine it with an
``AnyTransition``. The built-in transitions are types too
(``OpacityTransition``, ``MoveTransition``, ``ScaleTransition``,
``OffsetTransition``, ``PushTransition``, ``SlideTransition``,
``IdentityTransition`` and ``AsymmetricTransition``), with the static members
`.opacity`, `.move(edge:)`, `.scale`, `.scale(_:anchor:)`, `.offset(_:)`,
`.offset(x:y:)`, `.push(from:)`, `.slide` and `.identity`. Compose them with
``Transition/combined(with:)`` and ``Transition/animation(_:)``, and build on
one inside your own body with ``Transition/apply(content:phase:)``. A built-in
type behaves exactly as the matching ``AnyTransition`` value, so
`.transition(OpacityTransition())` and `.transition(.opacity)` are the same
transition. ``AnyTransition/modifier(active:identity:)`` makes a transition
from two values of one ``ViewModifier``; see "Drive A Transition With Your
Own Modifier" below.

Every modifier a body applies to `content` lands on a boundary around the
view, separate from the view's own modifiers. A body that places `content`
twice mounts the view twice, each with its own state.

When the view is inserted inside an animation scope, it appears through the
`willAppear` body and moves to the `identity` body. `Spotlight` fades in from
an opacity of zero while its background goes from gray to blue. The views on
screen are those of the `identity` body from the first frame. What animates
is the value of each modifier, from the value the `willAppear` body gives the
same view. These modifiers interpolate:

- `opacity`.
- `foregroundStyle` and `tint`, on the views of the body and on the views of
  the content that inherit them.
- A style given to `background`, to a shape's `fill` or `stroke`, and to
  `border`.
- `padding`, `offset`, `position` and `frame`.
- The path of a shape and of a `clipShape`, when both phases build the path
  from the same elements. This is how a wipe or an iris grows.
- The dash phase and the trim of a stroke.
- The string of a ``Text`` under a ``View/contentTransition(_:)``.

Any other difference between the two phases shows its `identity` value from
the first frame: a blend mode, a text attribute, a string with no content
transition, a modifier that only one phase applies. So keep the same views
and modifiers in every phase, and change their values. A view that only the
`identity` body has is present from the first frame. A view that only the
`willAppear` body has is never shown, and SwiftTUI reports a runtime issue
that names the transition.

A view the body adds, such as an overlay, mounts with the view the transition
is attached to. It has ordinary state, `onAppear` and tasks, stays while that
view is present, and leaves with it.

When the view is removed inside an animation scope, it leaves through the
`didDisappear` body. `Spotlight` fades out while its background goes from
blue to gray. The same modifiers interpolate, each from the value on screen,
so a removal that interrupts an insertion carries on from where the insertion
was, and a spring keeps its velocity. A value that does not interpolate shows
its `didDisappear` value from the first frame of the removal. The removal ends
when the last value it animates settles, so a body with nothing to interpolate
leaves at once.

SwiftTUI ends the life of the view when its removal starts. That frame
cancels its tasks, runs `onDisappear` and drops its state, where SwiftUI
waits for the removal to end. What you see afterwards is the view as it was
last drawn, inside the `didDisappear` body. Three things follow:

- The departing content does not change and is not laid out again. A body
  that gives it another size moves or crops it. An environment value the
  `didDisappear` body writes for `content`, such as `underline()`, does not
  reach it; SwiftTUI reports a runtime issue. `foregroundStyle` and `tint`
  are the exceptions, and they animate.
- The `didDisappear` body is drawn and not mounted. A view it adds shows its
  initial state and runs no `onAppear`, task or action. SwiftTUI reports a
  runtime issue when a view that only the `didDisappear` body has declares
  one.
- The body is laid out where the view was, under the size it had, and the
  views around it close up at once.

A body that places `content` inside a ``GeometryReader`` or a lazy stack
cannot be drawn around the departing view. Its removal plays without the
body, and SwiftTUI reports a runtime issue. Read the size in a `background`
or an `overlay` of `content` instead.

With no animation scope the view shows the `identity` body at once, and a
removed view leaves at once. ``Transition/animation(_:)`` gives the
transition an animation of its own. Reduce Motion disables a custom
transition as it disables the built-in ones, whatever
``TransitionProperties/hasMotion`` says.

Inside a body, ``Transition/apply(content:phase:)`` on ``OpacityTransition``
and ``OffsetTransition`` animates like the modifiers above. A move relative to
an edge and a scale act on the placed frame of the view, which a body cannot
express, so ``MoveTransition``, ``PushTransition``, ``SlideTransition`` and
``ScaleTransition`` report a runtime issue when a body applies them outside
the identity phase. Combine them with the body instead:

```swift
Text("Saved!")
  .transition(Spotlight().combined(with: .move(edge: .leading)))
```

### Drive A Transition With Your Own Modifier

The modifiers above interpolate one value each. For a transition that no
single value describes (a typewriter reveal, a dissolve, a set of blinds),
put a view modifier or a view that conforms to `Animatable` in the body. Its
`animatableData` animates as the modifier values do: on insertion from the
data the `willAppear` body gives it to the data of the `identity` body, and
on removal from the data on screen to the data of the `didDisappear` body.
Its body runs on every frame of the transition with the interpolated data.

``AnyTransition/modifier(active:identity:)`` is the short form for one
modifier. It applies `active` outside the `identity` phase and `identity` in
it:

```swift
struct Reveal: ViewModifier, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content
      .opacity(min(1, max(0, progress)))
      .padding(.leading, Int((4 * (1 - progress)).rounded()))
  }
}

Text("Saved!").transition(
  .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)))
```

`progress` runs from 0 to 1 while the view arrives and from 1 to 0 while it
leaves, and `body(content:)` runs for each frame with the value between. A
view the body adds can conform in the same way, and so can a modifier inside
your own ``Transition``:

```swift
struct RevealIn: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(Reveal(progress: phase.isIdentity ? 1 : 0))
  }
}
```

What to expect:

- **A spring takes `progress` outside 0…1.** A spring with bounce passes its
  target and comes back, so `progress` is above 1 for a few frames on the way
  in and below 0 on the way out. The body gets the values as they are. Clamp
  what must stay in range, as `Reveal` does for its opacity.
- **An interruption continues from the value on screen.** A removal during
  the insertion, and a re-insertion during the removal, carry `progress` on
  from its current value, and a spring keeps its velocity. Under a timing
  curve `progress` turns round on the next frame.
- **With no animation the body runs once.** A plain state write,
  `withAnimation(nil)` and Reduce Motion insert the view with the `identity`
  data and remove it at once. Reduce Motion that turns on in flight ends the
  transition on that frame.
- **On insertion the conformer is part of the live view.** It is mounted,
  and only its own subtree runs again for a frame; for a modifier that
  includes the content it wraps. On the frame of the insertion its body runs
  more than once: to build the view, and again with the data the transition
  starts from.
- **On removal SwiftTUI evaluates the `didDisappear` body again for each
  frame it draws.** That body is drawn and not mounted, as described above,
  and the content inside it is the view as it was last drawn. The frame on
  which the removal ends draws nothing, so the last data the conformer sees
  on the way out is the sample before the target.
- **Keep what the conformer writes apart from what else the transition
  animates.** A view has one opacity, one padding, one offset. When the
  conformer writes one of them and another part of the same transition
  animates the same property of the same view (a plain modifier whose value
  differs between phases, or the fade of `.combined(with: .opacity)`), the
  two do not compose: one of them takes its end value at once. Have the
  conformer write a different property, or wrap `content` in a stack and put
  one of the two on the stack.

- **A body that returns several views animates each conformer with the view
  that holds it.** Each of those views arrives and leaves through the
  transition by itself. A conformer animates when the view it wraps, or the
  view it is part of, plays the transition, under that view's transaction.
  Views of one body that leave together stay until its conformers have
  settled.

A shape that conforms to `Animatable` also animates inside a body, in a
`clipShape`, a `fill` or a `stroke`, and costs less: its `path(in:)` runs for
each frame and no view is evaluated. Prefer it where a shape can draw the
effect. A conformer the body places inside a ``GeometryReader`` or a lazy
stack is evaluated while that view lays out and gets its `identity` data at
once. So does a modifier that wraps several views and adds none of its own:
put such views in a stack and apply the modifier to the stack. See
<doc:Divergences-And-Gaps>.

## Roll A Number When It Changes

``View/contentTransition(_:)`` describes how a ``Text`` changes when its
string changes inside an animation scope.
``ContentTransition/numericText(countsDown:)`` rolls each changed digit
column through the intermediate digits, like a counter:

```swift
struct Odometer: View {
  @State private var count = 41

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(count)")
        .contentTransition(.numericText())
      Button("Add ten") {
        withAnimation(.easeInOut(duration: .milliseconds(800))) {
          count += 10
        }
      }
    }
  }
}
```

Pressing the button rolls the tens column `4 → 5` over the animation's
curve, dimming it at the midpoint, and leaves the units column untouched. A
digit that has further to go passes through every digit on the way
(`7 → 8 → 9 → 0`); ``ContentTransition/numericText(countsDown:)`` with
`countsDown: true` rolls the other way, and
``ContentTransition/numericText(value:)`` picks the direction from the sign
of the change in `value`. When the string changes length (`99 → 109`) the
text lays out at its new width at once and the added column fades in while
the shared columns roll. Columns that are not digits cross-fade, and
``ContentTransition/opacity`` cross-fades the whole string.

The roll is a drawing-time substitution on the new string's layout: the text
is measured once, at its new value, so a rolling number never re-wraps its
neighbours. Like a transition, it plays only inside an animation scope — an
unanimated write cuts to the new string, and so does
``ContentTransition/identity`` (the default). The modifier writes the
environment, so setting it on a container reaches every `Text` inside,
including `Label` and `Button` titles.

Numeric text also animates in viewport-realized `List` rows. Keep the row ID
stable so the runtime can compare the previous and current text presentation;
changing the ID creates a different row rather than a text update.

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

A scope that performs no state write still completes without waiting for an
unrelated frame. Completion-driven application logic therefore does not need
to force an invalidation just to finish an empty scope.

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

## March A Dashed Border

`StrokeStyle.dashPhase` is animatable. Changing it moves the dash pattern round
all four edges of a border, which is a marching-ants selection:

```swift
struct Selection: View {
  @State private var phase = 0.0

  var body: some View {
    Text("selected")
      .padding(1)
      .border(style: StrokeStyle(borderSet: .single, dash: [2, 1], dashPhase: phase))
      .onAppear {
        withAnimation(.linear(duration: .seconds(1)).repeatForever(autoreverses: false)) {
          phase = -3
        }
      }
  }
}
```

Animate the phase by a whole number of pattern lengths, here `2 + 1`, so the
loop has no jump. A positive phase starts further into the pattern, which moves
the dashes toward the top-leading corner. A negative phase marches them
clockwise. The phase never affects layout, so the border's content is not
measured again while it moves.

For two colors, stack two borders whose phases differ by one dash. The cells of
an unpainted segment are left alone, so the lower border shows through the gaps
of the upper one. The same style animates on `Rectangle().stroke(style:)` and on
a `Divider`.

## Chase A Light Round A Border

An `AngularGradient` paints by angle round a center, so on a border it colors
each cell by where it sits round the view. Animate its angle and the colors
chase round the edge:

```swift
struct Chase: View {
  @State private var turn = 0.0

  var body: some View {
    Text("working")
      .padding(1)
      .border(.conicGradient(colors: [.cyan, .blue, .cyan], angle: .degrees(turn)))
      .onAppear {
        withAnimation(.linear(duration: .seconds(2)).repeatForever(autoreverses: false)) {
          turn = 360
        }
      }
  }
}
```

Repeat the first color as the last, so the turn closes without a seam. Angles
follow SwiftUI: zero is at three o'clock and they increase clockwise. They are
measured on screen, so a quarter turn is a quarter turn whatever the view's
proportions in cells. The same paint animates on `Rectangle().stroke(_:)`.

## Draw An Outline On

A trim's interval is animatable on a stroke, so an outline can draw itself on:

```swift
struct Ring: View {
  @State private var progress = 0.0

  var body: some View {
    Circle()
      .trim(from: 0, to: progress)
      .stroke(.tint)
      .onAppear {
        withAnimation(.easeOut(duration: .seconds(1))) { progress = 1 }
      }
  }
}
```

Like a dash phase, the interval never affects layout.

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
``KeyframeTrack`` addresses one `Animatable` property of the value by key
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
by default, loops. When the value is itself `Animatable`, list bare
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
- `Int` properties step, because integer `VectorArithmetic` scaling
  truncates. Use `Double` tracks and round in the content closure.

Under reduce motion a trigger change writes the end value at once,
repeating mode rests at its initial value, and a `repeating: false` run
shows its end value from its first frame.

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

Add ``View/transition(_:)-(AnyTransition)`` to both instances and the swap
cross-fades along one path: the departing instance's exit overlay travels to the destination
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

The default opacity transition also applies to an animated matched-geometry
swap without an explicit `.transition`. Use `.transition(.identity)` when a
swap should have no fade. An offset transition (`.move`, `.offset`, `.slide`)
composes additively with the matched translation when applied inside the effect.

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

Nested matches compose in displayed coordinates, including when the source
itself is moving. Descendants inherit the displayed parent movement even when
their own animation is disabled; they do not receive that movement twice.

## Reduce Motion

Users opt out of animation by launching your app with `--reduce-motion` or
`SWIFTTUI_REDUCE_MOTION=1` (the accessibility bundle `--accessible` /
`SWIFTTUI_ACCESSIBLE=1` implies it); see the
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables)
reference. Every built-in animation then renders in static form:

- Animated state changes apply instantly at their final value, and
  `withAnimation` completions still fire.
- ``View/contentTransition(_:)`` cuts to the new string instead of rolling.
- ``PhaseAnimator`` rests at its first phase instead of cycling.
- A triggered or non-repeating ``KeyframeAnimator`` settles at its final
  value; a repeating animator rests at its initial value. Changing Reduce
  Motion during a run settles its value immediately, so restoring motion
  does not reveal a stale intermediate sample. A triggered phase animator
  similarly settles at its first phase.
- ``TimelineView`` schedules run at a low cadence — the `.animation`
  schedule holds its displayed instant while motion is reduced, and
  periodic schedules fire at most once per second.

The same settled rendering applies when output is not an interactive
terminal (piped output, CI), keeping captured output deterministic. Read
``EnvironmentValues/accessibilityReduceMotion`` in your own views to swap
decorative motion for a static equivalent, exactly as the built-in views do.

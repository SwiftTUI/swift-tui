# Driving The Run Loop

Step a scene on the real run loop, frame by frame, on a clock the test owns.

## Overview

A one-shot render shows one frame. It cannot show an animation in flight, a
transition from its first frame to its last, or what a key press does to
state. Those need the run loop: its scheduler arms the frames, its input
dispatch finds the handler, and its animation controller keeps the samples.

``RunLoopTestHarness`` builds a view on that run loop and gives the test its
clock. A frame is rendered when the test asks for one, at the instant the
test names. No call sleeps, and no call waits for a signal. The other
primitives in this package answer *how does a test wait?* The harness takes
the wait away.

The harness is part of the Testing SPI. A package outside swift-tui uses it
with `@_spi(Testing) import SwiftTUITestSupport` and public API alone.

## A First Test

The view below starts an 800 ms linear animation when it gets the `g` key.
`Bar` conforms to `Animatable`, so its body runs with the sample of every
frame.

```swift
import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

struct Meter: View {
  @State private var level = 0.0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("press g")
        .focusable()
        .onKeyPress(.character("g")) { _ in
          withAnimation(.linear(duration: .milliseconds(800))) { level = 1 }
          return .handled
        }
      Bar(level: level)
    }
    .frame(width: 40, height: 4, alignment: .topLeading)
  }
}

@MainActor
@Test func theBarFillsAlongALine() throws {
  let harness = try RunLoopTestHarness(size: CellSize(width: 40, height: 4)) {
    Meter()
  }
  defer { harness.shutdown() }

  // The frame of the key press: the animation's first frame.
  try harness.press(KeyPress(.character("g")))
  let start = harness.now

  // Every later frame of the animation, each at its own instant.
  while try harness.advanceToNextWake() {
    let progress = min(1, start.duration(to: harness.now) / .milliseconds(800))
    #expect(harness.lines[1] == Bar.text(at: progress))
  }
  #expect(harness.now == start.advanced(by: .milliseconds(825)))
}
```

The frame fills the surface from its top leading corner, so the bar is on
the second row of ``RunLoopTestHarness/lines``. The loop runs 25 times. The
run loop renders an animation every 33 ms, so the frames stand at 33 ms,
66 ms and so on, and the first frame past the 800 ms, at 825 ms, shows the
end value. After it no frame is armed and
``RunLoopTestHarness/advanceToNextWake()`` returns `false`.

## What The Harness Runs

The run loop, the renderer, the frame scheduler, the focus tracker and the
registries are the ones an interactive session uses. Selective evaluation is
on after the first frame, as in a session. Each call renders on the run
loop's synchronous frame driver, inside the registration scope a running
session has, so a `withAnimation` in a button action or a key handler
registers its animation and its completion.

The surface records what the run loop presents.
``RunLoopTestHarness/frame`` is the last presented `RasterSurface`, with its
cells and style runs. ``RunLoopTestHarness/lines`` is its text, and
``RunLoopTestHarness/frameCount`` counts the frames, the first one included.
The surface reports a Unicode terminal with the fallback appearance. It has
no clipboard, and it declines a link the scene opens, so a test starts no
program.

## Moving Time

The clock starts at `MonotonicInstant.zero`, the instant of the first frame.
It moves only in two calls.

- ``RunLoopTestHarness/advanceToNextWake()`` moves it to
  ``RunLoopTestHarness/nextWake``, the next instant at which the scheduler
  has a frame armed, and renders that frame. Use it to look at every frame.
- ``RunLoopTestHarness/advance(by:)`` moves it by a duration and renders
  every frame that falls due on the way, each at its own instant. A deadline
  exactly at the end of the interval is rendered. The clock then stands at
  the end of the interval, whether or not a frame was rendered there. It
  returns the number of frames presented.

A frame deadline is not only an animation's next tick. A long press arms its
timer as one, and so does a scroll that is coming to rest.

``RunLoopTestHarness/nextWake`` reports what the scheduler has armed,
whatever armed it. A scene at rest has nothing armed and it is `nil`, with a
view under `.transition(_:)` in the scene as without one.

The frame that draws the end state of a transition is not always its last
frame. An insertion that moves or scales the view, every removal and a
matched-geometry travel arm one more frame after it. That frame draws the
same picture and arms nothing. So do not expect
``RunLoopTestHarness/nextWake`` to be `nil` after the length of the curve.
To run a transition to its end, step until
``RunLoopTestHarness/advanceToNextWake()`` returns `false`.

A scene with an animation that repeats forever always has a frame armed.
Step such a scene a known number of times, or by a duration, and not until
nothing is armed.

To put a frame on a round number, choose a duration that is a multiple of
33 ms. A 1320 ms animation is forty frames long, and its quarters end on
frames 10, 20, 30 and 40.

## Sending Input

``RunLoopTestHarness/press(_:)``, ``RunLoopTestHarness/send(_:)``,
``RunLoopTestHarness/paste(_:)`` and ``RunLoopTestHarness/resize(to:)``
deliver an event through the run loop's input dispatch, at the current
instant, and render the frame it causes. They do not move the clock.

- A key goes to key commands, to the handlers of the focused view, then to
  focus traversal and activation. The first focusable view has the focus
  after the first frame.
- A mouse event gets the harness's instant as its timestamp. A click is a
  `.down` and an `.up`, sent in two calls.
- A paste goes to the focused view, or to a drop destination when the text
  is a list of paths.
- A resize changes the size of the surface and delivers the window-change
  signal a terminal sends.

## Changes Made Outside The Run Loop

A test can hold a `Binding` the scene handed it, or an observable model the
scene reads, and change it between calls. The change asks for a frame, and
nothing is presented until the test calls ``RunLoopTestHarness/render()``:

```swift
model.count = 5
#expect(harness.nextWake == harness.now)  // a frame is due
try harness.render()
#expect(harness.lines[0] == "count 5")
```

When no frame is due, `render()` invalidates the root first. It always
presents a frame, and that frame shows a change the view graph cannot
observe, such as a plain property of a class.

A `withAnimation` round such a change in the test body animates it. Its
completion is not called: a completion is registered with the run loop
that is in scope, and outside a call of the harness none is. Start an
animation whose completion matters from the scene, as the first test does.

## Ending A Test

Call ``RunLoopTestHarness/shutdown()`` when the test is done, in a `defer`.
It cancels the tasks the scene started. After it the presented frame stays
readable and a call that renders throws. Calling it twice is harmless, and
a harness that is released without it releases the run loop, which cancels
the tasks too.

## Limits

- Every frame is rendered by the synchronous frame driver. The asynchronous
  render modes are not driven.
- A `.task` starts when its view appears, and its body runs when the test
  suspends. The harness neither runs task work nor waits for it. Wait for a
  task with ``AsyncEvent`` or a condition signal, then render.
- A view that reads the wall clock itself, such as `TimelineView`, does not
  follow the virtual clock.
- The harness is not a session that can end. The framework's exit keys are
  off, and the `requestTermination` action reports `false`.
- A call made from a callback that runs during another call of the same
  harness throws. So does a call on a scene that changes its own state on
  every frame, after 16 render passes at one instant.

The framework's own tests of the harness are in
`Tests/SwiftTUITests/RunLoopTestHarnessTests.swift`. The tests in
`Scripts/data/transition-consumer/Tests/TransitionConsumerTests/DemonstrationRunLoopTests.swift`
use it from a package outside swift-tui.

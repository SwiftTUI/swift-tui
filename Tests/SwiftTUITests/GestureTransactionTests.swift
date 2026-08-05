import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage-0 pins for the gesture-transaction surface (org plan
/// 2026-08-04-002 §3, verified against real SwiftUI 2026-08-05):
///
/// - A transaction mutated inside a `Gesture.updating(_:body:)` body governs
///   the during-gesture `@GestureState` writes.
/// - The end-of-gesture reset is governed solely by `GestureState`'s reset
///   transaction; without one the reset snaps — the body transaction does
///   NOT carry over to the reset (SwiftUI probe, reset-body-only variant).
/// - SwiftUI hands the body an inert transaction: no animation preset and
///   `isContinuous` NOT auto-set (probe, continuous variant).
@MainActor
@Suite("Gesture transactions")
struct GestureTransactionTests {
  @Test("a body-set animation governs during-gesture @GestureState writes")
  func bodyTransactionAnimatesDuringGestureWrites() throws {
    let animation = Animation.linear(duration: .milliseconds(400))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionDuring"),
      size: .init(width: 24, height: 4)
    ) {
      DragOpacityProbe(bodyAnimation: animation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    let start = try #require(harness.point(forText: "pin"))
    try withAnimationSinks(controller) {
      _ = try harness.sendMouse(.down(.primary), at: start)
      _ = try harness.sendMouse(
        .dragged(.primary),
        at: Point(x: start.x + 6, y: start.y)
      )
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(animation.animationBox),
      """
      the updating body set an animation on its inout Transaction, so the \
      gesture-state write it scoped must animate — a missing box means the \
      body transaction was discarded (the pre-plan stand-in behavior)
      """
    )

    // Cleanup: release outside the sink scope; the reset (no reset
    // transaction here) must not start anything new either way.
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))
  }

  @Test("the body receives an inert transaction — no preset animation, not continuous")
  func bodyTransactionArrivesInert() throws {
    let observedContinuity = LockedBox<[Bool]>([])
    let observedAnimations = LockedBox<[Bool]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionInert"),
      size: .init(width: 24, height: 4)
    ) {
      InertTransactionProbe(
        observedContinuity: observedContinuity,
        observedAnimations: observedAnimations
      )
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    let start = try #require(harness.point(forText: "pin"))
    try withAnimationSinks(controller) {
      _ = try harness.sendMouse(.down(.primary), at: start)
      _ = try harness.sendMouse(
        .dragged(.primary),
        at: Point(x: start.x + 6, y: start.y)
      )
      _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))
    }

    #expect(!observedContinuity.value.isEmpty, "the updater must have run")
    // SwiftUI probe (2026-08-05): drag updating bodies see
    // isContinuous == false and no preset animation.
    #expect(observedContinuity.value.allSatisfy { $0 == false })
    #expect(observedAnimations.value.allSatisfy { $0 == false })
  }

  @Test("the GestureState reset transaction animates the end-of-gesture reset")
  func resetTransactionGovernsTerminalReset() throws {
    let resetAnimation = Animation.linear(duration: .milliseconds(350))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionReset"),
      size: .init(width: 24, height: 4)
    ) {
      ResetTransactionProbe(resetAnimation: resetAnimation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    let start = try #require(harness.point(forText: "pin"))
    try withAnimationSinks(controller) {
      _ = try harness.sendMouse(.down(.primary), at: start)
      _ = try harness.sendMouse(
        .dragged(.primary),
        at: Point(x: start.x + 6, y: start.y)
      )
      #expect(
        controller.activeAnimationCount == 0,
        "during-gesture writes snap when the body leaves the transaction alone"
      )
      _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(resetAnimation.animationBox),
      "the terminal-phase seed reset must animate with the reset transaction"
    )
  }

  @Test("the reset closure sees the current value and governs the reset")
  func resetClosureGovernsTerminalReset() throws {
    let resetAnimation = Animation.linear(duration: .milliseconds(350))
    let observedValues = LockedBox<[Double]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionResetClosure"),
      size: .init(width: 24, height: 4)
    ) {
      ResetClosureProbe(
        resetAnimation: resetAnimation,
        observedValues: observedValues
      )
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    let start = try #require(harness.point(forText: "pin"))
    try withAnimationSinks(controller) {
      _ = try harness.sendMouse(.down(.primary), at: start)
      _ = try harness.sendMouse(
        .dragged(.primary),
        at: Point(x: start.x + 6, y: start.y)
      )
      _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(resetAnimation.animationBox),
      "the reset closure's transaction edit must govern the seed reset"
    )
    #expect(
      observedValues.value.contains { $0 != 0 },
      "the reset closure receives the value being reset, not the seed"
    )
  }

  @Test("the plain reset path never animates, reset transaction or not")
  func plainResetPathNeverAnimates() throws {
    // `UpdatingDecorator.tearDown` and the registry's subtree drain both
    // reset through `GestureStateBox.resetToSeed()` — the unscoped path.
    // Pin the pair directly on a live-bound box: the plain path must not
    // animate even when a reset transaction was authored, while the
    // end-of-gesture path (`resetToSeedApplyingResetTransaction`) must.
    let resetAnimation = Animation.linear(duration: .milliseconds(350))
    let captured = CapturedGestureStateBox()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionTeardown"),
      size: .init(width: 32, height: 6)
    ) {
      TeardownResetProbe(resetAnimation: resetAnimation, captured: captured)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    let box = try #require(captured.box)
    let snapshot = try #require(captured.snapshot)

    try withAnimationSinks(controller) {
      withImperativeAuthoringContext(snapshot) {
        box.setValue(Vector(dx: 6, dy: 0))
      }
      _ = try harness.render()
      #expect(harness.frame.contains("dragging"), "the slot write must land")

      // Resolve-time path (teardown / registry drain): never animates.
      withImperativeAuthoringContext(snapshot) {
        box.resetToSeed()
      }
      _ = try harness.render()
      #expect(!harness.frame.contains("dragging"), "the plain reset must land")
      #expect(
        controller.activeAnimationCount == 0,
        "the plain reset path must ignore the authored reset transaction"
      )

      // End-of-gesture path: the same box, the same reset transaction —
      // this one animates.
      withImperativeAuthoringContext(snapshot) {
        box.setValue(Vector(dx: 6, dy: 0))
      }
      _ = try harness.render()
      withImperativeAuthoringContext(snapshot) {
        box.resetToSeedApplyingResetTransaction()
      }
      _ = try harness.render()
      #expect(
        controller.debugStateSnapshot().activeAnimationBoxesByKey.values
          .contains(resetAnimation.animationBox),
        "the end-of-gesture reset path must apply the authored reset transaction"
      )
    }
  }

  @Test("without a reset transaction the end-of-gesture reset snaps")
  func resetWithoutResetTransactionSnaps() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureTransactionSnapReset"),
      size: .init(width: 24, height: 4)
    ) {
      DragOpacityProbe(bodyAnimation: nil)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    let start = try #require(harness.point(forText: "pin"))
    try withAnimationSinks(controller) {
      _ = try harness.sendMouse(.down(.primary), at: start)
      _ = try harness.sendMouse(
        .dragged(.primary),
        at: Point(x: start.x + 6, y: start.y)
      )
      #expect(
        controller.activeAnimationCount == 0,
        "an untouched body transaction must not animate during-gesture writes"
      )
      _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))
      #expect(
        controller.activeAnimationCount == 0,
        """
        no reset transaction exists, so the seed reset must snap — the SwiftUI \
        probe pinned that the body transaction does not govern the reset
        """
      )
    }
  }
}

private struct InertTransactionProbe: View {
  @GestureState var drag = Vector(dx: 0, dy: 0)
  let observedContinuity: LockedBox<[Bool]>
  let observedAnimations: LockedBox<[Bool]>

  var body: some View {
    Text("pin")
      .opacity(drag.dx == 0 ? 1.0 : 0.25)
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($drag) { value, state, transaction in
            observedContinuity.withLock { $0.append(transaction.isContinuous) }
            observedAnimations.withLock { $0.append(transaction.animation != nil) }
            state = value.translation
          }
      )
  }
}

private struct ResetTransactionProbe: View {
  @GestureState var drag: Vector
  init(resetAnimation: Animation) {
    var transaction = Transaction()
    transaction.animation = resetAnimation
    _drag = GestureState(initialValue: Vector(dx: 0, dy: 0), resetTransaction: transaction)
  }

  var body: some View {
    Text("pin")
      .opacity(drag.dx == 0 ? 1.0 : 0.25)
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($drag) { value, state, _ in
            state = value.translation
          }
      )
  }
}

private struct ResetClosureProbe: View {
  @GestureState var drag: Vector
  init(resetAnimation: Animation, observedValues: LockedBox<[Double]>) {
    _drag = GestureState(
      initialValue: Vector(dx: 0, dy: 0),
      reset: { value, transaction in
        observedValues.withLock { $0.append(value.dx) }
        transaction.animation = resetAnimation
      }
    )
  }

  var body: some View {
    Text("pin")
      .opacity(drag.dx == 0 ? 1.0 : 0.25)
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($drag) { value, state, _ in
            state = value.translation
          }
      )
  }
}

@MainActor
private final class CapturedGestureStateBox {
  var box: GestureStateBox<Vector>?
  var snapshot: ImperativeAuthoringContextSnapshot?
}

private struct TeardownResetProbe: View {
  @GestureState var drag: Vector
  let captured: CapturedGestureStateBox

  init(resetAnimation: Animation, captured: CapturedGestureStateBox) {
    var transaction = Transaction()
    transaction.animation = resetAnimation
    _drag = GestureState(initialValue: Vector(dx: 0, dy: 0), resetTransaction: transaction)
    self.captured = captured
  }

  var body: some View {
    // Capture what a recognizer captures: the box behind the projected
    // binding and the authoring snapshot its callbacks run under.
    captured.box = $drag.box
    captured.snapshot = currentImperativeAuthoringContextSnapshot()
    return Text(drag.dx == 0 ? "idle" : "dragging")
      .opacity(drag.dx == 0 ? 1.0 : 0.25)
  }
}

/// A pin whose opacity tracks the drag so gesture-state writes produce an
/// animatable change the controller can observe.
private struct DragOpacityProbe: View {
  @GestureState var drag = Vector(dx: 0, dy: 0)
  let bodyAnimation: Animation?

  var body: some View {
    Text("pin")
      .opacity(drag.dx == 0 ? 1.0 : 0.25)
      .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($drag) { value, state, transaction in
            if let bodyAnimation {
              transaction.animation = bodyAnimation
            }
            state = value.translation
          }
      )
  }
}

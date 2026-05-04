import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct ExclusiveGestureTests {
  private func identity(_ s: String) -> Identity {
    Identity(components: [IdentityComponent(rawValue: s)])
  }
  private func ctx() -> GestureRecognizerBuildContext {
    .init(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { _ in }
    )
  }
  private func event(
    _ kind: LocalPointerEvent.Kind,
    at location: Point = .zero
  ) -> LocalPointerEvent {
    LocalPointerEvent(
      kind: kind,
      location: location,
      targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1))
    )
  }

  @Test("Double-tap wins when first is double-tap and second is single-tap")
  func doubleWinsOverSingle() {
    var singleCount = 0
    var doubleCount = 0
    let g = TapGesture(count: 2).onEnded { doubleCount += 1 }
      .exclusively(before: TapGesture().onEnded { singleCount += 1 })
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(doubleCount == 1)
    #expect(singleCount == 0)
  }

  @Test("Second wins when first fails on movement")
  func secondWinsAfterFirstFails() {
    var firstCount = 0
    var secondCount = 0
    // Both are TapGesture, but force first to fail via a drag event.
    let g = TapGesture().onEnded { firstCount += 1 }
      .exclusively(before: TapGesture().onEnded { secondCount += 1 })
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    // A drag kills the first's completion (moves outside target), but
    // a second clean down+up tries the second.
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 100, y: 100)))
    // First should have transitioned to .failed. Now feed clean events
    // — second should recognize.
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    // First .failed before it could end; second recognizes the
    // clean down+up as a tap.
    #expect(firstCount == 0)
    #expect(secondCount == 1)
  }

  @Test("ExclusiveGesture gates second deadline on first phase")
  func gateSecondDeadlineOnFirstPhase() {
    let t0 = MonotonicInstant.now()
    let firstDeadline = t0.advanced(by: .milliseconds(100))
    let secondDeadline = t0.advanced(by: .milliseconds(500))

    // Create recognizers manually to control deadline scheduling.
    let firstRec = AnyGestureRecognizer(
      LongPressGestureRecognizer(
        minimumDuration: .milliseconds(100),
        maximumDistance: 0,
        requestDeadline: { _ in }
      )
    )
    let secondRec = AnyGestureRecognizer(
      LongPressGestureRecognizer(
        minimumDuration: .milliseconds(500),
        maximumDistance: 0,
        requestDeadline: { _ in }
      )
    )
    let exclusive = ExclusiveGestureRecognizer<Bool>(
      first: firstRec,
      second: secondRec
    )

    // Simulate both recognizers receiving down events with timestamp t0.
    let downEvent = LocalPointerEvent(
      kind: .down(.primary),
      location: .zero,
      targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
      timestamp: t0
    )
    _ = firstRec.handle(event: downEvent)
    _ = secondRec.handle(event: downEvent)

    // At t0 + 100ms, first's deadline fires.
    let firstFired = exclusive.handleDeadline(at: firstDeadline)
    #expect(firstFired == true)
    #expect(firstRec.phase == .ended)

    // At t0 + 500ms, second's deadline would fire, but first already ended.
    // With the fix, second should NOT process this deadline.
    let secondFired = exclusive.handleDeadline(at: secondDeadline)
    #expect(secondFired == false)
    // Second's recognizer should still be in .possible (it never transitioned).
    #expect(secondRec.phase == .possible)
  }
}

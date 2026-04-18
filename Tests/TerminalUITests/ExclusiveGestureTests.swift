import Foundation
import Testing

@testable import Core
@testable import View

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
      targetRect: Rect(origin: .zero, size: Size(width: 4, height: 1))
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
}

import Foundation
import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct LongPressGestureTests {
  private func identity(_ s: String) -> Identity {
    Identity(components: [IdentityComponent(rawValue: s)])
  }

  @Test("Fires .ended(true) when held past minimumDuration")
  func firesOnHold() throws {
    var scheduledDeadline: MonotonicInstant?
    let ctx = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { scheduledDeadline = $0 }
    )
    let g = LongPressGesture(minimumDuration: .milliseconds(50))
    let rec = g._makeRecognizer(context: ctx)
    let t0 = MonotonicInstant.now()
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: .zero,
        targetRect: Rect(origin: .zero, size: Size(width: 4, height: 1)),
        timestamp: t0
      ))
    let scheduled = try #require(scheduledDeadline)
    _ = rec.handleDeadline(at: scheduled)
    #expect(rec.phase == .ended)
    let value: Bool? = rec.currentValue()
    #expect(value == true)
  }

  @Test("Fails when pointer moves beyond maximumDistance before deadline")
  func failsOnMovement() {
    let ctx = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { _ in }
    )
    let g = LongPressGesture(minimumDuration: .seconds(1), maximumDistance: 0)
    let rec = g._makeRecognizer(context: ctx)
    let rect = Rect(origin: .zero, size: Size(width: 4, height: 4))
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: Point(x: 1, y: 1),
        targetRect: rect
      ))
    _ = rec.handle(
      event: .init(
        kind: .dragged(.primary),
        location: Point(x: 3, y: 3),
        targetRect: rect
      ))
    #expect(rec.phase == .failed)
  }

  @Test("Fails when pointer lifts before deadline")
  func failsOnEarlyRelease() {
    let ctx = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { _ in }
    )
    let g = LongPressGesture(minimumDuration: .seconds(1))
    let rec = g._makeRecognizer(context: ctx)
    let rect = Rect(origin: .zero, size: Size(width: 4, height: 1))
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: .zero,
        targetRect: rect
      ))
    _ = rec.handle(
      event: .init(
        kind: .up(.primary),
        location: .zero,
        targetRect: rect
      ))
    #expect(rec.phase == .failed)
  }
}

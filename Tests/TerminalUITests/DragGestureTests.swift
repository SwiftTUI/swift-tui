import Foundation
import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct DragGestureTests {
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
    at point: Point,
    at time: MonotonicInstant = .now()
  ) -> LocalPointerEvent {
    .init(
      kind: kind,
      location: point,
      targetRect: CellRect(origin: .zero, size: CellSize(width: 20, height: 5)),
      timestamp: time
    )
  }

  @Test("DragGesture values track translation and startLocation")
  func tracksTranslation() throws {
    let rec = DragGesture()._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 2, y: 1)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 5, y: 3)))
    let value: DragGesture.Value? = rec.currentValue()
    let v = try #require(value)
    #expect(v.startLocation == Point(x: 2, y: 1))
    #expect(v.location == Point(x: 5, y: 3))
    #expect(v.translation == Size(width: 3, height: 2))
  }

  @Test("DragGesture ends on .up")
  func endsOnUp() {
    let rec = DragGesture()._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 0, y: 0)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 3, y: 0)))
    _ = rec.handle(event: event(.up(.primary), at: Point(x: 3, y: 0)))
    #expect(rec.phase == .ended)
  }

  @Test("minimumDistance suppresses recognition until threshold")
  func minDistanceThreshold() {
    let rec = DragGesture(minimumDistance: 3)._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 0, y: 0)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 1, y: 0)))
    #expect(rec.phase == .possible)
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 4, y: 0)))
    #expect(rec.phase == .changed || rec.phase == .began)
  }

  @Test("DragGesture currentValue exposes velocity after multiple samples")
  func velocityComputed() throws {
    let rec = DragGesture()._makeRecognizer(context: ctx())
    let t0 = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 0, y: 0), at: t0))
    // 10 cells right over 100ms
    let t1 = t0.advanced(by: .milliseconds(50))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 5, y: 0), at: t1))
    let t2 = t0.advanced(by: .milliseconds(100))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 10, y: 0), at: t2))
    let value: DragGesture.Value? = rec.currentValue()
    let v = try #require(value)
    #expect(v.velocity == Size(width: 100, height: 0))
    #expect(v.predictedEndTranslation == Size(width: 35, height: 0))
    #expect(v.predictedEndLocation == Point(x: 35, y: 0))
  }
}

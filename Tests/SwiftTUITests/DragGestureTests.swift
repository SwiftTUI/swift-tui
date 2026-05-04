import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

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
      location: precise(point),
      targetRect: CellRect(origin: .zero, size: CellSize(width: 20, height: 5)),
      timestamp: time
    )
  }

  private func precise(_ point: Point) -> PointerLocation {
    .subCell(location: point, source: .nativePixels, metrics: .estimated)
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
    #expect(v.translation == Vector(dx: 3, dy: 2))
    #expect(v.pointer.location == Point(x: 5, y: 3))
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
    #expect(v.velocity == Vector(dx: 100, dy: 0))
    #expect(v.predictedEndTranslation == Vector(dx: 35, dy: 0))
    #expect(v.predictedEndLocation == Point(x: 35, y: 0))
  }

  @Test("DragGesture path preserves ordered sub-cell samples")
  func pathPreservesSubCellSamples() throws {
    let rec = DragGesture()._makeRecognizer(context: ctx())
    let t0 = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 1.25, y: 1.25), at: t0))
    _ = rec.handle(
      event: event(
        .dragged(.primary),
        at: Point(x: 1.5, y: 1.25),
        at: t0.advanced(by: .milliseconds(10))
      ))
    _ = rec.handle(
      event: event(
        .dragged(.primary),
        at: Point(x: 1.75, y: 1.25),
        at: t0.advanced(by: .milliseconds(20))
      ))

    let value: DragGesture.Value? = rec.currentValue()
    let v = try #require(value)

    #expect(v.location == Point(x: 1.75, y: 1.25))
    #expect(v.translation == Vector(dx: 0.5, dy: 0))
    #expect(
      v.path.map(\.location) == [
        Point(x: 1.25, y: 1.25),
        Point(x: 1.5, y: 1.25),
        Point(x: 1.75, y: 1.25),
      ])
    #expect(
      v.path.map(\.pointer.cell) == [
        CellPoint(x: 1, y: 1),
        CellPoint(x: 1, y: 1),
        CellPoint(x: 1, y: 1),
      ])
  }

  @Test("DragGesture velocity preserves fractional cells per second")
  func velocityPreservesFractionalCellsPerSecond() throws {
    let rec = DragGesture()._makeRecognizer(context: ctx())
    let t0 = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 0, y: 0), at: t0))
    _ = rec.handle(
      event: event(
        .dragged(.primary),
        at: Point(x: 0.05, y: 0),
        at: t0.advanced(by: .milliseconds(100))
      ))

    let value: DragGesture.Value? = rec.currentValue()
    let v = try #require(value)

    #expect(abs(v.velocity.dx - 0.5) < 0.0001)
    #expect(v.velocity.dy == 0)
  }
}

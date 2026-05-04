import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct TapGestureTests {
  private func identity(_ s: String) -> Identity {
    Identity(components: [IdentityComponent(rawValue: s)])
  }

  private func event(
    _ kind: LocalPointerEvent.Kind,
    at point: Point = .zero
  ) -> LocalPointerEvent {
    LocalPointerEvent(
      kind: kind,
      location: point,
      targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1))
    )
  }

  private func ctx() -> GestureRecognizerBuildContext {
    .init(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { _ in }
    )
  }

  @Test("TapGesture count:1 — single down+up transitions to .ended")
  func singleTap() {
    let tap = TapGesture()
    let rec = tap._makeRecognizer(context: ctx())
    #expect(rec.phase == .possible)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase == .ended)
  }

  @Test("TapGesture count:2 — single tap does not end; double does")
  func doubleTap() {
    let tap = TapGesture(count: 2)
    let rec = tap._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase != .ended)

    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase == .ended)
  }

  @Test("TapGesture fails when pointer moves off target between down and up")
  func movesOffCancels() {
    let tap = TapGesture()
    let rec = tap._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary), at: Point(x: 1, y: 0)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 100, y: 100)))
    #expect(rec.phase == .failed)
  }
}

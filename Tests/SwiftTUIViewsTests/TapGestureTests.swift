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

  @Test("Multi-tap sequences fail once the inter-tap window expires (F158)")
  func multiTapFailsAfterInterTapWindow() throws {
    var armed: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { armed.append($0) }
    )
    let rec = TapGesture(count: 2)._makeRecognizer(context: context)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    // One tap of two completed: the window is armed and the sequence is
    // still live.
    #expect(armed.count == 1)
    #expect(rec.phase == .possible)

    _ = rec.handleDeadline(at: try #require(armed.first))
    #expect(rec.phase == .failed)
  }

  @Test("Single-tap recognizers never arm an inter-tap deadline")
  func singleTapArmsNoDeadline() {
    var armed: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { armed.append($0) }
    )
    let rec = TapGesture()._makeRecognizer(context: context)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase == .ended)
    #expect(armed.isEmpty)
  }

  @Test("A next-tap down after the expired window fails at event time")
  func lateDownFailsAtEventTime() throws {
    // Deadline wakes are scheduler-driven, so the next tap's `.down` can
    // arrive before the pending deadline frame drains. Honor the event
    // timestamp, like LongPressGestureRecognizer does on release. The
    // window is pinned explicitly: another suite's run-loop test may hold
    // the `interTapWindowOverride` test seam across its awaits.
    let t0 = MonotonicInstant.now()
    let rec = AnyGestureRecognizer(
      TapGestureRecognizer(count: 2, interTapWindow: .milliseconds(350))
    )
    _ = rec.handle(
      event: LocalPointerEvent(
        kind: .down(.primary),
        location: .zero,
        targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
        timestamp: t0
      )
    )
    _ = rec.handle(
      event: LocalPointerEvent(
        kind: .up(.primary),
        location: .zero,
        targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
        timestamp: t0.advanced(by: .milliseconds(10))
      )
    )
    _ = rec.handle(
      event: LocalPointerEvent(
        kind: .down(.primary),
        location: .zero,
        targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
        timestamp: t0.advanced(by: .seconds(5))
      )
    )
    #expect(rec.phase == .failed)
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

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

  @Test("A drag that fails the first tap fails a tap fallback too — the hand-off replays the evidence")
  func dragFailsBothTapsThroughReplay() {
    var firstCount = 0
    var secondCount = 0
    // Both are TapGesture. Before the F158 replay, `second` "won" here only
    // because it never saw the disqualifying drag — the fallback received
    // events from the failure onward, so it recognized a tap the user never
    // performed. With the buffered-prefix replay, the drag that fails the
    // first tap fails the fallback tap too; the composite is failed until
    // dispatch re-arms it, after which `first` (not the fallback) takes a
    // clean tap.
    let g = TapGesture().onEnded { firstCount += 1 }
      .exclusively(before: TapGesture().onEnded { secondCount += 1 })
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 100, y: 100)))
    #expect(rec.phase == .failed)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(firstCount == 0)
    #expect(secondCount == 0)

    rec.reArm()
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(firstCount == 1)
    #expect(secondCount == 0)
  }

  @Test("Single tap falls through to second after the inter-tap window expires")
  func singleTapFallsThroughOnTimeout() throws {
    var singleCount = 0
    var doubleCount = 0
    var armed: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { armed.append($0) }
    )
    // The canonical composition (F158): double-tap exclusively before
    // single-tap. The first tap arms the inter-tap window; when it expires
    // the double-tap FAILS, and the buffered first-tap events replay into
    // the single-tap fallback.
    let g = TapGesture(count: 2).onEnded { doubleCount += 1 }
      .exclusively(before: TapGesture().onEnded { singleCount += 1 })
    let rec = g._makeRecognizer(context: context)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(armed.count == 1)

    let expiry = try #require(armed.first)
    _ = rec.handleDeadline(at: expiry)
    #expect(doubleCount == 0)
    #expect(singleCount == 1)
  }

  @Test("A second tap inside the window still wins the double-tap")
  func secondTapInsideWindowWins() throws {
    var singleCount = 0
    var doubleCount = 0
    var armed: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { armed.append($0) }
    )
    let g = TapGesture(count: 2).onEnded { doubleCount += 1 }
      .exclusively(before: TapGesture().onEnded { singleCount += 1 })
    let rec = g._makeRecognizer(context: context)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(doubleCount == 1)
    #expect(singleCount == 0)

    // The armed window firing after completion must not disturb anything.
    let expiry = try #require(armed.first)
    _ = rec.handleDeadline(at: expiry)
    #expect(doubleCount == 1)
    #expect(singleCount == 0)
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

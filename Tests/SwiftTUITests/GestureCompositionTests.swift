import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// F158 — `SimultaneousGesture` and `SequenceGesture` (SwiftUI-parity
/// composition, operator-approved full set).
@MainActor
@Suite
struct GestureCompositionTests {
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
    at location: Point = .zero,
    timestamp: MonotonicInstant = .now()
  ) -> LocalPointerEvent {
    LocalPointerEvent(
      kind: kind,
      location: location,
      targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
      timestamp: timestamp
    )
  }

  @Test("SimultaneousGesture recognizes when either child recognizes")
  func simultaneousRecognizesOnEitherChild() {
    var values: [SimultaneousGesture<TapGesture, LongPressGesture>.Value] = []
    let g = TapGesture().simultaneously(with: LongPressGesture())
      .onEnded { values.append($0) }
    let rec = g._makeRecognizer(context: ctx())

    // A quick tap: the tap child ends; the long-press child fails on the
    // early release. The composite ends with only `first` populated.
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase == .ended)
    #expect(values.count == 1)
    if let value = values.first {
      #expect(value.first != nil)
      #expect(value.second == nil)
    }
  }

  @Test("SimultaneousGesture fails only when both children fail")
  func simultaneousFailsOnlyWhenBothFail() {
    let g = TapGesture().simultaneously(with: TapGesture(count: 2))
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    // A big drag fails both tap children.
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 100, y: 100)))
    #expect(rec.phase == .failed)
  }

  @Test("SequenceGesture delivers events to second only after first ends")
  func sequenceGatesSecondOnFirstCompletion() {
    var ended: [SequenceGesture<TapGesture, LongPressGesture>.Value] = []
    var armed: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { armed.append($0) }
    )
    let g = TapGesture()
      .sequenced(before: LongPressGesture(minimumDuration: .milliseconds(100)))
      .onEnded { ended.append($0) }
    let rec = g._makeRecognizer(context: context)

    let t0 = MonotonicInstant.now()
    // Stage one: a tap.
    _ = rec.handle(event: event(.down(.primary), timestamp: t0))
    _ = rec.handle(event: event(.up(.primary), timestamp: t0))
    #expect(rec.phase == .began)
    // The long press must not have started yet: no deadline armed by it.
    #expect(armed.isEmpty)

    // Stage two: press and hold past the minimum duration.
    _ = rec.handle(event: event(.down(.primary), timestamp: t0.advanced(by: .milliseconds(50))))
    #expect(armed.count == 1)
    _ = rec.handleDeadline(at: t0.advanced(by: .milliseconds(200)))
    #expect(rec.phase == .ended)
    #expect(ended.count == 1)
    if case .second(_, let secondValue)? = ended.first {
      #expect(secondValue == true)
    } else {
      Issue.record("expected a .second value once stage two completed")
    }
  }

  @Test("SequenceGesture fails when the first stage fails")
  func sequenceFailsWithFirstStage() {
    let g = TapGesture().sequenced(before: TapGesture())
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 100, y: 100)))
    #expect(rec.phase == .failed)
  }
}

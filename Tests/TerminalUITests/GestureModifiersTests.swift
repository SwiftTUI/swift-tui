import Foundation
import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct GestureModifiersTests {
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
  private func event(_ kind: LocalPointerEvent.Kind) -> LocalPointerEvent {
    .init(
      kind: kind,
      location: .zero,
      targetRect: Rect(origin: .zero, size: Size(width: 4, height: 1))
    )
  }

  @Test(".onEnded fires once when gesture reaches .ended")
  func onEndedFires() {
    var fired = 0
    let g = TapGesture().onEnded { fired += 1 }
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(fired == 1)
  }

  @Test(".onEnded does not fire if gesture fails")
  func onEndedDoesNotFireOnFail() {
    var fired = 0
    let g = TapGesture().onEnded { fired += 1 }
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(
      event: .init(
        kind: .dragged(.primary),
        location: Point(x: 100, y: 100),
        targetRect: Rect(origin: .zero, size: Size(width: 4, height: 1))
      ))
    #expect(fired == 0)
  }

  @Test(".updating invokes the updater closure during events")
  func updatingWrites() {
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    let binding = GestureStateBinding(box: box)
    var invocations = 0
    let g = TapGesture().updating(binding) { _, state, _ in
      invocations += 1
      state = 99
    }
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(invocations >= 1)  // updater was actually called during the gesture
  }

  @Test(".updating resets state on end")
  func updatingResetsOnEnd() {
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    let binding = GestureStateBinding(box: box)
    let g = TapGesture().updating(binding) { _, state, _ in state = 99 }
    let rec = g._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(box.currentValue() == 0)
  }

  @Test(".map transforms the gesture value type")
  func mapTransforms() {
    // TapGesture.Value is Void; .map can produce something else, but
    // the new value is only read from .currentValue() on .ended.
    let mapped = TapGesture().map { _ in 42 }
    let rec = mapped._makeRecognizer(context: ctx())
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    let value: Int? = rec.currentValue()
    #expect(value == 42)
  }
}

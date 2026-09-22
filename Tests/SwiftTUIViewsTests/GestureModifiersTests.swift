import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

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
      targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1))
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
        targetRect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1))
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

  @Test("T257: deadline recognition delivers updating before reset", arguments: 0..<3)
  func updatingReceivesDeadlineValue(composition: Int) throws {
    let box = GestureStateBox<Bool>(seed: false, slotOrdinal: 0)
    let binding = GestureStateBinding(box: box)
    var values: [Bool] = []
    var deadlines: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("T257"), gestureStateRegistry: nil,
      requestDeadline: { deadlines.append($0) }
    )
    let updater: @MainActor (Bool, inout Bool, inout Transaction) -> Void = {
      value, state, transaction in
      values.append(value)
      state = value
      transaction.tracksVelocity = true
    }
    let first = LongPressGesture(minimumDuration: .milliseconds(50))
    let second = LongPressGesture(minimumDuration: .milliseconds(100))
    let recognizer: AnyGestureRecognizer
    switch composition {
    case 1:
      recognizer = first.simultaneously(with: second)
        .map { $0.first == true || $0.second == true }
        .updating(binding, body: updater)._makeRecognizer(context: context)
    case 2:
      recognizer = first.exclusively(before: second)
        .updating(binding, body: updater)._makeRecognizer(context: context)
    default:
      recognizer = first.updating(binding, body: updater)._makeRecognizer(context: context)
    }
    _ = recognizer.handle(event: event(.down(.primary)))
    #expect(values.isEmpty)
    let deadline = try #require(deadlines.min())
    #expect(recognizer.handleDeadline(at: deadline))
    #expect(values == [true])
    #expect(recognizer.phase == .ended)
    #expect(box.currentValue() == false)
    #expect(!recognizer.handleDeadline(at: deadline))
    #expect(values == [true])
    recognizer.tearDown()
  }

  @Test("T257: sequence deadline updates survive until the entire gesture ends")
  func updatingReceivesSequenceDeadlines() throws {
    let box = GestureStateBox<String>(seed: "seed", slotOrdinal: 0)
    var values: [String] = []
    var deadline: MonotonicInstant?
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("T257-sequence"), gestureStateRegistry: nil,
      requestDeadline: { deadline = $0 }
    )
    let recognizer = LongPressGesture(minimumDuration: .milliseconds(50))
      .sequenced(before: LongPressGesture(minimumDuration: .milliseconds(50)))
      .map { value in
        switch value {
        case .first: "first"
        case .second: "second"
        }
      }
      .updating(GestureStateBinding(box: box)) { value, state, _ in
        values.append(value)
        state = value
      }
      ._makeRecognizer(context: context)
    _ = recognizer.handle(event: event(.down(.primary)))
    let firstDeadline = try #require(deadline)
    #expect(recognizer.handleDeadline(at: firstDeadline))
    #expect(values == ["first"])
    #expect(box.currentValue() == "first")
    #expect(!recognizer.phase.isTerminal)
    var secondPress = event(.down(.primary))
    secondPress.timestamp = firstDeadline.advanced(by: .milliseconds(1))
    _ = recognizer.handle(event: secondPress)
    values.removeAll()
    let secondDeadline = try #require(deadline)
    #expect(secondDeadline > firstDeadline)
    #expect(recognizer.handleDeadline(at: secondDeadline))
    #expect(values == ["second"])
    #expect(recognizer.phase == .ended)
    #expect(box.currentValue() == "seed")
    recognizer.tearDown()
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

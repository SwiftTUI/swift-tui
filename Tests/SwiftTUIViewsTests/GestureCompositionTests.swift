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

  @Test("SimultaneousGesture surfaces recognizing children's values mid-gesture")
  func simultaneousSurfacesMidGestureValues() {
    let box = GestureStateBox<Double>(seed: 0, slotOrdinal: 0)
    var observed: [[Double?]] = []
    var ended: [SimultaneousGesture<DragGesture, DragGesture>.Value] = []
    let rec = DragGesture().simultaneously(with: DragGesture(minimumDistance: 2))
      .updating(GestureStateBinding(box: box)) { value, state, _ in
        observed.append([value.first?.translation.dx, value.second?.translation.dx])
        state = value.first?.translation.dx ?? -1
      }
      .onEnded { ended.append($0) }
      ._makeRecognizer(context: ctx())

    // The first drag begins on press; the second only past two cells, so
    // until then the composite carries the first child's value alone.
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 1, y: 0)))
    #expect(rec.phase == .changed)
    #expect(box.currentValue() == 1)
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 3, y: 0)))
    #expect(observed == [[0, nil], [1, nil], [3, 3]])
    #expect(box.currentValue() == 3)
    #expect(ended.isEmpty)

    _ = rec.handle(event: event(.up(.primary), at: Point(x: 3, y: 0)))
    #expect(rec.phase == .ended)
    #expect(box.currentValue() == 0)
    #expect(ended.count == 1)
    #expect(ended.first?.first?.translation.dx == 3)
    #expect(ended.first?.second?.translation.dx == 3)
  }

  @Test("SimultaneousGesture ends with a still-recognizing child's current value")
  func simultaneousEndCarriesRecognizingChildValue() throws {
    var ended: [SimultaneousGesture<LongPressGesture, DragGesture>.Value] = []
    var deadlines: [MonotonicInstant] = []
    let context = GestureRecognizerBuildContext(
      attachingIdentity: identity("r"),
      gestureStateRegistry: nil,
      requestDeadline: { deadlines.append($0) }
    )
    let rec = LongPressGesture(minimumDuration: .milliseconds(50), maximumDistance: 5)
      .simultaneously(with: DragGesture())
      .onEnded { ended.append($0) }
      ._makeRecognizer(context: context)

    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 2, y: 0)))
    #expect(rec.phase == .changed)
    // The long press recognizes while the drag is still in flight: the
    // composite ends once, carrying both children's values.
    #expect(rec.handleDeadline(at: try #require(deadlines.first)))
    #expect(rec.phase == .ended)
    #expect(ended.count == 1)
    #expect(ended.first?.first == true)
    #expect(ended.first?.second?.translation.dx == 2)
  }

  @Test("ExclusiveGesture surfaces the active child's value mid-gesture")
  func exclusiveSurfacesMidGestureValues() {
    let box = GestureStateBox<String>(seed: "idle", slotOrdinal: 0)
    var observed: [String] = []
    let updater: @MainActor (String, inout String, inout Transaction) -> Void = {
      value, state, _ in
      observed.append(value)
      state = value
    }
    let direct = DragGesture().map { "first \(Int($0.translation.dx))" }
      .exclusively(before: DragGesture().map { _ in "second" })
      .updating(GestureStateBinding(box: box), body: updater)
      ._makeRecognizer(context: ctx())
    _ = direct.handle(event: event(.down(.primary)))
    _ = direct.handle(event: event(.dragged(.primary), at: Point(x: 2, y: 0)))
    #expect(direct.phase == .changed)
    #expect(observed == ["first 0", "first 2"])
    #expect(box.currentValue() == "first 2")
    _ = direct.handle(event: event(.up(.primary), at: Point(x: 2, y: 0)))
    #expect(box.currentValue() == "idle")

    // A drag fails the long press, handing the stream to the drag fallback,
    // whose in-flight value the composite now carries.
    observed.removeAll()
    let fallback = LongPressGesture(minimumDuration: .seconds(10)).map { _ in "press" }
      .exclusively(before: DragGesture().map { "drag \(Int($0.translation.dx))" })
      .updating(GestureStateBinding(box: box), body: updater)
      ._makeRecognizer(context: ctx())
    _ = fallback.handle(event: event(.down(.primary)))
    #expect(observed.isEmpty)
    _ = fallback.handle(event: event(.dragged(.primary), at: Point(x: 2, y: 0)))
    #expect(fallback.phase == .changed)
    #expect(observed == ["drag 2"])
    #expect(box.currentValue() == "drag 2")
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

  @Test("SequenceGesture reports .first while the first stage is mid-gesture")
  func sequenceReportsFirstStageMidGesture() {
    var observed: [String] = []
    let rec = DragGesture().sequenced(before: TapGesture())
      .map { value in
        switch value {
        case .first(let drag): "first \(Int(drag.translation.dx))"
        case .second: "second"
        }
      }
      .onChanged { observed.append($0) }
      ._makeRecognizer(context: ctx())

    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.dragged(.primary), at: Point(x: 2, y: 0)))
    #expect(rec.phase == .changed)
    _ = rec.handle(event: event(.up(.primary), at: Point(x: 2, y: 0)))
    #expect(rec.phase == .began)
    _ = rec.handle(event: event(.down(.primary)))
    _ = rec.handle(event: event(.up(.primary)))
    #expect(rec.phase == .ended)
    #expect(observed == ["first 0", "first 2", "second"])
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

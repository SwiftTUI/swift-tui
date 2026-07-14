import Testing

@_spi(Testing) import SwiftTUITestSupport

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F128: one-shot gestures must re-arm for the next interaction. A fired (or
/// jitter-failed) recognizer parks in a terminal phase; when the action
/// mutates no state — a clipboard write, an external side effect — no
/// re-resolve re-authors a fresh recognizer, so every later press routed to
/// the parked terminal recognizer died. A fresh `.down` is an unambiguous
/// new interaction: it re-arms terminal recognizers before dispatch.
@MainActor
@Suite
struct GestureRearmTests {
  @MainActor
  final class SideEffectCounter {
    private(set) var count = 0
    func record() { count += 1 }
  }

  private struct StatelessTapFixture: View {
    let counter: SideEffectCounter

    var body: some View {
      Text("Fire twice")
        .frame(width: 20, height: 1, alignment: .leading)
        .onTapGesture {
          counter.record()
        }
    }
  }

  @Test("a stateless tap action fires on every tap, not only the first")
  func statelessTapFiresOnEveryTap() throws {
    let counter = SideEffectCounter()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureRearmRoot"),
      size: .init(width: 30, height: 4)
    ) {
      StatelessTapFixture(counter: counter)
    }
    defer { harness.shutdown() }
    // Selective evaluation on: a stateless action invalidates nothing, so no
    // re-resolve re-authors a fresh recognizer between taps — the live-app
    // shape in which the parked terminal recognizer goes tap-dead.
    harness.runLoop.renderer.enableSelectiveEvaluation()

    _ = try harness.clickText("Fire twice")
    #expect(counter.count == 1)
    _ = try harness.clickText("Fire twice")
    #expect(
      counter.count == 2,
      "the second tap routed into a parked terminal recognizer and died"
    )
    _ = try harness.clickText("Fire twice")
    #expect(counter.count == 3)
  }

  // MARK: - Sub-cell jitter slop

  private func tapEvent(
    _ kind: LocalPointerEvent.Kind,
    at location: Point
  ) -> LocalPointerEvent {
    let pointerLocation = PointerLocation.subCell(
      location: location,
      source: .terminalPixels,
      metrics: CellPixelMetrics(width: 10, height: 20, source: .reported)
    )
    return LocalPointerEvent(
      kind: kind,
      location: pointerLocation,
      targetRect: .init(origin: .zero, size: .init(width: 10, height: 2))
    )
  }

  @Test("sub-cell pointer jitter within one cell does not fail a tap")
  func subCellJitterDoesNotFailTap() {
    let recognizer = TapGestureRecognizer(count: 1)

    _ = recognizer.handle(event: tapEvent(.down(.primary), at: Point(x: 2.1, y: 1.2)))
    // A hand tremor under pixel precision: fractional movement well inside
    // the pressed cell. The old jitter leg failed the tap on ANY movement.
    _ = recognizer.handle(event: tapEvent(.dragged(.primary), at: Point(x: 2.5, y: 1.4)))
    _ = recognizer.handle(event: tapEvent(.up(.primary), at: Point(x: 2.5, y: 1.4)))

    #expect(recognizer.phase == .ended, "sub-cell jitter failed the tap")
  }

  @Test("movement of a full cell or more still fails the tap")
  func fullCellMovementStillFailsTap() {
    let recognizer = TapGestureRecognizer(count: 1)

    _ = recognizer.handle(event: tapEvent(.down(.primary), at: Point(x: 2.1, y: 1.2)))
    _ = recognizer.handle(event: tapEvent(.dragged(.primary), at: Point(x: 4.3, y: 1.2)))
    _ = recognizer.handle(event: tapEvent(.up(.primary), at: Point(x: 4.3, y: 1.2)))

    #expect(recognizer.phase == .failed, "a real drag must still fail the tap")
  }
}

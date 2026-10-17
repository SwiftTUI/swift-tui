import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct GestureOwnershipAndHandoffTests {
  private func context(_ name: String) -> GestureRecognizerBuildContext {
    .init(
      attachingIdentity: Identity(components: [name]), gestureStateRegistry: nil,
      requestDeadline: { _ in })
  }

  private func event(_ kind: LocalPointerEvent.Kind, _ time: MonotonicInstant, x: Int = 1)
    -> LocalPointerEvent
  {
    .init(
      kind: kind, location: Point(x: Double(x), y: 0),
      targetRect: .init(origin: .zero, size: .init(width: 8, height: 1)), timestamp: time)
  }

  @Test func sequenceHonorsDueHoldBeforeReleaseWithoutSchedulerWake() {
    let rec = LongPressGesture(minimumDuration: .milliseconds(100))
      .sequenced(before: DragGesture())._makeRecognizer(context: context("late-wake"))
    let start = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), start))
    _ = rec.handle(event: event(.up(.primary), start.advanced(by: .milliseconds(150))))
    #expect(rec.phase.isTerminal)
    #expect(!rec.isActive)
  }

  @Test func exclusiveDragFallbackStartsWithNewPressAfterExpiredTapWindow() {
    let rec = TapGesture(count: 2).map { _ in 0.0 }
      .exclusively(before: DragGesture(minimumDistance: 0).map { $0.translation.dx })
      ._makeRecognizer(context: context("new-press"))
    let start = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), start))
    _ = rec.handle(event: event(.up(.primary), start))
    let later = start.advanced(by: TapGesture.effectiveInterTapWindow)
    _ = rec.handle(event: event(.down(.primary), later))
    #expect(rec.isActive)
    _ = rec.handle(event: event(.dragged(.primary), later, x: 4))
    #expect(rec.currentValue(as: Double.self) == 3)
    _ = rec.handle(event: event(.up(.primary), later, x: 4))
    #expect(rec.phase == .ended)
  }

  @Test func exclusiveWinnerKeepsItsActiveSimultaneousChildAndNeverStartsFallback() {
    var dragValues: [Double] = []
    var fallbackCount = 0
    let rec = LongPressGesture(minimumDuration: .milliseconds(100))
      .simultaneously(
        with: DragGesture(minimumDistance: 0).onChanged { dragValues.append($0.translation.dx) }
      )
      .map { _ in true }
      .exclusively(before: TapGesture().map { true }.onEnded { _ in fallbackCount += 1 })
      ._makeRecognizer(context: context("winning-composite"))
    let start = MonotonicInstant.now()
    _ = rec.handle(event: event(.down(.primary), start))
    #expect(rec.handleDeadline(at: start.advanced(by: .milliseconds(100))))
    #expect(rec.phase == .ended)
    #expect(rec.isActive)
    _ = rec.handle(event: event(.dragged(.primary), start.advanced(by: .milliseconds(110)), x: 4))
    #expect(dragValues.last == 3)
    _ = rec.handle(event: event(.up(.primary), start.advanced(by: .milliseconds(120)), x: 4))
    #expect(!rec.isActive)
    #expect(fallbackCount == 0)
  }

  @Test func spatialTapUsesTheSamePressBoundaryAndInterTapDeadline() {
    let start = MonotonicInstant.now()
    let outside = SpatialTapGesture(count: 2)._makeRecognizer(context: context("spatial-boundary"))
    _ = outside.handle(event: event(.down(.primary), start))
    _ = outside.handle(event: event(.up(.primary), start))
    _ = outside.handle(event: event(.down(.primary), start, x: 20))
    _ = outside.handle(event: event(.up(.primary), start))
    #expect(outside.phase == .failed)

    let timeout = SpatialTapGesture(count: 2)._makeRecognizer(context: context("spatial-timeout"))
    _ = timeout.handle(event: event(.down(.primary), start))
    _ = timeout.handle(event: event(.up(.primary), start))
    #expect(timeout.handleDeadline(at: start.advanced(by: TapGesture.effectiveInterTapWindow)))
    #expect(timeout.phase == .failed)
    #expect(!timeout.handleDeadline(at: start.advanced(by: .seconds(1))))
  }

  private final class CapturedBinding {
    var binding: GestureStateBinding<Int>?
    var scope: ImperativeAuthoringContextSnapshot?
  }

  private struct Probe: View {
    @GestureState private var offset = 0
    let captured: CapturedBinding
    var body: some View {
      captured.binding = $offset
      captured.scope = currentImperativeAuthoringContextSnapshot()
      return Text("\(offset)")
    }
  }

  @Test func projectedGestureBindingsKeepTheirExactGraphOwner() throws {
    let captured = CapturedBinding()
    let probe = Probe(captured: captured)
    let firstGraph = ViewGraph()
    let secondGraph = ViewGraph()
    let identity = Identity(components: ["shared-authored-gesture"])
    func mount(_ graph: ViewGraph) {
      graph.beginFrame()
      var context = ResolveContext(identity: identity)
      context.viewGraph = graph
      _ = Resolver().resolve(probe, in: context)
    }
    mount(firstGraph)
    let first = try #require(captured.binding)
    mount(secondGraph)
    let second = try #require(captured.binding)
    let secondScope = captured.scope
    first.setValue(7)
    second.setValue(11)
    #expect(first.currentValue() == 7)
    #expect(second.currentValue() == 11)
    withImperativeAuthoringContext(secondScope) {
      first.setValue(13)
      #expect(first.currentValue() == 13)
      #expect(second.currentValue() == 11)
      first.eraseToAnyBinding().resetToSeed()
    }
    #expect(first.currentValue() == 0)
    #expect(second.currentValue() == 11)
    withExtendedLifetime((firstGraph, secondGraph)) {}
  }
}

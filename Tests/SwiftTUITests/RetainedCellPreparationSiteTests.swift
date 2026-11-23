import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private final class PreparationRecorder: Sendable { let values = Mutex<[String]>([]) }
private struct Mark: CellPreparedLayerKernel {
  let name: String
  let recorder: PreparationRecorder
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.recorder === rhs.recorder
  }
  func makeState() -> String { name }
  func prepare(_ state: inout String, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let observed = name + " uses " + state
    recorder.values.withLock { $0.append(observed) }
    return CellLayerShader { p, layer, _ in layer.sample(at: p) }
  }
}
private struct TwoRuns: Transition {
  let recorder: PreparationRecorder
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.layerEffect(
      Mark(name: "A", recorder: recorder), maxSampleOffset: .zero, isEnabled: phase.isIdentity
    )
    .layerEffect(Mark(name: "B", recorder: recorder), maxSampleOffset: .zero)
    .opacity(phase.isIdentity ? 1 : 0.15)
  }
}
private struct ReviewPanel: View {
  var visible: Bool
  let rec: PreparationRecorder
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("steady")
      if visible { Text("x").transition(TwoRuns(recorder: rec)) }
    }
  }
}
@MainActor
@Suite struct RetainedCellPreparationSiteTests {
  @Test("Disabling one stacked kernel for removal preserves its sibling’s original run")
  func removalContinuesTheEnabledSibling() {
    let renderer = DefaultRenderer()
    let rec = PreparationRecorder()
    let id = testIdentity("independentRemoval")
    let start = MonotonicInstant(offset: .seconds(100))
    let animation = Animation.linear(duration: .seconds(1))
    var tx = TransactionSnapshot()
    tx.animationRequest = .animate(animation.animationBox)
    func frame(_ ms: Int, _ visible: Bool, _ animated: Bool = false) {
      _ = renderer.render(
        ReviewPanel(visible: visible, rec: rec),
        context: .init(identity: id, transaction: animated ? tx : .init()),
        proposal: .init(width: 8, height: 3), frameInstant: start.advanced(by: .milliseconds(ms)))
    }
    withAnimationSinks(renderer.internalAnimationController) {
      renderer.internalAnimationController.register(animation)
      frame(0, true)
      frame(20, false, true)
      frame(320, false)
    }
    #expect(rec.values.withLock { $0 } == ["A uses A", "B uses B", "B uses B", "B uses B"])
  }
}

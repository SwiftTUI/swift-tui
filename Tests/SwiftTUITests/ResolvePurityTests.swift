import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
struct ResolvePurityTests {
  @Test("Aborting a prepared frame head leaves no observable subsystem change")
  func abortLeavesNoResidue() {
    let renderer = DefaultRenderer()

    _ = renderer.render(VStack { Text("a") })
    let baseline = renderer.debugRuntimeSubsystemSnapshot()

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      VStack {
        Text("a")
        Text("b")
      }
    )
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)

    let afterAbort = renderer.debugRuntimeSubsystemSnapshot()
    #expect(baseline == afterAbort, "aborted head left observable residue")
  }
}

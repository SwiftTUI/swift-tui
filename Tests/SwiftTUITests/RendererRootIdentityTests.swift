import SwiftTUICore
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite
struct RendererRootIdentityTests {
  @Test("A root switch retires the old graph and mounts fresh state")
  func rootSwitch() async throws {
    let renderer = DefaultRenderer()
    let proposal = ProposedSize(width: 24, height: 3)
    let first = ResolveContext(identity: testIdentity("First"))
    let second = ResolveContext(identity: testIdentity("Second"))

    let initial = renderer.render(RootSeed(1), context: first, proposal: proposal)
    let oldLeaf = try #require(
      initial.commitPlan.lifecycle.first {
        if case .appear = $0.operation { return true }
        return false
      }?.identity)
    let same = renderer.render(RootSeed(2), context: first, proposal: proposal)
    #expect(same.rasterSurface.lines.contains { $0.contains("seed 1") })

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      RootSeed(3), context: second, proposal: proposal)
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    let restored = renderer.render(RootSeed(2), context: first, proposal: proposal)
    #expect(restored.rasterSurface.lines.contains { $0.contains("seed 1") })
    #expect(renderer.viewGraph.debugTeardownCoherenceViolation() == nil)

    let switched = await renderer.renderAsync(RootSeed(3), context: second, proposal: proposal)
    #expect(switched.rasterSurface.lines.contains { $0.contains("seed 3") })
    #expect(
      switched.commitPlan.lifecycle.contains {
        guard $0.identity == oldLeaf, case .disappear = $0.operation else { return false }
        return true
      })
    #expect(renderer.viewGraph.debugTeardownCoherenceViolation() == nil)

    let returning = renderer.render(RootSeed(4), context: first, proposal: proposal)
    #expect(returning.rasterSurface.lines.contains { $0.contains("seed 4") })
    #expect(renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
  }
}

private struct RootSeed: View {
  @State private var seed: Int

  init(_ seed: Int) {
    _seed = State(initialValue: seed)
  }

  var body: some View {
    VStack {
      Text("seed \(seed)").onAppear {}.onDisappear {}
    }
  }
}

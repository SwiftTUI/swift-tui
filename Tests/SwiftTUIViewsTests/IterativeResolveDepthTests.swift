import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct IterativeResolveDepthTests {
  @Test("deep custom bodies consume completed child shapes once")
  func customBodyDepth() {
    let probe = ResolveDepthProbe()
    let result = Resolver().resolve(DeepResolveBody(depth: 1_000, probe: probe))
    #expect(probe.evaluations == 1_001)
    #expect(result.subtreeNodeCount >= 1)
  }

  @Test("erased modifier and entity chains resolve with their actual children")
  func erasedModifierDepth() {
    // AnyView policy: runtime depth is the subject of this type-erasure test.
    var view = AnyView(Text("leaf"))
    for index in 0..<300 { view = AnyView(view.padding(0).id(index)) }
    let result = Resolver().resolve(view)
    #expect(result.subtreeNodeCount >= 300)
  }
  @Test("a completed deep continuation draft restores the exact graph checkpoint")
  func deepDraftRollback() {
    let graph = ViewGraph()
    var context = ResolveContext(
      identity: testIdentity("DeepRollback"), environmentValues: .init(),
      applyEnvironmentValues: true)
    context.viewGraph = graph
    // AnyView policy: runtime wrapper depth exercises continuation unwinding.
    var view = AnyView(Text("leaf").onAppear {}.task {})
    for index in 0..<64 { view = AnyView(VStack { view }.id(index)) }
    ResolveWorkDiagnostics.reset()
    graph.beginFrame()
    let first = Resolver().resolve(view, in: context)
    _ = graph.finalizeFrame(rootIdentity: context.identity, resolved: first, placed: nil)
    let checkpoint = graph.makeCheckpoint()
    let before = graph.debugTotalStateSnapshot()
    graph.beginFrame()
    let replacement = Resolver().resolve(Text("replacement"), in: context)
    _ = graph.finalizeFrame(rootIdentity: context.identity, resolved: replacement, placed: nil)
    #expect(graph.debugTotalStateSnapshot() != before)
    graph.restoreCheckpoint(checkpoint)
    #expect(graph.debugTotalStateSnapshot() == before)
    #expect(ResolveWorkDiagnostics.maximumDrains == 1)
    #expect(ResolveWorkDiagnostics.activeDrains == 0)
  }

}

@MainActor
private final class ResolveDepthProbe { var evaluations = 0 }

private struct DeepResolveBody: View {
  let depth: Int
  let probe: ResolveDepthProbe

  var body: some View {
    probe.evaluations += 1
    return Group {
      if depth == 0 {
        Text("leaf")
      } else {
        DeepResolveBody(depth: depth - 1, probe: probe)
      }
    }
  }
}

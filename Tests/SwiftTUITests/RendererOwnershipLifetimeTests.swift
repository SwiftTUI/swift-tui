import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Renderer ownership lifetime")
struct RendererOwnershipLifetimeTests {
  @Test("borrowed context references retain independent value-copy semantics")
  func borrowedContextCopiesRemainIndependent() {
    let firstGraph = ViewGraph()
    let secondGraph = ViewGraph()
    var first = ResolveContext()
    first.viewGraph = firstGraph
    var second = first
    second.viewGraph = secondGraph
    #expect(first.viewGraph === firstGraph)
    #expect(second.viewGraph === secondGraph)
    second.viewGraph = nil
    #expect(first.viewGraph === firstGraph)

    let firstOwner = SwiftTUICore.ViewNode(identity: testIdentity("FirstOwner"))
    let secondOwner = SwiftTUICore.ViewNode(identity: testIdentity("SecondOwner"))
    let firstScope = AuthoringContext(
      viewIdentity: firstOwner.identity, focusedValues: .init(), viewNode: firstOwner
    )
    var secondScope = firstScope
    secondScope.viewNode = secondOwner
    #expect(firstScope.viewNode === firstOwner)
    #expect(secondScope.viewNode === secondOwner)
  }

  @Test("retained parent and child contexts do not retain their borrowed graph")
  func retainedContextCopiesReleaseGraph() {
    let probe = RendererOwnershipProbe()
    let (parent, child) = makeBorrowedContextCopies(probe)
    #expect(probe.graph == nil)
    #expect(parent.viewGraph == nil)
    #expect(child.viewGraph == nil)
  }

  @Test("a graph releases after direct resolution without renderer frame state")
  func resolvedGraphIsReleased() {
    let probe = RendererOwnershipProbe()
    resolvePlainText(probe)
    #expect(probe.graph == nil)
  }

  @Test("releasing a renderer releases its graph after a plain text render")
  func plainRendererReleasesGraph() {
    let probe = RendererOwnershipProbe()
    renderPlainText(probe)
    #expect(probe.graph == nil)
  }

  @Test("retiring a sheet releases its body owner when the renderer is released")
  func retiredSheetBodyIsReleased() {
    let probe = RendererOwnershipProbe()
    renderAndRemoveSheet(probe)
    #expect(probe.owner == nil)
    #expect(probe.graph == nil)
  }

  private func renderPlainText(_ probe: RendererOwnershipProbe) {
    let renderer = DefaultRenderer()
    probe.graph = renderer.viewGraph
    _ = renderer.render(Text("Content"), proposal: .init(width: 40, height: 10))
  }

  private func makeBorrowedContextCopies(
    _ probe: RendererOwnershipProbe
  ) -> (ResolveContext, ResolveContext) {
    let graph = ViewGraph()
    probe.graph = graph
    var parent = ResolveContext(identity: testIdentity("BorrowedParent"))
    parent.viewGraph = graph
    let child = parent.child(component: .named("Child"))
    return (parent, child)
  }

  private func resolvePlainText(_ probe: RendererOwnershipProbe) {
    let graph = ViewGraph()
    probe.graph = graph
    let identity = testIdentity("DirectOwnership")
    var context = ResolveContext(identity: identity)
    context.viewGraph = graph
    graph.beginFrame()
    _ = Resolver().resolve(Text("Content"), in: context)
    let resolved = graph.snapshot(rootIdentity: identity)
    _ = graph.finalizeFrame(resolved: resolved, placed: nil)
  }

  private func renderAndRemoveSheet(_ probe: RendererOwnershipProbe) {
    let renderer = DefaultRenderer()
    probe.graph = renderer.viewGraph
    let context = ResolveContext(identity: testIdentity("RendererOwnership"))
    _ = renderer.render(
      Text("Base").sheet(isPresented: .constant(true)) {
        RendererOwnershipBody(probe: probe).id(testIdentity("DepartingBody"))
      }.sheetStyle(.dropdown),
      context: context,
      proposal: .init(width: 64, height: 24)
    )
    #expect(probe.owner != nil)
    _ = renderer.render(
      Text("Removed"), context: context, proposal: .init(width: 64, height: 24)
    )
    #expect(probe.owner.flatMap { renderer.viewGraph.nodeForViewNodeID($0.viewNodeID) } == nil)
  }
}

@MainActor
private final class RendererOwnershipProbe {
  weak var graph: ViewGraph?
  weak var owner: SwiftTUICore.ViewNode?
}

private struct RendererOwnershipBody: View {
  let probe: RendererOwnershipProbe

  var body: some View {
    let _ = probe.owner = ViewNodeContext.current
    VStack { Text("Content") }
  }
}

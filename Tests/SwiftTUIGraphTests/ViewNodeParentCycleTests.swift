import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite struct ViewNodeParentCycleTests {
  @Test(arguments: [false, true])
  func refusesAncestorAsNewOrReclaimedChild(reclaim: Bool) {
    let graph = ViewGraph()
    let ancestor = graph.nodeForIdentity(for: testIdentity("ancestor"))
    let middle = graph.nodeForIdentity(for: testIdentity("middle"))
    let node = graph.nodeForIdentity(for: testIdentity("node"))
    let sibling = graph.nodeForIdentity(for: testIdentity("sibling"))
    let other = graph.nodeForIdentity(for: testIdentity("other"))

    func apply(_ parent: ViewNode, children: [ViewNode]) {
      parent.apply(
        resolved: ResolvedNode(
          identity: parent.identity, kind: .root, children: children.map(\.committed)),
        children: children)
    }

    if reclaim {
      apply(node, children: [ancestor, sibling])
      // A competing parent takes the child while the old listing survives.
      apply(other, children: [ancestor])
    }
    apply(ancestor, children: [middle])
    apply(middle, children: [node])
    apply(node, children: [ancestor, sibling])

    #expect(ancestor.parent === (reclaim ? other : nil))
    #expect(node.parent === middle)
    #expect(middle.parent === ancestor)
    #expect(sibling.parent === node)
    #expect(node.children.map(\.viewNodeID) == [sibling.viewNodeID])
    #expect(node.committed.children.map(\.viewNodeID) == [sibling.viewNodeID])
    #expect(
      !graph.lifetimeAnchors.anchors(for: ancestor.viewNodeID).contains(.parent(node.viewNodeID)))
    #expect(graph.frameRuntimeIssues.map(\.typedCode) == [.Structure.parentCycle])
  }

  @Test func lifecycleReportsAnExistingParentCycle() {
    let graph = ViewGraph()
    let node = graph.nodeForIdentity(for: testIdentity("node"))
    let first = graph.nodeForIdentity(for: testIdentity("first"))
    let second = graph.nodeForIdentity(for: testIdentity("second"))
    node.parent = first
    first.parent = second
    second.parent = first

    #expect(!node.participatesInStructuralLifecycle)
    #expect(graph.frameRuntimeIssues.map(\.typedCode) == [.Structure.parentCycle])
    #expect(graph.frameRuntimeIssues.first?.identity == node.identity)
  }
}

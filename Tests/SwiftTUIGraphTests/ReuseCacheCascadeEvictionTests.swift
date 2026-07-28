import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Reuse-cache cascade eviction")
struct ReuseCacheCascadeEvictionTests {
  @Test("owner and cached-node descendants are evicted when the cascade returns")
  func ownerAndNodeDescendantsAreEvictedByReturn() {
    let graph = ViewGraph()
    let source = evaluateStoredNode(graph, named: "Source")
    let unrelated = testIdentity("ReuseCacheCascadeEviction", "Unrelated")

    store(
      graph,
      namespace: "owner-rooted",
      owner: source.identity.child("Toolbar"),
      nodeIdentity: unrelated
    )
    store(
      graph,
      namespace: "node-rooted",
      owner: unrelated,
      nodeIdentity: source.identity.child("CachedBody")
    )
    store(
      graph,
      namespace: "unrelated",
      owner: unrelated,
      nodeIdentity: unrelated.child("CachedBody")
    )

    graph.beginFrame()
    graph.removeSubtree(rootedAt: source)

    #expect(!contains(graph, namespace: "owner-rooted"))
    #expect(!contains(graph, namespace: "node-rooted"))
    #expect(contains(graph, namespace: "unrelated"))
  }

  @Test("one cascade-end flush covers a hosted-detached relation island")
  func hostedDetachedIslandIsCovered() {
    let graph = ViewGraph()
    let source = evaluateStoredNode(graph, named: "Host")
    let detached = evaluateStoredNode(graph, named: "Detached")
    let unrelated = testIdentity("ReuseCacheCascadeEviction", "Unrelated")
    graph.lifetimeAnchors.insert(
      anchor: .hostedDetached(source.viewNodeID),
      for: detached.viewNodeID
    )
    store(
      graph,
      namespace: "detached-island",
      owner: detached.identity.child("Toolbar"),
      nodeIdentity: unrelated
    )
    store(
      graph,
      namespace: "unrelated",
      owner: unrelated,
      nodeIdentity: unrelated.child("CachedBody")
    )

    graph.beginFrame()
    graph.removeSubtree(rootedAt: source)

    #expect(graph.nodeIfExists(for: source.viewNodeID) == nil)
    #expect(graph.nodeIfExists(for: detached.viewNodeID) == nil)
    #expect(!contains(graph, namespace: "detached-island"))
    #expect(contains(graph, namespace: "unrelated"))
  }

  private func store(
    _ graph: ViewGraph,
    namespace: String,
    owner: Identity,
    nodeIdentity: Identity
  ) {
    graph.storeResolvedNodeReuseCache(
      namespace: namespace,
      owner: owner,
      signature: "signature",
      node: ResolvedNode(identity: nodeIdentity, kind: .view("Cached"))
    )
  }

  private func contains(_ graph: ViewGraph, namespace: String) -> Bool {
    graph.resolvedNodeReuseCache.keys.contains { $0.namespace == namespace }
  }

  private func evaluateStoredNode(
    _ graph: ViewGraph,
    named name: String
  ) -> ViewNode {
    let identity = testIdentity("ReuseCacheCascadeEviction", name)
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    _ = graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: identity, kind: .view(name)),
      accessedStateSlots: 0
    )
    return node
  }
}

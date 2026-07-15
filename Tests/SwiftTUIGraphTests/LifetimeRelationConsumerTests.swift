import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Lifetime relation teardown consumers")
struct LifetimeRelationConsumerTests {
  @Test("teardown consumers obtain lifetime decisions from the relation")
  func teardownConsumerSourceBoundary() throws {
    let removal = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraphSubtreeRemoval.swift"
    )
    #expect(removal.contains("lifetimeAnchors.removalTargets"))
    #expect(removal.contains("lifetimeAnchors.removeRemovalEdges"))
    #expect(removal.contains("lifetimeAnchors.hasAnchorOutside"))

    let entities = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraphEntityRouting.swift"
    )
    #expect(entities.contains("lifetimeAnchors.qualifiedEntityHome"))

    let collapse = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraphChainCollapse.swift"
    )
    #expect(collapse.contains("lifetimeAnchors.qualifiedEntityHome"))

    let graph = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraph.swift"
    )
    #expect(graph.contains("lifetimeAnchors.targets(of: .navigationSurface"))
    #expect(graph.contains("lifetimeRelationReachabilitySnapshot()"))
  }

  @Test("relation-only child participates in downward removal")
  func relationOnlyChildIsRemoved() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("RelationConsumer", "Root")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))

    graph.beginFrame()
    let source = evaluateStoredNode(
      graph: graph,
      identity: testIdentity("RelationConsumer", "Source")
    )
    let target = evaluateStoredNode(
      graph: graph,
      identity: testIdentity("RelationConsumer", "Target")
    )
    graph.lifetimeAnchors.insert(
      anchor: .committedValue(source.viewNodeID),
      for: target.viewNodeID
    )

    graph.beginFrame()
    graph.removeSubtree(rootedAt: source)

    #expect(graph.nodeIfExists(for: source.viewNodeID) == nil)
    #expect(graph.nodeIfExists(for: target.viewNodeID) == nil)
    #expect(graph.lifetimeAnchors.isInverseConsistent)
  }

  @Test("outside anchor spares a relation-only child")
  func outsideAnchorSparesRelationOnlyChild() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("RelationConsumerOutside", "Root")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))

    graph.beginFrame()
    let source = evaluateStoredNode(
      graph: graph,
      identity: testIdentity("RelationConsumerOutside", "Source")
    )
    let outside = evaluateStoredNode(
      graph: graph,
      identity: testIdentity("RelationConsumerOutside", "Outside")
    )
    let target = evaluateStoredNode(
      graph: graph,
      identity: testIdentity("RelationConsumerOutside", "Target")
    )
    graph.lifetimeAnchors.insert(
      anchor: .committedValue(source.viewNodeID),
      for: target.viewNodeID
    )
    graph.lifetimeAnchors.insert(
      anchor: .hostedDetached(outside.viewNodeID),
      for: target.viewNodeID
    )

    graph.beginFrame()
    graph.removeSubtree(rootedAt: source)

    #expect(graph.nodeIfExists(for: source.viewNodeID) == nil)
    #expect(graph.nodeIfExists(for: target.viewNodeID) === target)
    #expect(
      graph.lifetimeAnchors.anchors(for: target.viewNodeID)
        == [.hostedDetached(outside.viewNodeID)]
    )
    #expect(graph.lifetimeAnchors.isInverseConsistent)
  }

  private func evaluateStoredNode(
    graph: ViewGraph,
    identity: Identity
  ) -> ViewNode {
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    _ = graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: identity, kind: .view("Fixture")),
      accessedStateSlots: 0
    )
    return node
  }
}

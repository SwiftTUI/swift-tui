import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Teardown reachability context equivalence")
struct TeardownContextEquivalenceTests {
  @Test("all anchor kinds preserve keep decisions and deterministic reachability chains")
  func anchorKindsPreserveDecisionsAndChains() {
    let fixture = makeAnchorFixture()

    #expect(
      fixture.index.keepDecision(
        for: nodeID(2),
        removalCascade: [nodeID(2)],
        context: fixture.context
      )
        == LifetimeKeepDecision(
          shouldKeep: true,
          reason: .anchor(.parent(nodeID(1))),
          diagnosticChain: [
            .root(nodeID(1)),
            .anchor(.parent(nodeID(1)), target: nodeID(2)),
          ]
        )
    )
    #expect(
      fixture.index.keepDecision(
        for: nodeID(4),
        removalCascade: [nodeID(2), nodeID(4)],
        context: fixture.context
      )
        == LifetimeKeepDecision(
          shouldKeep: false,
          reason: .noAnchorOutsideRemovalCascade,
          diagnosticChain: []
        )
    )
    #expect(
      fixture.index.keepDecision(
        for: nodeID(7),
        removalCascade: [nodeID(7)],
        context: fixture.context
      )
        == LifetimeKeepDecision(
          shouldKeep: true,
          reason: .qualifiedEntityHome(fixture.duplicateEntity),
          diagnosticChain: [.entityHome(fixture.duplicateEntity, nodeID(7))]
        )
    )

    let reachable = fixture.index.reachableNodeIDs(context: fixture.context)
    #expect(
      reachable.nodeIDs
        == [
          nodeID(1), nodeID(2), nodeID(3), nodeID(4), nodeID(5), nodeID(6), nodeID(7),
        ]
    )
    #expect(
      reachable.chainByNodeID
        == [
          nodeID(1): [.root(nodeID(1))],
          nodeID(2): [
            .root(nodeID(1)),
            .anchor(.parent(nodeID(1)), target: nodeID(2)),
          ],
          nodeID(3): [
            .root(nodeID(1)),
            .anchor(.committedValue(nodeID(1)), target: nodeID(3)),
          ],
          nodeID(4): [
            .root(nodeID(1)),
            .anchor(.parent(nodeID(1)), target: nodeID(2)),
            .anchor(.hostedDetached(nodeID(2)), target: nodeID(4)),
          ],
          nodeID(5): [
            .root(nodeID(1)),
            .anchor(.committedValue(nodeID(1)), target: nodeID(3)),
            .anchor(.navigationSurface(nodeID(3)), target: nodeID(5)),
          ],
          nodeID(6): [.entityHome(fixture.primaryEntity, nodeID(6))],
          nodeID(7): [.entityHome(fixture.duplicateEntity, nodeID(7))],
        ]
    )
  }

  @Test("graph removal leaves unrelated peers and their anchors untouched")
  func graphRemovalLeavesPeersUntouched() {
    let graph = ViewGraph()
    let source = evaluateStoredNode(graph, named: "Source")
    let removed = evaluateStoredNode(graph, named: "Removed")
    let peerSource = evaluateStoredNode(graph, named: "PeerSource")
    let peer = evaluateStoredNode(graph, named: "Peer")
    graph.lifetimeAnchors.insert(
      anchor: .committedValue(source.viewNodeID),
      for: removed.viewNodeID
    )
    graph.lifetimeAnchors.insert(
      anchor: .navigationSurface(peerSource.viewNodeID),
      for: peer.viewNodeID
    )

    graph.beginFrame()
    graph.removeSubtree(rootedAt: source)

    #expect(graph.nodeIfExists(for: source.viewNodeID) == nil)
    #expect(graph.nodeIfExists(for: removed.viewNodeID) == nil)
    #expect(graph.nodeIfExists(for: peerSource.viewNodeID) === peerSource)
    #expect(graph.nodeIfExists(for: peer.viewNodeID) === peer)
    #expect(
      graph.lifetimeAnchors.anchors(for: peer.viewNodeID)
        == [.navigationSurface(peerSource.viewNodeID)]
    )
    #expect(graph.lifetimeAnchors.isInverseConsistent)
  }

  private func makeAnchorFixture() -> (
    index: LifetimeAnchorIndex,
    context: LifetimeReachabilityContext,
    primaryEntity: EntityIdentity,
    duplicateEntity: EntityIdentity
  ) {
    let primaryEntity = EntityIdentity("row", occurrence: 0)
    let duplicateEntity = EntityIdentity("row", occurrence: 1)
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .parent(nodeID(1)), for: nodeID(2))
    index.insert(anchor: .committedValue(nodeID(1)), for: nodeID(3))
    index.insert(anchor: .hostedDetached(nodeID(2)), for: nodeID(4))
    index.insert(anchor: .navigationSurface(nodeID(3)), for: nodeID(5))
    index.insert(anchor: .entityHome(primaryEntity), for: nodeID(6))
    index.insert(anchor: .entityHome(duplicateEntity), for: nodeID(7))
    let context = LifetimeReachabilityContext(
      candidateRootID: nodeID(1),
      activeEntityIdentities: [primaryEntity, duplicateEntity],
      liveEntityHomeByIdentity: [
        primaryEntity: nodeID(6),
        duplicateEntity: nodeID(7),
      ]
    )
    return (index, context, primaryEntity, duplicateEntity)
  }

  private func evaluateStoredNode(
    _ graph: ViewGraph,
    named name: String
  ) -> ViewNode {
    let identity = testIdentity("TeardownContextEquivalence", name)
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    _ = graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: identity, kind: .view(name)),
      accessedStateSlots: 0
    )
    return node
  }
}

private func nodeID(_ rawValue: Int) -> ViewNodeID {
  ViewNodeID(rawValue: UInt64(rawValue))
}

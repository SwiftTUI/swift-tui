// Producers and context construction for the unified lifetime relation.

extension ViewGraph {
  func lifetimeReachabilityContext(
    candidateRootID: ViewNodeID? = nil,
    activeEntities: Set<EntityIdentity> = []
  ) -> LifetimeReachabilityContext? {
    guard let candidateRootID = candidateRootID ?? root?.viewNodeID else {
      return nil
    }
    var qualifiedHomes: [EntityIdentity: ViewNodeID] = [:]
    for entity in activeEntities {
      guard let nodeID = entityRoutingTable.route(entity),
        let node = nodeIfExists(for: nodeID)
      else {
        continue
      }
      let facts = EntityHomeLifetimeFacts(
        entityIsActive: true,
        routeOwnsNode: true,
        occurrence: entity.occurrence,
        resolvedIdentityIndexOwnsNode:
          nodeIDByIdentity[node.resolvedIdentity] == nodeID
      )
      if entityHomeQualifiesForLifetime(facts) {
        qualifiedHomes[entity] = nodeID
      }
    }
    return LifetimeReachabilityContext(
      candidateRootID: candidateRootID,
      activeEntityIdentities: activeEntities,
      liveEntityHomeByIdentity: qualifiedHomes,
      parentedNodeIDs: Set(
        nodesByNodeID.values.compactMap { node in
          node.parent == nil ? nil : node.viewNodeID
        })
    )
  }

  package func replaceParentTargets(
    of parentNodeID: ViewNodeID,
    with children: [ViewNode]
  ) {
    guard nodeIfExists(for: parentNodeID) != nil else {
      lifetimeAnchors.removeNode(parentNodeID)
      return
    }
    let childNodeIDs = Set(
      children.compactMap { child in
        nodeIfExists(for: child.viewNodeID) === child ? child.viewNodeID : nil
      })
    lifetimeAnchors.replaceTargets(
      ofKind: .parent,
      sourcedBy: parentNodeID,
      with: childNodeIDs
    )
  }

  /// Projects nearest-distinct stamped committed-value edges in one linear
  /// walk of the accepted tree.
  func replaceCommittedValueAnchors(in acceptedRoot: ResolvedNode) {
    var targetsBySource: [ViewNodeID: Set<ViewNodeID>] = [:]
    var visitedSources: Set<ViewNodeID> = []
    var stack: [(resolved: ResolvedNode, source: ViewNodeID?, crossedValueOnlyLayer: Bool)] = [
      (acceptedRoot, nil, false)
    ]

    while let entry = stack.popLast() {
      let resolved = entry.resolved
      var source = entry.source
      var crossedValueOnlyLayer = entry.crossedValueOnlyLayer
      if let stampedNodeID = resolved.viewNodeID,
        let stampedNode = nodeIfExists(for: stampedNodeID)
      {
        visitedSources.insert(stampedNodeID)
        if let nearestStampedAncestor = entry.source,
          nearestStampedAncestor != stampedNodeID,
          stampedNode.parent?.viewNodeID == nearestStampedAncestor
            || (crossedValueOnlyLayer
              && (stampedNode.evaluationHost != nil
                || lifetimeAnchors.anchors(for: stampedNodeID).contains { anchor in
                  anchor.kind == .hostedDetached
                }))
        {
          targetsBySource[nearestStampedAncestor, default: []].insert(stampedNodeID)
        }
        source = stampedNodeID
        crossedValueOnlyLayer = false
      } else if entry.source != nil {
        crossedValueOnlyLayer = true
      }
      for child in resolved.children.reversed() {
        stack.append((child, source, crossedValueOnlyLayer))
      }
    }

    for source in visitedSources {
      lifetimeAnchors.replaceTargets(
        ofKind: .committedValue,
        sourcedBy: source,
        with: targetsBySource[source, default: []]
      )
    }
  }

  func bindEntityRoute(
    _ entity: EntityIdentity,
    to nodeID: ViewNodeID
  ) {
    entityRoutingTable.bind(entity, to: nodeID)
    if nodeIfExists(for: nodeID) != nil {
      lifetimeAnchors.rehomeEntity(entity, to: nodeID)
    } else {
      lifetimeAnchors.removeEntityHome(for: nodeID)
    }
  }

  func releaseEntityRoute(for nodeID: ViewNodeID) {
    entityRoutingTable.release(nodeID)
    lifetimeAnchors.removeEntityHome(for: nodeID)
  }

  func enqueueTeardownWork(
    _ reason: TeardownWorkReason,
    for nodeID: ViewNodeID
  ) {
    teardownBarrierWork.enqueue(reason, for: nodeID)
  }

  func consumeTeardownWork(
    _ reason: TeardownWorkReason,
    for nodeIDs: Set<ViewNodeID>
  ) {
    for nodeID in nodeIDs {
      teardownBarrierWork.remove(reason, for: nodeID)
    }
  }

  func discardTeardownWork(for nodeID: ViewNodeID) {
    teardownBarrierWork.removeNode(nodeID)
  }
}

// Shadow writers for Proposal -003's unified lifetime relation. Legacy
// ledgers remain authoritative until the Stage-5 consumer cutover.

extension ViewGraph {
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

  func replaceEvaluationHostAnchor(for node: ViewNode) {
    guard nodeIfExists(for: node.viewNodeID) === node else {
      lifetimeAnchors.removeNode(node.viewNodeID)
      return
    }
    let anchors: Set<LifetimeAnchor> =
      if let host = node.evaluationHost,
        nodeIfExists(for: host.viewNodeID) === host
      {
        [.evaluationHost(host.viewNodeID)]
      } else {
        []
      }
    lifetimeAnchors.replaceAnchors(
      ofKind: .evaluationHost,
      for: node.viewNodeID,
      with: anchors
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
                || detachedHostedSubtreeHostByRoot[stampedNodeID] != nil))
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
    switch reason {
    case .resolveScopeScratch:
      break
    case .entityRoutedRemoval:
      pendingEntityRoutedRemovalNodeIDs.insert(nodeID)
    case .absorbedShadow:
      absorbedShadowedNodeIDs.insert(nodeID)
    case .departedNavigationSurface:
      departedNavigationSurfaceContentNodeIDs.insert(nodeID)
    }
  }

  func consumeTeardownWork(
    _ reason: TeardownWorkReason,
    for nodeIDs: Set<ViewNodeID>
  ) {
    for nodeID in nodeIDs {
      teardownBarrierWork.remove(reason, for: nodeID)
    }
  }
}

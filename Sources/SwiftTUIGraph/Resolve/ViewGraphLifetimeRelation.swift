// Producers and context construction for the unified lifetime relation.

extension ViewGraph {
  func lifetimeReachabilityContext(
    candidateRootID: ViewNodeID? = nil,
    activeEntities: Set<EntityIdentity> = []
  ) -> LifetimeReachabilityContext? {
    #if DEBUG
      noteReachabilityContextBuild()
    #endif
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
      liveEntityHomeByIdentity: qualifiedHomes
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
  ///
  /// The walk runs per computed-node epilogue (`finishEvaluation`) and per
  /// retained serve, so its per-visited-node constant is serve-path-hot.
  /// It iterates sibling groups instead of pushing per-node value copies: a
  /// `ResolvedNode` carries ~ten refcounted fields, and copying one per
  /// visited node was the `initializeWithCopy for ResolvedNode` signature in
  /// the serve-path profile (plan 2026-08-12-003). A group entry retains one
  /// child-array buffer for the whole sibling run; per-node reads go through
  /// subscripts at +0.
  func replaceCommittedValueAnchors(in acceptedRoot: ResolvedNode) {
    var targetsBySource: [ViewNodeID: Set<ViewNodeID>] = [:]
    var visitedSources: Set<ViewNodeID> = []
    var nodesWalked = 0

    struct SiblingGroup {
      let siblings: [ResolvedNode]
      var nextIndex: Int
      let source: ViewNodeID?
      let crossedValueOnlyLayer: Bool
    }

    // Visits one node: records its nearest-distinct committed-value edge and
    // returns the (source, crossedValueOnlyLayer) pair its children inherit.
    func visit(
      stampedNodeID: ViewNodeID?,
      source: ViewNodeID?,
      crossedValueOnlyLayer: Bool
    ) -> (source: ViewNodeID?, crossedValueOnlyLayer: Bool) {
      nodesWalked += 1
      if let stampedNodeID,
        let stampedNode = nodeIfExists(for: stampedNodeID)
      {
        visitedSources.insert(stampedNodeID)
        // A `.id`-re-rooted node keeps a STALE `parent` back-reference to the
        // generation that last committed it as a child. When that generation
        // departs, the back-reference names an unstored (or aliased) object,
        // the adjacency test below rejects, and the node gets no
        // committed-value edge at all — even though the accepted tree really
        // does carry it under `nearestStampedAncestor`. Being in the accepted
        // committed value tree IS the claim, so a stale back-reference must
        // not veto it.
        let parentBackReferenceIsStale =
          stampedNode.parent.map { nodeIfExists(for: $0.viewNodeID) !== $0 } ?? false
        if let nearestStampedAncestor = source,
          nearestStampedAncestor != stampedNodeID,
          stampedNode.parent?.viewNodeID == nearestStampedAncestor
            || parentBackReferenceIsStale
            || (crossedValueOnlyLayer
              && (stampedNode.evaluationHost != nil
                || lifetimeAnchors.anchors(for: stampedNodeID).contains { anchor in
                  anchor.kind == .hostedDetached
                }))
        {
          targetsBySource[nearestStampedAncestor, default: []].insert(stampedNodeID)
        }
        return (stampedNodeID, false)
      }
      if source != nil {
        return (source, true)
      }
      return (source, crossedValueOnlyLayer)
    }

    let rootInherited = visit(
      stampedNodeID: acceptedRoot.viewNodeID,
      source: nil,
      crossedValueOnlyLayer: false
    )
    var stack: [SiblingGroup] = []
    if !acceptedRoot.children.isEmpty {
      stack.append(
        SiblingGroup(
          siblings: acceptedRoot.children,
          nextIndex: 0,
          source: rootInherited.source,
          crossedValueOnlyLayer: rootInherited.crossedValueOnlyLayer
        )
      )
    }
    while let top = stack.indices.last {
      let index = stack[top].nextIndex
      guard index < stack[top].siblings.count else {
        stack.removeLast()
        continue
      }
      stack[top].nextIndex = index + 1
      let inherited = visit(
        stampedNodeID: stack[top].siblings[index].viewNodeID,
        source: stack[top].source,
        crossedValueOnlyLayer: stack[top].crossedValueOnlyLayer
      )
      let grandchildren = stack[top].siblings[index].children
      if !grandchildren.isEmpty {
        stack.append(
          SiblingGroup(
            siblings: grandchildren,
            nextIndex: 0,
            source: inherited.source,
            crossedValueOnlyLayer: inherited.crossedValueOnlyLayer
          )
        )
      }
    }

    var replaceCalls = 0
    var replaceNoops = 0
    for source in visitedSources {
      replaceCalls += 1
      let changed = lifetimeAnchors.replaceTargets(
        ofKind: .committedValue,
        sourcedBy: source,
        with: targetsBySource[source, default: []]
      )
      if !changed {
        replaceNoops += 1
      }
    }
    resolveDiagnostics.recordAnchorWalk(
      nodesWalked: nodesWalked,
      replaceCalls: replaceCalls,
      replaceNoops: replaceNoops
    )
  }

  func bindEntityRoute(
    _ entity: EntityIdentity,
    to nodeID: ViewNodeID
  ) {
    entityRoutingTable.bind(entity, to: nodeID)
    if let node = nodeIfExists(for: nodeID) {
      node.noteHomedEntityIdentity(entity)
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

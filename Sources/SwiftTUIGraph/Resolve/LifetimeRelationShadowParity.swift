/// Shadow comparison between Proposal -003's relation and the legacy lifetime
/// ledgers. Legacy answers remain authoritative while this report is active.
package struct LifetimeRelationParityReport: Equatable, Sendable {
  package var legacyReachableNodeIDs: Set<ViewNodeID>
  package var relationReachableNodeIDs: Set<ViewNodeID>
  package var missingRelationNodeIDs: Set<ViewNodeID>
  package var extraRelationNodeIDs: Set<ViewNodeID>
  package var reasonDivergenceNodeIDs: Set<ViewNodeID>
  package var inverseViolations: [LifetimeAnchorInverseViolation]
  package var removedNodeReferenceDescriptions: [String]
  package var divergenceDescriptions: [String]
  package var legacyWork: LegacyTeardownWorkSnapshot
  package var relationWork: TeardownBarrierWork

  package var workMatches: Bool {
    var expected = TeardownBarrierWork()
    for nodeID in legacyWork.entityRoutedRemovalNodeIDs {
      expected.enqueue(.entityRoutedRemoval, for: nodeID)
    }
    for nodeID in legacyWork.absorbedShadowNodeIDs {
      expected.enqueue(.absorbedShadow, for: nodeID)
    }
    for nodeID in legacyWork.departedNavigationSurfaceNodeIDs {
      expected.enqueue(.departedNavigationSurface, for: nodeID)
    }
    return expected == relationWork
  }

  package var isEqual: Bool {
    missingRelationNodeIDs.isEmpty
      && extraRelationNodeIDs.isEmpty
      && reasonDivergenceNodeIDs.isEmpty
      && inverseViolations.isEmpty
      && removedNodeReferenceDescriptions.isEmpty
      && workMatches
  }

  package var detail: String {
    let smallest =
      missingRelationNodeIDs
      .union(extraRelationNodeIDs)
      .union(reasonDivergenceNodeIDs)
      .sorted()
      .first
      .map(String.init(describing:)) ?? "none"
    return """
      lifetime relation parity diverged: smallest=\(smallest) \
      missing=\(missingRelationNodeIDs.sorted()) \
      extra=\(extraRelationNodeIDs.sorted()) \
      reasons=\(reasonDivergenceNodeIDs.sorted()) \
      inverse=\(inverseViolations) \
      removedRefs=\(removedNodeReferenceDescriptions) \
      diagnostics=\(divergenceDescriptions) \
      workMatches=\(workMatches) legacyWork=\(legacyWork) relationWork=\(relationWork)
      """
  }
}

extension ViewGraph {
  package func debugLifetimeRelationParity(
    activeEntities: Set<EntityIdentity>
  ) -> LifetimeRelationParityReport? {
    guard let legacy = legacyLifetimeReachabilitySnapshot(),
      let rootNodeID = root?.viewNodeID
    else {
      return nil
    }

    guard
      var context = lifetimeReachabilityContext(
        candidateRootID: rootNodeID,
        activeEntities: activeEntities
      )
    else {
      return nil
    }
    context
      .liveEntityHomeByIdentity  // Entity homes qualify a local removal decision; the legacy teardown
    // census never promotes them to global committed-root seeds. Keep this
    // closure comparison on that same question. Stage-5 keep parity below
    // still supplies the qualified homes to `keepDecision`.
    = [:]
    let relation = lifetimeAnchors.reachableNodeIDs(context: context)
    let storedLegacyReachable = legacy.reachableNodeIDs.intersection(legacy.storedNodeIDs)
    let reasonDivergences = Set<ViewNodeID>(
      legacy.keepReasonsByNodeID.compactMap { nodeID, reason in
        guard legacy.storedNodeIDs.contains(nodeID) else {
          return nil
        }
        return legacyReasonHasRelationMirror(reason, nodeID: nodeID) ? nil : nodeID
      }
    )
    let storedNodeIDs = Set(nodesByNodeID.keys)
    var removedReferences: [String] = []
    for (nodeID, anchors) in lifetimeAnchors.anchorsByNodeID {
      if !storedNodeIDs.contains(nodeID) {
        removedReferences.append("target:\(nodeID):\(anchors)")
      }
      for anchor in anchors {
        if let source = anchor.sourceNodeID,
          !storedNodeIDs.contains(source)
        {
          removedReferences.append("source:\(source)->\(nodeID):\(anchor.kind)")
        }
      }
    }
    removedReferences.sort()

    let missing = storedLegacyReachable.subtracting(relation.nodeIDs)
    let extra = relation.nodeIDs.subtracting(storedLegacyReachable)
    let divergentNodeIDs = missing.union(extra).union(reasonDivergences)
    let divergenceDescriptions = divergentNodeIDs.sorted().prefix(4).map { nodeID in
      let node = nodesByNodeID[nodeID]
      let anchorSources = lifetimeAnchors.anchors(for: nodeID).compactMap { anchor in
        anchor.sourceNodeID.map { sourceNodeID in
          let sourcePath = nodesByNodeID[sourceNodeID]?.identity.path ?? "?"
          return "\(anchor.kind):\(sourceNodeID):\(sourcePath)"
        }
      }.sorted()
      return """
        \(nodeID) path=\(node?.identity.path ?? "?") \
        legacy=\(String(describing: legacy.keepReasonsByNodeID[nodeID])) \
        relation=\(lifetimeAnchors.anchors(for: nodeID)) \
        sources=\(anchorSources) \
        chain=\(String(describing: relation.anchorChain(to: nodeID))) \
        parent=\(String(describing: node?.parent?.viewNodeID)) \
        eval=\(String(describing: node?.evaluationHost?.viewNodeID)) \
        hosted=\(String(describing: detachedHostedSubtreeHostByRoot[nodeID]))
        """
    }

    return LifetimeRelationParityReport(
      legacyReachableNodeIDs: storedLegacyReachable,
      relationReachableNodeIDs: relation.nodeIDs,
      missingRelationNodeIDs: missing,
      extraRelationNodeIDs: extra,
      reasonDivergenceNodeIDs: reasonDivergences,
      inverseViolations: lifetimeAnchors.inverseConsistencyViolations(),
      removedNodeReferenceDescriptions: removedReferences,
      divergenceDescriptions: divergenceDescriptions,
      legacyWork: legacyTeardownWorkSnapshot(),
      relationWork: teardownBarrierWork
    )
  }

  func verifyLifetimeRelationParity(
    resolved: ResolvedNode
  ) {
    guard
      let report = debugLifetimeRelationParity(
        activeEntities: entityIdentities(in: resolved)
      )
    else {
      return
    }
    #if DEBUG
      precondition(report.isEqual, report.detail)
    #else
      if SoundnessProbeConfiguration.isSampledFrame, !report.isEqual {
        SoundnessProbeConfiguration.recordLifetimeRelationViolation(report.detail)
      }
    #endif
  }

  private func legacyReasonHasRelationMirror(
    _ reason: LegacyLifetimeReachabilityReason,
    nodeID: ViewNodeID
  ) -> Bool {
    let anchors = lifetimeAnchors.anchors(for: nodeID)
    switch reason {
    case .root:
      return root?.viewNodeID == nodeID
    case .structuralChild:
      // A re-adopted node can remain in the previous parent's lazily rewired
      // children array while its current parent edge already names the new
      // owner. The legacy reason's source is therefore not authoritative;
      // parity is between the structural/committed reason classes here.
      return anchors.contains { anchor in
        anchor.kind == .parent || anchor.kind == .committedValue
      }
    case .committedValue(let source):
      return anchors.contains(.committedValue(source))
    case .hostedDetached(let source):
      return anchors.contains(.hostedDetached(source))
    case .navigationSurface(let source):
      return anchors.contains(.navigationSurface(source))
    case .parent(let source):
      return anchors.contains(.parent(source))
        || anchors.contains(.committedValue(source))
    case .evaluationHost(let source):
      if anchors.contains(.evaluationHost(source)) {
        return true
      }
      // The weak host reason has no one-to-one mapping once an accepted
      // committed/hosted edge makes the same node durable. Reachability parity
      // is the authority in that case; the migration edge is required only
      // for census nodes with no durable incoming relation.
      return anchors.contains { anchor in
        switch anchor {
        case .parent, .committedValue, .hostedDetached, .navigationSurface:
          true
        case .entityHome, .evaluationHost:
          false
        }
      }
    }
  }
}

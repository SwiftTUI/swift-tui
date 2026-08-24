/// A durable reason that a runtime node remains reachable.
///
/// Anchors point from the associated source to the node that stores the anchor.
/// Entity homes are conditional seeds rather than node-to-node edges.
package enum LifetimeAnchor: Hashable, Sendable {
  case parent(ViewNodeID)
  case committedValue(ViewNodeID)
  case hostedDetached(ViewNodeID)
  case entityHome(EntityIdentity)
  case navigationSurface(ViewNodeID)

  package enum Kind: CaseIterable, Hashable, Sendable {
    case parent
    case committedValue
    case hostedDetached
    case entityHome
    case navigationSurface
  }

  package var kind: Kind {
    switch self {
    case .parent:
      .parent
    case .committedValue:
      .committedValue
    case .hostedDetached:
      .hostedDetached
    case .entityHome:
      .entityHome
    case .navigationSurface:
      .navigationSurface
    }
  }

  package var sourceNodeID: ViewNodeID? {
    switch self {
    case .parent(let source),
      .committedValue(let source),
      .hostedDetached(let source),
      .navigationSurface(let source):
      source
    case .entityHome:
      nil
    }
  }
}

/// Frame facts that qualify conditional lifetime edges.
package struct LifetimeReachabilityContext: Equatable, Sendable {
  package var candidateRootID: ViewNodeID
  package var activeEntityIdentities: Set<EntityIdentity>
  package var liveEntityHomeByIdentity: [EntityIdentity: ViewNodeID]

  package init(
    candidateRootID: ViewNodeID,
    activeEntityIdentities: Set<EntityIdentity> = [],
    liveEntityHomeByIdentity: [EntityIdentity: ViewNodeID] = [:]
  ) {
    self.candidateRootID = candidateRootID
    self.activeEntityIdentities = activeEntityIdentities
    self.liveEntityHomeByIdentity = liveEntityHomeByIdentity
  }
}

/// One deterministic step in the shortest known anchor chain to a node.
package enum LifetimeReachabilityStep: Equatable, Hashable, Sendable {
  case root(ViewNodeID)
  case entityHome(EntityIdentity, ViewNodeID)
  case anchor(LifetimeAnchor, target: ViewNodeID)
}

/// Reachability closure plus reproducible shortest-chain diagnostics.
package struct LifetimeReachabilityResult: Equatable, Sendable {
  package var nodeIDs: Set<ViewNodeID>
  package var chainByNodeID: [ViewNodeID: [LifetimeReachabilityStep]]

  package func anchorChain(
    to nodeID: ViewNodeID
  ) -> [LifetimeReachabilityStep]? {
    chainByNodeID[nodeID]
  }
}

package enum LifetimeKeepReason: Equatable, Hashable, Sendable {
  case anchor(LifetimeAnchor)
  case qualifiedEntityHome(EntityIdentity)
  case noAnchorOutsideRemovalCascade
}

package struct LifetimeKeepDecision: Equatable, Sendable {
  package var shouldKeep: Bool
  package var reason: LifetimeKeepReason
  package var diagnosticChain: [LifetimeReachabilityStep]
}

package enum LifetimeAnchorInverseDirection: Equatable, Hashable, Sendable {
  case forwardMissingFromInverse
  case inverseMissingFromForward
  case sourceMissingFromCanonical
  case canonicalMissingFromSource
}

package struct LifetimeAnchorInverseViolation: Equatable, Hashable, Sendable {
  package var direction: LifetimeAnchorInverseDirection
  package var nodeID: ViewNodeID
  package var anchor: LifetimeAnchor
}

package struct LifetimeUnreachableNodeForensics: Equatable, Sendable {
  package var nodeID: ViewNodeID
  package var incomingAnchors: [LifetimeAnchor]
  package var outgoingNodeIDs: [ViewNodeID]
}

/// Runtime-node lifetime relation with incoming, target, and source projections.
///
/// Every mutation goes through this value so all three projections move
/// atomically.
package struct LifetimeAnchorIndex: Equatable, Sendable {
  package var anchorsByNodeID: [ViewNodeID: Set<LifetimeAnchor>]
  package var nodeIDsByAnchor: [LifetimeAnchor: Set<ViewNodeID>]
  package var anchorsBySourceNodeID: [ViewNodeID: Set<LifetimeAnchor>]

  package var edgeCount: Int {
    anchorsByNodeID.values.reduce(into: 0) { count, anchors in
      count += anchors.count
    }
  }

  package init(
    anchorsByNodeID: [ViewNodeID: Set<LifetimeAnchor>] = [:],
    nodeIDsByAnchor: [LifetimeAnchor: Set<ViewNodeID>] = [:],
    anchorsBySourceNodeID: [ViewNodeID: Set<LifetimeAnchor>]? = nil
  ) {
    self.anchorsByNodeID = anchorsByNodeID
    self.nodeIDsByAnchor = nodeIDsByAnchor
    self.anchorsBySourceNodeID =
      anchorsBySourceNodeID ?? Self.sourceProjection(from: nodeIDsByAnchor)
  }

  package mutating func insert(
    anchor: LifetimeAnchor,
    for nodeID: ViewNodeID
  ) {
    anchorsByNodeID[nodeID, default: []].insert(anchor)
    nodeIDsByAnchor[anchor, default: []].insert(nodeID)
    if let sourceNodeID = anchor.sourceNodeID {
      anchorsBySourceNodeID[sourceNodeID, default: []].insert(anchor)
    }
  }

  package mutating func remove(
    anchor: LifetimeAnchor,
    for nodeID: ViewNodeID
  ) {
    anchorsByNodeID[nodeID]?.remove(anchor)
    if anchorsByNodeID[nodeID]?.isEmpty == true {
      anchorsByNodeID.removeValue(forKey: nodeID)
    }
    nodeIDsByAnchor[anchor]?.remove(nodeID)
    if nodeIDsByAnchor[anchor]?.isEmpty == true {
      nodeIDsByAnchor.removeValue(forKey: anchor)
      if let sourceNodeID = anchor.sourceNodeID {
        anchorsBySourceNodeID[sourceNodeID]?.remove(anchor)
        if anchorsBySourceNodeID[sourceNodeID]?.isEmpty == true {
          anchorsBySourceNodeID.removeValue(forKey: sourceNodeID)
        }
      }
    }
  }

  package mutating func replaceAnchors(
    ofKind kind: LifetimeAnchor.Kind,
    for nodeID: ViewNodeID,
    with anchors: Set<LifetimeAnchor>
  ) {
    precondition(anchors.allSatisfy { $0.kind == kind })
    for anchor in anchorsByNodeID[nodeID, default: []] where anchor.kind == kind {
      remove(anchor: anchor, for: nodeID)
    }
    for anchor in anchors {
      insert(anchor: anchor, for: nodeID)
    }
  }

  /// Re-homes one detached root, preserving the one-host-per-root invariant.
  package mutating func rehomeDetachedRoot(
    _ rootNodeID: ViewNodeID,
    to hostNodeID: ViewNodeID
  ) {
    replaceAnchors(
      ofKind: .hostedDetached,
      for: rootNodeID,
      with: [.hostedDetached(hostNodeID)]
    )
  }

  /// Re-homes an entity exactly as `EntityRoutingTable.bind` does: one node
  /// per entity and one entity per node.
  package mutating func rehomeEntity(
    _ entity: EntityIdentity,
    to nodeID: ViewNodeID
  ) {
    for previousNodeID in nodeIDsByAnchor[.entityHome(entity), default: []]
    where previousNodeID != nodeID {
      remove(anchor: .entityHome(entity), for: previousNodeID)
    }
    for previousAnchor in anchorsByNodeID[nodeID, default: []]
    where previousAnchor.kind == .entityHome && previousAnchor != .entityHome(entity) {
      remove(anchor: previousAnchor, for: nodeID)
    }
    insert(anchor: .entityHome(entity), for: nodeID)
  }

  package mutating func removeEntityHome(for nodeID: ViewNodeID) {
    for anchor in anchorsByNodeID[nodeID, default: []] where anchor.kind == .entityHome {
      remove(anchor: anchor, for: nodeID)
    }
  }

  /// Returns whether any edge actually changed. An unchanged target set —
  /// the common case for the per-node committed-value projection refresh —
  /// returns before allocating the two symmetric-difference sets.
  @discardableResult
  package mutating func replaceTargets(
    ofKind kind: LifetimeAnchor.Kind,
    sourcedBy sourceNodeID: ViewNodeID,
    with targetNodeIDs: Set<ViewNodeID>
  ) -> Bool {
    let anchor: LifetimeAnchor
    switch kind {
    case .parent:
      anchor = .parent(sourceNodeID)
    case .committedValue:
      anchor = .committedValue(sourceNodeID)
    case .hostedDetached:
      anchor = .hostedDetached(sourceNodeID)
    case .navigationSurface:
      anchor = .navigationSurface(sourceNodeID)
    case .entityHome:
      preconditionFailure("entity-home anchors have no ViewNodeID source")
    }
    let previous = nodeIDsByAnchor[anchor, default: []]
    guard previous != targetNodeIDs else {
      return false
    }
    for nodeID in previous.subtracting(targetNodeIDs) {
      remove(anchor: anchor, for: nodeID)
    }
    for nodeID in targetNodeIDs.subtracting(previous) {
      insert(anchor: anchor, for: nodeID)
    }
    return true
  }

  /// Replaces one host's active navigation targets and returns its departed set.
  @discardableResult
  package mutating func replaceNavigationSurfaces(
    hostedBy hostNodeID: ViewNodeID,
    with nodeIDs: Set<ViewNodeID>
  ) -> Set<ViewNodeID> {
    let anchor = LifetimeAnchor.navigationSurface(hostNodeID)
    let previous = nodeIDsByAnchor[anchor, default: []]
    guard previous != nodeIDs else {
      return []
    }
    for nodeID in previous.subtracting(nodeIDs) {
      remove(anchor: anchor, for: nodeID)
    }
    for nodeID in nodeIDs.subtracting(previous) {
      insert(anchor: anchor, for: nodeID)
    }
    return previous.subtracting(nodeIDs)
  }

  package func anchors(
    for nodeID: ViewNodeID
  ) -> Set<LifetimeAnchor> {
    anchorsByNodeID[nodeID, default: []]
  }

  package func targets(
    of anchor: LifetimeAnchor
  ) -> Set<ViewNodeID> {
    nodeIDsByAnchor[anchor, default: []]
  }

  /// All node-to-node targets sourced by `nodeID`, across anchor kinds.
  package func targets(
    of nodeID: ViewNodeID
  ) -> Set<ViewNodeID> {
    var result: Set<ViewNodeID> = []
    for anchor in anchorsBySourceNodeID[nodeID, default: []] {
      result.formUnion(nodeIDsByAnchor[anchor, default: []])
    }
    return result
  }

  /// Outgoing teardown cascade targets. Evaluation-host migration edges do not
  /// define removal descent.
  package func removalTargets(
    of nodeID: ViewNodeID
  ) -> Set<ViewNodeID> {
    var result: Set<ViewNodeID> = []
    for anchor in [
      LifetimeAnchor.parent(nodeID),
      .committedValue(nodeID),
      .hostedDetached(nodeID),
      .navigationSurface(nodeID),
    ] {
      result.formUnion(nodeIDsByAnchor[anchor, default: []])
    }
    return result
  }

  package func removalCascade(
    from rootNodeID: ViewNodeID
  ) -> Set<ViewNodeID> {
    var result: Set<ViewNodeID> = []
    var queue = [rootNodeID]
    var cursor = 0
    while cursor < queue.count {
      let nodeID = queue[cursor]
      cursor += 1
      guard result.insert(nodeID).inserted else {
        continue
      }
      queue.append(contentsOf: removalTargets(of: nodeID).sorted())
    }
    return result
  }

  /// Removes every incoming and outgoing edge that names `nodeID`.
  package mutating func removeNode(_ nodeID: ViewNodeID) {
    let incomingAnchors = Array(anchorsByNodeID[nodeID, default: []])
    for anchor in incomingAnchors {
      remove(anchor: anchor, for: nodeID)
    }
    // Snapshot the bucket before `remove` mutates the source projection.
    let outgoingAnchors = Array(anchorsBySourceNodeID[nodeID, default: []])
    for anchor in outgoingAnchors {
      let targetNodeIDs = Array(nodeIDsByAnchor[anchor, default: []])
      for targetNodeID in targetNodeIDs {
        remove(anchor: anchor, for: targetNodeID)
      }
    }
  }

  package func hasAnchorOutside(
    _ nodeID: ViewNodeID,
    excluding removalCascade: Set<ViewNodeID>,
    context: LifetimeReachabilityContext
  ) -> Bool {
    keepDecision(
      for: nodeID,
      removalCascade: removalCascade,
      context: context
    ).shouldKeep
  }

  package func keepDecision(
    for nodeID: ViewNodeID,
    removalCascade: Set<ViewNodeID>,
    context: LifetimeReachabilityContext
  ) -> LifetimeKeepDecision {
    let incoming = sortedAnchors(anchorsByNodeID[nodeID, default: []])
    for anchor in incoming {
      switch anchor {
      case .entityHome(let entity):
        if entityHomeIsQualified(entity, nodeID: nodeID, context: context) {
          return LifetimeKeepDecision(
            shouldKeep: true,
            reason: .qualifiedEntityHome(entity),
            diagnosticChain: [.entityHome(entity, nodeID)]
          )
        }
      default:
        if let source = anchor.sourceNodeID,
          !removalCascade.contains(source)
        {
          return LifetimeKeepDecision(
            shouldKeep: true,
            reason: .anchor(anchor),
            diagnosticChain: [.root(source), .anchor(anchor, target: nodeID)]
          )
        }
      }
    }
    return LifetimeKeepDecision(
      shouldKeep: false,
      reason: .noAnchorOutsideRemovalCascade,
      diagnosticChain: []
    )
  }

  package func qualifiedEntityHome(
    for nodeID: ViewNodeID,
    context: LifetimeReachabilityContext
  ) -> EntityIdentity? {
    sortedAnchors(anchorsByNodeID[nodeID, default: []]).compactMap { anchor -> EntityIdentity? in
      guard case .entityHome(let entity) = anchor,
        entityHomeIsQualified(entity, nodeID: nodeID, context: context)
      else {
        return nil
      }
      return entity
    }.first
  }

  package mutating func removeRemovalEdges(
    from sourceNodeID: ViewNodeID,
    to targetNodeID: ViewNodeID
  ) {
    for anchor in [
      LifetimeAnchor.parent(sourceNodeID),
      .committedValue(sourceNodeID),
      .hostedDetached(sourceNodeID),
      .navigationSurface(sourceNodeID),
    ] {
      remove(anchor: anchor, for: targetNodeID)
    }
  }

  package func reachableNodeIDs(
    from rootNodeIDs: Set<ViewNodeID> = [],
    context: LifetimeReachabilityContext
  ) -> LifetimeReachabilityResult {
    var reachable: Set<ViewNodeID> = []
    var chainByNodeID: [ViewNodeID: [LifetimeReachabilityStep]] = [:]
    var queue: [ViewNodeID] = []

    func enqueue(
      _ nodeID: ViewNodeID,
      chain: [LifetimeReachabilityStep]
    ) {
      guard reachable.insert(nodeID).inserted else {
        return
      }
      chainByNodeID[nodeID] = chain
      queue.append(nodeID)
    }

    var roots = rootNodeIDs
    roots.insert(context.candidateRootID)
    for nodeID in roots.sorted() {
      enqueue(nodeID, chain: [.root(nodeID)])
    }

    for entity in context.liveEntityHomeByIdentity.keys.sorted(by: entityIdentityLessThan) {
      guard let nodeID = context.liveEntityHomeByIdentity[entity],
        entityHomeIsQualified(entity, nodeID: nodeID, context: context),
        nodeIDsByAnchor[.entityHome(entity), default: []].contains(nodeID)
      else {
        continue
      }
      enqueue(nodeID, chain: [.entityHome(entity, nodeID)])
    }

    var cursor = 0
    while cursor < queue.count {
      let source = queue[cursor]
      cursor += 1
      for (anchor, target) in sortedOutgoingEdges(from: source) {
        enqueue(
          target,
          chain: chainByNodeID[source, default: []] + [.anchor(anchor, target: target)]
        )
      }
    }
    return LifetimeReachabilityResult(
      nodeIDs: reachable,
      chainByNodeID: chainByNodeID
    )
  }

  package func anchorChain(
    to nodeID: ViewNodeID,
    from rootNodeIDs: Set<ViewNodeID> = [],
    context: LifetimeReachabilityContext
  ) -> [LifetimeReachabilityStep]? {
    reachableNodeIDs(from: rootNodeIDs, context: context).anchorChain(to: nodeID)
  }

  package func unreachableNodeForensics(
    storedNodeIDs: Set<ViewNodeID>,
    from rootNodeIDs: Set<ViewNodeID> = [],
    context: LifetimeReachabilityContext,
    limit: Int = 8
  ) -> [LifetimeUnreachableNodeForensics] {
    let reachable = reachableNodeIDs(from: rootNodeIDs, context: context).nodeIDs
    return storedNodeIDs.subtracting(reachable).sorted().prefix(max(0, limit)).map { nodeID in
      LifetimeUnreachableNodeForensics(
        nodeID: nodeID,
        incomingAnchors: sortedAnchors(anchorsByNodeID[nodeID, default: []]),
        outgoingNodeIDs: targets(of: nodeID).sorted()
      )
    }
  }

  package func inverseConsistencyViolations() -> [LifetimeAnchorInverseViolation] {
    var violations: Set<LifetimeAnchorInverseViolation> = []
    for (nodeID, anchors) in anchorsByNodeID {
      for anchor in anchors where !nodeIDsByAnchor[anchor, default: []].contains(nodeID) {
        violations.insert(
          LifetimeAnchorInverseViolation(
            direction: .forwardMissingFromInverse,
            nodeID: nodeID,
            anchor: anchor
          )
        )
      }
    }
    for (anchor, nodeIDs) in nodeIDsByAnchor {
      for nodeID in nodeIDs where !anchorsByNodeID[nodeID, default: []].contains(anchor) {
        violations.insert(
          LifetimeAnchorInverseViolation(
            direction: .inverseMissingFromForward,
            nodeID: nodeID,
            anchor: anchor
          )
        )
      }
    }
    for (sourceNodeID, anchors) in anchorsBySourceNodeID {
      for anchor in anchors
      where anchor.sourceNodeID != sourceNodeID
        || nodeIDsByAnchor[anchor, default: []].isEmpty
      {
        violations.insert(
          LifetimeAnchorInverseViolation(
            direction: .sourceMissingFromCanonical,
            nodeID: sourceNodeID,
            anchor: anchor
          )
        )
      }
    }
    for (anchor, nodeIDs) in nodeIDsByAnchor where !nodeIDs.isEmpty {
      guard let sourceNodeID = anchor.sourceNodeID,
        !anchorsBySourceNodeID[sourceNodeID, default: []].contains(anchor)
      else {
        continue
      }
      violations.insert(
        LifetimeAnchorInverseViolation(
          direction: .canonicalMissingFromSource,
          nodeID: sourceNodeID,
          anchor: anchor
        )
      )
    }
    return violations.sorted(by: inverseViolationLessThan)
  }

  package var isInverseConsistent: Bool {
    inverseConsistencyViolations().isEmpty
  }

  private func entityHomeIsQualified(
    _ entity: EntityIdentity,
    nodeID: ViewNodeID,
    context: LifetimeReachabilityContext
  ) -> Bool {
    context.activeEntityIdentities.contains(entity)
      && context.liveEntityHomeByIdentity[entity] == nodeID
  }

  private func sortedOutgoingEdges(
    from source: ViewNodeID
  ) -> [(LifetimeAnchor, ViewNodeID)] {
    var result: [(LifetimeAnchor, ViewNodeID)] = []
    for anchor in anchorsBySourceNodeID[source, default: []] {
      for nodeID in nodeIDsByAnchor[anchor, default: []] {
        result.append((anchor, nodeID))
      }
    }
    return result.sorted { lhs, rhs in
      if lifetimeAnchorLessThan(lhs.0, rhs.0) {
        return true
      }
      if lifetimeAnchorLessThan(rhs.0, lhs.0) {
        return false
      }
      return lhs.1 < rhs.1
    }
  }

  private static func sourceProjection(
    from nodeIDsByAnchor: [LifetimeAnchor: Set<ViewNodeID>]
  ) -> [ViewNodeID: Set<LifetimeAnchor>] {
    var result: [ViewNodeID: Set<LifetimeAnchor>] = [:]
    for (anchor, nodeIDs) in nodeIDsByAnchor where !nodeIDs.isEmpty {
      if let sourceNodeID = anchor.sourceNodeID {
        result[sourceNodeID, default: []].insert(anchor)
      }
    }
    return result
  }
}

private func sortedAnchors(
  _ anchors: Set<LifetimeAnchor>
) -> [LifetimeAnchor] {
  anchors.sorted(by: lifetimeAnchorLessThan)
}

private func entityIdentityLessThan(
  _ lhs: EntityIdentity,
  _ rhs: EntityIdentity
) -> Bool {
  if lhs.description != rhs.description {
    return lhs.description < rhs.description
  }
  return lhs.occurrence < rhs.occurrence
}

private func lifetimeAnchorLessThan(
  _ lhs: LifetimeAnchor,
  _ rhs: LifetimeAnchor
) -> Bool {
  func rank(_ kind: LifetimeAnchor.Kind) -> Int {
    switch kind {
    case .parent: 0
    case .committedValue: 1
    case .hostedDetached: 2
    case .entityHome: 3
    case .navigationSurface: 4
    }
  }
  let lhsRank = rank(lhs.kind)
  let rhsRank = rank(rhs.kind)
  if lhsRank != rhsRank {
    return lhsRank < rhsRank
  }
  switch (lhs, rhs) {
  case (.entityHome(let lhsEntity), .entityHome(let rhsEntity)):
    return entityIdentityLessThan(lhsEntity, rhsEntity)
  default:
    return lhs.sourceNodeID! < rhs.sourceNodeID!
  }
}

private func inverseViolationLessThan(
  _ lhs: LifetimeAnchorInverseViolation,
  _ rhs: LifetimeAnchorInverseViolation
) -> Bool {
  if lhs.nodeID != rhs.nodeID {
    return lhs.nodeID < rhs.nodeID
  }
  if lifetimeAnchorLessThan(lhs.anchor, rhs.anchor) {
    return true
  }
  if lifetimeAnchorLessThan(rhs.anchor, lhs.anchor) {
    return false
  }
  func rank(_ direction: LifetimeAnchorInverseDirection) -> Int {
    switch direction {
    case .forwardMissingFromInverse: 0
    case .inverseMissingFromForward: 1
    case .sourceMissingFromCanonical: 2
    case .canonicalMissingFromSource: 3
    }
  }
  return rank(lhs.direction) < rank(rhs.direction)
}

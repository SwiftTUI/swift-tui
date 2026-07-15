extension ViewGraph {
  func lifetimeRelationReachabilitySnapshot()
    -> LegacyLifetimeReachabilitySnapshot?
  {
    guard let root,
      var context = lifetimeReachabilityContext(
        candidateRootID: root.viewNodeID
      )
    else {
      return nil
    }

    // Entity routes qualify local teardown decisions; they do not turn a
    // detached node into a committed-root census seed.
    context.liveEntityHomeByIdentity = [:]
    let relation = lifetimeAnchors.reachableNodeIDs(context: context)
    var reasons: [ViewNodeID: LegacyLifetimeReachabilityReason] = [:]
    for (nodeID, chain) in relation.chainByNodeID {
      guard let last = chain.last else {
        continue
      }
      switch last {
      case .root:
        reasons[nodeID] = .root
      case .entityHome:
        break
      case .anchor(let anchor, _):
        switch anchor {
        case .parent(let source):
          reasons[nodeID] = .parent(source)
        case .committedValue(let source):
          reasons[nodeID] = .committedValue(source)
        case .hostedDetached(let source):
          reasons[nodeID] = .hostedDetached(source)
        case .navigationSurface(let source):
          reasons[nodeID] = .navigationSurface(source)
        case .evaluationHost(let source):
          reasons[nodeID] = .evaluationHost(source)
        case .entityHome:
          break
        }
      }
    }

    // Stale-alias detection remains a structural object-integrity check, not
    // a lifetime-policy read. Walk the committed child objects exactly once.
    var staleAliasDetail: String?
    var visited: Set<ViewNodeID> = []
    var stack = [root]
    while let node = stack.popLast() {
      guard visited.insert(node.viewNodeID).inserted else {
        continue
      }
      if let stored = nodesByNodeID[node.viewNodeID],
        stored !== node
      {
        staleAliasDetail = """
          teardown coherence: committed structure holds a stale copy of \
          \(node.viewNodeID) at \(node.identity.path)
          """
        break
      }
      stack.append(contentsOf: node.children)
    }

    return LegacyLifetimeReachabilitySnapshot(
      storedNodeIDs: Set(nodesByNodeID.keys),
      reachableNodeIDs: relation.nodeIDs,
      keepReasonsByNodeID: reasons,
      staleAliasDetail: staleAliasDetail
    )
  }
}

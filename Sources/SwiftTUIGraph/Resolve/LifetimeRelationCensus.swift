extension ViewGraph {
  func lifetimeReachabilitySnapshot()
    -> LifetimeReachabilitySnapshot?
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

    return LifetimeReachabilitySnapshot(
      storedNodeIDs: Set(nodesByNodeID.keys),
      reachableNodeIDs: relation.nodeIDs,
      staleAliasDetail: staleAliasDetail
    )
  }
}

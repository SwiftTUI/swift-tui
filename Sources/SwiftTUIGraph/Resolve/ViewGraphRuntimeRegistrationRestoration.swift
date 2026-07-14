@MainActor
package enum ViewGraphRuntimeRegistrationRestorer {
  package static func restoreLiveIdentities(
    _ viewNodeIDs: Set<ViewNodeID>,
    into registrations: RuntimeRegistrationSet,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    let nodes = viewNodeIDs.compactMap { nodesByNodeID[$0] }
    for node in nodes.sorted(by: canonicalNodeOrder) {
      node.restoreOwnRuntimeRegistrations(into: registrations)
    }
  }

  private static func canonicalNodeOrder(
    lhs: ViewNode,
    rhs: ViewNode
  ) -> Bool {
    if lhs.identity == rhs.identity {
      return lhs.viewNodeID < rhs.viewNodeID
    }
    return lhs.identity < rhs.identity
  }

  package static func restoreResolvedSubtree(
    _ resolved: ResolvedNode,
    into registrations: RuntimeRegistrationSet,
    nodesByNodeID: [ViewNodeID: ViewNode],
    nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
  ) {
    var restoredNodeIDs: Set<ViewNodeID> = []
    restoreResolvedSubtree(
      resolved,
      into: registrations,
      nodesByNodeID: nodesByNodeID,
      nodeIDsByStructuralPath: nodeIDsByStructuralPath,
      restoredNodeIDs: &restoredNodeIDs
    )
  }

  /// The action-registration identities carried by the graph nodes of a
  /// reused resolved subtree, in resolved-tree order (children in authored
  /// order, matched nodes in canonical order, identities sorted within one
  /// node). Consumers that re-point cached registrations at current
  /// closures (the toolbar strip's reuse refresh) derive their target
  /// identities from the same node records `restoreResolvedSubtree`
  /// replays, so a lowering change can never strand the refresh on a
  /// hand-mirrored stale identity path (F175).
  package static func actionRegistrationIdentities(
    in resolved: ResolvedNode,
    nodesByNodeID: [ViewNodeID: ViewNode],
    nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
  ) -> [Identity] {
    var visitedNodeIDs: Set<ViewNodeID> = []
    var seenIdentities: Set<Identity> = []
    var identities: [Identity] = []
    var work: [ResolvedNode] = [resolved]
    while let current = work.popLast() {
      var nodeIDs = nodeIDsByStructuralPath[current.structuralPath] ?? []
      if let viewNodeID = current.viewNodeID {
        nodeIDs.insert(viewNodeID)
      }
      let nodes = nodeIDs.compactMap { nodesByNodeID[$0] }
      for node in nodes.sorted(by: canonicalNodeOrder) {
        guard visitedNodeIDs.insert(node.viewNodeID).inserted else {
          continue
        }
        for identity in node.registeredHandlers.action.registrations.keys.sorted()
        where seenIdentities.insert(identity).inserted {
          identities.append(identity)
        }
      }
      work.append(contentsOf: current.children.reversed())
    }
    return identities
  }

  private static func restoreResolvedSubtree(
    _ resolved: ResolvedNode,
    into registrations: RuntimeRegistrationSet,
    nodesByNodeID: [ViewNodeID: ViewNode],
    nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>],
    restoredNodeIDs: inout Set<ViewNodeID>
  ) {
    var nodeIDs = nodeIDsByStructuralPath[resolved.structuralPath] ?? []
    if let viewNodeID = resolved.viewNodeID {
      nodeIDs.insert(viewNodeID)
    }

    let nodes = nodeIDs.compactMap { nodesByNodeID[$0] }
    for node in nodes.sorted(by: canonicalNodeOrder) {
      guard restoredNodeIDs.insert(node.viewNodeID).inserted else {
        continue
      }
      node.restoreOwnRuntimeRegistrations(
        into: registrations
      )
    }

    for child in resolved.children {
      restoreResolvedSubtree(
        child,
        into: registrations,
        nodesByNodeID: nodesByNodeID,
        nodeIDsByStructuralPath: nodeIDsByStructuralPath,
        restoredNodeIDs: &restoredNodeIDs
      )
    }
  }
}

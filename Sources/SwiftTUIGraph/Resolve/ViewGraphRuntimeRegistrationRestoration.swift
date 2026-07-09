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

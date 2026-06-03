@MainActor
enum ViewGraphInvalidationPlanner {
  static func invalidate(
    _ viewNodeIDs: Set<ViewNodeID>,
    invalidatedNodeIDs: inout Set<ViewNodeID>,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    invalidatedNodeIDs.formUnion(viewNodeIDs)
    markDirty(viewNodeIDs, nodesByNodeID: nodesByNodeID)
  }

  static func invalidateAndQueueDirty(
    _ viewNodeIDs: Set<ViewNodeID>,
    invalidatedNodeIDs: inout Set<ViewNodeID>,
    graphLocalDirtyNodeIDs: inout Set<ViewNodeID>,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    invalidatedNodeIDs.formUnion(viewNodeIDs)
    for viewNodeID in viewNodeIDs {
      guard let node = nodesByNodeID[viewNodeID] else {
        continue
      }
      node.markDirty()
      graphLocalDirtyNodeIDs.insert(viewNodeID)
    }
  }

  static func queueDirty(
    _ viewNodeIDs: Set<ViewNodeID>,
    graphLocalDirtyNodeIDs: inout Set<ViewNodeID>,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    graphLocalDirtyNodeIDs.formUnion(viewNodeIDs)
    markDirty(viewNodeIDs, nodesByNodeID: nodesByNodeID)
  }

  static func stateChangeDirtyNodeIDs(
    for key: StateSlotKey,
    ownerNodeID: ViewNodeID?,
    stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
  ) -> Set<ViewNodeID> {
    var result = stateSlotDependents[key] ?? []
    if let ownerNodeID {
      result.insert(ownerNodeID)
    }
    return result
  }

  static func observationChangeDirtyNodeIDs(
    observedBy viewNodeID: ViewNodeID,
    nodesByNodeID: [ViewNodeID: ViewNode],
    observableDependents: [ObjectIdentifier: Set<ViewNodeID>]
  ) -> Set<ViewNodeID> {
    Set([viewNodeID]).union(
      ViewGraphDependencyIndex.observableDependents(
        triggeredBy: viewNodeID,
        nodesByNodeID: nodesByNodeID,
        observableDependents: observableDependents
      )
    )
  }

  static func environmentReaderDirtyNodeIDs(
    within identities: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>,
    environmentDependents: [ObjectIdentifier: Set<ViewNodeID>],
    identityByNodeID: [ViewNodeID: Identity]
  ) -> Set<ViewNodeID> {
    ViewGraphDependencyIndex.environmentDependents(
      within: identities,
      changedKeys: changedKeys,
      environmentDependents: environmentDependents,
      identityByNodeID: identityByNodeID
    )
  }

  private static func markDirty(
    _ viewNodeIDs: Set<ViewNodeID>,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    for viewNodeID in viewNodeIDs {
      nodesByNodeID[viewNodeID]?.markDirty()
    }
  }
}

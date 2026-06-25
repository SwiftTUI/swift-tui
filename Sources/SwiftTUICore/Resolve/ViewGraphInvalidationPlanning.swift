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
    stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
  ) -> Set<ViewNodeID> {
    var result = stateSlotDependents[key] ?? []
    // Legacy: always dirty the owner (defense-in-depth for deferred / conditional
    // reads). Reader-attributed mode dirties only genuine readers — a
    // projection-only owner is recorded as no reader and is therefore spared,
    // which is what takes sheet/palette open from O(background) to O(overlay).
    if !ReaderAttributionConfiguration.isEnabled {
      result.insert(key.owner)
    }
    return result
  }

  static func observationChangeDirtyNodeIDs(
    observedBy viewNodeID: ViewNodeID,
    nodesByNodeID: [ViewNodeID: ViewNode],
    observableDependents: [ObjectIdentifier: Set<ViewNodeID>],
    observableKeyPathDependents: [ObservableKeyPathKey: Set<ViewNodeID>]
  ) -> Set<ViewNodeID> {
    // Precise firing: the `withObservationTracking` onChange already fired for
    // exactly the node that read the mutated property, so the firing node alone
    // is the correct dirty set. Dropping the co-reader union stops a `\.hot`
    // write from dirtying `\.cold`/`\.rare` peers on the same object token.
    if PreciseObservationFiringConfiguration.isEnabled {
      return Set([viewNodeID])
    }
    // Key-path narrowing: keep the firing node and the co-readers that recorded
    // one of its key paths, dropping different-key-path peers — but only when
    // every co-reader is key-path-attributed (else fall back to the object
    // union below, over-invalidate rather than miss).
    if ObservableKeyPathInvalidationConfiguration.isEnabled,
      let narrowed = ViewGraphDependencyIndex.keyPathNarrowedObservableDependents(
        triggeredBy: viewNodeID,
        nodesByNodeID: nodesByNodeID,
        observableDependents: observableDependents,
        observableKeyPathDependents: observableKeyPathDependents
      )
    {
      return Set([viewNodeID]).union(narrowed)
    }
    return Set([viewNodeID]).union(
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

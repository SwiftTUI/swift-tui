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

  // Takes the whole `DirtyState` group as ONE `inout` value: the caller's two
  // dirty sets live in the same stored group property, and two simultaneous
  // `inout` projections of one class ivar are a dynamic exclusivity violation
  // under the `_modify` field accessors.
  static func invalidateAndQueueDirty(
    _ viewNodeIDs: Set<ViewNodeID>,
    dirtyState: inout ViewGraph.DirtyState,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    dirtyState.invalidatedNodeIDs.formUnion(viewNodeIDs)
    for viewNodeID in viewNodeIDs {
      guard let node = nodesByNodeID[viewNodeID] else {
        continue
      }
      node.markDirty()
      dirtyState.graphLocalDirtyNodeIDs.insert(viewNodeID)
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

  static func stateChangeDirtyOwnerLifetimeIDs(
    for key: StateSlotKey,
    stateSlotDependents: [StateSlotKey: Set<NodeOwnerLifetimeID>]
  ) -> Set<NodeOwnerLifetimeID> {
    // Reader-attributed: dirty only the genuine readers — a projection-only owner
    // is recorded as no reader and is therefore spared, which is what takes
    // sheet/palette open from O(background) to O(overlay). The write side
    // (`ViewNode.stateChangeInvalidationIdentities`) falls back to the owner when
    // no readers were recorded (deferred / conditional reads), so a change is
    // never dropped.
    stateSlotDependents[key] ?? []
  }

  static func observationChangeDirtyNodeIDs(
    observedBy viewNodeID: ViewNodeID
  ) -> Set<ViewNodeID> {
    // Precise firing: the `withObservationTracking` onChange already fired for
    // exactly the node that read the mutated property, so the firing node alone
    // is the correct dirty set. Dropping the co-reader union stops a `\.hot`
    // write from dirtying `\.cold`/`\.rare` peers on the same object token. A node
    // that records an object token cannot be memo-reused, so it always re-resolves
    // and re-arms its tracking — it cannot go deaf.
    Set([viewNodeID])
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

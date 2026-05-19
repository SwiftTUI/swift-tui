@MainActor
enum ViewGraphInvalidationPlanner {
  static func invalidate(
    _ identities: Set<Identity>,
    invalidatedIdentities: inout Set<Identity>,
    nodesByIdentity: [Identity: ViewNode]
  ) {
    invalidatedIdentities.formUnion(identities)
    markDirty(identities, nodesByIdentity: nodesByIdentity)
  }

  static func invalidateAndQueueDirty(
    _ identities: Set<Identity>,
    invalidatedIdentities: inout Set<Identity>,
    graphLocalDirtyIdentities: inout Set<Identity>,
    nodesByIdentity: [Identity: ViewNode]
  ) {
    invalidatedIdentities.formUnion(identities)
    for identity in identities {
      guard let node = nodesByIdentity[identity] else {
        continue
      }
      node.markDirty()
      graphLocalDirtyIdentities.insert(identity)
    }
  }

  static func queueDirty(
    _ identities: Set<Identity>,
    graphLocalDirtyIdentities: inout Set<Identity>,
    nodesByIdentity: [Identity: ViewNode]
  ) {
    graphLocalDirtyIdentities.formUnion(identities)
    markDirty(identities, nodesByIdentity: nodesByIdentity)
  }

  static func stateChangeDirtyIdentities(
    for key: StateSlotKey,
    stateSlotDependents: [StateSlotKey: Set<Identity>]
  ) -> Set<Identity> {
    Set([key.identity]).union(stateSlotDependents[key] ?? [])
  }

  static func observationChangeDirtyIdentities(
    observedBy identity: Identity,
    nodesByIdentity: [Identity: ViewNode],
    observableDependents: [ObjectIdentifier: Set<Identity>]
  ) -> Set<Identity> {
    Set([identity]).union(
      ViewGraphDependencyIndex.observableDependents(
        triggeredBy: identity,
        nodesByIdentity: nodesByIdentity,
        observableDependents: observableDependents
      )
    )
  }

  static func environmentReaderDirtyIdentities(
    within identities: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>,
    environmentDependents: [ObjectIdentifier: Set<Identity>]
  ) -> Set<Identity> {
    ViewGraphDependencyIndex.environmentDependents(
      within: identities,
      changedKeys: changedKeys,
      environmentDependents: environmentDependents
    )
  }

  private static func markDirty(
    _ identities: Set<Identity>,
    nodesByIdentity: [Identity: ViewNode]
  ) {
    for identity in identities {
      nodesByIdentity[identity]?.markDirty()
    }
  }
}

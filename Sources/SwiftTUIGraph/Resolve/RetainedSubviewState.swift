/// Persistent state owned by a declaring container while its captured content
/// has no presentation host. Unlike a lazy tab's value-only dormant archive,
/// this keeps authored reference values alive for the container's lifetime.
/// It retains no graph node, evaluator, dependency, or runtime registration.
@MainActor
package struct RetainedSubviewState {
  package struct Record {
    package var identity: Identity
    package var entityIdentity: EntityIdentity?
    package var slots: [StateSlotIdentifier: AnyStateSlot]
  }

  package var records: [Record]
}

extension ViewGraph {
  package func captureRetainedSubviewState(
    using locator: DormantStateArchiveLocator
  ) -> RetainedSubviewState {
    let records = locator.nodeIDs.compactMap { nodeID -> RetainedSubviewState.Record? in
      guard let node = nodeForViewNodeID(nodeID) else { return nil }
      let slots = node.stateSlots.filter { $0.value.dormantPolicy == .persistent }
      let entity = node.committed.entityIdentity ?? node.lastHomedEntityIdentity
      guard !slots.isEmpty || entity != nil else { return nil }
      return .init(identity: node.identity, entityIdentity: entity, slots: slots)
    }
    return .init(records: records.sorted { $0.identity < $1.identity })
  }

  /// Prepare routes without displacing another owner at a co-resident
  /// structural identity. Authored resolution claims the matching entity;
  /// normal frame teardown reclaims records no longer present in the content.
  package func restoreRetainedSubviewState(_ state: RetainedSubviewState) {
    for record in state.records {
      let node: ViewNode
      if let entity = record.entityIdentity {
        node = prepareEntityRoutedOwnerPreservingCoResidentIdentity(
          identity: record.identity, entityIdentity: entity)
      } else {
        node = prepareDynamicPropertyUpdate(identity: record.identity)
      }
      for (identifier, slot) in record.slots {
        node.restoreStateSlot(identifier, slot: slot)
      }
    }
  }
}

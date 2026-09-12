/// Persistent state owned by a declaring container while its captured content
/// has no presentation host. Like a lazy tab's authored-state archive,
/// this keeps model references alive for the container's lifetime.
/// It retains no graph node, evaluator, dependency, or runtime registration.
@MainActor
package struct RetainedSubviewState {
  package struct Record {
    package var identity: Identity
    package var entityIdentity: EntityIdentity?
    package var slots: [StateSlotIdentifier: AnyStateSlot]
  }

  package var records: [Record]
  private var dormantArchive: DormantStateArchive? = nil

  package init(records: [Record]) { self.records = records }

  package var restorationRecords: [Record] {
    guard let dormantArchive else { return records }
    return dormantArchive.records.map {
      Record(
        identity: $0.identity, entityIdentity: $0.entityIdentity,
        slots: $0.stateSlots.mapValues { AnyStateSlot(restoringDormant: $0) })
    }
  }
}

extension RetainedSubviewState: DormantStateProjecting {
  package func dormantStateProjection() -> Self? {
    if dormantArchive != nil { return self }
    var projected: [DormantStateArchive.NodeRecord] = []
    for record in records {
      var slots: [StateSlotIdentifier: DormantStateSlotSnapshot] = [:]
      for (identifier, slot) in record.slots {
        // Project slot storage without carrying its comparator or live owner.
        guard let snapshot = slot.dormantSnapshot() else { return nil }
        slots[identifier] = snapshot
      }
      projected.append(
        .init(
          identity: record.identity, entityIdentity: record.entityIdentity,
          stateSlots: slots))
    }
    var result = Self(records: [])
    result.dormantArchive = DormantStateArchive(records: projected)
    return result
  }
}

extension ViewGraph {
  package func captureRetainedSubviewState(
    using locator: DormantStateArchiveLocator
  ) -> RetainedSubviewState {
    let records = locator.nodeIDs.compactMap { nodeID -> RetainedSubviewState.Record? in
      guard let node = nodeForViewNodeID(nodeID) else { return nil }
      let slots = node.stateSlots.filter { $0.value.dormantPolicy.survivesDormancy }
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
    for record in state.restorationRecords {
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

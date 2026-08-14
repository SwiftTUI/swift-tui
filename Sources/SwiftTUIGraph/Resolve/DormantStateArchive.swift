/// Persistent value state captured for a temporarily dormant lazy payload.
///
/// This is deliberately not a `ViewNode.Checkpoint`: it stores no nodes,
/// children, resolved output, registrations, handlers, dependencies,
/// observations, lifecycle phase, or evaluator closures. Each record contains
/// only the subset of a node's state slots whose producer explicitly marked
/// them persistent for dormancy. Empty-slot records are closure-free entity
/// routing anchors: they preserve just enough owner topology for descendant
/// state records to rejoin the same lifetime after the live nodes are torn
/// down; they do not retain a node or any of its runtime fields.
@MainActor
package struct DormantStateArchive {
  package struct NodeRecord {
    package var identity: Identity
    package var entityIdentity: EntityIdentity?
    package var stateSlots: [StateSlotIdentifier: DormantStateSlotSnapshot]
  }

  package var records: [NodeRecord]

  package init(records: [NodeRecord] = []) {
    self.records = records
  }

  package var persistentSlotCount: Int {
    records.reduce(into: 0) { $0 += $1.stateSlots.count }
  }
}

/// A transient lookup recipe for the nodes stamped into the currently active
/// lazy payload. It retains IDs only, never graph nodes or runtime effects.
@MainActor
package struct DormantStateArchiveLocator: Sendable {
  package var nodeIDs: [ViewNodeID]

  package init(nodeIDs: [ViewNodeID]) {
    self.nodeIDs = nodeIDs
  }
}

extension ViewGraph {
  /// Captures persistent slot values reachable below `rootIdentity` through
  /// both the live parent/child graph and stamped committed-value islands.
  /// The latter is needed for capture-hosted content whose evaluation seam is
  /// not represented by a normal `ViewNode.children` edge.
  package func captureDormantStateArchive(
    rootedAt rootIdentity: Identity
  ) -> DormantStateArchive {
    captureDormantStateArchive(root: nodeForIdentity(rootIdentity))
  }

  /// Records the stamped node IDs of a freshly resolved lazy payload. Keeping
  /// this locator while the payload is active lets a later tab switch read the
  /// slots' latest imperative values without retaining any node object.
  package func dormantStateArchiveLocator(
    rootedAt rootResolvedNode: ResolvedNode
  ) -> DormantStateArchiveLocator {
    var nodeIDs: Set<ViewNodeID> = []
    var pending: [ViewNode] = []
    var nodesByEvaluationHost: [ViewNodeID: [ViewNode]] = [:]
    for candidate in nodesByNodeID.values {
      if candidate.parent == nil, let host = candidate.evaluationHost {
        nodesByEvaluationHost[host.viewNodeID, default: []].append(candidate)
      }
    }

    func enqueueStampedNodes(in resolved: ResolvedNode) {
      if let viewNodeID = resolved.viewNodeID,
        let node = nodeForViewNodeID(viewNodeID)
      {
        pending.append(node)
      }
      for child in resolved.children {
        enqueueStampedNodes(in: child)
      }
    }

    enqueueStampedNodes(in: rootResolvedNode)
    while let node = pending.popLast() {
      guard nodeIDs.insert(node.viewNodeID).inserted else {
        continue
      }
      pending.append(contentsOf: node.children)
      pending.append(contentsOf: nodesByEvaluationHost[node.viewNodeID] ?? [])
      enqueueStampedNodes(in: node.snapshot())
    }
    return DormantStateArchiveLocator(nodeIDs: nodeIDs.sorted())
  }

  package func captureDormantStateArchive(
    using locator: DormantStateArchiveLocator
  ) -> DormantStateArchive {
    return captureDormantStateArchive(
      pending: locator.nodeIDs.compactMap(nodeForViewNodeID)
    )
  }

  private func captureDormantStateArchive(
    root: ViewNode?
  ) -> DormantStateArchive {
    guard let root else {
      return DormantStateArchive()
    }

    return captureDormantStateArchive(pending: [root])
  }

  private func captureDormantStateArchive(
    pending initialNodes: [ViewNode]
  ) -> DormantStateArchive {

    var records: [DormantStateArchive.NodeRecord] = []
    var visited: Set<ViewNodeID> = []
    var pending = initialNodes
    var nodesByEvaluationHost: [ViewNodeID: [ViewNode]] = [:]
    for candidate in nodesByNodeID.values {
      if candidate.parent == nil, let host = candidate.evaluationHost {
        nodesByEvaluationHost[host.viewNodeID, default: []].append(candidate)
      }
    }

    func enqueueStampedNodes(in resolved: ResolvedNode) {
      if let viewNodeID = resolved.viewNodeID,
        let node = nodeForViewNodeID(viewNodeID)
      {
        pending.append(node)
      }
      for child in resolved.children {
        enqueueStampedNodes(in: child)
      }
    }

    while let node = pending.popLast() {
      guard visited.insert(node.viewNodeID).inserted else {
        continue
      }

      var persistentSlots: [StateSlotIdentifier: DormantStateSlotSnapshot] = [:]
      for (identifier, slot) in node.stateSlots where slot.dormantPolicy == .persistent {
        if let snapshot = slot.dormantSnapshot() {
          persistentSlots[identifier] = snapshot
        } else if slot.isInitialized {
          recordFrameRuntimeIssue(
            RuntimeIssue(
              severity: .warning,
              code: "tab.dormantStateUnsupportedValue",
              message:
                "TabView cannot archive persistent state slot \(identifier.ordinal) containing "
                + "\(slot.storedTypeDescription); it will restart from its authored value. "
                + "Use recursively value-only state or hoist this ownership above TabView.",
              identity: node.identity,
              source: "DormantStateArchive"
            )
          )
        }
      }
      let entityIdentity = node.committed.entityIdentity ?? node.lastHomedEntityIdentity
      if !persistentSlots.isEmpty || entityIdentity != nil {
        records.append(
          .init(
            identity: node.identity,
            entityIdentity: entityIdentity,
            stateSlots: persistentSlots
          )
        )
      }

      pending.append(contentsOf: node.children)
      pending.append(contentsOf: nodesByEvaluationHost[node.viewNodeID] ?? [])
      enqueueStampedNodes(in: node.snapshot())
    }

    records.sort { lhs, rhs in
      lhs.identity < rhs.identity
    }
    return DormantStateArchive(records: records)
  }

  /// Seeds freshly activated nodes before their dynamic-property update/body
  /// evaluation. Nodes that no longer exist in the authored payload are only
  /// placeholders in this candidate frame and are swept by normal graph
  /// reachability at the frame barrier; the archive itself owns no node.
  package func restoreDormantStateArchive(
    _ archive: DormantStateArchive
  ) {
    for record in archive.records {
      let node =
        if let entityIdentity = record.entityIdentity {
          prepareEntityRoutedOwnerPreservingCoResidentIdentity(
            identity: record.identity,
            entityIdentity: entityIdentity
          )
        } else {
          prepareDynamicPropertyUpdate(identity: record.identity)
        }
      for (identifier, slot) in record.stateSlots {
        node.restoreStateSlot(
          identifier,
          slot: AnyStateSlot(restoringDormant: slot)
        )
      }
    }
  }
}

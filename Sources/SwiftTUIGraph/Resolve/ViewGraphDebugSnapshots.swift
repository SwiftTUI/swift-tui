extension ViewGraph {
  package struct ObjectDependencySnapshot: Equatable {
    package var objectIdentifier: String
    package var dependents: Set<ViewNodeID>
  }

  package struct DebugTotalStateSnapshot: Equatable {
    package var root: Identity?
    package var nodesByNodeID: [ViewNodeID: ViewNode.DebugTotalStateSnapshot]
    package var nodeIDByIdentity: [Identity: ViewNodeID]
    package var identityByNodeID: [ViewNodeID: Identity]
    package var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
    package var entityRoutingTable: EntityRoutingTable
    package var lifetimeAnchors: LifetimeAnchorIndex
    package var nextViewNodeIDRawValue: UInt64
    package var flattenedStateOwnerNodeIDByIdentity: [Identity: ViewNodeID]
    package var effectRegistrationOwnerNodeIDs: Set<ViewNodeID>
    package var rootEvaluator: Bool
    package var evaluationRootIdentity: Identity?
    package var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
    package var viewportLifecycleOrder: [ViewportLifecycleKey]
    package var frameOrder: [ViewNodeID]
    package var evaluatedNodeIDsThisFrame: Set<ViewNodeID>
    package var stableTaskCancelEvents: [LifecycleEvent]
    package var stableTaskStartEvents: [LifecycleEvent]
    package var structuralAppearEvents: [LifecycleEvent]
    package var structuralTaskCancelEvents: [LifecycleEvent]
    package var structuralDisappearEvents: [LifecycleEvent]
    package var teardownBarrierWork: TeardownBarrierWork
    package var invalidatedNodeIDs: Set<ViewNodeID>
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID>
    package var latestLifecycleEvents: [LifecycleEvent]
    package var stateMutationKeys: Set<StateSlotKey>
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]
    package var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
    package var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var taskDescriptorNodeSlots: [String: String]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
    package var environmentDependents: [ObjectDependencySnapshot]
    package var observableDependents: [ObjectDependencySnapshot]
    package var currentFrameID: UInt64
    package var liveNodeIDs: Set<ViewNodeID>
    package var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry]
    package var changeObservationValues: [ChangeObservationValueKey: String]
    package var committedRuntimeRegistrationFingerprint: RuntimeRegistrationGraphFingerprint?
    package var pendingRuntimeRegistrationRefreshRoots: Set<Identity>

    package var invalidatedIdentities: Set<Identity> {
      identities(for: invalidatedNodeIDs)
    }

    package var graphLocalDirtyIdentities: Set<Identity> {
      identities(for: graphLocalDirtyNodeIDs)
    }

    package var liveIdentities: Set<Identity> {
      identities(for: liveNodeIDs)
    }

    private func identities(
      for nodeIDs: Set<ViewNodeID>
    ) -> Set<Identity> {
      Set(nodeIDs.compactMap { identityByNodeID[$0] })
    }
  }
}

extension ViewGraph {
  /// Debug oracle for the ``CommittedFreshness`` stranded-listing invariant:
  /// nodes whose committed snapshot freshness still admits value-blind
  /// consultation (`isCommittedSnapshotFresh` and NOT flagged
  /// foreign-parented) while a listed child has been adopted under a
  /// DIFFERENT live parent. Such a node can no longer hear the child's
  /// subtree change — the upward staleness walks follow the child's single
  /// `parent` slot — so serving it commits superseded interior content and
  /// stamps (the divergent-resolvedIdentity capture-host orphaning seam
  /// behind the gallery Tab-wrap stamp-coherence crash).
  ///
  /// `identityPathSuffix` scopes the walk to one authored slot. A graph-wide
  /// sweep is NOT globally assertable: route- and chain-absorb co-listings
  /// legitimately list nodes seated elsewhere and are covered by their own
  /// soundness protocols (value verification, stamp-claim withdrawal), so
  /// callers name the resolve-root slot whose listings must stay owned.
  package func debugStrandedFreshServableViolations(
    identityPathSuffix: String
  ) -> [String] {
    let graph = debugTotalStateSnapshot()
    var violations: [String] = []
    for (nodeID, node) in graph.nodesByNodeID {
      guard node.isCommittedSnapshotFresh, !node.hasForeignParentedChild else { continue }
      guard let identity = graph.identityByNodeID[nodeID] else { continue }
      guard identity.path.hasSuffix(identityPathSuffix) else { continue }
      for childIdentity in node.children where childIdentity != identity {
        guard
          let childID = graph.nodeIDByIdentity[childIdentity],
          childID != nodeID,
          let child = graph.nodesByNodeID[childID],
          let childParent = child.parentIdentity,
          childParent != identity
        else { continue }
        violations.append(
          "servable \(nodeID) at \(identity.path) lists child \(childID) at "
            + "\(childIdentity.path) whose parent is \(childParent.path)"
        )
      }
    }
    return violations.sorted()
  }
}

func debugObjectDependencySnapshot(
  _ dependencies: [ObjectIdentifier: Set<ViewNodeID>]
) -> [ViewGraph.ObjectDependencySnapshot] {
  dependencies.map { objectIdentifier, dependents in
    ViewGraph.ObjectDependencySnapshot(
      objectIdentifier: String(describing: objectIdentifier),
      dependents: dependents
    )
  }.sorted { lhs, rhs in
    lhs.objectIdentifier < rhs.objectIdentifier
  }
}

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
    package var nextViewNodeIDRawValue: UInt64
    package var rootEvaluator: Bool
    package var evaluationRootIdentity: Identity?
    package var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
    package var viewportLifecycleOrder: [ViewportLifecycleKey]
    package var frameOrder: [ViewNodeID]
    package var stableTaskCancelEvents: [LifecycleEvent]
    package var stableTaskStartEvents: [LifecycleEvent]
    package var structuralAppearEvents: [LifecycleEvent]
    package var structuralTaskCancelEvents: [LifecycleEvent]
    package var structuralDisappearEvents: [LifecycleEvent]
    package var pendingEntityRoutedRemovalNodeIDs: Set<ViewNodeID>
    package var requiresRootEvaluation: Bool
    package var invalidatedNodeIDs: Set<ViewNodeID>
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID>
    package var latestLifecycleEvents: [LifecycleEvent]
    package var stateMutationKeys: Set<StateSlotKey>
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]
    package var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
    package var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var taskDescriptorNodeSlots: [ViewNodeID: String]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
    package var environmentDependents: [ObjectDependencySnapshot]
    package var observableDependents: [ObjectDependencySnapshot]
    package var currentFrameID: UInt64
    package var liveNodeIDs: Set<ViewNodeID>
    package var resolvedNodeReuseCache:
      [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry]
    package var committedRuntimeRegistrationFingerprint:
      RuntimeRegistrationGraphFingerprint?

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

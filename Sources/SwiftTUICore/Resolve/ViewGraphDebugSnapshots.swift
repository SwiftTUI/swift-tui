extension ViewGraph {
  package struct ObjectDependencySnapshot: Equatable {
    package var objectIdentifier: String
    package var dependents: Set<Identity>
  }

  package struct DebugTotalStateSnapshot: Equatable {
    package var root: Identity?
    package var nodesByIdentity: [Identity: ViewNode.DebugTotalStateSnapshot]
    package var rootEvaluator: Bool
    package var evaluationRootIdentity: Identity?
    package var viewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode]
    package var viewportLifecycleOrder: [Identity]
    package var frameOrder: [Identity]
    package var stableTaskCancelEvents: [LifecycleEvent]
    package var stableTaskStartEvents: [LifecycleEvent]
    package var structuralAppearEvents: [LifecycleEvent]
    package var structuralTaskCancelEvents: [LifecycleEvent]
    package var structuralDisappearEvents: [LifecycleEvent]
    package var invalidatedIdentities: Set<Identity>
    package var graphLocalDirtyIdentities: Set<Identity>
    package var latestLifecycleEvents: [LifecycleEvent]
    package var registrationAliasesByIdentity: [Identity: Set<Identity>]
    package var registrationAliasTargets: [Identity: Identity]
    package var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
    package var lifecycleEvaluationTargetsByOwner: [Identity: Set<Identity>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [Identity: Set<Identity>]
    package var taskDescriptorIdentitySlots: [Identity: String]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var registrationAliasDiagnostics: RegistrationAliasDiagnostics
    package var stateSlotDependents: [StateSlotKey: Set<Identity>]
    package var environmentDependents: [ObjectDependencySnapshot]
    package var observableDependents: [ObjectDependencySnapshot]
    package var currentFrameID: UInt64
    package var liveIdentities: Set<Identity>
  }
}

func debugObjectDependencySnapshot(
  _ dependencies: [ObjectIdentifier: Set<Identity>]
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

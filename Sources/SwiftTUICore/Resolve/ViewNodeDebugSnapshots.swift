extension ViewNode {
  /// A comparable value snapshot of one `ViewNode`'s full state.
  ///
  /// Built by `debugTotalStateSnapshot()` (in `ViewNode.swift`, where the live
  /// private state is reachable) and consumed by checkpoint-totality testing
  /// and runtime diagnostics. This file holds only the data shape.
  package struct DebugTotalStateSnapshot: Equatable {
    package struct StateSlotSnapshot: Equatable {
      package var ordinal: Int
      package var storedTypeDescription: String
    }

    package struct HandlerSnapshot: Equatable {
      package var actionRegistrationIdentities: [String]
      package var keyHandlerRegistrationIdentities: [String]
      package var keyPressHandlerRegistrationIdentities: [String]
      package var pasteHandlerRegistrationIdentities: [String]
      package var terminationHandlerRegistrationIdentities: [String]
      package var pointerHandlerRouteIDs: [String]
      package var pointerHoverHandlerRouteIDs: [String]
      package var gestureRegistrationIdentities: [String]
      package var gestureStateRegistrationIdentities: [String]
      package var defaultFocusScopeIdentities: [String]
      package var defaultFocusCandidateIdentities: [String]
      package var focusBindingIdentities: [String]
      package var focusedValuesIdentities: [String]
      package var scrollPositionIdentities: [String]
      package var lifecycleHandlerIDs: [String]
      package var taskRegistrationIdentities: [String]
      package var preferenceObservationHandlerIDs: [String]
      package var commandRegistrations: [String]
      package var dropDestinationIdentities: [String]
    }

    package var viewNodeID: ViewNodeID
    package var invalidatorInstalled: Bool
    package var ownerGraphInstalled: Bool
    package var parentIdentity: Identity?
    package var committed: ResolvedNode
    package var isCommittedSnapshotFresh: Bool
    package var children: [Identity]
    package var stateSlots: [StateSlotSnapshot]
    package var dependencies: DependencySet
    package var lifecycleState: NodeLifecycleState
    package var registeredHandlers: HandlerSnapshot
    package var isDirty: Bool
    package var wasPresentAtFrameStart: Bool
    package var wasVisitedThisFrame: Bool
    package var previousChildrenIdentities: [Identity]
    package var previousLifecycleMetadata: LifecycleMetadata
    package var bodyStateSlotCount: Int?
    package var currentBodyStateSlotCount: Int
    package var pendingChangeHandlerIDs: [String]
    package var dependencyTracker: DependencySet
    package var registrationCaptureDepth: Int
    package var runtimeRegistrationMutationGeneration: UInt64
    package var checkpointMutationGeneration: UInt64
    package var evaluationDepth: Int
    package var hasCommittedPresence: Bool
    package var suppressesStructuralLifecycle: Bool
    package var nextChangeModifierOrdinal: Int
    package var nextNavigationDestinationModifierOrdinal: Int
    package var preparedFrameID: UInt64
    package var visitedFrameID: UInt64
    package var evaluatorInstalled: Bool
  }
}

extension ViewNode {
  /// A comparable value snapshot of one `ViewNode`'s full state.
  ///
  /// Built by `debugTotalStateSnapshot()` (in `ViewNode.swift`, where the live
  /// private state is reachable) and consumed by checkpoint-totality testing
  /// and runtime diagnostics. This file holds only the data shape.
  package struct DebugTotalStateSnapshot: Equatable {
    package struct StateSlotSnapshot: Equatable {
      package var slot: StateSlotIdentifier
      package var storedTypeDescription: String
    }

    package struct HandlerSnapshot: Equatable {
      package var actionRegistrationIdentities: [String]
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
    package var ownerLifetimeID: NodeOwnerLifetimeID
    package var invalidatorInstalled: Bool
    package var ownerGraphInstalled: Bool
    package var parentIdentity: Identity?
    @CheckpointCommittedValue package var committed: ResolvedNode
    package var isCommittedSnapshotFresh: Bool
    package var hasStaleIslandDescendant: Bool
    package var hasForeignParentedChild: Bool
    package var children: [Identity]
    package var hotReloadDeclarationNames: [StateSlotIdentifier: [String]]
    package var stateSlots: [StateSlotSnapshot]
    package var dependencies: DependencySet
    package var lifecycleState: NodeLifecycleState
    package var registeredHandlers: HandlerSnapshot
    package var lastHomedEntityIdentity: EntityIdentity?
    package var isDirty: Bool
    package var wasPresentAtFrameStart: Bool
    package var wasVisitedThisFrame: Bool
    package var previousChildrenIdentities: [Identity]
    package var previousLifecycleMetadata: LifecycleMetadata
    package var bodyStateSlotCount: Int?
    package var currentBodyStateSlotCount: Int
    package var pendingChangeHandlerIDs: [LifecycleHandlerID]
    package var dynamicPropertyLeaseKeysSeenThisUpdate: Set<DynamicPropertyLeaseRegistrationKey>
    package var nextDynamicPropertyLeaseOccurrenceOrdinal: Int
    package var dynamicPropertyLeaseTokens: [DynamicPropertyLeaseRegistrationKey: UInt64]
    package var hostsAuthoredStateClaims: Bool
    package var dependencyTracker: DependencySet
    package var registrationCaptureDepth: Int
    package var runtimeRegistrationMutationGeneration: UInt64
    package var evaluationDepth: Int
    package var hasCommittedPresence: Bool
    package var suppressesStructuralLifecycle: Bool
    package var focusPresentationInertSlotIdentities: Set<Identity>
    package var focusPresentationValueVerifiedSlotIdentities: Set<Identity>
    package var nextNavigationDestinationModifierOrdinal: Int
    package var nextTaskModifierOrdinal: Int
    package var nextValueAnimationModifierOrdinal: Int
    package var preparedFrameID: UInt64
    package var visitedFrameID: UInt64
    package var evaluatorInstalled: Bool
  }
}

/// Restoring a graph rewrites each node's committed value. If both snapshots
/// retained the same child array, every element in that array is the same
/// value on both sides of the restore. Compare the two roots normally without
/// walking that shared subtree again for each ancestor in the graph.
@propertyWrapper
package struct CheckpointCommittedValue: Equatable {
  package var wrappedValue: ResolvedNode

  package init(wrappedValue: ResolvedNode) {
    self.wrappedValue = wrappedValue
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    let before = lhs.wrappedValue
    let after = rhs.wrappedValue
    let sharesChildStorage = before.children.withUnsafeBufferPointer { before in
      after.children.withUnsafeBufferPointer { after in
        unsafe before.baseAddress == after.baseAddress
      }
    }
    if sharesChildStorage {
      // The node-field comparison also checks the two logical child counts.
      return ResolvedNode.haveEqualNodeFields(before, after)
    }
    return before == after
  }
}

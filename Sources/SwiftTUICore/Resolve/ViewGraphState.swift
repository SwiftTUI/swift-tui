package struct LifecycleStateNode: Equatable, Sendable {
  var identity: Identity
  var appearHandlerIDs: [String]
  var disappearHandlerIDs: [String]
  var task: TaskDescriptor?
}

extension ViewGraph {
  package struct Checkpoint {
    package var root: ViewNode?
    package var nodesByIdentity: [Identity: ViewNode]
    package var rootEvaluator: (@MainActor () -> Void)?
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
    package var stateMutationKeys: Set<StateSlotKey>
    package var registrationAliasesByIdentity: [Identity: Set<Identity>]
    package var registrationAliasTargets: [Identity: Identity]
    package var registrationAliasDiagnostics: RegistrationAliasDiagnostics
    package var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
    package var lifecycleEvaluationTargetsByOwner: [Identity: Set<Identity>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [Identity: Set<Identity>]
    package var taskDescriptorIdentitySlots: [Identity: TaskDescriptorIdentitySlot]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var stateSlotDependents: [StateSlotKey: Set<Identity>]
    package var environmentDependents: [ObjectIdentifier: Set<Identity>]
    package var observableDependents: [ObjectIdentifier: Set<Identity>]
    package var currentFrameID: UInt64
    package var liveIdentities: Set<Identity>
    package var nodeCheckpoints: [Identity: ViewNode.Checkpoint]
  }

  package struct StateMutationOverlay {
    package var stateSlots: [StateSlotKey: AnyStateSlot]
    package var invalidatedIdentities: Set<Identity>
    package var graphLocalDirtyIdentities: Set<Identity>
    package var stateMutationKeys: Set<StateSlotKey>
  }
}

package struct DirtyEvaluationPlan: Equatable, Sendable {
  package let frontierIdentities: [Identity]
}

/// Retained `.task(id:)` comparison state for one lifecycle identity.
///
/// The slot lives on the main-actor view graph, so it can compare the authored
/// `ID: Equatable` value without requiring `ID: Sendable` or deriving identity
/// from the value's textual representation.
package struct TaskDescriptorIdentitySlot {
  package let label: String
  private let isEqual: (Any) -> Bool

  package init<ID: Equatable>(
    label: String,
    value: ID
  ) {
    self.label = label
    isEqual = { candidate in
      guard let candidate = candidate as? ID else {
        return false
      }
      return candidate == value
    }
  }

  package func matches<ID: Equatable>(_ value: ID) -> Bool {
    isEqual(value)
  }
}

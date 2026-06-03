package struct LifecycleStateNode: Equatable, Sendable {
  var viewNodeID: ViewNodeID?
  var identity: Identity
  var appearHandlerIDs: [String]
  var disappearHandlerIDs: [String]
  var task: TaskDescriptor?
}

package enum ViewportLifecycleKey: Hashable, Sendable {
  case viewNode(ViewNodeID)
  case identity(Identity)
}

extension ViewGraph {
  package struct Checkpoint {
    package var root: ViewNode?
    package var nodesByNodeID: [ViewNodeID: ViewNode]
    package var nodeIDByIdentity: [Identity: ViewNodeID]
    package var identityByNodeID: [ViewNodeID: Identity]
    package var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
    package var nextViewNodeIDRawValue: UInt64
    package var rootEvaluator: (@MainActor () -> Void)?
    package var evaluationRootIdentity: Identity?
    package var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
    package var viewportLifecycleOrder: [ViewportLifecycleKey]
    package var frameOrder: [ViewNodeID]
    package var stableTaskCancelEvents: [LifecycleEvent]
    package var stableTaskStartEvents: [LifecycleEvent]
    package var structuralAppearEvents: [LifecycleEvent]
    package var structuralTaskCancelEvents: [LifecycleEvent]
    package var structuralDisappearEvents: [LifecycleEvent]
    package var requiresRootEvaluation: Bool
    package var invalidatedNodeIDs: Set<ViewNodeID>
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID>
    package var latestLifecycleEvents: [LifecycleEvent]
    package var stateMutationKeys: Set<StateSlotKey>
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]
    package var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
    package var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>]
    package var taskDescriptorNodeSlots: [ViewNodeID: TaskDescriptorIdentitySlot]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
    package var environmentDependents: [ObjectIdentifier: Set<ViewNodeID>]
    package var observableDependents: [ObjectIdentifier: Set<ViewNodeID>]
    package var currentFrameID: UInt64
    package var liveNodeIDs: Set<ViewNodeID>
    package var nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  }

  package struct StateMutationOverlay {
    package var stateSlots: [StateMutationSlotKey: AnyStateSlot]
    package var requiresRootEvaluation: Bool
    package var invalidatedNodeIDs: Set<ViewNodeID>
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID>
    package var stateMutationKeys: Set<StateSlotKey>
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]
  }
}

package struct StateMutationSlotKey: Hashable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var ordinal: Int

  package init(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    ordinal: Int
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.ordinal = ordinal
  }
}

package struct DirtyEvaluationPlan: Equatable, Sendable {
  package let frontierNodeIDs: [ViewNodeID]
  package let frontierIdentities: [Identity]

  package init(
    frontierNodeIDs: [ViewNodeID],
    frontierIdentities: [Identity]
  ) {
    self.frontierNodeIDs = frontierNodeIDs
    self.frontierIdentities = frontierIdentities
  }
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

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

package struct ResolvedNodeReuseCacheKey: Hashable, Sendable {
  package var namespace: String
  package var owner: Identity

  package init(
    namespace: String,
    owner: Identity
  ) {
    self.namespace = namespace
    self.owner = owner
  }
}

package struct ResolvedNodeReuseCacheEntry: Equatable, Sendable {
  package var signature: String
  package var node: ResolvedNode
  package var frameID: UInt64

  package init(
    signature: String,
    node: ResolvedNode,
    frameID: UInt64
  ) {
    self.signature = signature
    self.node = node
    self.frameID = frameID
  }
}

extension ViewGraph {
  package struct Checkpoint {
    package var root: ViewNode?
    package var nodesByNodeID: [ViewNodeID: ViewNode]
    package var nodeIDByIdentity: [Identity: ViewNodeID]
    package var identityByNodeID: [ViewNodeID: Identity]
    package var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
    package var entityRoutingTable: EntityRoutingTable
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
    package var taskDescriptorNodeSlots: [ViewNodeID: TaskDescriptorIdentitySlot]
    package var nextTaskDescriptorIdentityToken: UInt64
    package var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
    package var environmentDependents: [ObjectIdentifier: Set<ViewNodeID>]
    package var observableDependents: [ObjectIdentifier: Set<ViewNodeID>]
    package var currentFrameID: UInt64
    package var liveNodeIDs: Set<ViewNodeID>
    package var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry]
    package var committedRuntimeRegistrationFingerprint:
      RuntimeRegistrationGraphFingerprint?
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
  package var key: StateSlotKey

  package init(
    key: StateSlotKey
  ) {
    self.key = key
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

package struct DirtyEvaluationPlanDiagnostics: Equatable, Sendable {
  package var result: String
  package var frontierRootCount: Int
  package var invalidatedIdentityCount: Int
  package var unmappedInvalidatedIdentityCount: Int
  package var unmappedInvalidatedIdentitySample: [Identity]
  package var selectiveEvaluationDisabledReasons: [String]

  package init(
    result: String,
    frontierRootCount: Int = 0,
    invalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentitySample: [Identity] = [],
    selectiveEvaluationDisabledReasons: [String] = []
  ) {
    self.result = result
    self.frontierRootCount = frontierRootCount
    self.invalidatedIdentityCount = invalidatedIdentityCount
    self.unmappedInvalidatedIdentityCount = unmappedInvalidatedIdentityCount
    self.unmappedInvalidatedIdentitySample = unmappedInvalidatedIdentitySample
    self.selectiveEvaluationDisabledReasons = selectiveEvaluationDisabledReasons
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

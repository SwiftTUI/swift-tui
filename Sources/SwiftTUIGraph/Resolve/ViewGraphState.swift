package struct LifecycleStateNode: Equatable, Sendable {
  var viewNodeID: ViewNodeID?
  var identity: Identity
  var appearHandlerIDs: [String]
  var disappearHandlerIDs: [String]
  var tasks: [TaskDescriptor]

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    appearHandlerIDs: [String],
    disappearHandlerIDs: [String],
    tasks: [TaskDescriptor]
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.appearHandlerIDs = appearHandlerIDs
    self.disappearHandlerIDs = disappearHandlerIDs
    self.tasks = tasks
  }
}

package enum ViewportLifecycleKey: Hashable, Sendable {
  case viewNode(ViewNodeID)
  case identity(Identity)
}

/// Key for `onChange`'s cross-frame previous-value memory: the observing node's
/// *stable* `Identity` (survives `.id`-churn re-minting) plus a per-node modifier
/// ordinal so multiple `onChange` modifiers on one node do not collide.
package struct ChangeObservationValueKey: Hashable, Sendable {
  package var identity: Identity
  package var ordinal: Int

  package init(identity: Identity, ordinal: Int) {
    self.identity = identity
    self.ordinal = ordinal
  }
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
  // The checkpoint mirrors ViewGraph's field groups (see
  // ViewGraphFieldGroups.swift) one-for-one, so makeCheckpoint/restoreCheckpoint
  // move whole groups instead of copying every field by hand. `root` and
  // `nodeCheckpoints` are the only non-group members. Per-node staleness rides
  // each image's capture-metadata generation; graph fields restore
  // unconditionally (whole-group COW assignments), so the checkpoint carries no
  // graph-level mutation state.
  package struct Checkpoint {
    package var root: ViewNode?
    package var index: GraphIndex
    package var rootEvaluation: RootEvaluation
    package var viewportLifecycle: ViewportLifecycleState
    package var eventBuffers: LifecycleEventBuffers
    package var dirtyState: DirtyState
    package var lifecycleEvaluation: LifecycleEvaluationOwnership
    package var taskDescriptors: TaskDescriptorState
    package var dependencyIndex: DependencyIndex
    package var frameCommit: FrameCommitState
    package var nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  }

  package struct StateMutationOverlay {
    package var stateSlots: [StateMutationSlotKey: AnyStateSlot]
    package var invalidatedNodeIDs: Set<ViewNodeID>
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID>
    package var stateMutationKeys: Set<StateSlotKey>
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]

    package var isEmpty: Bool {
      stateSlots.isEmpty && invalidatedNodeIDs.isEmpty
        && graphLocalDirtyNodeIDs.isEmpty && stateMutationKeys.isEmpty
        && stateMutationNodeIDsByKey.isEmpty
    }
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
  // Unmapped identities split by how the queue boundary resolved them:
  // remapped onto a nearest live ancestor, or dropped (no live ancestor).
  // remapped + dropped == unmapped.
  package var remappedInvalidatedIdentityCount: Int
  package var droppedInvalidatedIdentityCount: Int
  // Live invalidated nodes the planner had to union into the graph-local
  // dirty set because the two rails diverged (F10 slice 2). Zero on healthy
  // selective frames; routine on non-selective frames, where `invalidate()`
  // fills only the invalidated rail.
  package var reconciledInvalidatedNodeCount: Int
  package var selectiveEvaluationDisabledReasons: [String]

  package init(
    result: String,
    frontierRootCount: Int = 0,
    invalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentityCount: Int = 0,
    unmappedInvalidatedIdentitySample: [Identity] = [],
    remappedInvalidatedIdentityCount: Int = 0,
    droppedInvalidatedIdentityCount: Int = 0,
    reconciledInvalidatedNodeCount: Int = 0,
    selectiveEvaluationDisabledReasons: [String] = []
  ) {
    self.result = result
    self.frontierRootCount = frontierRootCount
    self.invalidatedIdentityCount = invalidatedIdentityCount
    self.unmappedInvalidatedIdentityCount = unmappedInvalidatedIdentityCount
    self.unmappedInvalidatedIdentitySample = unmappedInvalidatedIdentitySample
    self.remappedInvalidatedIdentityCount = remappedInvalidatedIdentityCount
    self.droppedInvalidatedIdentityCount = droppedInvalidatedIdentityCount
    self.reconciledInvalidatedNodeCount = reconciledInvalidatedNodeCount
    self.selectiveEvaluationDisabledReasons = selectiveEvaluationDisabledReasons
  }
}

/// Identifies one `.task`/`.task(id:)` modifier's comparison slot.
package struct TaskDescriptorSlotKey: Hashable {
  package let node: ViewNodeID
  package let ordinal: Int

  package init(node: ViewNodeID, ordinal: Int) {
    self.node = node
    self.ordinal = ordinal
  }
}

/// Retained `.task(id:)` comparison state for one task-modifier slot.
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

// Cohesive value-typed field groups for ViewGraph's reconciliation state.
//
// Each group clusters a set of stored properties that share a purpose and a
// checkpoint lifetime. ViewGraph stores one instance of each group and exposes
// every original field as a private computed accessor that forwards into its
// group, so the reconciliation body reads and writes the fields by their
// original names while makeCheckpoint/restoreCheckpoint move whole groups.
//
// Adding a field to any group automatically extends the checkpoint and debug
// snapshot contracts; ViewGraphCheckpointTotalityTests fails until the new
// field appears in both.

extension ViewGraph {
  /// Node store plus the identity, structural-path, and entity-routing indices
  /// that map between identities, view-node IDs, and the live `ViewNode`s.
  package struct GraphIndex {
    package var nodesByNodeID: [ViewNodeID: ViewNode] = [:]
    package var nodeIDByIdentity: [Identity: ViewNodeID] = [:]
    package var identityByNodeID: [ViewNodeID: Identity] = [:]
    package var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>] = [:]
    package var entityRoutingTable: EntityRoutingTable = .init()
    package var nextViewNodeIDRawValue: UInt64 = 0
  }

  /// The root evaluator closure and the identity it re-roots from.
  package struct RootEvaluation {
    package var rootEvaluator: (@MainActor () -> Void)?
    package var evaluationRootIdentity: Identity?
  }

  /// Viewport (lazy-container) lifecycle bookkeeping carried across frames.
  package struct ViewportLifecycleState {
    package var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode] = [:]
    package var viewportLifecycleOrder: [ViewportLifecycleKey] = []
  }

  /// Per-frame ordering and lifecycle-event accumulation buffers. `beginFrame`
  /// clears these with `removeAll(keepingCapacity:)`; the latest committed
  /// lifecycle events persist until the next frame replaces them.
  package struct LifecycleEventBuffers {
    package var frameOrder: [ViewNodeID] = []
    package var stableTaskCancelEvents: [LifecycleEvent] = []
    package var stableTaskStartEvents: [LifecycleEvent] = []
    package var structuralAppearEvents: [LifecycleEvent] = []
    package var structuralTaskCancelEvents: [LifecycleEvent] = []
    package var structuralDisappearEvents: [LifecycleEvent] = []
    package var pendingEntityRoutedRemovalNodeIDs: Set<ViewNodeID> = []
    package var latestLifecycleEvents: [LifecycleEvent] = []
  }

  /// The dirty frontier: what must be re-evaluated, and the state-mutation keys
  /// driving it. `finalizeFrame` clears these once the frame commits.
  package struct DirtyState {
    package var requiresRootEvaluation: Bool = false
    package var invalidatedNodeIDs: Set<ViewNodeID> = []
    package var graphLocalDirtyNodeIDs: Set<ViewNodeID> = []
    package var stateMutationKeys: Set<StateSlotKey> = []
    package var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>] = [:]
  }

  /// Lifecycle-evaluation ownership edges: which owner re-evaluates which
  /// targets, and which targets each owner recorded this frame.
  package struct LifecycleEvaluationOwnership {
    package var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID] = [:]
    package var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>] = [:]
    package var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>] = [:]
  }

  /// Stable `.task(id:)` identity slots and the monotonically increasing token
  /// that mints fresh labels.
  package struct TaskDescriptorState {
    package var taskDescriptorNodeSlots: [TaskDescriptorSlotKey: TaskDescriptorIdentitySlot] = [:]
    package var nextTaskDescriptorIdentityToken: UInt64 = 0
  }

  /// Reverse-dependency edges from state slots, environment keys, and
  /// observable objects to the view nodes that read them.
  package struct DependencyIndex {
    package var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>] = [:]
    package var environmentDependents: [ObjectIdentifier: Set<ViewNodeID>] = [:]
    package var observableDependents: [ObjectIdentifier: Set<ViewNodeID>] = [:]
  }

  /// Frame counter, the live-node working set, the resolved-node reuse cache,
  /// the committed runtime-registration fingerprint, and the checkpoint epoch.
  package struct FrameCommitState {
    package var currentFrameID: UInt64 = 0
    package var liveNodeIDs: Set<ViewNodeID> = []
    package var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry] =
      [:]
    package var committedRuntimeRegistrationFingerprint: RuntimeRegistrationGraphFingerprint?
    package var checkpointMutationEpoch: UInt64 = 0
  }
}

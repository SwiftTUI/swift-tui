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
    // Subtrees a host resolves every frame but does not commit as children (a
    // navigation stack's root while a destination is presented). They are
    // reachable through neither committed values nor parent links, so their
    // lifetime anchors to the declaring host: `removeSubtree` descends these
    // edges when the host departs. See `recordDetachedHostedSubtree`.
    package var detachedHostedSubtreeRootsByHost: [ViewNodeID: Set<ViewNodeID>] = [:]
    package var detachedHostedSubtreeHostByRoot: [ViewNodeID: ViewNodeID] = [:]
    // Authored state-owner nodes whose identity index entry a single-child
    // flattening absorber claimed: `normalizeResolvedElements(count == 1)`
    // lets a wrapper commit a snapshot whose root identity is its only
    // child's, so the wrapper owns `nodeIDByIdentity[childIdentity]` —
    // planning and invalidation must keep landing there (its evaluator
    // re-runs the collapsed chain and stitches the output). The authored
    // child node keeps the live `@State`/`@FocusState` slots, so identity →
    // node resolution for AUTHORING (`beginEvaluation`, imperative-state
    // re-keys) prefers it through this map — otherwise every post-commit
    // pass re-hosts the slots on the absorber, re-seeded from authored
    // defaults. Recorded by `reindexIdentity` when the shadowed occupant is
    // authored at the claimed identity and holds state slots; removed when
    // that node leaves the graph. See `pruneAbsorbedShadowedNodes` (the
    // owner's lifetime anchors to the absorber's hosted-detached edge) and
    // `liveStateOwnerNode`.
    package var flattenedStateOwnerNodeIDByIdentity: [Identity: ViewNodeID] = [:]
    // Per-NavigationStack-host set of the CONTENT-subtree node IDs of the
    // pushed-destination surfaces `resolveActiveDestinationChain` minted this
    // frame — the out-of-band `NavigationDestinationSurface` payload roots (one
    // per active `NavigationDestinationInstance`). Node IDs, not identities:
    // the surface's own identity collapses onto the reused stack node under a
    // `.id("owner-\(gen)")` fold (the identity index re-points to the live
    // host), so an identity lookup at the barrier would land on the live host,
    // whereas the payload content node stays distinct per generation. Keyed by
    // the resolving host node's stable `ViewNodeID` so the previous-frame set
    // survives the host's per-generation resolved-identity churn. A frame's
    // active set is diffed against the previous frame's; a departed content
    // node (its declaration root reminted the surface at a new identity — a
    // leak the structural child diff never sees, since the content node is not
    // a parented child) is queued in `departedNavigationSurfaceContentNodeIDs`.
    // Entries drop when the host node leaves the graph. See
    // `recordActiveNavigationSurfaces` / `tearDownDepartedNavigationSurfaces`.
    package var activeNavigationSurfaceContentNodeIDsByHost: [ViewNodeID: Set<ViewNodeID>] = [:]
    // Pushed-destination surface content nodes that departed a host's active
    // set this frame, owed a dedicated teardown at the finalize barrier.
    // Consumed (and cleared) by `tearDownDepartedNavigationSurfaces`, which
    // `removeSubtree`s each departed content subtree — cascading its
    // detached-hosted Button base/overlay. Checkpoint-covered so a discarded
    // frame draft rolls the queue back with the rest of the prepared frame
    // state.
    package var departedNavigationSurfaceContentNodeIDs: Set<ViewNodeID> = []
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
    // ViewNodeIDs whose view body was *freshly evaluated* this frame (a
    // `beginEvaluation` visit), as distinct from `frameOrder`, which also
    // includes reused subtree roots grafted by value (`recordReusedSubtree`).
    // The animation controller's transition-collection prune consults exactly
    // this set so a re-evaluated node that dropped its `.transition()` modifier
    // is unregistered, while a reused node's registration is preserved.
    package var evaluatedNodeIDsThisFrame: Set<ViewNodeID> = []
    package var stableTaskCancelEvents: [LifecycleEvent] = []
    package var stableTaskStartEvents: [LifecycleEvent] = []
    package var structuralAppearEvents: [LifecycleEvent] = []
    package var structuralTaskCancelEvents: [LifecycleEvent] = []
    package var structuralDisappearEvents: [LifecycleEvent] = []
    package var pendingEntityRoutedRemovalNodeIDs: Set<ViewNodeID> = []
    // Nodes whose identity index entry was overwritten by another node's
    // re-rooted resolved identity this frame (a transparent chain collapse
    // absorbed their output). The finalize barrier reclaims the ones that end
    // the frame parentless and un-routed — nothing can reach them again. See
    // `pruneAbsorbedShadowedNodes`.
    package var absorbedShadowedNodeIDs: Set<ViewNodeID> = []
    package var latestLifecycleEvents: [LifecycleEvent] = []
  }

  /// The dirty frontier: what must be re-evaluated, and the state-mutation keys
  /// driving it. `finalizeFrame` clears these once the frame commits.
  package struct DirtyState {
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
  /// `onChange`'s cross-frame previous-value memory, and the committed
  /// runtime-registration fingerprint.
  ///
  /// The checkpoint mutation epoch deliberately lives *outside* this group (as
  /// a plain stored property on ``ViewGraph``): it is tracker metadata about
  /// mutations, not state — restores bump it rather than write it back, keeping
  /// it monotonic. See the matching per-node generation on ``ViewNode``.
  package struct FrameCommitState {
    package var currentFrameID: UInt64 = 0
    package var liveNodeIDs: Set<ViewNodeID> = []
    package var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry] =
      [:]
    // `onChange` previous-value memory, keyed by the observing node's *stable*
    // identity so it survives `.id`-churn re-minting of that node (a fresh
    // `ViewNode` with empty state slots) and is present before the node first
    // lands in the identity index. Persists across frames (not cleared by
    // `beginFrame`); `finalizeFrame` prunes entries whose identity no longer has
    // a live node. See `ChangeLifecycleModifier`.
    package var changeObservationValues: [ChangeObservationValueKey: AnyStateSlot] = [:]
    package var committedRuntimeRegistrationFingerprint: RuntimeRegistrationGraphFingerprint?
    // Identities whose registrations were refreshed in place since the last
    // commit (`ViewGraph.refreshActionRegistration`), owed to the next
    // commit's publication. Checkpointed with the group: a discarded frame's
    // restore rolls the queued roots back alongside the node records they
    // describe.
    package var pendingRuntimeRegistrationRefreshRoots: Set<Identity> = []
  }
}

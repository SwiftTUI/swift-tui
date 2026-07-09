extension ViewGraph {
  package func makeCheckpoint() -> Checkpoint {
    let checkpoint = GraphCheckpointStore.makeCheckpoint(
      root: root,
      index: index,
      rootEvaluation: rootEvaluation,
      viewportLifecycle: viewportLifecycle,
      eventBuffers: eventBuffers,
      dirtyState: dirtyState,
      lifecycleEvaluation: lifecycleEvaluation,
      taskDescriptors: taskDescriptors,
      dependencyIndex: dependencyIndex,
      frameCommit: frameCommit,
      nodeCheckpoints: nodeCheckpointImageStore.currentImages(of: nodesByNodeID)
    )
    #if DEBUG
      // Every capture under DEBUG, gated on the probe toggle so tests can
      // explicitly opt out to observe fast-path behavior (the oracle's ungated
      // restore bumps every generation, forcing full re-imaging next capture).
      if SoundnessProbeConfiguration.isEnabled {
        verifyCheckpointIsRestoreNoOp(checkpoint)
      }
    #else
      // Release: verify the store-built checkpoint on sampled frames when the
      // soundness probe is opted in. Off-sample captures keep the fast path
      // (no restore, no snapshots).
      if SoundnessProbeConfiguration.isSampledFrame {
        verifyCheckpointIsRestoreNoOp(checkpoint)
      }
    #endif
    return checkpoint
  }

  /// F29 create-side oracle: restoring a just-created checkpoint must be a
  /// state no-op. A stale store image (a mutation the generation tracking
  /// missed), membership drift, or graph-field skew all surface here as a
  /// before/after debug-snapshot mismatch. It also covers the one recording
  /// seam property observation cannot see — `DependencyTracker` state is part
  /// of the node debug snapshot.
  ///
  /// Must use the UNGATED restore: a stale image is precisely a node whose
  /// generation matches while its state does not, and the generation-gated
  /// production restore would skip exactly those nodes, making the check
  /// vacuous.
  ///
  /// It is sound to leave the restore applied: on a match the restore changed
  /// nothing, and on a mismatch the graph now equals the checkpoint callers
  /// were about to trust anyway — consistent-but-flagged, mirroring the
  /// restore oracle's mutate-then-report contract.
  private func verifyCheckpointIsRestoreNoOp(_ checkpoint: Checkpoint) {
    let before = debugTotalStateSnapshot()
    restoreCheckpointUngated(checkpoint)
    if before != debugTotalStateSnapshot() {
      SoundnessProbeConfiguration.recordCheckpointStoreViolation(
        "checkpoint store: restoring a just-created checkpoint changed graph state"
      )
    }
  }

  /// Restores the checkpoint, rewriting only nodes whose live generation
  /// differs from the image's captured generation — sound unconditionally
  /// under monotonic generations (every mutation and every restore bumps a
  /// node's generation, nothing rewinds, so an equal generation proves equal
  /// state). Node *membership* always rides the whole-group `index` restore,
  /// which is what makes created/removed nodes correct without per-node
  /// images. Returns the number of nodes rewritten.
  ///
  /// Carries its own gated-vs-ungated soundness oracle (every restore in
  /// DEBUG, sampled frames in release): after the gated restore, an ungated
  /// rewrite of the same images must not change graph state.
  @discardableResult
  package func restoreCheckpoint(_ checkpoint: Checkpoint) -> Int {
    restoreCheckpointGraphFields(checkpoint)

    let restoredNodeCount = ViewGraphNodeCheckpointing.restoreNodeCheckpoints(
      checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
    nodeCheckpointImageStore.adopt(
      images: checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
    #if DEBUG
      if SoundnessProbeConfiguration.isEnabled {
        verifyGatedRestoreMatchesUngated(checkpoint)
      }
    #else
      if SoundnessProbeConfiguration.isSampledFrame {
        verifyGatedRestoreMatchesUngated(checkpoint)
      }
    #endif
    return restoredNodeCount
  }

  /// Successor of the Stage-2B delta-restore oracle: the generation-gated
  /// restore must leave the graph byte-equal to an unconditional rewrite of
  /// every image. A divergence means a node was skipped whose generation
  /// matched while its state did not — the same unsoundness class the create
  /// oracle hunts, caught at the restore seam. Reuses the delta-checkpoint
  /// violation counter (same contract: a scoped restore diverged from the
  /// full one). Sound to leave the ungated result applied: on a match the two
  /// are equal, on a mismatch the ungated rewrite is the correct state.
  private func verifyGatedRestoreMatchesUngated(_ checkpoint: Checkpoint) {
    let gated = debugTotalStateSnapshot()
    restoreCheckpointUngated(checkpoint)
    if gated != debugTotalStateSnapshot() {
      SoundnessProbeConfiguration.recordDeltaCheckpointViolation(
        "gen-gated restore diverged from ungated restore"
      )
    }
  }

  /// The ungated ground truth used by the two oracles above: rewrites every
  /// node from its image regardless of generations, then re-adopts the store.
  private func restoreCheckpointUngated(_ checkpoint: Checkpoint) {
    restoreCheckpointGraphFields(checkpoint)
    ViewGraphNodeCheckpointing.restoreNodeCheckpointsUngated(
      checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
    nodeCheckpointImageStore.adopt(
      images: checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
  }

  private func restoreCheckpointGraphFields(_ checkpoint: Checkpoint) {
    root = checkpoint.root
    index = checkpoint.index
    rootEvaluation = checkpoint.rootEvaluation
    viewportLifecycle = checkpoint.viewportLifecycle
    eventBuffers = checkpoint.eventBuffers
    dirtyState = checkpoint.dirtyState
    lifecycleEvaluation = checkpoint.lifecycleEvaluation
    taskDescriptors = checkpoint.taskDescriptors
    dependencyIndex = checkpoint.dependencyIndex
    frameCommit = checkpoint.frameCommit
  }
}

@MainActor
package final class ViewGraph {
  // CHECKPOINT TOTALITY CONTRACT (audit finding F4):
  // The mutable graph state is grouped into the value-typed field groups in
  // ViewGraphFieldGroups.swift. Every field of every group MUST appear in
  // ViewGraph.Checkpoint and DebugTotalStateSnapshot. The source-level
  // ViewGraphCheckpointTotalityTests guard fails when a new field escapes
  // checkpoint coverage. makeCheckpoint/restoreCheckpoint move whole groups,
  // so the groups carry the totality contract by construction.
  package private(set) var root: ViewNode?

  // Cohesive field groups (see ViewGraphFieldGroups.swift). Every original field
  // is forwarded by a private computed accessor below, so reconciliation logic
  // is unchanged while makeCheckpoint/restoreCheckpoint move whole groups.
  // Unlike ViewNode's groups these carry no mutation observers: graph fields
  // are restored unconditionally (whole-group COW assignments, measured ~free),
  // so nothing consumes a graph-side mutation signal — per-node staleness is
  // what the generation counters track.
  private var index: GraphIndex
  private var rootEvaluation: RootEvaluation
  private var viewportLifecycle: ViewportLifecycleState
  private var eventBuffers: LifecycleEventBuffers
  private var dirtyState: DirtyState
  private var lifecycleEvaluation: LifecycleEvaluationOwnership
  private var taskDescriptors: TaskDescriptorState
  private var dependencyIndex: DependencyIndex
  private var frameCommit: FrameCommitState

  var nodesByNodeID: [ViewNodeID: ViewNode] {
    get { index.nodesByNodeID }
    set { index.nodesByNodeID = newValue }
  }
  var nodeIDByIdentity: [Identity: ViewNodeID] {
    get { index.nodeIDByIdentity }
    set { index.nodeIDByIdentity = newValue }
  }
  var identityByNodeID: [ViewNodeID: Identity] {
    get { index.identityByNodeID }
    set { index.identityByNodeID = newValue }
  }
  var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>] {
    get { index.nodeIDsByStructuralPath }
    set { index.nodeIDsByStructuralPath = newValue }
  }
  var entityRoutingTable: EntityRoutingTable {
    get { index.entityRoutingTable }
    set { index.entityRoutingTable = newValue }
  }
  var nextViewNodeIDRawValue: UInt64 {
    get { index.nextViewNodeIDRawValue }
    set { index.nextViewNodeIDRawValue = newValue }
  }
  var detachedHostedSubtreeRootsByHost: [ViewNodeID: Set<ViewNodeID>] {
    get { index.detachedHostedSubtreeRootsByHost }
    set { index.detachedHostedSubtreeRootsByHost = newValue }
  }
  var detachedHostedSubtreeHostByRoot: [ViewNodeID: ViewNodeID] {
    get { index.detachedHostedSubtreeHostByRoot }
    set { index.detachedHostedSubtreeHostByRoot = newValue }
  }
  var flattenedStateOwnerNodeIDByIdentity: [Identity: ViewNodeID] {
    get { index.flattenedStateOwnerNodeIDByIdentity }
    set { index.flattenedStateOwnerNodeIDByIdentity = newValue }
  }
  private var rootEvaluator: (@MainActor () -> Void)? {
    get { rootEvaluation.rootEvaluator }
    set { rootEvaluation.rootEvaluator = newValue }
  }
  private var evaluationRootIdentity: Identity? {
    get { rootEvaluation.evaluationRootIdentity }
    set { rootEvaluation.evaluationRootIdentity = newValue }
  }
  private var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode] {
    get { viewportLifecycle.viewportLifecycleNodesByKey }
    set { viewportLifecycle.viewportLifecycleNodesByKey = newValue }
  }
  private var viewportLifecycleOrder: [ViewportLifecycleKey] {
    get { viewportLifecycle.viewportLifecycleOrder }
    set { viewportLifecycle.viewportLifecycleOrder = newValue }
  }
  private var frameOrder: [ViewNodeID] {
    get { eventBuffers.frameOrder }
    set { eventBuffers.frameOrder = newValue }
  }
  private var stableTaskCancelEvents: [LifecycleEvent] {
    get { eventBuffers.stableTaskCancelEvents }
    set { eventBuffers.stableTaskCancelEvents = newValue }
  }
  private var stableTaskStartEvents: [LifecycleEvent] {
    get { eventBuffers.stableTaskStartEvents }
    set { eventBuffers.stableTaskStartEvents = newValue }
  }
  private var structuralAppearEvents: [LifecycleEvent] {
    get { eventBuffers.structuralAppearEvents }
    set { eventBuffers.structuralAppearEvents = newValue }
  }
  private var structuralTaskCancelEvents: [LifecycleEvent] {
    get { eventBuffers.structuralTaskCancelEvents }
    set { eventBuffers.structuralTaskCancelEvents = newValue }
  }
  var structuralDisappearEvents: [LifecycleEvent] {
    get { eventBuffers.structuralDisappearEvents }
    set { eventBuffers.structuralDisappearEvents = newValue }
  }
  var pendingEntityRoutedRemovalNodeIDs: Set<ViewNodeID> {
    get { eventBuffers.pendingEntityRoutedRemovalNodeIDs }
    set { eventBuffers.pendingEntityRoutedRemovalNodeIDs = newValue }
  }
  var absorbedShadowedNodeIDs: Set<ViewNodeID> {
    get { eventBuffers.absorbedShadowedNodeIDs }
    set { eventBuffers.absorbedShadowedNodeIDs = newValue }
  }
  private var latestLifecycleEvents: [LifecycleEvent] {
    get { eventBuffers.latestLifecycleEvents }
    set { eventBuffers.latestLifecycleEvents = newValue }
  }
  var invalidatedNodeIDs: Set<ViewNodeID> {
    get { dirtyState.invalidatedNodeIDs }
    set { dirtyState.invalidatedNodeIDs = newValue }
  }
  var graphLocalDirtyNodeIDs: Set<ViewNodeID> {
    get { dirtyState.graphLocalDirtyNodeIDs }
    set { dirtyState.graphLocalDirtyNodeIDs = newValue }
  }
  private var stateMutationKeys: Set<StateSlotKey> {
    get { dirtyState.stateMutationKeys }
    set { dirtyState.stateMutationKeys = newValue }
  }
  private var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>] {
    get { dirtyState.stateMutationNodeIDsByKey }
    set { dirtyState.stateMutationNodeIDsByKey = newValue }
  }
  var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID] {
    get { lifecycleEvaluation.lifecycleEvaluationOwnersByNodeID }
    set { lifecycleEvaluation.lifecycleEvaluationOwnersByNodeID = newValue }
  }
  var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>] {
    get { lifecycleEvaluation.lifecycleEvaluationTargetsByOwner }
    set { lifecycleEvaluation.lifecycleEvaluationTargetsByOwner = newValue }
  }
  var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>] {
    get { lifecycleEvaluation.lifecycleEvaluationTargetsRecordedByOwner }
    set { lifecycleEvaluation.lifecycleEvaluationTargetsRecordedByOwner = newValue }
  }
  var taskDescriptorNodeSlots: [TaskDescriptorSlotKey: TaskDescriptorIdentitySlot] {
    get { taskDescriptors.taskDescriptorNodeSlots }
    set { taskDescriptors.taskDescriptorNodeSlots = newValue }
  }
  private var nextTaskDescriptorIdentityToken: UInt64 {
    get { taskDescriptors.nextTaskDescriptorIdentityToken }
    set { taskDescriptors.nextTaskDescriptorIdentityToken = newValue }
  }
  private var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>] {
    get { dependencyIndex.stateSlotDependents }
    set { dependencyIndex.stateSlotDependents = newValue }
  }
  private var environmentDependents: [ObjectIdentifier: Set<ViewNodeID>] {
    get { dependencyIndex.environmentDependents }
    set { dependencyIndex.environmentDependents = newValue }
  }
  private var observableDependents: [ObjectIdentifier: Set<ViewNodeID>] {
    get { dependencyIndex.observableDependents }
    set { dependencyIndex.observableDependents = newValue }
  }

  var currentFrameID: UInt64 {
    get { frameCommit.currentFrameID }
    set { frameCommit.currentFrameID = newValue }
  }
  var liveNodeIDs: Set<ViewNodeID> {
    get { frameCommit.liveNodeIDs }
    set { frameCommit.liveNodeIDs = newValue }
  }
  var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry] {
    get { frameCommit.resolvedNodeReuseCache }
    set { frameCommit.resolvedNodeReuseCache = newValue }
  }
  private var changeObservationValues: [ChangeObservationValueKey: AnyStateSlot] {
    get { frameCommit.changeObservationValues }
    set { frameCommit.changeObservationValues = newValue }
  }
  private var committedRuntimeRegistrationFingerprint: RuntimeRegistrationGraphFingerprint? {
    get { frameCommit.committedRuntimeRegistrationFingerprint }
    set { frameCommit.committedRuntimeRegistrationFingerprint = newValue }
  }
  private var pendingRuntimeRegistrationRefreshRoots: Set<Identity> {
    get { frameCommit.pendingRuntimeRegistrationRefreshRoots }
    set { frameCommit.pendingRuntimeRegistrationRefreshRoots = newValue }
  }
  /// F29: derived cache behind ``makeCheckpoint()`` — one live image per node,
  /// refreshed by generation compare, handed out as an O(1) COW copy. Meta-state
  /// outside the checkpointed field groups: it is never part of a checkpoint,
  /// and every `restoreCheckpoint` resets it wholesale from the restore target.
  /// Coherence is enforced by the restore-no-op oracle in `makeCheckpoint()`.
  private var nodeCheckpointImageStore = NodeCheckpointImageStore()

  /// Whether a previous `onChange` value has been recorded for this
  /// `(identity, ordinal)` — i.e. "this is not the first observation," a signal
  /// that survives node re-minting because it is keyed by the stable identity.
  package func hasChangeObservationValue(
    identity: Identity,
    ordinal: Int
  ) -> Bool {
    changeObservationValues[.init(identity: identity, ordinal: ordinal)] != nil
  }

  /// The previously-observed `onChange` value for this `(identity, ordinal)`, or
  /// `nil` if none is recorded (or a stored value of a different type).
  package func changeObservationValue<Value>(
    identity: Identity,
    ordinal: Int,
    as type: Value.Type
  ) -> Value? {
    guard let slot = changeObservationValues[.init(identity: identity, ordinal: ordinal)],
      slot.stores(Value.self)
    else {
      return nil
    }
    return slot.value(as: Value.self)
  }

  /// Records the latest observed `onChange` value for this `(identity, ordinal)`
  /// so the next resolve can detect a transition. Persists across frames and
  /// across `.id`-churn re-minting; pruned by `finalizeFrame` once the identity
  /// no longer has a live node.
  package func recordChangeObservationValue<Value>(
    _ value: Value,
    identity: Identity,
    ordinal: Int
  ) {
    changeObservationValues[.init(identity: identity, ordinal: ordinal)] = AnyStateSlot(value)
  }

  /// Drops `onChange` previous-value entries whose identity no longer has a live
  /// node. A node re-minted this frame (owner `.id` churn) is re-created at the
  /// same identity before finalize, so it stays live and its baseline survives;
  /// only genuinely-departed identities are pruned. Keeps the store bounded
  /// without coupling to per-node teardown (which the churn re-mint goes
  /// through).
  private func pruneDepartedChangeObservationValues() {
    guard !changeObservationValues.isEmpty else {
      return
    }
    changeObservationValues = changeObservationValues.filter { key, _ in
      nodeIDByIdentity[key.identity] != nil
    }
  }

  func nodeIfExists(
    for identity: Identity
  ) -> ViewNode? {
    GraphNodeIndexQuery.node(for: identity, in: index)
  }

  func nodeIfExists(
    for viewNodeID: ViewNodeID
  ) -> ViewNode? {
    GraphNodeIndexQuery.node(for: viewNodeID, in: index)
  }

  private func nodeForResolvedNode(
    _ resolved: ResolvedNode
  ) -> ViewNode {
    if let viewNodeID = resolved.viewNodeID,
      let node = nodeIfExists(for: viewNodeID)
    {
      return node
    }
    return nodeForIdentity(for: resolved.identity)
  }

  func nodeIDsForResolvedNode(
    _ resolved: ResolvedNode
  ) -> Set<ViewNodeID> {
    GraphNodeIndexQuery.nodeIDs(forResolvedNode: resolved, in: index)
  }

  private func viewNodeID(
    for identity: Identity
  ) -> ViewNodeID? {
    GraphNodeIndexQuery.viewNodeID(for: identity, in: index)
  }

  private func identities(
    for viewNodeIDs: Set<ViewNodeID>
  ) -> Set<Identity> {
    GraphNodeIndexQuery.identities(for: viewNodeIDs, in: index)
  }

  private func nodeIDs(
    for identities: Set<Identity>
  ) -> Set<ViewNodeID> {
    GraphNodeIndexQuery.nodeIDs(for: identities, in: index)
  }

  private func applyResolvedNode(
    _ node: ViewNode,
    resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    let previousStructuralPath = node.committed.structuralPath
    let previousResolvedIdentity = node.resolvedIdentity
    node.apply(
      resolved: resolved,
      children: children
    )
    bindEntityIdentity(from: resolved, to: node.viewNodeID)
    reindexIdentity(
      for: node,
      previousResolvedIdentity: previousResolvedIdentity
    )
    reindexStructuralPath(
      for: node,
      previous: previousStructuralPath
    )
  }

  private func reindexIdentity(
    for node: ViewNode,
    previousResolvedIdentity: Identity
  ) {
    if previousResolvedIdentity != node.identity,
      previousResolvedIdentity != node.resolvedIdentity,
      nodeIDByIdentity[previousResolvedIdentity] == node.viewNodeID
    {
      nodeIDByIdentity.removeValue(forKey: previousResolvedIdentity)
    }
    nodeIDByIdentity[node.identity] = node.viewNodeID
    // A re-rooted resolved identity that overwrites another node's index entry
    // shadows that node: if it stays parentless and un-routed through this
    // frame's walk, nothing can ever reach it again (a chain collapse absorbed
    // its output — see `pruneAbsorbedShadowedNodes`). Record the candidate;
    // the finalize barrier decides.
    if node.resolvedIdentity != node.identity,
      let shadowedNodeID = nodeIDByIdentity[node.resolvedIdentity],
      shadowedNodeID != node.viewNodeID
    {
      absorbedShadowedNodeIDs.insert(shadowedNodeID)
      // The shadowed node shares this node's re-rooted resolved identity — a
      // chain collapse absorbed its output into this node (the interior mint
      // of a collapsed `.id` chain). While warm, the interior stays alive
      // through re-evaluation, but it lives in NO committed value tree and
      // owns only its per-generation allocation identity, so this node's
      // teardown could never reach it. Anchor its lifetime here with a
      // hosted-detached edge; the teardown descent's visited/entity guards
      // keep it whenever it is genuinely live (steady frames, G13 siblings,
      // re-homed controls).
      recordDetachedHostedNode(shadowedNodeID, hostedByNodeID: node.viewNodeID)
      // A shadowed node AUTHORED at the claimed identity that holds state
      // slots is a single-child flattening's state owner, not a chain
      // interior: the child resolved onto its own node, then this wrapper's
      // one-element body normalized to that child element and claimed its
      // identity. Register the authored node so authoring-host resolution
      // keeps hosting the child's `@State`/`@FocusState` there instead of
      // re-seeding fresh slots on this absorber every later pass.
      if let shadowed = nodesByNodeID[shadowedNodeID],
        shadowed.identity == node.resolvedIdentity,
        !shadowed.stateSlots.isEmpty
      {
        flattenedStateOwnerNodeIDByIdentity[node.resolvedIdentity] = shadowedNodeID
      }
    }
    nodeIDByIdentity[node.resolvedIdentity] = node.viewNodeID
    identityByNodeID[node.viewNodeID] = node.resolvedIdentity
  }

  private func reindexStructuralPath(
    for node: ViewNode,
    previous: StructuralPath
  ) {
    if previous != node.committed.structuralPath {
      nodeIDsByStructuralPath[previous]?.remove(node.viewNodeID)
      if nodeIDsByStructuralPath[previous]?.isEmpty == true {
        nodeIDsByStructuralPath.removeValue(forKey: previous)
      }
    }
    nodeIDsByStructuralPath[node.committed.structuralPath, default: []].insert(
      node.viewNodeID
    )
  }

  /// Resolves invalidated identities onto evaluation targets. An identity
  /// that no longer maps to a live node is remapped onto its nearest live
  /// ancestor (`nearestLiveAncestorNodeID`); an identity with no live
  /// ancestor at all is dropped. Neither case escalates to root evaluation
  /// anymore — the plan diagnostics carry the remapped/dropped counts so a
  /// census can still surface rail drift (F10 slice 1). The per-identity
  /// resolution also retires the old `count`-mismatch heuristic, which
  /// false-escalated when two identities mapped to the same node.
  private func nodeIDsForInvalidation(
    _ identities: Set<Identity>
  ) -> Set<ViewNodeID> {
    var viewNodeIDs = Set<ViewNodeID>()
    viewNodeIDs.reserveCapacity(identities.count)
    for identity in identities {
      if let viewNodeID = viewNodeID(for: identity) {
        viewNodeIDs.insert(viewNodeID)
      } else if let ancestorNodeID = nearestLiveAncestorNodeID(for: identity) {
        viewNodeIDs.insert(ancestorNodeID)
      }
    }
    return viewNodeIDs
  }

  /// Occupancy reading for the profiling memory signal. Computed, so it stays
  /// outside the checkpoint totality contract above.
  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    MemoryMetricSnapshot(
      name: "ViewGraph.nodesByIdentity",
      count: nodesByNodeID.count,
      detail: [
        "liveNodeIDs": liveNodeIDs.count,
        "invalidatedNodeIDs": invalidatedNodeIDs.count,
      ]
    )
  }

  package init() {
    index = GraphIndex()
    rootEvaluation = RootEvaluation()
    viewportLifecycle = ViewportLifecycleState()
    eventBuffers = LifecycleEventBuffers()
    dirtyState = DirtyState()
    lifecycleEvaluation = LifecycleEvaluationOwnership()
    taskDescriptors = TaskDescriptorState()
    dependencyIndex = DependencyIndex()
    frameCommit = FrameCommitState()
    // Make this graph recoverable from its scope identity so `@State` reads and
    // writes that fire outside a resolve pass (tasks, gestures, imperative
    // actions) can reach the live owner node — see `LiveViewGraphRegistry`.
    LiveViewGraphRegistry.register(self)
  }

  package func debugTotalStateSnapshot() -> DebugTotalStateSnapshot {
    DebugTotalStateSnapshot(
      root: root?.identity,
      nodesByNodeID: nodesByNodeID.mapValues { node in
        node.debugTotalStateSnapshot()
      },
      nodeIDByIdentity: nodeIDByIdentity,
      identityByNodeID: identityByNodeID,
      nodeIDsByStructuralPath: nodeIDsByStructuralPath,
      entityRoutingTable: entityRoutingTable,
      nextViewNodeIDRawValue: nextViewNodeIDRawValue,
      detachedHostedSubtreeRootsByHost: detachedHostedSubtreeRootsByHost,
      detachedHostedSubtreeHostByRoot: detachedHostedSubtreeHostByRoot,
      flattenedStateOwnerNodeIDByIdentity: flattenedStateOwnerNodeIDByIdentity,
      rootEvaluator: rootEvaluator != nil,
      evaluationRootIdentity: evaluationRootIdentity,
      viewportLifecycleNodesByKey: viewportLifecycleNodesByKey,
      viewportLifecycleOrder: viewportLifecycleOrder,
      frameOrder: frameOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents,
      pendingEntityRoutedRemovalNodeIDs: pendingEntityRoutedRemovalNodeIDs,
      absorbedShadowedNodeIDs: absorbedShadowedNodeIDs,
      invalidatedNodeIDs: invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
      latestLifecycleEvents: latestLifecycleEvents,
      stateMutationKeys: stateMutationKeys,
      stateMutationNodeIDsByKey: stateMutationNodeIDsByKey,
      lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID,
      lifecycleEvaluationTargetsByOwner: lifecycleEvaluationTargetsByOwner,
      lifecycleEvaluationTargetsRecordedByOwner: lifecycleEvaluationTargetsRecordedByOwner,
      taskDescriptorNodeSlots: Dictionary(
        uniqueKeysWithValues: taskDescriptorNodeSlots.map { key, slot in
          ("\(key.node.rawValue)#\(key.ordinal)", slot.label)
        }
      ),
      nextTaskDescriptorIdentityToken: nextTaskDescriptorIdentityToken,
      stateSlotDependents: stateSlotDependents,
      environmentDependents: debugObjectDependencySnapshot(environmentDependents),
      observableDependents: debugObjectDependencySnapshot(observableDependents),
      currentFrameID: currentFrameID,
      liveNodeIDs: liveNodeIDs,
      resolvedNodeReuseCache: resolvedNodeReuseCache,
      changeObservationValues: changeObservationValues.mapValues { $0.storedTypeDescription },
      committedRuntimeRegistrationFingerprint: committedRuntimeRegistrationFingerprint,
      pendingRuntimeRegistrationRefreshRoots: pendingRuntimeRegistrationRefreshRoots
    )
  }

  package func cachedReusableResolvedNode(
    namespace: String,
    owner: Identity,
    signature: String,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> ResolvedNode? {
    // Every denial branch records a `cache-*` reason (F94) so this path is
    // diagnosable through the same `[REUSE-TRACE]` histogram as its
    // `reusableSnapshot` siblings; `record` self-guards on `isEnabled`.
    let key = ResolvedNodeReuseCacheKey(namespace: namespace, owner: owner)
    guard var entry = resolvedNodeReuseCache[key] else {
      ReuseDenialTrace.record("cache-miss")
      return nil
    }
    guard entry.signature == signature else {
      ReuseDenialTrace.record("cache-stale-signature")
      return nil
    }

    let cachedNode =
      entry.node.viewNodeID.flatMap { nodeIfExists(for: $0) }
      ?? nodeIfExists(for: entry.node.identity)
    guard let node = cachedNode else {
      resolvedNodeReuseCache.removeValue(forKey: key)
      ReuseDenialTrace.record("cache-node-departed")
      return nil
    }

    guard entry.node.environmentSnapshot == environment else {
      ReuseDenialTrace.record("cache-environment-mismatch")
      return nil
    }
    guard entry.node.transactionSnapshot.isReuseEquivalent(to: transaction) else {
      ReuseDenialTrace.record("cache-transaction-mismatch")
      return nil
    }

    if entry.frameID == currentFrameID {
      return entry.node
    }

    guard
      node.canReuse(
        frameID: currentFrameID,
        environment: environment,
        transaction: transaction
      )
    else {
      if ReuseDenialTrace.isEnabled {
        // Trace-only second evaluation: the production guard stays the
        // boolean fast path; the reason lookup runs only when tracing.
        let reason =
          node.canReuseDenialReason(
            frameID: currentFrameID,
            environment: environment,
            transaction: transaction
          ) ?? "can-reuse-denied"
        ReuseDenialTrace.record("cache-\(reason)")
      }
      return nil
    }

    entry.node = node.snapshot()
    entry.frameID = currentFrameID
    resolvedNodeReuseCache[key] = entry
    return entry.node
  }

  package func storeResolvedNodeReuseCache(
    namespace: String,
    owner: Identity,
    signature: String,
    node: ResolvedNode
  ) {
    let key = ResolvedNodeReuseCacheKey(namespace: namespace, owner: owner)
    resolvedNodeReuseCache[key] = ResolvedNodeReuseCacheEntry(
      signature: signature,
      node: node,
      frameID: currentFrameID
    )
  }

  package func refreshActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    in actionRegistry: LocalActionRegistry?
  ) {
    let registration = LocalActionRegistry.Registration(
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
    guard let node = nodeIfExists(for: identity) else {
      actionRegistry?.restore([identity: registration])
      return
    }
    let owner = RuntimeRegistrationOwnerKey(
      viewNodeID: node.viewNodeID,
      identity: identity,
      structuralPath: StructuralPath(identity: identity)
    )
    actionRegistry?.restore(
      [identity: registration],
      ownersByIdentity: [identity: owner]
    )
    node.recordActionRegistration(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: owner
    )
    // The registry restored above is frame-scoped (resolve-context) state, not
    // the persistent live registry — the refreshed handler reaches the live
    // registry only through the node record via the commit publication. Queue
    // the identity as a publication root so the committing draft escalates an
    // `.unchanged` publication to cover it: without this, a frame that formed
    // no dirty plan commits `.unchanged` while this node's registration
    // mutated — the stale live handler survives and the F63 `.unchanged`
    // fingerprint oracle traps (the gallery todo-delete crash).
    pendingRuntimeRegistrationRefreshRoots.insert(identity)
  }

  /// Drains the identities whose registrations were refreshed in place since
  /// the last commit (`refreshActionRegistration`,
  /// `installLayoutRealizedChildren`). The committing frame draft merges
  /// these into its publication so the refreshed records reach the live
  /// registry even on frames that formed no dirty plan.
  package func takePendingRuntimeRegistrationRefreshRoots() -> [Identity] {
    guard !pendingRuntimeRegistrationRefreshRoots.isEmpty else {
      return []
    }
    let roots = pendingRuntimeRegistrationRefreshRoots.sorted()
    pendingRuntimeRegistrationRefreshRoots.removeAll()
    return roots
  }

  package func invalidate(_ identities: Set<Identity>) {
    ViewGraphInvalidationPlanner.invalidate(
      nodeIDsForInvalidation(identities),
      invalidatedNodeIDs: &invalidatedNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  /// Returns the graph node for the given identity, if any.
  ///
  /// Used by view modifiers such as ``ValueAnimationModifier`` that need
  /// to reach into per-node state slot storage without triggering
  /// invalidation.
  package func nodeForIdentity(_ identity: Identity) -> ViewNode? {
    nodeIfExists(for: identity)
  }

  package func nodeForViewNodeID(_ viewNodeID: ViewNodeID) -> ViewNode? {
    nodeIfExists(for: viewNodeID)
  }
  /// Resolves the live node that owns imperative state registered against
  /// `viewNodeID` at `identity`. The registration-time node wins while it is
  /// still the live occupant of its identity; when the identity has been
  /// re-minted to a fresh node after registration (a lazy-tab revisit, a
  /// displacement eviction), the fresh occupant is returned instead, so
  /// closure-held `@State` projections (`.task` loops, `.onAppear`, gesture
  /// callbacks) keep reading and writing the state the committed graph
  /// serves. Without the identity re-key the closures write the orphaned
  /// node's slots: the writes invalidate the identity (dirtying the fresh
  /// node), the fresh node re-resolves its unchanged slots, and every frame
  /// completes empty — the gallery Life-tab revisit freeze. Mirrors
  /// `onChange`'s identity-keyed cross-frame memory.
  package func liveStateOwnerNode(
    registeredOwner viewNodeID: ViewNodeID,
    identity: Identity
  ) -> ViewNode? {
    let registered = nodeIfExists(for: viewNodeID)
    if let registered {
      let occupant = nodeIfExists(for: registered.identity)
      if occupant === registered {
        return registered
      }
      // Single-child flattening: the occupant is the absorber that claimed
      // the registered node's identity at commit, but the registered node
      // stays the live slot host (authoring-host resolution keeps hosting
      // there). Deferring to the occupant would land imperative writes in
      // slots the child's body never reads again.
      if flattenedStateOwnerNodeIDByIdentity[registered.identity] == registered.viewNodeID {
        return registered
      }
      // The registered node's own identity is the exact index key its
      // successor occupies; the authoring identity below can name a different
      // node when state slots live on a wrapper (a capture-host or modifier
      // node) rather than the authored view's node.
      if let occupant {
        return occupant
      }
    }
    // A re-minted identity's index entry can name a flattening absorber;
    // the authored successor holding the live slots wins over it.
    if let stateOwner = flattenedStateOwnerNode(for: identity) {
      return stateOwner
    }
    if let reminted = nodeIfExists(for: identity) {
      return reminted
    }
    return registered
  }

  package func containsNode(
    for identity: Identity
  ) -> Bool {
    nodeIfExists(for: identity) != nil
  }

  /// Whether the node at `identity` is queued dirty work for the next
  /// selective plan, or sits below a queued dirty ancestor whose re-resolve
  /// reaches it (same ancestry walk as the dirty-frontier planner, crossing
  /// capture-hosted island seams via `evaluationHost`). The frame head uses
  /// this to predict — before planning — that a presentation emitter will
  /// re-resolve this frame and escalate the plan to the portal root, so the
  /// narrow plan the escalation would re-do is skipped entirely.
  package func hasQueuedDirtyEvaluationPath(
    to identity: Identity
  ) -> Bool {
    guard let node = nodeIfExists(for: identity) else {
      return false
    }
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []
    while let candidate = current {
      guard visited.insert(ObjectIdentifier(candidate)).inserted else {
        return false
      }
      if candidate.isDirty, graphLocalDirtyNodeIDs.contains(candidate.viewNodeID) {
        return true
      }
      current = candidate.parent ?? candidate.evaluationHost
    }
    return false
  }

  /// Whether the live node at `identity` is a childless leaf of `kind`.
  /// Used by the run loop's focus-sync rerender to recognize re-carried
  /// invalidation identities whose re-resolve cannot host relocated content
  /// (the zero-size presentation trigger leaf) — see
  /// `RunLoop.rerenderScheduledFrame(from:convergence:)`. A missing node
  /// returns `false` so departed identities keep their re-carry semantics.
  package func isChildlessLeaf(
    _ identity: Identity,
    kind: NodeKind
  ) -> Bool {
    guard let node = nodeIfExists(for: identity) else {
      return false
    }
    return node.children.isEmpty && node.committed.kind == kind
  }

  package func translatePresentationPortalInvalidations(
    _ identities: Set<Identity>,
    portalRootIdentity: Identity,
    activeOverlayEntryIdentities: Set<Identity> = []
  ) -> Set<Identity> {
    let activeEntryIdentities = activeOverlayEntryIdentities.union(
      presentationOverlayEntryIdentities(portalRootIdentity: portalRootIdentity)
    )
    return Set(
      identities.map { identity in
        guard nodeIfExists(for: identity) == nil else {
          return identity
        }
        return presentationPortalInvalidationTarget(
          for: identity,
          portalRootIdentity: portalRootIdentity,
          activeOverlayEntryIdentities: activeEntryIdentities
        ) ?? identity
      }
    )
  }

  private func presentationPortalInvalidationTarget(
    for identity: Identity,
    portalRootIdentity: Identity,
    activeOverlayEntryIdentities: Set<Identity>
  ) -> Identity? {
    if isPresentationOverlayEntryIdentity(
      identity,
      portalRootIdentity: portalRootIdentity
    ) {
      var candidate = identity.parent
      while let current = candidate {
        guard
          isPresentationOverlayEntryIdentity(
            current,
            portalRootIdentity: portalRootIdentity
          )
        else {
          break
        }
        if nodeIfExists(for: current) != nil {
          return current
        }
        candidate = current.parent
      }
    }

    let identityPath = identity.path
    let overlayHostIdentity = presentationOverlayHostIdentity(
      portalRootIdentity: portalRootIdentity
    )
    for entryIdentity in activeOverlayEntryIdentities.sorted() {
      let entryPath = entryIdentity.path
      guard identityPath == entryPath || identityPath.hasPrefix("\(entryPath)/") else {
        continue
      }
      for target in [
        entryIdentity.child("body"),
        entryIdentity,
        overlayHostIdentity,
      ] {
        if nodeIfExists(for: target) != nil {
          return target
        }
      }
    }
    if identityPath.hasPrefix("\(overlayHostIdentity.path)/entry:"),
      nodeIfExists(for: overlayHostIdentity) != nil
    {
      return overlayHostIdentity
    }
    // Do NOT fall back to the portal root for an unmapped overlay-entry
    // identity. The portal root is the graph root and an ancestor of the
    // content, so mapping an overlay-entry invalidation onto it sweeps the
    // entire disjoint background into the reuse-conflict cone — the dominant
    // sheet open/close-settle residual. Leaving it unmapped keeps the
    // identity disjoint from the background, and `installPresentationPortalEvaluator`
    // already force-queues the portal root for re-resolution whenever the
    // invalidation set is non-empty, so the overlay still composes.
    return nil
  }

  private func isPresentationOverlayEntryIdentity(
    _ identity: Identity,
    portalRootIdentity: Identity
  ) -> Bool {
    guard identity.isDescendant(of: portalRootIdentity) else {
      return false
    }

    let suffix = Array(
      identity.components.dropFirst(portalRootIdentity.components.count)
    )
    guard suffix.count >= 3 else {
      return false
    }

    return suffix[0] == "PortalHost"
      && suffix[1] == "overlays"
      && suffix[2].hasPrefix("entry:")
  }

  private func presentationOverlayHostIdentity(
    portalRootIdentity: Identity
  ) -> Identity {
    portalRootIdentity
      .child("PortalHost")
      .child("overlays")
  }

  private func presentationOverlayEntryIdentities(
    portalRootIdentity: Identity
  ) -> Set<Identity> {
    Set(
      nodeIDByIdentity.keys.filter {
        isPresentationOverlayEntryRootIdentity(
          $0,
          portalRootIdentity: portalRootIdentity
        )
      }
    )
  }

  private func isPresentationOverlayEntryRootIdentity(
    _ identity: Identity,
    portalRootIdentity: Identity
  ) -> Bool {
    guard identity.isDescendant(of: portalRootIdentity) else {
      return false
    }

    let suffix = Array(
      identity.components.dropFirst(portalRootIdentity.components.count)
    )
    guard suffix.count == 3 else {
      return false
    }

    return suffix[0] == "PortalHost"
      && suffix[1] == "overlays"
      && suffix[2].hasPrefix("entry:")
  }

  /// Invalidates identities AND queues them as graph-local dirty so that
  /// `selectiveDirtyEvaluationPlan()` can include them in the dirty frontier
  /// instead of falling back to full root re-evaluation.  Only identities
  /// with existing graph nodes are queued.
  package func invalidateAndQueueDirty(_ identities: Set<Identity>) {
    ViewGraphInvalidationPlanner.invalidateAndQueueDirty(
      nodeIDsForInvalidation(identities),
      invalidatedNodeIDs: &invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  /// Invalidates existing graph nodes at or below `identities` and queues them
  /// as graph-local dirty work without treating a missing authored identity as
  /// a root-evaluation requirement.
  ///
  /// Finite retained-reuse suppression scopes often name an authored identity
  /// whose concrete reader node is a descendant. Root forcing used to make that
  /// descendant reachable. The dirty-frontier path instead queues the existing
  /// exact/descendant nodes and lets evaluator-target planning choose the
  /// nearest reachable roots.
  package func invalidateAndQueueDirtyDescendants(
    of identities: Set<Identity>,
    focusPresentationMembers: Set<Identity> = []
  ) {
    let viewNodeIDs = Set(
      identityByNodeID.compactMap { viewNodeID, identity -> ViewNodeID? in
        if identities.contains(where: { target in
          identity == target || identity.isDescendant(of: target)
        }) {
          return viewNodeID
        }
        // Focus/press members honor focus-presentation slot declarations: a
        // descendant below an inert OR value-verified slot the member itself
        // declared needs no queueing (see
        // `focusPresentationInertSlotExempts(member:identity:)` /
        // `focusPresentationValueVerifiedSlotExempts(member:identity:)`; the
        // value-verified kind still denies value-blind Layer-A reuse — the
        // member's own body re-run re-presents its values, and the memo
        // compare decides recompute-vs-reuse per slot). One non-exempting
        // matching member keeps the node queued.
        let matchingMembers = focusPresentationMembers.filter { member in
          identity == member || identity.isDescendant(of: member)
        }
        guard !matchingMembers.isEmpty else {
          return nil
        }
        return matchingMembers.contains { member in
          !focusPresentationInertSlotExempts(member: member, identity: identity)
            && !focusPresentationValueVerifiedSlotExempts(member: member, identity: identity)
        } ? viewNodeID : nil
      }
    )
    if ReuseDenialTrace.isEnabled {
      for member in focusPresentationMembers {
        let slots =
          nodeIfExists(for: member)?
          .focusPresentationInertSlotIdentities ?? []
        let valueVerifiedSlots =
          nodeIfExists(for: member)?
          .focusPresentationValueVerifiedSlotIdentities ?? []
        ReuseDenialTrace.recordSuppressionScopeDescription(
          "member-slots(\(member.path))=\(slots.count)+vv\(valueVerifiedSlots.count)"
        )
      }
    }
    guard !viewNodeIDs.isEmpty else {
      return
    }
    ViewGraphInvalidationPlanner.invalidateAndQueueDirty(
      viewNodeIDs,
      invalidatedNodeIDs: &invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  /// Records a focus-presentation-inert slot declaration on the declaring
  /// control's node — see `ViewNode.declareFocusPresentationInertSlot(_:)`.
  /// No-op when the control has no graph node yet (a declaration always runs
  /// inside the control's own resolve, so the node exists on live paths).
  package func declareFocusPresentationInertSlot(
    _ slotIdentity: Identity,
    forControl controlIdentity: Identity
  ) {
    guard let node = nodeIfExists(for: controlIdentity) else {
      if ReuseDenialTrace.isEnabled {
        ReuseDenialTrace.recordSuppressionScopeDescription(
          "inert-slot-NO-NODE(control=\(controlIdentity.path))"
        )
      }
      return
    }
    if ReuseDenialTrace.isEnabled,
      !node.focusPresentationInertSlotIdentities.contains(slotIdentity)
    {
      ReuseDenialTrace.recordSuppressionScopeDescription(
        "inert-slot(control=\(controlIdentity.path),slot=\(slotIdentity.path))"
      )
    }
    node.declareFocusPresentationInertSlot(slotIdentity)
  }

  /// Whether `identity` sits at or below a focus-presentation-inert slot that
  /// `member` (a focus/press suppression-scope member) itself declared, which
  /// exempts it from the member's descendant suppression cone. The slot node
  /// itself is included: its handed-down value is covered by the same promise.
  package func focusPresentationInertSlotExempts(
    member: Identity,
    identity: Identity
  ) -> Bool {
    guard let node = nodeIfExists(for: member) else {
      return false
    }
    return node.focusPresentationInertSlotIdentities.contains { slot in
      identity.isDescendant(of: slot)
    }
  }

  /// Whether the control at `identity` has declared any
  /// focus-presentation-inert slots. The run loop uses this to decide whether
  /// a focus/press move's tracker invalidation of that identity can ride the
  /// suppression scope instead of the frame's invalidation set — for a
  /// declaring control the invalidation's blanket descendant cone would
  /// conflict-deny exactly the content the slot declaration exempts.
  package func hasFocusPresentationInertSlots(for identity: Identity) -> Bool {
    nodeIfExists(for: identity)?
      .focusPresentationInertSlotIdentities.isEmpty == false
  }

  /// Records a focus-presentation value-verified slot declaration on the
  /// declaring control's node — see
  /// `ViewNode.declareFocusPresentationValueVerifiedSlot(_:)`. No-op when the
  /// control has no graph node yet (a declaration always runs inside the
  /// control's own resolve, so the node exists on live paths).
  package func declareFocusPresentationValueVerifiedSlot(
    _ slotIdentity: Identity,
    forControl controlIdentity: Identity
  ) {
    guard let node = nodeIfExists(for: controlIdentity) else {
      if ReuseDenialTrace.isEnabled {
        ReuseDenialTrace.recordSuppressionScopeDescription(
          "vv-slot-NO-NODE(control=\(controlIdentity.path))"
        )
      }
      return
    }
    if ReuseDenialTrace.isEnabled,
      !node.focusPresentationValueVerifiedSlotIdentities.contains(slotIdentity)
    {
      ReuseDenialTrace.recordSuppressionScopeDescription(
        "vv-slot(control=\(controlIdentity.path),slot=\(slotIdentity.path))"
      )
    }
    node.declareFocusPresentationValueVerifiedSlot(slotIdentity)
  }

  /// Whether `identity` sits at or below a focus-presentation value-verified
  /// slot that `member` (a focus/press suppression-scope member) itself
  /// declared. Such a descendant is exempt from the member's dirty-queue walk
  /// and from *memoized* (value-verified) reuse denial — but never from
  /// value-blind Layer-A denial: the slot's handed-down value may flip with
  /// the member's focus presentation, and only an `Equatable`-equal value
  /// proves the subtree unchanged.
  package func focusPresentationValueVerifiedSlotExempts(
    member: Identity,
    identity: Identity
  ) -> Bool {
    guard let node = nodeIfExists(for: member) else {
      return false
    }
    return node.focusPresentationValueVerifiedSlotIdentities.contains { slot in
      identity.isDescendant(of: slot)
    }
  }

  package func queueDirty(
    _ identities: Set<Identity>
  ) {
    ViewGraphInvalidationPlanner.queueDirty(
      nodeIDsForInvalidation(identities),
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func queueDirtyForStateChange(
    _ key: StateSlotKey
  ) {
    stateMutationKeys.insert(key)
    stateMutationNodeIDsByKey[key, default: []].insert(key.owner)
    ViewGraphInvalidationPlanner.queueDirty(
      ViewGraphInvalidationPlanner.stateChangeDirtyNodeIDs(
        for: key,
        stateSlotDependents: stateSlotDependents
      ),
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func stateMutationOverlay() -> StateMutationOverlay {
    var stateSlots: [StateMutationSlotKey: AnyStateSlot] = [:]
    for key in stateMutationKeys {
      var capturedSlot = false
      for viewNodeID in stateMutationNodeIDsByKey[key] ?? [] {
        guard
          let slot = nodeIfExists(for: viewNodeID)?.stateSlotStorage(
            ordinal: key.ordinal
          )
        else {
          continue
        }
        stateSlots[
          StateMutationSlotKey(
            key: StateSlotKey(
              owner: viewNodeID,
              ordinal: key.ordinal
            )
          )
        ] = slot
        capturedSlot = true
      }
      guard !capturedSlot,
        let slot = nodeIfExists(for: key.owner)?.stateSlotStorage(
          ordinal: key.ordinal
        )
      else {
        continue
      }
      stateSlots[
        StateMutationSlotKey(
          key: key
        )
      ] = slot
    }
    return StateMutationOverlay(
      stateSlots: stateSlots,
      invalidatedNodeIDs: invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
      stateMutationKeys: stateMutationKeys,
      stateMutationNodeIDsByKey: stateMutationNodeIDsByKey
    )
  }

  package func applyStateMutationOverlay(
    _ overlay: StateMutationOverlay
  ) {
    guard !overlay.isEmpty else {
      return
    }
    for (key, slot) in overlay.stateSlots {
      let node = nodeIfExists(for: key.key.owner)
      guard let node else {
        // The overlay exists to carry in-flight state writes across a
        // discarded async frame draft; a vanished owner means the write is
        // dropped here — the F63/F43 lost-write class. Counted (F93) so a
        // lost-write report starts from the alarm, not from adding logging.
        SoundnessProbeConfiguration.recordStateSlotRestorationDrop(
          "state-slot restoration dropped: owner \(key.key.owner) ordinal \(key.key.ordinal) no longer exists"
        )
        continue
      }
      node.restoreStateSlot(ordinal: key.key.ordinal, slot: slot)
      node.markDirty()
    }
    invalidatedNodeIDs.formUnion(overlay.invalidatedNodeIDs)
    graphLocalDirtyNodeIDs.formUnion(overlay.graphLocalDirtyNodeIDs)
    stateMutationKeys.formUnion(overlay.stateMutationKeys)
    for (key, viewNodeIDs) in overlay.stateMutationNodeIDsByKey {
      stateMutationNodeIDsByKey[key, default: []].formUnion(viewNodeIDs)
    }
  }

  package func queueDirtyForObservationChange(
    observedBy identity: Identity
  ) {
    guard let viewNodeID = viewNodeID(for: identity) else {
      return
    }
    ViewGraphInvalidationPlanner.queueDirty(
      ViewGraphInvalidationPlanner.observationChangeDirtyNodeIDs(
        observedBy: viewNodeID
      ),
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func invalidateEnvironmentReaders(
    within identities: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>
  ) {
    let dirtyNodeIDs = ViewGraphInvalidationPlanner.environmentReaderDirtyNodeIDs(
      within: identities,
      changedKeys: changedKeys,
      environmentDependents: environmentDependents,
      identityByNodeID: identityByNodeID
    )
    guard !dirtyNodeIDs.isEmpty else {
      invalidate(identities)
      return
    }

    invalidatedNodeIDs.formUnion(dirtyNodeIDs)
    ViewGraphInvalidationPlanner.queueDirty(
      dirtyNodeIDs,
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func environmentDependentIdentities(
    for changedKeys: Set<ObjectIdentifier>
  ) -> Set<Identity> {
    changedKeys.reduce(into: Set<Identity>()) { partial, key in
      partial.formUnion(identities(for: environmentDependents[key] ?? []))
    }
  }

  package func setRootEvaluator(
    rootIdentity: Identity,
    _ evaluate: @escaping @MainActor () -> Void
  ) {
    evaluationRootIdentity = rootIdentity
    rootEvaluator = evaluate
  }

  package func setEvaluator(
    for identity: Identity,
    _ evaluate: @escaping @MainActor () -> Void
  ) {
    nodeForIdentity(for: identity).setEvaluator(evaluate)
  }

  package func recordLifecycleEvaluationOwner(
    target targetIdentity: Identity,
    owner ownerIdentity: Identity
  ) {
    guard
      let targetNodeID = viewNodeID(for: targetIdentity),
      let ownerNodeID = viewNodeID(for: ownerIdentity)
    else {
      return
    }
    if let previousOwner = lifecycleEvaluationOwnersByNodeID[targetNodeID],
      previousOwner != ownerNodeID
    {
      lifecycleEvaluationTargetsByOwner[previousOwner]?.remove(targetNodeID)
      if lifecycleEvaluationTargetsByOwner[previousOwner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: previousOwner)
      }
    }

    lifecycleEvaluationOwnersByNodeID[targetNodeID] = ownerNodeID
    lifecycleEvaluationTargetsByOwner[ownerNodeID, default: []].insert(targetNodeID)
    if lifecycleEvaluationTargetsRecordedByOwner[ownerNodeID] != nil {
      lifecycleEvaluationTargetsRecordedByOwner[ownerNodeID, default: []].insert(targetNodeID)
    }
  }

  package func taskDescriptorIdentityLabel<ID: Equatable>(
    for identity: Identity,
    ordinal: Int,
    value: ID
  ) -> String {
    let viewNodeID = nodeForIdentity(for: identity).viewNodeID
    return taskDescriptorIdentityLabel(
      for: viewNodeID,
      ordinal: ordinal,
      value: value
    )
  }

  package func taskDescriptorIdentityLabel<ID: Equatable>(
    for viewNodeID: ViewNodeID,
    ordinal: Int,
    value: ID
  ) -> String {
    let key = TaskDescriptorSlotKey(node: viewNodeID, ordinal: ordinal)
    if let slot = taskDescriptorNodeSlots[key],
      slot.matches(value)
    {
      return slot.label
    }

    nextTaskDescriptorIdentityToken &+= 1
    let label = "id:\(nextTaskDescriptorIdentityToken)"
    taskDescriptorNodeSlots[key] = TaskDescriptorIdentitySlot(
      label: label,
      value: value
    )
    return label
  }

  package func selectiveDirtyEvaluationPlan() -> DirtyEvaluationPlan? {
    selectiveDirtyEvaluationPlanWithDiagnostics(invalidatedIdentities: []).plan
  }

  package func selectiveDirtyEvaluationPlanWithDiagnostics(
    invalidatedIdentities: Set<Identity>
  ) -> (plan: DirtyEvaluationPlan?, diagnostics: DirtyEvaluationPlanDiagnostics) {
    let unmappedIdentities = unmappedInvalidatedIdentities(invalidatedIdentities)
    let baseDiagnostics = dirtyPlanBaseDiagnostics(
      invalidatedIdentities: invalidatedIdentities,
      unmappedIdentities: unmappedIdentities
    )
    guard root != nil else {
      return (nil, baseDiagnostics("nil_missing_root", 0))
    }
    guard !invalidatedNodeIDs.isEmpty || !graphLocalDirtyNodeIDs.isEmpty else {
      return (nil, baseDiagnostics("nil_no_dirty_work", 0))
    }
    guard !graphLocalDirtyNodeIDs.isEmpty else {
      return (nil, baseDiagnostics("nil_no_graph_local_dirty_nodes", 0))
    }

    // Inter-rail reconciliation (F10 slice 2): a live invalidated node
    // missing from the graph-local dirty set is unioned in instead of
    // nil-ing the plan (the retired
    // `nil_invalidated_nodes_not_graph_local_dirty` escalation into a full
    // root evaluation). Zero on healthy selective frames by construction;
    // routine on non-selective frames, where `invalidate()` fills only the
    // invalidated rail and the force-queued portal root dominates the
    // union, so the reconciled frontier still resolves from the root as
    // those frames intend. The count is census-visible on the plan
    // diagnostics.
    let unqueuedInvalidated =
      invalidatedNodeIDs
      .filter { nodesByNodeID[$0] != nil }
      .subtracting(graphLocalDirtyNodeIDs)
    if !unqueuedInvalidated.isEmpty {
      ViewGraphInvalidationPlanner.queueDirty(
        unqueuedInvalidated,
        graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
        nodesByNodeID: nodesByNodeID
      )
    }

    guard
      let targetPlan = ViewGraphDirtyEvaluationPlanner.targetPlan(
        input: ViewGraphDirtyEvaluationPlanningInput(
          hasRoot: root != nil,
          graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
          nodesByNodeID: nodesByNodeID,
          lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID
        )
      )
    else {
      var diagnostics = baseDiagnostics("nil_no_frontier", 0)
      diagnostics.reconciledInvalidatedNodeCount = unqueuedInvalidated.count
      return (nil, diagnostics)
    }

    for target in targetPlan.targetNodes {
      target.markDirty()
    }

    guard !targetPlan.targetNodes.isEmpty,
      targetPlan.targetNodes.allSatisfy(\.hasEvaluator)
    else {
      var diagnostics = baseDiagnostics("nil_missing_evaluator", targetPlan.targetNodes.count)
      diagnostics.reconciledInvalidatedNodeCount = unqueuedInvalidated.count
      return (nil, diagnostics)
    }

    let plan = DirtyEvaluationPlan(
      frontierNodeIDs: targetPlan.targetNodes.map(\.viewNodeID),
      frontierIdentities: targetPlan.targetNodes.map(\.identity)
    )
    var diagnostics = baseDiagnostics("formed", plan.frontierIdentities.count)
    diagnostics.reconciledInvalidatedNodeCount = unqueuedInvalidated.count
    return (plan, diagnostics)
  }

  package func noDirtyWorkPlanDiagnostics(
    invalidatedIdentities: Set<Identity>
  ) -> DirtyEvaluationPlanDiagnostics {
    let unmappedIdentities = unmappedInvalidatedIdentities(invalidatedIdentities)
    return dirtyPlanBaseDiagnostics(
      invalidatedIdentities: invalidatedIdentities,
      unmappedIdentities: unmappedIdentities
    )("unchanged_no_dirty_work", 0)
  }

  package func disabledSelectiveEvaluationPlanDiagnostics(
    invalidatedIdentities: Set<Identity>,
    selectiveEvaluationDisabledReasons: [String] = []
  ) -> DirtyEvaluationPlanDiagnostics {
    let unmappedIdentities = unmappedInvalidatedIdentities(invalidatedIdentities)
    let remappedCount = unmappedIdentities.filter {
      nearestLiveAncestorNodeID(for: $0) != nil
    }.count
    return DirtyEvaluationPlanDiagnostics(
      result: "nil_selective_evaluation_disabled",
      invalidatedIdentityCount: invalidatedIdentities.count,
      unmappedInvalidatedIdentityCount: unmappedIdentities.count,
      unmappedInvalidatedIdentitySample: Array(unmappedIdentities.prefix(5)),
      remappedInvalidatedIdentityCount: remappedCount,
      droppedInvalidatedIdentityCount: unmappedIdentities.count - remappedCount,
      selectiveEvaluationDisabledReasons: selectiveEvaluationDisabledReasons
    )
  }

  /// Whether any identities are dirty and need evaluation this frame.
  package var hasDirtyWork: Bool {
    !invalidatedNodeIDs.isEmpty || !graphLocalDirtyNodeIDs.isEmpty
  }

  package func evaluateDirtyNodes(
    using plan: DirtyEvaluationPlan? = nil
  ) -> Bool {
    guard let plan = plan ?? selectiveDirtyEvaluationPlan() else {
      rootEvaluator?()
      if let evaluationRootIdentity {
        root = nodeIfExists(for: evaluationRootIdentity)
      }
      return false
    }

    if ReuseDenialTrace.isEnabled {
      ReuseDenialTrace.recordPlanTargets(
        plan.frontierNodeIDs.compactMap { nodesByNodeID[$0]?.identity.path }
      )
    }
    for viewNodeID in plan.frontierNodeIDs {
      nodesByNodeID[viewNodeID]?.evaluate()
    }
    if let evaluationRootIdentity {
      root = nodeIfExists(for: evaluationRootIdentity)
    }
    return true
  }

  package func beginFrame() {
    // Diagnostic: flush the just-finished frame's reuse-denial histogram before
    // starting the next one (inert unless SWIFTTUI_REUSE_TRACE is set).
    ReuseDenialTrace.dumpAndReset(frameID: currentFrameID)
    // Diagnostic: flush the just-finished frame's memoization histogram.
    // In release this is opt-in and sampled by `MemoSkipTrace.beginFrame`.
    MemoSkipTrace.dumpAndReset(frameID: currentFrameID)
    currentFrameID &+= 1
    MemoSkipTrace.beginFrame(frameID: currentFrameID)
    // Latch this frame's reconciliation-soundness sampling decision from the
    // monotonic frame counter (no clock/RNG). Cheap when the probe is off.
    SoundnessProbeConfiguration.beginFrame(frameID: currentFrameID)
    frameOrder.removeAll(keepingCapacity: true)
    stableTaskCancelEvents.removeAll(keepingCapacity: true)
    stableTaskStartEvents.removeAll(keepingCapacity: true)
    structuralAppearEvents.removeAll(keepingCapacity: true)
    structuralTaskCancelEvents.removeAll(keepingCapacity: true)
    structuralDisappearEvents.removeAll(keepingCapacity: true)
    pendingEntityRoutedRemovalNodeIDs.removeAll(keepingCapacity: true)
    absorbedShadowedNodeIDs.removeAll(keepingCapacity: true)
    latestLifecycleEvents.removeAll(keepingCapacity: true)
  }

  package func beginEvaluation(
    identity: Identity,
    entityIdentity: EntityIdentity? = nil,
    invalidator: (any Invalidating)?,
    suppressesStructuralLifecycle: Bool = false
  ) -> ViewNode {
    let node = nodeForIdentity(
      for: identity,
      entityIdentity: entityIdentity
    )
    node.prepareForFrame(currentFrameID)
    if !node.wasVisitedThisFrame {
      frameOrder.append(node.viewNodeID)
    }
    node.beginEvaluation(
      frameID: currentFrameID,
      invalidator: invalidator,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle
    )
    if node.isAtOutermostEvaluationDepth {
      lifecycleEvaluationTargetsRecordedByOwner[node.viewNodeID] = []
    }
    return node
  }

  package func setSuppressesStructuralLifecycle(
    _ suppressesStructuralLifecycle: Bool,
    for identity: Identity
  ) {
    nodeIfExists(for: identity)?.setSuppressesStructuralLifecycle(suppressesStructuralLifecycle)
  }

  /// Whether a claim of `entityIdentity` at `identity` would cross-identity
  /// adopt a node whose body resolution is currently on the stack. A forwarded
  /// (`EntityRouteProvidingView`) claim from a wrapper-derived interior
  /// `resolveView` — a `.frame`/`.padding` content wrapper re-resolving the
  /// same chain one level down — must not steal the node an enclosing level of
  /// the chain claimed moments ago: re-indexing it away from the enclosing
  /// identity aliases the parent's committed child pairing (the stamp-coherence
  /// trap). Cross-frame adoption (the routed node is idle) and same-identity
  /// re-entrant claims (the transparent-chain collapse) are unaffected.
  package func entityRouteTargetsMidEvaluationNode(
    _ entityIdentity: EntityIdentity,
    claimedAt identity: Identity
  ) -> Bool {
    guard let routedNodeID = entityRoutingTable.route(entityIdentity),
      let node = nodeIfExists(for: routedNodeID)
    else {
      return false
    }
    return node.isEvaluating && node.identity != identity
  }

  /// Whether `entityIdentity` currently routes to `node`. The explicit-`.id`
  /// churn predicate uses this as a continuity signal: a slot whose resolved
  /// identity re-rooted away from its structural identity is NOT churning when
  /// the arriving modifier's entity already lives on this very node — that is
  /// the steady state of a collapsed chain whose deeper `.id` re-rooted the
  /// resolved identity (`.id(stable)` inside `.id(owner)`); treating it as
  /// churn re-records a departure and suppresses reuse on every frame.
  package func entityRouteIsBound(
    _ entityIdentity: EntityIdentity,
    to node: ViewNode
  ) -> Bool {
    entityRoutingTable.route(entityIdentity) == node.viewNodeID
  }

  package func prepareEntityRoutedOwner(
    _ entityIdentity: EntityIdentity,
    for node: ViewNode?
  ) {
    guard let node else {
      return
    }
    // The outermost same-frame claim owns the entity. This runs at the
    // innermost chain level (where the `.id` modifier resolves); when an
    // enclosing wrapper level already claimed the entity this frame — its
    // node is mid-evaluation on the stack, or already visited — re-binding
    // here would hand the entity to the innermost wrapper node and invert
    // next frame's adoption direction (the outer level would cross-identity
    // steal the inner node, aliasing the parent's committed child pairing).
    if let boundNodeID = entityRoutingTable.route(entityIdentity),
      boundNodeID != node.viewNodeID,
      let bound = nodeIfExists(for: boundNodeID),
      bound.isEvaluating
    {
      return
    }
    let existingEntityIdentity =
      node.committed.entityIdentity
      ?? entityRoutingTable.entityByNodeID[node.viewNodeID]
    if let existingEntityIdentity,
      existingEntityIdentity != entityIdentity
    {
      node.resetStateSlots()
    }
    entityRoutingTable.bind(entityIdentity, to: node.viewNodeID)
  }

  @discardableResult
  package func finishEvaluation(
    _ node: ViewNode,
    resolved: ResolvedNode,
    accessedStateSlots: Int
  ) -> ResolvedNode? {
    let previousDependencies = node.dependencies
    let previousResolvedIdentity = node.resolvedIdentity
    guard node.finishEvaluation(accessedStateSlots: accessedStateSlots) else {
      return nil
    }

    let resolved = resolvedPreservingLayoutRealizedChildren(
      resolved,
      for: node
    )
    pruneDetachedResolvedRootIfNeeded(
      previousResolvedIdentity: previousResolvedIdentity,
      replacedBy: resolved.identity,
      for: node
    )
    let childNodes = resolved.children.map(nodeForResolvedNode)
    recordValueOnlyChildInteriorAnchors(
      resolved.children,
      hostedBy: node
    )
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
    applyResolvedNode(
      node,
      resolved: resolved,
      children: childNodes
    )
    reindexDependencies(
      for: node,
      previous: previousDependencies
    )

    let emitsOwnLifecycleEvents = nodeEmitsOwnLifecycleEvents(node)
    let didChangeResolvedIdentity = previousResolvedIdentity != node.resolvedIdentity

    if node.wasPresentAtFrameStart {
      if emitsOwnLifecycleEvents {
        appendStableTaskLifecycleEvents(
          for: node,
          previousResolvedIdentity: previousResolvedIdentity,
          didChangeResolvedIdentity: didChangeResolvedIdentity
        )
      }
      node.setLifecycleState(.alive)
    } else {
      if emitsOwnLifecycleEvents,
        !node.lifecycleMetadata.appearHandlerIDs.isEmpty
      {
        structuralAppearEvents.append(
          .init(
            identity: node.identity,
            operation: .appear(handlerIDs: node.lifecycleMetadata.appearHandlerIDs)
          )
        )
      }
      if emitsOwnLifecycleEvents {
        for task in node.lifecycleMetadata.tasks {
          appendTaskStartEvent(
            identity: node.resolvedIdentity,
            task: task
          )
        }
      }
      node.setLifecycleState(.appearing)
    }
    pruneLifecycleEvaluationOwners(ownedBy: node.identity)
    return node.committed
  }

  /// A value-only child (a styling-wrapper ResolvedNode with no view node —
  /// button/text-field chrome resolved without its own `resolveView`) maps to
  /// a placeholder ViewNode that is never evaluated: its children array stays
  /// permanently empty, so the evaluated interior nodes beneath it
  /// (`…/ButtonBody/false/base`, `/overlay`, `/background`) are reachable only
  /// through weak `evaluationHost` links. Anchor them with hosted-detached
  /// edges from the EVALUATED parent (not the per-generation placeholder,
  /// which is re-minted and discarded on every re-resolve): the parent's
  /// teardown then reclaims the interiors, and the reachability census keeps
  /// them absorbed while the parent lives — otherwise a departing host
  /// generation (a dismissed presentation-overlay entry) strands one interior
  /// generation per entry, the F04 leak-census residual. The style-seam root
  /// fix (resolving style bodies through their own view node) supersedes this
  /// once landed.
  private func recordValueOnlyChildInteriorAnchors(
    _ resolvedChildren: [ResolvedNode],
    hostedBy node: ViewNode
  ) {
    for resolvedChild in resolvedChildren {
      guard resolvedChild.viewNodeID == nil,
        !resolvedChild.children.isEmpty
      else {
        continue
      }
      recordInteriorAnchors(
        under: resolvedChild,
        hostedByNodeID: node.viewNodeID
      )
    }
  }

  /// Records a hosted-detached edge from the placeholder to each nearest
  /// evaluated interior under a value-only resolved layer. Evaluated interiors
  /// wire their own children through `finishEvaluation`, so the walk stops at
  /// the first stamped node and recurses only through deeper value-only
  /// layers.
  private func recordInteriorAnchors(
    under resolved: ResolvedNode,
    hostedByNodeID hostID: ViewNodeID
  ) {
    for child in resolved.children {
      if let interiorID = child.viewNodeID,
        interiorID != hostID,
        nodeIfExists(for: interiorID) != nil
      {
        recordDetachedHostedNode(interiorID, hostedByNodeID: hostID)
      } else {
        recordInteriorAnchors(under: child, hostedByNodeID: hostID)
      }
    }
  }

  /// Declares that `host` resolved `resolved` this frame without committing it
  /// as a child (a navigation stack's root while a destination is presented).
  /// Such a subtree is reachable through neither committed values nor parent
  /// links — resolution is its only lifetime anchor — so `removeSubtree`
  /// descends these edges when the host departs, tearing the hosted subtree
  /// down with the same visited-sparing and entity-deferral guards as every
  /// other departed-subtree descent. Re-committing the subtree later (the
  /// destination dismisses) makes the edge redundant, not wrong: the host's
  /// teardown already reaches an attached child, and the walk is idempotent.
  package func recordDetachedHostedSubtree(
    _ resolved: ResolvedNode,
    hostedBy host: ViewNode?
  ) {
    guard let host,
      let rootNodeID = resolved.viewNodeID ?? viewNodeID(for: resolved.identity),
      rootNodeID != host.viewNodeID,
      nodeIfExists(for: rootNodeID) != nil
    else {
      return
    }
    recordDetachedHostedNode(rootNodeID, hostedByNodeID: host.viewNodeID)
  }

  private func recordDetachedHostedNode(
    _ rootNodeID: ViewNodeID,
    hostedByNodeID hostID: ViewNodeID
  ) {
    if detachedHostedSubtreeHostByRoot[rootNodeID] == hostID {
      return
    }
    if let previousHost = detachedHostedSubtreeHostByRoot[rootNodeID] {
      detachedHostedSubtreeRootsByHost[previousHost]?.remove(rootNodeID)
      if detachedHostedSubtreeRootsByHost[previousHost]?.isEmpty == true {
        detachedHostedSubtreeRootsByHost.removeValue(forKey: previousHost)
      }
    }
    detachedHostedSubtreeRootsByHost[hostID, default: []].insert(rootNodeID)
    detachedHostedSubtreeHostByRoot[rootNodeID] = hostID
    assertDetachedHostedLedgerInverse()
  }

  /// DEBUG-only inverse-consistency check for the detached-hosted ledger
  /// (F97): `rootsByHost` and `hostByRoot` are a hand-maintained
  /// bidirectional map mutated at three sites; a desync previously surfaced
  /// only later, through the teardown-coherence anchor forensics, far from
  /// the mutation that caused it. Validated at each mutation so corruption
  /// fails at its source.
  func assertDetachedHostedLedgerInverse() {
    #if DEBUG
      for (root, host) in detachedHostedSubtreeHostByRoot
      where detachedHostedSubtreeRootsByHost[host]?.contains(root) != true {
        assertionFailure(
          "detached-hosted ledger desync: hostByRoot[\(root)] = \(host) has no rootsByHost mirror"
        )
      }
      for (host, roots) in detachedHostedSubtreeRootsByHost {
        if roots.isEmpty {
          assertionFailure(
            "detached-hosted ledger desync: empty roots entry retained for host \(host)"
          )
        }
        for root in roots where detachedHostedSubtreeHostByRoot[root] != host {
          assertionFailure(
            "detached-hosted ledger desync: rootsByHost[\(host)] holds \(root) but hostByRoot disagrees"
          )
        }
      }
    #endif
  }

  package func installLayoutRealizedChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
    // A layout-dependent realization (a GeometryReader body) re-resolves its
    // content during the frame tail's layout pass — outside any dirty plan.
    // That resolve re-records the content's runtime registrations (bumping
    // node mutation generations) and this install can move nodes in or out of
    // the live set. On a frame that formed no dirty plan (a terminal-resize
    // frame: no state is dirty, but the new proposal re-realizes every
    // boundary) the publication would stay `.unchanged`, the refreshed
    // records would never reach the live registry, and the F63 DEBUG
    // fingerprint oracle would trap (the gallery Life-tab resize crash).
    // Queue the boundary as a publication root so the committing draft
    // escalates to a `.subtrees` publication covering the realized content —
    // the same escalation as `refreshActionRegistration`. Realized content
    // resolves under the boundary's identity, so a boundary-rooted subtree
    // covers it. Queued before the node guard: the realize resolve has
    // already evaluated content nodes even when the boundary itself is gone.
    pendingRuntimeRegistrationRefreshRoots.insert(identity)
    guard let node = nodeIfExists(for: identity) else {
      return
    }

    var resolved = node.snapshot()
    resolved.children = children
    let childNodes = children.map(nodeForResolvedNode)
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
    applyResolvedNode(
      node,
      resolved: resolved,
      children: childNodes
    )
  }

  package func prepareStructuralChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
    guard let node = nodeIfExists(for: identity) else {
      return
    }

    var resolved = node.snapshot()
    resolved.children = children
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
  }

  package func refreshResolvedMetadata(
    for resolved: ResolvedNode
  ) {
    let node: ViewNode?
    if let viewNodeID = resolved.viewNodeID {
      node = nodeIfExists(for: viewNodeID)
    } else {
      node = nodeIfExists(for: resolved.identity)
    }
    if let node {
      node.refreshResolvedMetadata(from: resolved)
    }
  }

  private func resolvedPreservingLayoutRealizedChildren(
    _ resolved: ResolvedNode,
    for node: ViewNode
  ) -> ResolvedNode {
    guard resolved.layoutRealizedContent != nil,
      resolved.children.isEmpty,
      !node.children.isEmpty
    else {
      return resolved
    }

    var preserved = resolved
    preserved.children = node.children.map { $0.snapshot() }
    return preserved
  }

  private func pruneDetachedResolvedRootIfNeeded(
    previousResolvedIdentity: Identity,
    replacedBy currentResolvedIdentity: Identity,
    for node: ViewNode
  ) {
    guard previousResolvedIdentity != currentResolvedIdentity else {
      return
    }
    guard previousResolvedIdentity != node.identity else {
      return
    }
    guard let previousResolvedRoot = nodeIfExists(for: previousResolvedIdentity) else {
      return
    }
    guard previousResolvedRoot.parent == nil else {
      return
    }
    guard !previousResolvedRoot.visitedThisFrame(currentFrameID) else {
      return
    }
    removeSubtree(rootedAt: previousResolvedRoot)
  }

  package func pruneDetachedIdentitySubtree(
    rootedAt identity: Identity
  ) {
    let staleNodes = nodesByNodeID.values
      .filter { node in
        node.prepareForFrame(currentFrameID)
        return (node.identity == identity || node.identity.isDescendant(of: identity))
          && node.wasPresentAtFrameStart
          && !node.visitedThisFrame(currentFrameID)
      }
      .sorted { lhs, rhs in
        if lhs.identity.components.count == rhs.identity.components.count {
          return lhs.identity < rhs.identity
        }
        return lhs.identity.components.count < rhs.identity.components.count
      }

    for node in staleNodes {
      guard nodeIfExists(for: node.viewNodeID) != nil else {
        continue
      }
      removeSubtree(rootedAt: node)
    }
  }

  package func recordReusedSubtree(
    _ subtree: ResolvedNode,
    invalidator: (any Invalidating)?,
    retained: Bool = false
  ) {
    let node = nodeForResolvedNode(subtree)
    node.prepareForFrame(currentFrameID)

    if node.wasVisitedThisFrame {
      return
    }
    frameOrder.append(node.viewNodeID)
    node.beginReuse(
      frameID: currentFrameID,
      invalidator: invalidator
    )
    let previousResolvedIdentity = node.resolvedIdentity
    if retained {
      // Retained subtree: this root passed reusableSnapshot's full disjointness
      // check (no identity or structural intersection with the frame's
      // invalidation), so every descendant is unchanged. Its committed snapshot
      // carries the whole subtree by value, and descendant presence
      // (`hasCommittedPresence`) and liveness (`liveIdentities`) both persist
      // across `beginFrame` — so we skip the O(subtree) descendant recursion and
      // refresh only this root. The root's children are unchanged, so
      // A retained snapshot already carries the unchanged descendants' runtime
      // node IDs. Commit it directly so runtime-ID stamping stays O(1) at the
      // retained root instead of walking the whole subtree again.
      node.applyRetainedSnapshot(subtree)
    } else {
      // Non-retained recursion: production resolve never reaches this branch
      // (both `reusableSnapshot` returns pass `retained: true`); the only
      // entry is `applySnapshot`, used by tests and snapshot hosting.  The
      // runtime-ID stamping fast path relies on that reachability fact: a
      // previously stamped tree re-applied here after descendant pruning
      // would keep its dead stamps past the `nodeForResolvedNode` identity
      // fallback (the debug stamp-coherence assertion trips on that case).
      let childNodes = subtree.children.map { child -> ViewNode in
        recordReusedSubtree(
          child,
          invalidator: invalidator
        )
        return nodeForResolvedNode(child)
      }
      applyStructuralChildDiff(
        for: node,
        resolved: subtree
      )
      applyResolvedNode(
        node,
        resolved: subtree,
        children: childNodes
      )
    }
    let emitsOwnLifecycleEvents = nodeEmitsOwnLifecycleEvents(node)
    let didChangeResolvedIdentity = previousResolvedIdentity != node.resolvedIdentity

    if !node.wasPresentAtFrameStart {
      if emitsOwnLifecycleEvents,
        !node.lifecycleMetadata.appearHandlerIDs.isEmpty
      {
        structuralAppearEvents.append(
          .init(
            identity: node.identity,
            operation: .appear(handlerIDs: node.lifecycleMetadata.appearHandlerIDs)
          )
        )
      }
      if emitsOwnLifecycleEvents {
        for task in node.lifecycleMetadata.tasks {
          appendTaskStartEvent(
            identity: node.resolvedIdentity,
            task: task
          )
        }
      }
      node.setLifecycleState(.appearing)
    } else {
      if emitsOwnLifecycleEvents {
        appendStableTaskLifecycleEvents(
          for: node,
          previousResolvedIdentity: previousResolvedIdentity,
          didChangeResolvedIdentity: didChangeResolvedIdentity
        )
      }
      node.setLifecycleState(.alive)
    }
  }

  /// Emits the stable-arm task lifecycle events for a present node by applying
  /// the shared ``TaskLifecycleDiff`` policy to its previous vs current task
  /// descriptors. Shared by the recompute (`finishEvaluation`) and reuse
  /// (`recordReusedSubtree`) paths, which previously mirrored this policy
  /// inline.
  private func appendStableTaskLifecycleEvents(
    for node: ViewNode,
    previousResolvedIdentity: Identity,
    didChangeResolvedIdentity: Bool
  ) {
    let diff = TaskLifecycleDiff.between(
      previous: node.previousLifecycleMetadata.tasks,
      current: node.lifecycleMetadata.tasks,
      identityChanged: didChangeResolvedIdentity
    )
    for task in diff.cancels {
      appendTaskCancelEvent(
        identity: diff.cancelsKeyToCurrentIdentity
          ? node.resolvedIdentity : previousResolvedIdentity,
        task: task,
        isStructural: false
      )
    }
    for task in diff.starts {
      appendTaskStartEvent(
        identity: node.resolvedIdentity,
        task: task
      )
    }
  }

  /// Diagnostic-only: records WHY retained reuse was denied for `identity` this
  /// frame, categorizing into suppressed / no-node / invalidated-empty / a
  /// `canReuse` sub-reason / invalidation-conflict. Inert unless the trace is on.
  /// Called from `resolveView` on the recompute path.
  @MainActor
  package func recordReuseDenialIfTracing(
    for identity: Identity,
    suppressed: Bool,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot,
    invalidatedIdentities: Set<Identity>
  ) {
    guard ReuseDenialTrace.isEnabled else {
      return
    }
    if suppressed {
      ReuseDenialTrace.record("suppressed")
      ReuseDenialTrace.recordSuppressedIdentity(identity.path)
      return
    }
    guard let node = nodeIfExists(for: identity) else {
      ReuseDenialTrace.record("no-node")
      return
    }
    if invalidatedIdentities.isEmpty {
      ReuseDenialTrace.record("invalidated-empty")
      return
    }
    if let reason = node.canReuseDenialReason(
      frameID: currentFrameID,
      environment: environment,
      transaction: transaction
    ) {
      ReuseDenialTrace.record(reason)
      return
    }
    // canReuse would succeed, so the only remaining denial is an identity /
    // structural intersection with the invalidation set. Capture the invalidated
    // identities so the dirty ancestor blocking the background is visible.
    ReuseDenialTrace.record("invalidation-conflict")
    for invalidated in invalidatedIdentities {
      ReuseDenialTrace.recordInvalidatedIdentity(invalidated.path)
    }
  }

  package func reusableSnapshot(
    for identity: Identity,
    invalidatedIdentities: Set<Identity>,
    invalidationSummary: InvalidationSummary? = nil,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot,
    allowsEmptyInvalidation: Bool = false,
    invalidator: (any Invalidating)?
  ) -> ResolvedNode? {
    guard let node = nodeIfExists(for: identity) else {
      return nil
    }
    // An empty invalidation set on a frame that still resolves means the
    // frame was forced for a reason OUTSIDE invalidation tracking, so
    // disjointness from the (empty) set proves nothing — deny reuse — UNLESS
    // the caller certifies that reason is fully named by a finite
    // retained-reuse suppression scope (focus/press runtime readers, active
    // animation cones). The caller rejects suppressed identities before
    // consulting this gate, so a node reaching it with
    // `allowsEmptyInvalidation` is outside every named recompute cone and
    // the environment/transaction equality checks below are the remaining
    // (sufficient) freshness proof.
    guard !invalidatedIdentities.isEmpty || allowsEmptyInvalidation else {
      return nil
    }

    node.prepareForFrame(currentFrameID)

    guard
      node.canReuse(
        frameID: currentFrameID,
        environment: environment,
        transaction: transaction
      )
    else {
      return nil
    }

    let invalidationSummary =
      invalidationSummary
      ?? .init(invalidatedIdentities: invalidatedIdentities)
    let resolvedIdentity = node.resolvedIdentity
    let identityIntersectsInvalidation =
      invalidationSummary.intersectsSubtree(at: identity)
      || (resolvedIdentity != identity
        && invalidationSummary.intersectsSubtree(at: resolvedIdentity))
    let structurallyIntersectsInvalidation = structuralInvalidationIntersects(
      node,
      invalidatedIdentities: invalidatedIdentities
    )
    if !identityIntersectsInvalidation,
      !structurallyIntersectsInvalidation
    {
      let snapshot = node.snapshot()
      recordReusedSubtree(
        snapshot,
        invalidator: invalidator,
        retained: true
      )
      return snapshot
    }

    // If the live-graph structural check already rejects reuse, skip the
    // O(invalidated × path) identity-conflict scan: its result cannot change the
    // outcome (the guard below rejects on structural intersection regardless).
    // Behavior-identical; avoids a redundant per-node scan on every frame where
    // a structural intersection is present.
    if structurallyIntersectsInvalidation {
      return nil
    }

    // NOT redundant with `identityIntersectsInvalidation` — do NOT remove this
    // (resolve_ms remediation tried and reverted it). Reaching here means the
    // structural-summary `intersectsSubtree` reported an intersection while the
    // live-graph structural walk did not. The summary walks ancestry on the
    // `StructuralPath` projection and is a *conservative over-approximation* for
    // divergent identities (`.id` / `ForEach` / portals); this precise
    // identity-axis self/ancestor/descendant scan can — and across the suite,
    // does — find no actual conflict, which legitimately rescues reuse the
    // summary alone would reject. Dropping it converts those reuses into
    // recomputes: behavior-safe but a measurable reuse-rate (resolve_ms)
    // *regression*, the opposite of the intended win.
    let conflictsWithInvalidation = invalidatedIdentities.contains { invalidatedIdentity in
      invalidatedIdentity == identity
        || invalidatedIdentity.isDescendant(of: identity)
        || identity.isDescendant(of: invalidatedIdentity)
        || invalidatedIdentity == resolvedIdentity
        || invalidatedIdentity.isDescendant(of: resolvedIdentity)
        || resolvedIdentity.isDescendant(of: invalidatedIdentity)
    }
    guard !conflictsWithInvalidation else {
      return nil
    }
    let snapshot = node.snapshot()
    recordReusedSubtree(
      snapshot,
      invalidator: invalidator,
      retained: true
    )
    return snapshot
  }

  /// Memoized-body reuse: the accept-branch the design centers on. Fires for a
  /// node that ``reusableSnapshot`` rejected *only* because it is a structural
  /// descendant of an invalidated ancestor (its own content is fresh) — when its
  /// freshly-presented view value is structurally equal to the value it was last
  /// resolved with, it has no recorded dependencies (the conservative safe
  /// subset), and it passes every non-dirty retained-reuse guard. Routes through
  /// the identical `snapshot()` + `recordReusedSubtree(retained:)` acceptance
  /// path as ``reusableSnapshot``, so all registration/lifecycle/island plumbing
  /// is preserved. Gated by ``MemoReuseConfiguration``; the caller also gates on
  /// the focus/press retained-reuse suppression scope (as for ``reusableSnapshot``).
  package func memoizedReusableSnapshot(
    for identity: Identity,
    viewValue: Any,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot,
    invalidatedIdentities: Set<Identity>,
    uncoveredEnvironmentKeys: Set<ObjectIdentifier>,
    invalidator: (any Invalidating)?
  ) -> ResolvedNode? {
    guard let node = nodeIfExists(for: identity) else {
      return nil
    }
    // No prior view value (first resolve, or feature was off last frame) ⇒
    // nothing to compare against.
    guard let priorViewValue = node.memoViewValue else {
      return nil
    }
    node.prepareForFrame(currentFrameID)
    guard
      !node.isDirty,
      !node.wasVisitedThisFrame,
      // A self-invalidated node must re-run; only nodes reached under a re-run
      // ancestor are memoization candidates.
      !invalidatedIdentities.contains(identity),
      node.canMemoReuse(environment: environment, transaction: transaction),
      // The reuse-safe dependency subset: no `@State`/`@Observable` reads, and no
      // `@Environment` read of a key excluded from the snapshot (focus/press).
      // Snapshot-covered environment reads are already verified by
      // `canMemoReuse`'s `environmentSnapshot ==`, so layout containers qualify —
      // the boundaries where whole-subtree reuse pays. State-value, observable,
      // and focus/press equality are deferred / enforced elsewhere.
      node.hasNoMemoUncoveredDependencies(uncoveredEnvironmentKeys: uncoveredEnvironmentKeys)
    else {
      return nil
    }
    // `Equatable`-only: a non-`Equatable` value (every framework container) is
    // skipped rather than reflected over — the reflective path costs more than
    // the body re-run it saves on trees without a high author boundary. Author
    // opt-in (a view conforming to `Equatable`, or wrapped in `EquatableView`) is
    // what makes a node a memo candidate.
    guard MemoValueComparator.compareEquatable(priorViewValue, viewValue) == .equal else {
      return nil
    }
    let snapshot = node.snapshot()
    recordReusedSubtree(
      snapshot,
      invalidator: invalidator,
      retained: true
    )
    return snapshot
  }

  #if DEBUG
    /// Value-verified-slot soundness oracle: when the memo layer reuses a
    /// subtree that value-blind Layer-A suppression would have denied (a
    /// focus/press move's member cone, exempted through a value-verified
    /// slot), no node in that subtree may carry a recorded *wholesale*
    /// runtime-focus dependency (`focusedIdentity`/`pressedIdentity`
    /// environment keys): such a reader is unioned into every focus move's
    /// scope as a full member, which makes the reused root an
    /// ancestor-of-member — an unexemptable match that blocks the memo gate.
    /// Reaching this assert with such a dependency means the member union
    /// and the memo exemption disagree. Side-field sentinel reads are legal
    /// here: their output can only change when the moved identity is at or
    /// below the reader, and the moved identities' own cones are never
    /// exempted.
    package func debugAssertMemoReuseSubtreeFreeOfRuntimeFocusDependencies(
      _ resolved: ResolvedNode,
      uncoveredEnvironmentKeys: Set<ObjectIdentifier>
    ) {
      var stack = [resolved]
      while let next = stack.popLast() {
        if let node = nodeIfExists(for: next.identity) {
          assert(
            node.dependencies.environmentReads.isDisjoint(
              with: uncoveredEnvironmentKeys
            ),
            """
            memoized reuse under a focus/press suppression scope served a \
            subtree containing a wholesale runtime-focus reader at \
            \(next.identity.path); the reader should have been a scope member \
            blocking this reuse
            """
          )
        }
        stack.append(contentsOf: next.children)
      }
    }
  #endif

  @discardableResult
  package func applySnapshot(
    _ resolved: ResolvedNode,
    placed: ViewportVisibilitySummary? = nil,
    invalidator: (any Invalidating)? = nil
  ) -> [LifecycleEvent] {
    beginFrame()
    recordReusedSubtree(
      resolved,
      invalidator: invalidator
    )
    return finalizeFrame(
      resolved: resolved,
      placed: placed
    )
  }

  package func finalizeFrame(
    rootIdentity: Identity
  ) -> [LifecycleEvent] {
    guard let root else {
      self.root = nodeIfExists(for: rootIdentity)
      return []
    }
    return finalizeFrame(
      resolved: root.snapshot(),
      placed: nil
    )
  }

  package func finalizeFrame(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?
  ) -> [LifecycleEvent] {
    return finalizeFrame(
      rootIdentity: resolved.identity,
      resolved: resolved,
      placed: placed
    )
  }

  package func previewLifecycleEvents(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?
  ) -> [LifecycleEvent] {
    previewLifecycleEventPlan(
      resolved: resolved,
      placed: placed
    ).events
  }

  package func previewLifecycleEventPlan(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?
  ) -> ViewGraphFrameLifecycleEventPlan {
    // The finalize-frame teardown barrier emits the departed subtrees'
    // cancel/disappear events (an entity-routed removal deferred out of the
    // structural diff resolves here, once the full old-vs-new entity set is
    // known). Run it for the preview too, so the previewed plan matches the
    // committed one. Both prunes are self-consuming — the later
    // `finalizeFrame` re-run is a no-op — and an aborted candidate rolls the
    // mutations back with the rest of the prepared frame state.
    prunePendingEntityRoutedRemovals(
      activeEntities: entityIdentities(in: resolved)
    )
    pruneAbsorbedShadowedNodes()
    return frameLifecycleEventPlan(
      resolved: resolved,
      placed: placed
    )
  }

  package func finalizeFrame(
    rootIdentity: Identity,
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?,
    previewedPlan: ViewGraphFrameLifecycleEventPlan? = nil
  ) -> [LifecycleEvent] {
    root = nodeIfExists(for: rootIdentity)
    let activeEntities = entityIdentities(in: resolved)
    prunePendingEntityRoutedRemovals(activeEntities: activeEntities)
    pruneAbsorbedShadowedNodes()

    for viewNodeID in frameOrder {
      guard let node = nodesByNodeID[viewNodeID] else {
        continue
      }
      node.setCommittedPresence(true)
      guard !node.wasPresentAtFrameStart else {
        continue
      }
      node.setLifecycleState(.alive)
    }

    // The async ordered-commit path already planned this frame's lifecycle
    // events for its drop-eligibility preview; nothing runs between the
    // preview and this finalize on the main actor, so the plan is reused
    // instead of recomputed (F61). The DEBUG recompute pins that premise: a
    // divergence means some state feeding the planner changed between
    // preview and commit, which would have shipped as a silently different
    // committed plan.
    let lifecyclePlan: ViewGraphFrameLifecycleEventPlan
    if let previewedPlan {
      #if DEBUG
        let recomputed = frameLifecycleEventPlan(
          resolved: resolved,
          placed: placed
        )
        assert(
          recomputed.events == previewedPlan.events,
          "previewed lifecycle events diverged from the committed frame's plan"
        )
        assert(
          recomputed.viewportLifecycleOrder == previewedPlan.viewportLifecycleOrder,
          "previewed viewport-lifecycle order diverged from the committed frame's plan"
        )
      #endif
      lifecyclePlan = previewedPlan
    } else {
      lifecyclePlan = frameLifecycleEventPlan(
        resolved: resolved,
        placed: placed
      )
    }
    latestLifecycleEvents = lifecyclePlan.events
    viewportLifecycleNodesByKey = lifecyclePlan.viewportLifecycleNodesByKey
    viewportLifecycleOrder = lifecyclePlan.viewportLifecycleOrder

    // A node visited this frame can be gone by commit (a mid-resolve
    // displacement eviction of an already-visited occupant, a reclaimed
    // shadowed mint) — carrying its ID into `liveNodeIDs` would strand a dead
    // entry there forever.
    liveNodeIDs.formUnion(frameOrder.filter { nodesByNodeID[$0] != nil })
    releaseInactiveEntityRoutes(
      activeEntities: activeEntities
    )
    pruneDepartedChangeObservationValues()
    invalidatedNodeIDs.removeAll(keepingCapacity: true)
    graphLocalDirtyNodeIDs.removeAll(keepingCapacity: true)
    stateMutationKeys.removeAll(keepingCapacity: true)
    stateMutationNodeIDsByKey.removeAll(keepingCapacity: true)
    if SoundnessProbeConfiguration.isSampledFrame,
      let violation = teardownCoherenceViolation()
    {
      if violation.isOverRemoval {
        SoundnessProbeConfiguration.recordTeardownCoherenceViolation(violation.detail)
      } else {
        // The leak direction stays assert-free until its measured residual
        // class (F91: lazy/List content strands under flipped branches —
        // see the leak-census ratchet in `FrameworkStressTests`) is burned
        // down; `teardownCoherenceLeakCount` watches it independently so
        // the class cannot grow silently.
        SoundnessProbeConfiguration.recordTeardownCoherenceLeak(
          violation.detail,
          unreachableCount: violation.unreachableCount
        )
      }
      #if DEBUG
        // The stale-alias direction measured zero across the stress suite
        // when introduced, so any hit is a regression of the deleted sweep's
        // failure mode.
        if violation.isOverRemoval {
          assertionFailure(violation.detail)
        }
      #endif
    }
    return latestLifecycleEvents
  }

  /// F04 teardown-coherence oracle. Runs at the end of ``finalizeFrame`` —
  /// the single point where the committed root and the teardown barriers are
  /// all settled for the frame — on sampled probe frames. Checks both
  /// subtractive failure directions the frame pipeline previously never
  /// observed:
  ///
  /// 1. **Over-removal (stale alias):** any node the committed structure
  ///    walks whose ID the store maps to a DIFFERENT object. Removing a live
  ///    re-adopted node (the deleted churn sweep's demonstrated failure mode)
  ///    surfaces this way. Child entries whose ID left the store entirely are
  ///    expected — children arrays rewire lazily on the parent's next apply.
  /// 2. **Under-removal (leak):** every stored node must be anchored to the
  ///    committed root. An orphan strand that event-driven teardown missed
  ///    trips this — the invariant the F02 root fixes established when the
  ///    identity-space sweep was deleted.
  ///
  /// Anchoring is wider than children arrays: capture-hosted islands (scoped
  /// content payloads, portal attachments, lazy tab bodies, lazy viewport
  /// entries) are deliberately reachable from their host only through body
  /// resolution, so they anchor through `parent`/`evaluationHost` object
  /// links instead of a children slot. `liveNodeIDs` is deliberately not
  /// consulted — it records frame-visitation for the registration
  /// fingerprint, not liveness (deferred hosts are stored and referenced
  /// without ever entering a finalized frame's order).
  ///
  /// The residual known at introduction (2026-07-02) — button styling-wrapper
  /// interiors (`ButtonBody/…/base`, `/overlay`, `/background`) stranded
  /// inside dismissed presentation-portal overlay entries — is CLOSED: the
  /// interiors under a value-only styling child are anchored to their
  /// evaluated parent with hosted-detached edges
  /// (`recordValueOnlyChildInteriorAnchors`), and the hosted-root teardown
  /// spares a visited root only while an anchor outside the removal cascade
  /// survives. `FrameworkStressTests` pins the zero-count
  /// ("portal overlay button chrome leaves no teardown-coherence orphans").
  private func teardownCoherenceViolation()
    -> (isOverRemoval: Bool, detail: String, unreachableCount: Int)?
  {
    guard let root else {
      return nil
    }
    var reachable: Set<ViewNodeID> = []

    // Walk the live structure: children arrays plus hosted-detached ledger
    // edges, descending only nodes the store still holds. A child entry whose
    // ID is absent from the store is EXPECTED — children arrays are lazily
    // rewired on the parent's next apply, so a removed variant strand
    // (ButtonBody press chrome is the common case) lingers until then. What
    // must never happen is aliasing: the store holding a DIFFERENT object for
    // an ID the committed structure still walks — that is the deleted sweep's
    // "removed a live re-adopted node" failure mode.
    var staleAliasDetail: String?
    func absorb(_ subtreeRoot: ViewNode) {
      var stack: [ViewNode] = [subtreeRoot]
      while let node = stack.popLast() {
        let nodeID = node.viewNodeID
        // `insert` doubles as the cycle guard: `ViewNode.apply` deliberately
        // tolerates self-in-children chains.
        guard reachable.insert(nodeID).inserted else {
          continue
        }
        guard let stored = nodesByNodeID[nodeID] else {
          continue
        }
        if stored !== node, staleAliasDetail == nil {
          staleAliasDetail = """
            teardown coherence: committed structure holds a stale copy of \
            \(nodeID) at \(node.identity.path)
            """
        }
        stack.append(contentsOf: node.children)
        for hostedRootID in detachedHostedSubtreeRootsByHost[nodeID] ?? [] {
          if let hostedRoot = nodesByNodeID[hostedRootID] {
            stack.append(hostedRoot)
          }
        }
      }
    }

    absorb(root)
    if let staleAliasDetail {
      return (isOverRemoval: true, detail: staleAliasDetail, unreachableCount: 0)
    }

    // Fixed point: absorb any stored node whose parent/evaluation-host anchor
    // is already reachable (island seams), then its subtree, until nothing
    // new is absorbed.
    var absorbedAny = true
    while absorbedAny {
      absorbedAny = false
      for node in nodesByNodeID.values where !reachable.contains(node.viewNodeID) {
        let anchor = node.parent ?? node.evaluationHost
        guard let anchor, reachable.contains(anchor.viewNodeID) else {
          continue
        }
        absorb(node)
        absorbedAny = true
      }
    }

    let unreachableIDs = nodesByNodeID.keys.filter { !reachable.contains($0) }
    guard unreachableIDs.isEmpty else {
      let samples = unreachableIDs.prefix(4).map { nodeID in
        let path = nodesByNodeID[nodeID]?.identity.path ?? "?"
        let forensics = teardownCoherenceAnchorForensics(for: nodeID)
        return "\(nodeID) at \(path) [\(forensics)]"
      }
      return (
        isOverRemoval: false,
        detail: """
        teardown coherence: \(unreachableIDs.count) stored node(s) \
        unreachable from the committed root: \(samples.joined(separator: ", "))
        """,
        unreachableCount: unreachableIDs.count
      )
    }
    return nil
  }

  /// Anchor forensics for one census orphan: which lifetime anchor broke.
  /// Cheap to build and only reached on a violation, where the detail is the
  /// entire diagnostic surface.
  private func teardownCoherenceAnchorForensics(for nodeID: ViewNodeID) -> String {
    guard let node = nodesByNodeID[nodeID] else {
      return "gone"
    }
    var parts: [String] = []
    if let parent = node.parent {
      let stored = nodesByNodeID[parent.viewNodeID]
      parts.append(
        "parent=\(parent.viewNodeID)/\(stored == nil ? "unstored" : (stored === parent ? "stored" : "aliased"))"
      )
    } else {
      parts.append("parent=nil")
    }
    if let host = node.evaluationHost {
      let stored = nodesByNodeID[host.viewNodeID]
      parts.append(
        "evalHost=\(host.viewNodeID)/\(stored == nil ? "unstored" : (stored === host ? "stored" : "aliased"))"
      )
    } else {
      parts.append("evalHost=nil")
    }
    let hostingEdges = detachedHostedSubtreeRootsByHost.filter { $0.value.contains(nodeID) }
    if hostingEdges.isEmpty {
      parts.append("ledger=none")
    } else {
      let hosts = hostingEdges.keys.map { hostID in
        "\(hostID)/\(nodesByNodeID[hostID] == nil ? "unstored" : "stored")"
      }
      parts.append("ledger=\(hosts.joined(separator: "+"))")
    }
    parts.append("lifecycle=\(node.lifecycleState)")
    return parts.joined(separator: " ")
  }

  package func snapshot() -> ResolvedNode {
    guard let root else {
      fatalError("View graph has no root snapshot.")
    }
    return root.snapshot()
  }

  package func snapshot(
    rootIdentity: Identity
  ) -> ResolvedNode {
    guard let root = nodeIfExists(for: rootIdentity) else {
      fatalError("View graph has no node for root identity \(rootIdentity).")
    }
    self.root = root
    return root.snapshot()
  }

  package func dependencies(
    for identity: Identity
  ) -> DependencySet? {
    nodeIfExists(for: identity)?.dependencies
  }

  package func stateDependentIdentities(
    for key: StateSlotKey
  ) -> Set<Identity> {
    identities(for: stateSlotDependents[key] ?? [])
  }

  package func environmentDependentIdentities(
    for key: ObjectIdentifier
  ) -> Set<Identity> {
    identities(for: environmentDependents[key] ?? [])
  }

  package func observableDependentIdentities(
    for key: ObjectIdentifier
  ) -> Set<Identity> {
    identities(for: observableDependents[key] ?? [])
  }

  package func liveIdentitySnapshot() -> Set<Identity> {
    identities(for: liveNodeIDs)
  }

  package func liveNodeIDSnapshot() -> Set<ViewNodeID> {
    liveNodeIDs
  }

  package func restoreRuntimeRegistrations(
    for resolved: ResolvedNode,
    into registrations: RuntimeRegistrationSet
  ) {
    ViewGraphRuntimeRegistrationRestorer.restoreResolvedSubtree(
      resolved,
      into: registrations,
      nodesByNodeID: nodesByNodeID,
      nodeIDsByStructuralPath: nodeIDsByStructuralPath
    )
  }

  package func restoreCurrentFrameRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    ViewGraphRuntimeRegistrationRestorer.restoreLiveIdentities(
      liveNodeIDs,
      into: registrations,
      nodesByNodeID: nodesByNodeID
    )
  }

  package var runtimeRegistrationLiveNodeCount: Int {
    liveNodeIDs.count
  }

  package func runtimeRegistrationPublicationDeltaForCurrentFrame()
    -> (delta: RuntimeRegistrationPublicationDelta, current: RuntimeRegistrationGraphFingerprint)?
  {
    let current = currentRuntimeRegistrationFingerprint()
    guard let committedRuntimeRegistrationFingerprint else {
      return nil
    }
    return (committedRuntimeRegistrationFingerprint.publicationDelta(to: current), current)
  }

  /// Records the committed fingerprint. The `.all` commit branch already builds
  /// the current fingerprint to compute its publication delta; pass it back here
  /// to avoid rebuilding the full O(liveNodeIDs) fingerprint a second time on the
  /// same frame. The `.all` ops between delta and record mutate only the live
  /// registration set, never the fingerprint's node sources, so the precomputed
  /// value is byte-identical to a rebuild. Other branches pass `nil` and rebuild.
  package func recordCommittedRuntimeRegistrationFingerprint(
    _ precomputed: RuntimeRegistrationGraphFingerprint? = nil
  ) {
    committedRuntimeRegistrationFingerprint = precomputed ?? currentRuntimeRegistrationFingerprint()
  }

  /// The `.unchanged`-publication commit record: nothing was re-evaluated
  /// this frame, so no node's registrations mutated and no node entered or
  /// left the live set — the previously committed fingerprint is still
  /// byte-accurate. Keeping it skips the full O(liveNodeIDs) rebuild that
  /// `.unchanged` commits used to pay every frame (F63). The DEBUG recompute
  /// pins that premise; the first frame (no committed fingerprint yet) still
  /// rebuilds.
  package func recordCommittedRuntimeRegistrationFingerprintForUnchangedFrame() {
    guard committedRuntimeRegistrationFingerprint != nil else {
      recordCommittedRuntimeRegistrationFingerprint()
      return
    }
    #if DEBUG
      assert(
        committedRuntimeRegistrationFingerprint == currentRuntimeRegistrationFingerprint(),
        """
        an .unchanged-publication frame changed the runtime-registration \
        fingerprint — a registration mutated or a node entered/left the live \
        set without recording a publication
        """
      )
    #endif
  }

  package func runtimeRegistrationDeltaRequiresFullPublication(
    _ delta: RuntimeRegistrationPublicationDelta
  ) -> Bool {
    runtimeRegistrationRootsRequireFullPublication(delta.removalRoots)
  }

  /// A publication rooted at the graph root (the portal host — an
  /// invalidation frame whose frontier collapses to the root publishes
  /// `.subtrees([portalRoot])`) covers every live node STRUCTURALLY, but the
  /// scoped reset/restore machinery matches IDENTITY prefixes — and
  /// capture-hosted island identities (a lazy tab payload's interiors) live
  /// in the authored identity space, which does not descend from the
  /// portal-host identity. A root-rooted scoped publication therefore both
  /// dropped island registrations an earlier narrow frame's reset had removed
  /// (dead controls: live=0/rebuilt=1) and failed to clear stale
  /// identity-space entries (live=1/rebuilt=0). Such roots must not take the
  /// identity-prefix scoped restore: `.subtrees` commits route them onto the
  /// fingerprint-delta body (whose roots are per-entry identities and thus
  /// island-safe), and a *delta* containing such roots takes the full
  /// reset-and-rebuild publication.
  package func runtimeRegistrationRootsRequireFullPublication(
    _ roots: [Identity]
  ) -> Bool {
    guard let root else {
      return true
    }
    return roots.contains { changedRoot in
      changedRoot == root.identity || changedRoot == root.resolvedIdentity
    }
  }

  private func currentRuntimeRegistrationFingerprint()
    -> RuntimeRegistrationGraphFingerprint
  {
    RuntimeRegistrationGraphFingerprint(
      entriesByNodeID: Dictionary(
        uniqueKeysWithValues: liveNodeIDs.compactMap { viewNodeID in
          guard
            let entry = nodesByNodeID[viewNodeID]?
              .runtimeRegistrationFingerprintEntry()
          else {
            return nil
          }
          return (viewNodeID, entry)
        }
      )
    )
  }

  /// Scoped counterpart to ``restoreCurrentFrameRuntimeRegistrations``: restores
  /// runtime registrations for ONLY the live subtrees rooted at `roots`. Used on
  /// `.subtrees` (and scoped `.all`) publication frames, where the preceding
  /// `removeSubtrees(rootedAt:)` cleared exactly these subtrees and untouched
  /// subtrees' registrations remain valid in place — so re-publishing the whole
  /// tree (the former behavior) is redundant O(tree) work.
  ///
  /// The restore is a **union** of two coverages:
  ///
  /// 1. Each root's live ViewNode subtree (the original behavior). This reaches
  ///    nodes through the live tree — including registrations whose effective
  ///    scope identity was re-rooted away from `roots` (e.g. `.keyCommand`
  ///    scopes) — and keeps the scoped restore byte-identical to a full rebuild
  ///    when no seam is present.
  /// 2. Plus live nodes selected by **identity prefix** that the ViewNode walk
  ///    cannot reach across capture-host island seams (lazy tab bodies,
  ///    presentation-portal attachments, `.id`-re-rooted subtrees, lazy viewport
  ///    entries). `removeSubtrees(rootedAt:)` clears those by identity prefix,
  ///    so without this a seam-hosted node's registrations — e.g. a lazy tab's
  ///    button action handler — were removed but never restored, leaving the
  ///    control dead until the next full publication.
  package func restoreRuntimeRegistrationSubtrees(
    rootedAt roots: [Identity],
    into registrations: RuntimeRegistrationSet
  ) {
    guard !roots.isEmpty else {
      return
    }
    var nodeIDs: Set<ViewNodeID> = []
    for root in roots {
      guard let node = nodeIfExists(for: root) else {
        continue
      }
      collectRuntimeRegistrationSubtreeNodeIDs(node, into: &nodeIDs)
    }
    for nodeID in liveNodeIDs where !nodeIDs.contains(nodeID) {
      guard let node = nodesByNodeID[nodeID] else {
        continue
      }
      // Match the node's resolved identity as well as its structural identity:
      // stacked modifier levels at one `.id`-replaced identity keep their
      // registrations on sibling evaluation nodes whose STRUCTURAL identities
      // sit outside the frontier root even when the root covers the resolved
      // identity they registered under. The scoped reset removed those
      // registrations by identity prefix, so missing such a sibling here would
      // drop its stacked handler until the next full publication.
      let identity = node.identity
      let resolvedIdentity = node.resolvedIdentity
      if roots.contains(where: { root in
        identity == root || identity.isDescendant(of: root)
          || resolvedIdentity == root || resolvedIdentity.isDescendant(of: root)
      }) {
        nodeIDs.insert(nodeID)
      }
    }
    ViewGraphRuntimeRegistrationRestorer.restoreLiveIdentities(
      nodeIDs,
      into: registrations,
      nodesByNodeID: nodesByNodeID
    )
  }

  private func collectRuntimeRegistrationSubtreeNodeIDs(
    _ node: ViewNode,
    into nodeIDs: inout Set<ViewNodeID>
  ) {
    guard nodeIDs.insert(node.viewNodeID).inserted else {
      return
    }
    for child in node.children {
      collectRuntimeRegistrationSubtreeNodeIDs(child, into: &nodeIDs)
    }
  }

  package func runtimeRegistrationSubtreeNodeCount(
    rootedAt roots: [Identity]
  ) -> Int {
    var traversedNodes: Set<ObjectIdentifier> = []
    var count = 0
    for root in roots {
      guard let node = nodeIfExists(for: root) else {
        continue
      }
      count += runtimeRegistrationSubtreeNodeCount(
        node,
        traversedNodes: &traversedNodes
      )
    }
    return count
  }

  /// Returns whether the ViewNode cover rooted at `roots` reaches at least
  /// `threshold` nodes. Stops walking as soon as the threshold is met, so a
  /// narrow cover costs O(cover) and a wide cover costs O(threshold).
  package func runtimeRegistrationSubtreeCoverReaches(
    _ threshold: Int,
    rootedAt roots: [Identity]
  ) -> Bool {
    guard threshold > 0 else {
      return true
    }
    var traversedNodes: Set<ObjectIdentifier> = []
    var remaining = threshold
    for root in roots {
      guard let node = nodeIfExists(for: root) else {
        continue
      }
      if runtimeRegistrationSubtreeCoverConsumes(
        node,
        remaining: &remaining,
        traversedNodes: &traversedNodes
      ) {
        return true
      }
    }
    return false
  }

  private func runtimeRegistrationSubtreeCoverConsumes(
    _ node: ViewNode,
    remaining: inout Int,
    traversedNodes: inout Set<ObjectIdentifier>
  ) -> Bool {
    guard traversedNodes.insert(ObjectIdentifier(node)).inserted else {
      return false
    }
    remaining -= 1
    if remaining <= 0 {
      return true
    }
    for child in node.children {
      if runtimeRegistrationSubtreeCoverConsumes(
        child,
        remaining: &remaining,
        traversedNodes: &traversedNodes
      ) {
        return true
      }
    }
    return false
  }

  /// Republishes low-volume effect registries from EVERY live node, regardless
  /// of the frame's runtime-registration publication scope. Scoped
  /// (`.subtrees`) publication restores registrations by walking each frontier
  /// root's ViewNode subtree, which cannot cross capture-host island seams
  /// (scoped content payloads, presentation-portal attachments, `.id`-re-rooted
  /// subtrees, lazy viewport entries) or intentionally reused stable subtrees.
  /// Lifecycle, task, and preference-observation effects for such nodes would
  /// otherwise reach the runtime without matching live registrations.
  package func republishAllEffectRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    registrations.lifecycleRegistry?.reset()
    registrations.taskRegistry?.reset()
    registrations.preferenceObservationRegistry?.reset()
    for nodeID in liveNodeIDs {
      nodesByNodeID[nodeID]?.restoreOwnEffectRegistrations(into: registrations)
    }
  }

  private func runtimeRegistrationSubtreeNodeCount(
    _ node: ViewNode,
    traversedNodes: inout Set<ObjectIdentifier>
  ) -> Int {
    guard traversedNodes.insert(ObjectIdentifier(node)).inserted else {
      return 0
    }
    var count = 1
    for child in node.children {
      count += runtimeRegistrationSubtreeNodeCount(child, traversedNodes: &traversedNodes)
    }
    return count
  }

  private func pruneLifecycleEvaluationOwners(
    ownedBy ownerIdentity: Identity
  ) {
    guard let ownerNodeID = viewNodeID(for: ownerIdentity) else {
      return
    }
    guard
      let recordedTargets = lifecycleEvaluationTargetsRecordedByOwner.removeValue(
        forKey: ownerNodeID
      )
    else {
      return
    }
    guard let targets = lifecycleEvaluationTargetsByOwner[ownerNodeID] else {
      return
    }
    let staleTargets = targets.subtracting(recordedTargets)
    for target in staleTargets {
      lifecycleEvaluationOwnersByNodeID.removeValue(forKey: target)
    }
    if recordedTargets.isEmpty {
      lifecycleEvaluationTargetsByOwner.removeValue(forKey: ownerNodeID)
    } else {
      lifecycleEvaluationTargetsByOwner[ownerNodeID] = recordedTargets
    }
  }

  private func nodeEmitsOwnLifecycleEvents(
    _ node: ViewNode
  ) -> Bool {
    let ownerNodeID = lifecycleEvaluationOwnersByNodeID[node.viewNodeID]
    return ViewGraphLifecycleEventCollector.nodeEmitsOwnLifecycleEvents(
      node,
      ownerNodeID: ownerNodeID,
      ownerExists: ownerNodeID.map { nodesByNodeID[$0] != nil } ?? false
    )
  }

  func appendTaskCancelEvent(
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool
  ) {
    ViewGraphLifecycleEventCollector.appendTaskCancelEvent(
      viewNodeID: viewNodeID(for: identity),
      identity: identity,
      task: task,
      isStructural: isStructural,
      stableTaskCancelEvents: &stableTaskCancelEvents,
      structuralTaskCancelEvents: &structuralTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents
    )
  }

  private func appendTaskStartEvent(
    identity: Identity,
    task: TaskDescriptor
  ) {
    ViewGraphLifecycleEventCollector.appendTaskStartEvent(
      viewNodeID: viewNodeID(for: identity),
      identity: identity,
      task: task,
      stableTaskCancelEvents: stableTaskCancelEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      stableTaskStartEvents: &stableTaskStartEvents
    )
  }

  // PERF (deferred, profiling-gated — resolve_ms win ii): this is O(invalidated
  // × depth) per reuse candidate. It could drop to O(depth) per candidate by
  // precomputing, once per frame, the invalidated-node id set plus the union of
  // their ancestors (so the self/ancestor/descendant test becomes set lookups +
  // one ancestor walk). That needs a frame-scoped cache — new mutable state on
  // the checkpoint-totality contract and a stale-cache hazard on a reuse-correct-
  // ness path — for a win that only materializes under *wide* invalidation (the
  // measured resolve-heavy scenario, `synthetic-narrow-invalidation`, keeps this
  // set small). Per the remediation plan's methodology, size it with the
  // `TermUIPerf compare --gate` budget before adding that complexity, rather than
  // optimizing by eye.
  private func structuralInvalidationIntersects(
    _ node: ViewNode,
    invalidatedIdentities: Set<Identity>
  ) -> Bool {
    for invalidatedIdentity in invalidatedIdentities {
      guard let invalidatedNode = nodeIfExists(for: invalidatedIdentity) else {
        continue
      }
      if invalidatedNode === node
        || invalidatedNode.isDescendant(of: node)
        || node.isDescendant(of: invalidatedNode)
      {
        return true
      }
    }
    return false
  }

  private func unmappedInvalidatedIdentities(
    _ invalidatedIdentities: Set<Identity>
  ) -> [Identity] {
    invalidatedIdentities
      .filter { viewNodeID(for: $0) == nil }
      .sorted()
  }

  /// Resolves an invalidated identity that no longer maps to a live node onto
  /// its nearest live ancestor. A departed identity names torn-down content
  /// (a focused control the previous frame removed, a churned subtree); the
  /// closest ancestor that still exists owns the region the departure
  /// changed, and the identity-axis reuse-conflict scan already denies
  /// retained reuse along that live ancestor chain, so evaluating the
  /// ancestor is the narrow equivalent of the full-root escalation this
  /// replaces. Returns nil for an identity space with no live ancestor at
  /// all (an `.id`-rebased subtree that departed wholesale) — there is no
  /// node an evaluation could target, and the caller drops the identity.
  private func nearestLiveAncestorNodeID(for identity: Identity) -> ViewNodeID? {
    var candidate = identity.parent
    while let current = candidate {
      if let viewNodeID = viewNodeID(for: current) {
        return viewNodeID
      }
      candidate = current.parent
    }
    return nil
  }

  /// Whether the identity still resolves to evaluation work: it maps to a
  /// live node, or the queue boundary can remap it onto a nearest live
  /// ancestor. Used by the rerender pass's target filter so a departed
  /// identity with a live ancestor is carried (and remapped at queue time)
  /// instead of dropped.
  package func hasLiveInvalidationTarget(for identity: Identity) -> Bool {
    viewNodeID(for: identity) != nil || nearestLiveAncestorNodeID(for: identity) != nil
  }

  /// Whether a runtime-focus side-field reader on the root path TO
  /// `identity` (self-inclusive) is AFFECTED by a focus/press move onto or
  /// off `identity`. The run loop's focus/press scope legs and the tracker's
  /// move-notification filter use this: framework controls compare the
  /// side-fields against identities at or below themselves, so a focus move
  /// onto `identity` can only change the output of readers on its root path
  /// — an identity whose path carries no affected reader needs no recompute
  /// cone at all (a chrome-only member).
  ///
  /// Two reader classes, distinguished by sentinel key:
  /// - `broadKey` readers recorded a plain side-field read; any move on
  ///   their path affects them.
  /// - `targetScopedKey` readers declared the exact identities they compare
  ///   against (`DependencySet.focusComparisonTargets`); they are affected
  ///   only when the moved identity is among their targets — a sheet's
  ///   `ScrollView` compares exclusively against itself and its synthetic
  ///   indicator identities, so a move onto an unrelated content descendant
  ///   leaves its output byte-identical and must not block that
  ///   descendant's demotion.
  ///
  /// Containment-bake and wrapper readers are outside this reasoning by
  /// construction: they record the wholesale-union `FocusedIdentityKey`
  /// dependency instead.
  package func hasRuntimeFocusReaderOnPath(
    affecting identity: Identity,
    broadKey: ObjectIdentifier,
    targetScopedKey: ObjectIdentifier
  ) -> Bool {
    let broadDependents = environmentDependents[broadKey] ?? []
    let targetScopedDependents = environmentDependents[targetScopedKey] ?? []
    guard !broadDependents.isEmpty || !targetScopedDependents.isEmpty else {
      return false
    }
    var current: Identity? = identity
    while let prefix = current {
      if let viewNodeID = viewNodeID(for: prefix) {
        if broadDependents.contains(viewNodeID) {
          if ReuseDenialTrace.isEnabled {
            ReuseDenialTrace.recordSuppressionScopeDescription(
              "focus-reader-path(reader=\(prefix.path))"
            )
          }
          return true
        }
        if targetScopedDependents.contains(viewNodeID),
          let node = nodeIfExists(for: prefix),
          node.dependencies.focusComparisonTargets.contains(identity)
        {
          if ReuseDenialTrace.isEnabled {
            ReuseDenialTrace.recordSuppressionScopeDescription(
              "focus-reader-path(target-reader=\(prefix.path))"
            )
          }
          return true
        }
      }
      current = prefix.parent
    }
    return false
  }

  /// Whether every identity reaches live graph work at or below itself —
  /// WITHOUT the nearest-live-ancestor remap `nodeIDsForInvalidation`
  /// applies. A certified state-write invalidation
  /// (`ViewNode.setStateSlot(ordinal:value:certifiedInvalidationIdentities:)`)
  /// relies on reuse-conflict denial reaching the certified subtrees; an
  /// identity with no node at or below it would deny nothing while its queue
  /// remap re-broadened onto the ancestor, so the caller must fall back to
  /// reader attribution instead.
  package func allIdentitiesReachLiveSubtrees(
    _ identities: Set<Identity>
  ) -> Bool {
    let unmatched = identities.filter { viewNodeID(for: $0) == nil }
    guard !unmatched.isEmpty else {
      return true
    }
    var remaining = unmatched
    for identity in nodeIDByIdentity.keys {
      remaining = remaining.filter { !identity.isDescendant(of: $0) }
      if remaining.isEmpty {
        return true
      }
    }
    return false
  }

  private func dirtyPlanBaseDiagnostics(
    invalidatedIdentities: Set<Identity>,
    unmappedIdentities: [Identity]
  ) -> (_ result: String, _ frontierRootCount: Int) -> DirtyEvaluationPlanDiagnostics {
    let remappedCount = unmappedIdentities.filter {
      nearestLiveAncestorNodeID(for: $0) != nil
    }.count
    return { result, frontierRootCount in
      DirtyEvaluationPlanDiagnostics(
        result: result,
        frontierRootCount: frontierRootCount,
        invalidatedIdentityCount: invalidatedIdentities.count,
        unmappedInvalidatedIdentityCount: unmappedIdentities.count,
        unmappedInvalidatedIdentitySample: Array(unmappedIdentities.prefix(5)),
        remappedInvalidatedIdentityCount: remappedCount,
        droppedInvalidatedIdentityCount: unmappedIdentities.count - remappedCount
      )
    }
  }

  private func applyStructuralChildDiff(
    for node: ViewNode,
    resolved: ResolvedNode
  ) {
    let previousSnapshot = node.snapshot()
    let retainedChildNodeIDs = Set(resolved.children.compactMap(\.viewNodeID))
    let plan = ViewGraphStructuralReconciler.removalPlan(
      oldChildDescriptors: previousSnapshot.children.map(ChildDescriptor.init),
      currentChildCount: node.children.count,
      committedChildren: previousSnapshot.children,
      newChildren: resolved.children
    )

    for removal in plan.removedChildren {
      guard node.children.indices.contains(removal.oldIndex)
      else {
        continue
      }
      let removedNode = node.children[removal.oldIndex]
      guard !retainedChildNodeIDs.contains(removedNode.viewNodeID) else {
        continue
      }
      if shouldDeferEntityRoutedRemoval(of: removedNode) {
        pendingEntityRoutedRemovalNodeIDs.insert(removedNode.viewNodeID)
        continue
      }

      // The removed child itself is authoritatively departed (positionally
      // diffed out and not retained), but its committed snapshot may descend —
      // via identity and node lookups — into nodes the arriving tree already
      // re-adopted this frame (a stable-`.id` control re-rooted out of a
      // churned `AnyView` payload resolves to the SAME identities as the
      // departing generation's committed children). Spare visited nodes in the
      // descent so tearing down the departed child cannot dismantle the live
      // replacement's subtree and drop its runtime registrations.
      removeSubtree(
        rootedAt: removedNode,
        committedSnapshot: removal.committedSnapshot,
        sparingVisitedNodes: true
      )
    }
  }

  private func reindexDependencies(
    for node: ViewNode,
    previous: DependencySet
  ) {
    ViewGraphDependencyIndex.reindex(
      viewNodeID: node.viewNodeID,
      previous: previous,
      current: node.dependencies,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
  }

  func removeDependencyEdges(
    for node: ViewNode
  ) {
    ViewGraphDependencyIndex.remove(
      viewNodeID: node.viewNodeID,
      dependencies: node.dependencies,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
  }

  private func frameLifecycleEventPlan(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?
  ) -> ViewGraphFrameLifecycleEventPlan {
    ViewGraphLifecycleEventCollector.frameLifecycleEventPlan(
      resolved: resolved,
      placed: placed,
      nodesByNodeID: nodesByNodeID,
      nodeIDByIdentity: nodeIDByIdentity,
      frameOrder: frameOrder,
      viewportLifecycleNodesByKey: viewportLifecycleNodesByKey,
      viewportLifecycleOrder: viewportLifecycleOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents
    )
  }
}

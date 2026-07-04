extension ViewGraph {
  package func makeCheckpoint() -> Checkpoint {
    GraphCheckpointStore.makeCheckpoint(
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
      nodesByNodeID: nodesByNodeID
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    restoreCheckpointGraphFields(checkpoint)

    ViewGraphNodeCheckpointing.restoreNodeCheckpoints(
      checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
  }

  package func restoreCheckpoint(
    _ checkpoint: Checkpoint,
    nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  ) {
    restoreCheckpointGraphFields(checkpoint)

    ViewGraphNodeCheckpointing.restoreNodeCheckpoints(
      nodeCheckpoints,
      nodesByNodeID: checkpoint.index.nodesByNodeID
    )
  }

  package func checkpointMutationStateSnapshot() -> CheckpointMutationState {
    GraphCheckpointStore.checkpointMutationStateSnapshot(
      epoch: checkpointMutationEpoch,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func checkpointMutationStateMatches(_ checkpoint: Checkpoint) -> Bool {
    checkpointMutationStateMatches(CheckpointMutationState(checkpoint: checkpoint))
  }

  package func checkpointMutationStateMatches(_ state: CheckpointMutationState) -> Bool {
    GraphCheckpointStore.checkpointMutationStateMatches(
      epoch: checkpointMutationEpoch,
      nodesByNodeID: nodesByNodeID,
      against: state
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
  private var index: GraphIndex
  private var rootEvaluation: RootEvaluation
  private var viewportLifecycle: ViewportLifecycleState
  private var eventBuffers: LifecycleEventBuffers
  private var dirtyState: DirtyState
  private var lifecycleEvaluation: LifecycleEvaluationOwnership
  private var taskDescriptors: TaskDescriptorState
  private var dependencyIndex: DependencyIndex
  private var frameCommit: FrameCommitState

  private var nodesByNodeID: [ViewNodeID: ViewNode] {
    get { index.nodesByNodeID }
    set { index.nodesByNodeID = newValue }
  }
  private var nodeIDByIdentity: [Identity: ViewNodeID] {
    get { index.nodeIDByIdentity }
    set { index.nodeIDByIdentity = newValue }
  }
  private var identityByNodeID: [ViewNodeID: Identity] {
    get { index.identityByNodeID }
    set { index.identityByNodeID = newValue }
  }
  private var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>] {
    get { index.nodeIDsByStructuralPath }
    set { index.nodeIDsByStructuralPath = newValue }
  }
  private var entityRoutingTable: EntityRoutingTable {
    get { index.entityRoutingTable }
    set { index.entityRoutingTable = newValue }
  }
  private var nextViewNodeIDRawValue: UInt64 {
    get { index.nextViewNodeIDRawValue }
    set { index.nextViewNodeIDRawValue = newValue }
  }
  private var detachedHostedSubtreeRootsByHost: [ViewNodeID: Set<ViewNodeID>] {
    get { index.detachedHostedSubtreeRootsByHost }
    set { index.detachedHostedSubtreeRootsByHost = newValue }
  }
  private var detachedHostedSubtreeHostByRoot: [ViewNodeID: ViewNodeID] {
    get { index.detachedHostedSubtreeHostByRoot }
    set { index.detachedHostedSubtreeHostByRoot = newValue }
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
  private var structuralDisappearEvents: [LifecycleEvent] {
    get { eventBuffers.structuralDisappearEvents }
    set { eventBuffers.structuralDisappearEvents = newValue }
  }
  private var pendingEntityRoutedRemovalNodeIDs: Set<ViewNodeID> {
    get { eventBuffers.pendingEntityRoutedRemovalNodeIDs }
    set { eventBuffers.pendingEntityRoutedRemovalNodeIDs = newValue }
  }
  private var absorbedShadowedNodeIDs: Set<ViewNodeID> {
    get { eventBuffers.absorbedShadowedNodeIDs }
    set { eventBuffers.absorbedShadowedNodeIDs = newValue }
  }
  private var latestLifecycleEvents: [LifecycleEvent] {
    get { eventBuffers.latestLifecycleEvents }
    set { eventBuffers.latestLifecycleEvents = newValue }
  }
  private var invalidatedNodeIDs: Set<ViewNodeID> {
    get { dirtyState.invalidatedNodeIDs }
    set { dirtyState.invalidatedNodeIDs = newValue }
  }
  private var graphLocalDirtyNodeIDs: Set<ViewNodeID> {
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
  private var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID] {
    get { lifecycleEvaluation.lifecycleEvaluationOwnersByNodeID }
    set { lifecycleEvaluation.lifecycleEvaluationOwnersByNodeID = newValue }
  }
  private var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>] {
    get { lifecycleEvaluation.lifecycleEvaluationTargetsByOwner }
    set { lifecycleEvaluation.lifecycleEvaluationTargetsByOwner = newValue }
  }
  private var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>] {
    get { lifecycleEvaluation.lifecycleEvaluationTargetsRecordedByOwner }
    set { lifecycleEvaluation.lifecycleEvaluationTargetsRecordedByOwner = newValue }
  }
  private var taskDescriptorNodeSlots: [TaskDescriptorSlotKey: TaskDescriptorIdentitySlot] {
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

  private var currentFrameID: UInt64 {
    get { frameCommit.currentFrameID }
    set { frameCommit.currentFrameID = newValue }
  }
  private var liveNodeIDs: Set<ViewNodeID> {
    get { frameCommit.liveNodeIDs }
    set { frameCommit.liveNodeIDs = newValue }
  }
  private var resolvedNodeReuseCache: [ResolvedNodeReuseCacheKey: ResolvedNodeReuseCacheEntry] {
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
  private var checkpointMutationEpoch: UInt64 {
    get { frameCommit.checkpointMutationEpoch }
    set { frameCommit.checkpointMutationEpoch = newValue }
  }

  private func recordCheckpointGraphMutation() {
    checkpointMutationEpoch &+= 1
  }

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
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
    changeObservationValues = changeObservationValues.filter { key, _ in
      nodeIDByIdentity[key.identity] != nil
    }
  }

  private func nodeIfExists(
    for identity: Identity
  ) -> ViewNode? {
    GraphNodeIndexQuery.node(for: identity, in: index)
  }

  private func nodeIfExists(
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

  private func nodeIDsForResolvedNode(
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
    recordCheckpointGraphMutation()
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
      checkpointMutationEpoch: checkpointMutationEpoch
    )
  }

  package func cachedReusableResolvedNode(
    namespace: String,
    owner: Identity,
    signature: String,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> ResolvedNode? {
    let key = ResolvedNodeReuseCacheKey(namespace: namespace, owner: owner)
    guard var entry = resolvedNodeReuseCache[key],
      entry.signature == signature
    else {
      return nil
    }

    let cachedNode =
      entry.node.viewNodeID.flatMap { nodeIfExists(for: $0) }
      ?? nodeIfExists(for: entry.node.identity)
    guard let node = cachedNode else {
      resolvedNodeReuseCache.removeValue(forKey: key)
      return nil
    }

    guard entry.node.environmentSnapshot == environment,
      entry.node.transactionSnapshot.isReuseEquivalent(to: transaction)
    else {
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

  package func containsNode(
    for identity: Identity
  ) -> Bool {
    nodeIfExists(for: identity) != nil
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
    recordCheckpointGraphMutation()
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
  package func invalidateAndQueueDirtyDescendants(of identities: Set<Identity>) {
    let viewNodeIDs = Set(
      identityByNodeID.compactMap { viewNodeID, identity in
        identities.contains { target in
          identity == target || identity.isDescendant(of: target)
        } ? viewNodeID : nil
      }
    )
    guard !viewNodeIDs.isEmpty else {
      return
    }
    recordCheckpointGraphMutation()
    ViewGraphInvalidationPlanner.invalidateAndQueueDirty(
      viewNodeIDs,
      invalidatedNodeIDs: &invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func queueDirty(
    _ identities: Set<Identity>
  ) {
    recordCheckpointGraphMutation()
    ViewGraphInvalidationPlanner.queueDirty(
      nodeIDsForInvalidation(identities),
      graphLocalDirtyNodeIDs: &graphLocalDirtyNodeIDs,
      nodesByNodeID: nodesByNodeID
    )
  }

  package func queueDirtyForStateChange(
    _ key: StateSlotKey
  ) {
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
    for (key, slot) in overlay.stateSlots {
      let node = nodeIfExists(for: key.key.owner)
      guard let node else {
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
    recordCheckpointGraphMutation()
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

    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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

    recordCheckpointGraphMutation()
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
      recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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
      recordCheckpointGraphMutation()
      node.resetStateSlots()
    }
    recordCheckpointGraphMutation()
    entityRoutingTable.bind(entityIdentity, to: node.viewNodeID)
  }

  @discardableResult
  package func finishEvaluation(
    _ node: ViewNode,
    resolved: ResolvedNode,
    accessedStateSlots: Int
  ) -> ResolvedNode? {
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
    if let previousHost = detachedHostedSubtreeHostByRoot[rootNodeID] {
      detachedHostedSubtreeRootsByHost[previousHost]?.remove(rootNodeID)
      if detachedHostedSubtreeRootsByHost[previousHost]?.isEmpty == true {
        detachedHostedSubtreeRootsByHost.removeValue(forKey: previousHost)
      }
    }
    detachedHostedSubtreeRootsByHost[hostID, default: []].insert(rootNodeID)
    detachedHostedSubtreeHostByRoot[rootNodeID] = hostID
  }

  package func installLayoutRealizedChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
    guard let node = nodeIfExists(for: identity) else {
      return
    }

    recordCheckpointGraphMutation()
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

    recordCheckpointGraphMutation()
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
      recordCheckpointGraphMutation()
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

  /// Reclaims nodes stranded by a transparent chain collapse this frame. A
  /// composite resolving through an identity-extending but node-less layer (a
  /// conditional branch) mints its own node during a cold resolve;
  /// `normalizeResolvedElements(count == 1)` then returns its output directly
  /// and the enclosing chain level's apply absorbs it — the inner node is
  /// never wired as a graph child, its identity index entry is overwritten by
  /// the absorber's reindex (`reindexIdentity` records that shadowing here),
  /// and no structural diff, entity release, or committed-snapshot descent can
  /// reach it again. Warm resolves land on the absorber via the identity
  /// index, so the stranded mint is exclusively a cold-resolve artifact.
  ///
  /// The reclaim is deferred to the finalize barrier because a shadowing alone
  /// does not prove abandonment mid-resolve: a duplicate-occurrence sibling
  /// (G13) legitimately overwrites the shared identity entry while the earlier
  /// occurrence is still awaiting its parent's apply. By the barrier, every
  /// live node reached by the frame's walk is parented (`ViewNode.apply` wires
  /// parent links) or is an entity's routed home — a shadowed, same-frame,
  /// parentless, non-routed node is unreachable by construction.
  private func pruneAbsorbedShadowedNodes() {
    guard !absorbedShadowedNodeIDs.isEmpty else {
      return
    }
    recordCheckpointGraphMutation()
    let candidates = absorbedShadowedNodeIDs
    absorbedShadowedNodeIDs.removeAll(keepingCapacity: true)
    for nodeID in candidates.sorted() {
      // Two stranded shapes qualify:
      // - a same-frame mint (`!wasPresentAtFrameStart`) — the cold-resolve
      //   chain-collapse artifact, reclaimable even though its mint visited it;
      // - a WARM strand (`!visitedThisFrame`) — the same absorbed interior
      //   discovered late: the absorber re-shadows its identity entry on every
      //   apply, so lookups land on the absorber and the interior is never
      //   visited again. Parentless, un-routed, and index-shadowed, nothing
      //   can reach it; without this arm it leaks until (at best) an identity
      //   prefix sweep. A visited warm node stays: something resolved it this
      //   frame, so it is live (a re-rooted control, a hosted detached root).
      guard let node = nodeIfExists(for: nodeID),
        node.viewNodeID != root?.viewNodeID,
        !node.wasPresentAtFrameStart || !node.visitedThisFrame(currentFrameID),
        node.parent == nil
      else {
        continue
      }
      // An entity's live home is never reclaimed here: adoption and the
      // outermost-claim rule move entity homes through `nodeForIdentity`, and
      // a routed node reached by shadowing (a re-rooted stable-`.id` control
      // is parent-detached by design) is still the entity's binding — its
      // lifetime belongs to the entity lifecycle (release/pending-removal).
      // Unless the home is stale: routing alone cannot prove liveness when
      // claims are suppressed inside a hosting boundary (`entityHosting`) —
      // the shadow that put this node in the candidate set means the arriving
      // tree re-resolved its identity onto a different node. A live home owns
      // its resolved-identity index entry (its apply reindexed it); duplicate
      // occurrences (> 0) share entries by design and stay route-governed.
      if let entityIdentity = entityRoutingTable.entityByNodeID[nodeID],
        entityRoutingTable.route(entityIdentity) == nodeID,
        entityIdentity.occurrence > 0
          || nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
      {
        continue
      }
      // The interior recorded runtime registrations while evaluating the chain
      // whose committed value the absorber now carries (the stamp fixed
      // point). Re-home that bookkeeping to the identity's current owner
      // before reclaiming the node — publication rebuilds walk live nodes
      // only, so registrations left on the reclaimed interior are silently
      // dropped and its committed tasks never start ("no task registration at
      // commit", the F43 start-skip).
      if node.registeredHandlers.hasRuntimeRegistrations,
        let absorberID = nodeIDByIdentity[node.identity],
        absorberID != node.viewNodeID,
        let absorber = nodesByNodeID[absorberID]
      {
        absorber.adoptRuntimeRegistrations(from: node)
        // The interior's task-descriptor identity slots move with the
        // registrations: the absorber evaluates this chain on the next warm
        // resolve, and a slot left keyed to the reclaimed node would miss,
        // mint a fresh identity token, and plan a spurious cancel + restart
        // of a task whose `.task(id:)` value never changed.
        for (key, slot) in taskDescriptorNodeSlots where key.node == node.viewNodeID {
          let adoptedKey = TaskDescriptorSlotKey(node: absorberID, ordinal: key.ordinal)
          if taskDescriptorNodeSlots[adoptedKey] == nil {
            taskDescriptorNodeSlots[adoptedKey] = slot
          }
        }
      }
      removeSubtree(rootedAt: node, sparingVisitedNodes: true)
    }
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
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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

  @discardableResult
  package func applySnapshot(
    _ resolved: ResolvedNode,
    placed: PlacedNode? = nil,
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
    recordCheckpointGraphMutation()
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
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
    return finalizeFrame(
      rootIdentity: resolved.identity,
      resolved: resolved,
      placed: placed
    )
  }

  package func previewLifecycleEvents(
    resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
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
    ).events
  }

  package func finalizeFrame(
    rootIdentity: Identity,
    resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
    recordCheckpointGraphMutation()
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

    let lifecyclePlan = frameLifecycleEventPlan(
      resolved: resolved,
      placed: placed
    )
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
      SoundnessProbeConfiguration.recordTeardownCoherenceViolation(violation.detail)
      #if DEBUG
        // The stale-alias direction measured zero across the stress suite
        // when introduced, so any hit is a regression of the deleted sweep's
        // failure mode. The leak direction stays counter-only until its
        // documented residual class (see ``teardownCoherenceViolation()``)
        // is burned down.
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
  private func teardownCoherenceViolation() -> (isOverRemoval: Bool, detail: String)? {
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
      return (isOverRemoval: true, detail: staleAliasDetail)
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
        """
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
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
    committedRuntimeRegistrationFingerprint = precomputed ?? currentRuntimeRegistrationFingerprint()
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
    recordCheckpointGraphMutation()
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

  private func appendTaskCancelEvent(
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool
  ) {
    recordCheckpointGraphMutation()
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
    recordCheckpointGraphMutation()
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

  private func nodeForIdentity(
    for identity: Identity,
    entityIdentity: EntityIdentity? = nil
  ) -> ViewNode {
    var displacedOccupant = false
    if let entityIdentity,
      let routedNodeID = entityRoutingTable.route(entityIdentity)
    {
      if let routedNode = nodeIfExists(for: routedNodeID) {
        recordCheckpointGraphMutation()
        // Re-routing moves the node to a new `Identity`. Clear the old
        // identity's index entry so nothing else resolving at the old
        // (possibly aliased) identity this frame adopts the moved node — that
        // would wire it as a child inside its own subtree (a children-graph
        // cycle). The node's own resolved identity is spared, mirroring
        // `reindexIdentity`: it is position-independent (an explicit-id
        // re-root resolves the same stable identity at every position), stays
        // correct across the move, and identity-keyed lookups (`onChange`'s
        // previous-value owner) read it mid-resolve, before the apply would
        // restore it.
        if let previousIdentity = identityByNodeID[routedNodeID],
          previousIdentity != identity,
          previousIdentity != routedNode.resolvedIdentity,
          nodeIDByIdentity[previousIdentity] == routedNodeID
        {
          nodeIDByIdentity.removeValue(forKey: previousIdentity)
        }
        nodeIDByIdentity[identity] = routedNodeID
        identityByNodeID[routedNodeID] = identity
        entityRoutingTable.bind(entityIdentity, to: routedNodeID)
        if identity != routedNode.identity {
          // Adopted across identities: the committed value's positional stamp
          // pairing is unverified against whatever children this position
          // resolves next — withdraw the fast-path claim.
          routedNode.withdrawCommittedStampClaim()
        }
        return routedNode
      }
      recordCheckpointGraphMutation()
      entityRoutingTable.release(routedNodeID)
    }

    if let existing = nodeIfExists(for: identity) {
      if let entityIdentity {
        let existingEntityIdentity =
          existing.committed.entityIdentity
          ?? entityRoutingTable.entityByNodeID[existing.viewNodeID]
        if existingEntityIdentity == entityIdentity {
          recordCheckpointGraphMutation()
          entityRoutingTable.bind(entityIdentity, to: existing.viewNodeID)
          return existing
        }
        // A different entity (or none) occupies this `Identity` slot. A
        // duplicate-occurrence sibling (`occurrence > 0`, e.g. the second `7`
        // in `ForEach([7, 7])`) shares an `Identity` with the primary
        // (`occurrence == 0`) sibling but is a *distinct* runtime lifetime: it
        // must not adopt or evict the primary's node. Fall through to mint a
        // fresh `ViewNodeID` so duplicate-id siblings get independent
        // `@State`/lifecycle (G13). Cross-frame reuse of each occurrence is
        // handled above by the entity route; this fallback only runs on first
        // allocation, so the `nodeIDByIdentity` index landing on the
        // last-resolved occurrence is acceptable — the node store
        // (`nodesByNodeID`), entity routing, and parent→child teardown all
        // track both siblings.
        if entityIdentity.occurrence == 0 {
          if existingEntityIdentity != nil {
            // The displaced occupant's resolved subtree departs right here.
            // The eviction's descent covers committed values, live children,
            // and hosted-detached edges; the fresh node minted below carries
            // the displacement mark so `ExactIdentityModifier`'s churn
            // predicate (reuse suppression) fires even though the fresh node
            // was never present at frame start.
            removeSubtree(rootedAt: existing)
            displacedOccupant = true
          } else {
            recordCheckpointGraphMutation()
            entityRoutingTable.bind(entityIdentity, to: existing.viewNodeID)
            return existing
          }
        }
      } else {
        return existing
      }
    }

    recordCheckpointGraphMutation()
    nextViewNodeIDRawValue &+= 1
    let viewNodeID = ViewNodeID(rawValue: nextViewNodeIDRawValue)
    let node = ViewNode(
      viewNodeID: viewNodeID,
      identity: identity
    )
    node.ownerGraph = self
    nodesByNodeID[viewNodeID] = node
    nodeIDByIdentity[identity] = viewNodeID
    identityByNodeID[viewNodeID] = identity
    if let entityIdentity {
      entityRoutingTable.bind(entityIdentity, to: viewNodeID)
    }
    if displacedOccupant {
      node.entityDisplacedOccupantFrameID = currentFrameID
    }
    return node
  }

  private func bindEntityIdentity(
    from resolved: ResolvedNode,
    to viewNodeID: ViewNodeID
  ) {
    guard let entityIdentity = resolved.entityIdentity else {
      return
    }
    // The outermost same-frame claim owns the entity (see
    // `prepareEntityRoutedOwner`). The entity-carrying resolved value bubbles
    // through every wrapper level of its chain, and each level's apply lands
    // here — an inner level must not re-bind the entity away from the
    // enclosing claimer still on the evaluation stack, or next frame's
    // forwarded claim adopts the inner node cross-identity and aliases the
    // parent's committed child pairing.
    if let boundNodeID = entityRoutingTable.route(entityIdentity),
      boundNodeID != viewNodeID,
      let bound = nodeIfExists(for: boundNodeID),
      bound.isEvaluating
    {
      return
    }
    recordCheckpointGraphMutation()
    entityRoutingTable.bind(entityIdentity, to: viewNodeID)
  }

  private func entityIdentities(
    in resolved: ResolvedNode
  ) -> Set<EntityIdentity> {
    var entities: Set<EntityIdentity> = []
    func visit(_ node: ResolvedNode) {
      if let entityIdentity = node.entityIdentity {
        entities.insert(entityIdentity)
      }
      for child in node.children {
        visit(child)
      }
    }
    visit(resolved)
    return entities
  }

  private func releaseInactiveEntityRoutes(
    activeEntities: Set<EntityIdentity>
  ) {
    recordCheckpointGraphMutation()
    entityRoutingTable.releaseEntities(notIn: activeEntities)
    entityRoutingTable.releaseNodes(notIn: liveNodeIDs)
  }

  private func shouldDeferEntityRoutedRemoval(
    of node: ViewNode
  ) -> Bool {
    guard let entityIdentity = node.committed.entityIdentity else {
      return false
    }
    return entityRoutingTable.route(entityIdentity) == node.viewNodeID
  }

  private func prunePendingEntityRoutedRemovals(
    activeEntities: Set<EntityIdentity>
  ) {
    recordCheckpointGraphMutation()
    // Fixed-point: removing a pending subtree can itself defer deeper
    // entity-routed descendants back into the pending set. Each pass consumes
    // a disjoint snapshot and either keeps or removes every node in it, so
    // the loop strictly shrinks into the finite node store.
    while !pendingEntityRoutedRemovalNodeIDs.isEmpty {
      let pendingNodeIDs = pendingEntityRoutedRemovalNodeIDs
      pendingEntityRoutedRemovalNodeIDs.removeAll(keepingCapacity: true)
      for viewNodeID in pendingNodeIDs {
        guard let node = nodeIfExists(for: viewNodeID),
          let entityIdentity = node.committed.entityIdentity,
          // Use the frame-stamped `visitedThisFrame` signal, not the stored
          // `wasVisitedThisFrame` bool: a genuinely-gone node is never
          // re-prepared in the frame it disappears, so the stored bool stays
          // stale-`true` from its last live frame and would wrongly skip the
          // teardown — leaking the node (and, for duplicate-id siblings, the
          // occurrence-`>0` lifetime) in `nodesByNodeID` forever (G13).
          !node.visitedThisFrame(currentFrameID)
        else {
          continue
        }
        // Keep the node only while it is still the entity's live home: the
        // entity must be active in the new tree AND still route here. An
        // active entity that re-homed to another node this frame (an owner
        // churn re-attached it to the arriving generation) leaves this node a
        // displaced stale copy — tear it down, sparing any descendants the
        // arriving tree already re-adopted (they are visited).
        //
        // Routing alone cannot prove liveness when the entity's claims are
        // suppressed inside a hosting boundary (`entityHosting`): the arriving
        // generation re-resolves the same re-rooted identity onto a fresh
        // structural node without ever re-binding the route, and the stale
        // copy would be kept as "the home" forever. The resolved-identity
        // index is the tiebreaker — the live home's apply owns that entry; a
        // stale copy lost it to the arriving node's reindex. Duplicate-id
        // occurrences (> 0) are exempt: siblings share the identity entry by
        // design, so only the entity route is authoritative for them (G13).
        if activeEntities.contains(entityIdentity),
          entityRoutingTable.route(entityIdentity) == node.viewNodeID,
          entityIdentity.occurrence > 0
            || nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
        {
          continue
        }
        removeSubtree(rootedAt: node, sparingVisitedNodes: true)
      }
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
        recordCheckpointGraphMutation()
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

  /// Per-cascade re-entrancy guard for subtree removal. One walk instance is
  /// created at each removal root and threaded through the descent, so aliased
  /// identity/structural-path lookups cannot re-enter a node the cascade is
  /// already removing.
  private final class SubtreeRemovalWalk {
    var enteredNodeIDs: Set<ViewNodeID> = []
  }

  private func removeSubtree(
    rootedAt node: ViewNode,
    committedSnapshot: ResolvedNode? = nil,
    sparingVisitedNodes: Bool = false,
    isSubtreeDescent: Bool = false,
    walk: SubtreeRemovalWalk? = nil
  ) {
    guard let current = nodesByNodeID[node.viewNodeID],
      current === node
    else {
      return
    }
    // The descent below walks committed snapshots whose identity and
    // structural-path lookups can alias a node already being removed higher in
    // this same cascade (an absolute-`.id` re-root shares structural paths with
    // its wrapper). Re-entering it re-runs the whole body with no progress —
    // track entered nodes per removal cascade and run the node-local teardown
    // once. A re-entry still descends its own snapshot's children: an aliased
    // snapshot can cover departed descendants the first entry's snapshot does
    // not, and the descent strictly shrinks into the finite resolved tree.
    let walk = walk ?? SubtreeRemovalWalk()
    guard walk.enteredNodeIDs.insert(node.viewNodeID).inserted else {
      guard let committedSnapshot else {
        return
      }
      // The re-entry snapshot can name an interior node DISTINCT from the
      // re-entered absorber: a chain collapse leaves the interior's value
      // stamped with the absorber, but the interior still owns its re-rooted
      // identity index entry (a `.id` slot node under a hosting boundary).
      // Enter any not-yet-entered node the snapshot maps to — the walk's
      // entered-set makes this cycle-proof and strictly shrinking. When
      // nothing new maps, fall back to the children-only descent.
      var interiorNodes = nodeIDsForResolvedNode(committedSnapshot)
        .subtracting(walk.enteredNodeIDs)
        .compactMap { nodeIfExists(for: $0) }
      if interiorNodes.isEmpty,
        let interior = nodeIfExists(for: committedSnapshot.identity),
        !walk.enteredNodeIDs.contains(interior.viewNodeID)
      {
        interiorNodes = [interior]
      }
      guard !interiorNodes.isEmpty else {
        for child in committedSnapshot.children {
          removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
        }
        return
      }
      interiorNodes.sort { lhs, rhs in
        if lhs.identity == rhs.identity {
          return lhs.viewNodeID < rhs.viewNodeID
        }
        return lhs.identity < rhs.identity
      }
      for interior in interiorNodes {
        removeSubtree(
          rootedAt: interior,
          committedSnapshot: committedSnapshot,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
      return
    }

    // A departed-subtree teardown (an explicitly diffed-out child, a churn
    // orphan) removes a root the caller has already judged gone, but the walk
    // DOWN from that root goes through committed snapshots and identity/node
    // lookups that can land on nodes the arriving tree re-adopted this frame
    // (a stable-`.id` control re-rooted out of the departing generation, a
    // reused chrome node). A visited node reached by DESCENT therefore belongs
    // to the live tree — leave it, and its subtree, alone. The explicit root
    // is still removed unconditionally, and callers that do not opt in keep
    // the narrower parent-detached keep-guard below (some removals — e.g. a
    // pruned navigation destination — legitimately tear down visited roots).
    if sparingVisitedNodes,
      isSubtreeDescent,
      node.visitedThisFrame(currentFrameID)
    {
      return
    }

    // A node reached while tearing down a *departing* subtree (e.g. an owner
    // whose `.id` churned) may itself be a re-rooted stable-`.id` descendant
    // (a control under an `AnyView`/captured-subview scope) that the *arriving*
    // subtree already re-resolved this frame at its re-rooted identity. Because
    // its identity is re-rooted, it has no live parent link (`parent == nil`) —
    // the same property the retained-reuse decision observes — so it only appears
    // here through the departing owner's committed children, yet its runtime node
    // is genuinely live now. Dropping it would mint a fresh node next frame,
    // churning its route/registration identity and breaking same-node
    // interactions (a click whose press/release straddle the churn stops
    // dispatching). Keep it when it was visited this frame and is parent-detached;
    // a genuinely departing node either was not visited (pruned normally) or is
    // still parented under the surviving tree (e.g. an entity-routed owner being
    // replaced), so its lifecycle/registrations are retired as before.
    // …unless nothing can reach the node anymore: a live re-rooted node owns
    // its identity index entry (its apply reindexed it) or is an entity's
    // routed home, and the arriving tree finds it through one of those. A
    // visited, parent-detached node with neither is a stranded same-frame
    // mint whose output a chain collapse absorbed (`pruneAbsorbedShadowedNodes`)
    // — keeping it would leak it beyond every teardown path's reach.
    if node.parent == nil,
      node.viewNodeID != root?.viewNodeID,
      node.visitedThisFrame(currentFrameID),
      nodeIDByIdentity[node.identity] == node.viewNodeID
        || nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
        || entityRoutingTable.entityByNodeID[node.viewNodeID].map({ entity in
          entityRoutingTable.route(entity) == node.viewNodeID
        }) ?? false
    {
      return
    }

    // An entity-routed node reached by DESCENT is not necessarily departing
    // with the subtree being torn down: its entity may reappear elsewhere this
    // frame (a stable explicit-id control inside a churned owner, an `AnyView`
    // payload whose entity is re-attached by the arriving generation). Defer
    // the decision to the frame barrier (`prunePendingEntityRoutedRemovals`),
    // where the full old-vs-new entity set is known — the Stage 6 release
    // contract. An explicitly removed root (`isSubtreeDescent == false`, e.g.
    // the mid-resolve different-entity eviction) is still torn down
    // unconditionally; that eviction is load-bearing for same-frame
    // convergence of fixed-slot explicit-id churn.
    if isSubtreeDescent,
      shouldDeferEntityRoutedRemoval(of: node)
    {
      recordCheckpointGraphMutation()
      pendingEntityRoutedRemovalNodeIDs.insert(node.viewNodeID)
      return
    }

    recordCheckpointGraphMutation()
    node.prepareForFrame(currentFrameID)
    let snapshot = committedSnapshot ?? node.committed
    removeResolvedNodeReuseCaches(rootedAt: node.identity)
    if node.resolvedIdentity != node.identity {
      removeResolvedNodeReuseCaches(rootedAt: node.resolvedIdentity)
    }
    if snapshot.identity != node.identity,
      snapshot.identity != node.resolvedIdentity
    {
      removeResolvedNodeReuseCaches(rootedAt: snapshot.identity)
    }
    if snapshot.children.isEmpty {
      for child in node.children {
        removeSubtree(
          rootedAt: child,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    } else {
      for child in snapshot.children {
        removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
      }
      // A chain collapse can absorb an interior node's output as the
      // absorber's own resolved value: the committed value tree then names
      // the interior's identity with the absorber's stamp, so the value
      // descent above re-enters the absorber and never reaches the interior
      // node itself (its structural-path and identity index entries were
      // rewritten by the same collapse). The interior stays reachable only
      // as a live child — descend whatever is still parented here that the
      // value descent did not cover. A child the arriving tree re-adopted
      // was re-parented by its apply and is skipped; a child already reached
      // through the values is a no-op via the walk's entered-set.
      for child in node.children where child.parent === node {
        removeSubtree(
          rootedAt: child,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    }

    // Hosted detached subtrees: content this node resolved but did not commit
    // as a child (see `recordDetachedHostedSubtree`) is reachable through
    // neither the committed values above nor the parent links — its lifetime
    // anchors here. Visited roots (still being resolved by a live replacement)
    // and entity-routed re-homes are kept by the descent's standard guards.
    if let hostedRootIDs = detachedHostedSubtreeRootsByHost.removeValue(forKey: node.viewNodeID) {
      for hostedRootID in hostedRootIDs.sorted() {
        detachedHostedSubtreeHostByRoot.removeValue(forKey: hostedRootID)
        guard let hostedRoot = nodeIfExists(for: hostedRootID) else {
          continue
        }
        // Spare a visited hosted root only while something OUTSIDE this
        // removal cascade still anchors it (a live parent or a live
        // re-binding evaluation host): "visited this frame" alone is not
        // liveness — a dismissing overlay entry resolves its content one
        // last time in the frame that tears the whole entry down, and
        // sparing on that visit strands the root with no anchor at all
        // (unreachable until an eventual same-identity re-mint reuses it —
        // the census leak the hosted ledger exists to prevent).
        let anchor = hostedRoot.parent ?? hostedRoot.evaluationHost
        let anchorSurvivesRemoval =
          anchor.map { anchor in
            nodeIfExists(for: anchor.viewNodeID) === anchor
              && !walk.enteredNodeIDs.contains(anchor.viewNodeID)
          } ?? false
        removeSubtree(
          rootedAt: hostedRoot,
          sparingVisitedNodes: anchorSurvivesRemoval,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    }
    if let hostID = detachedHostedSubtreeHostByRoot.removeValue(forKey: node.viewNodeID) {
      detachedHostedSubtreeRootsByHost[hostID]?.remove(node.viewNodeID)
      if detachedHostedSubtreeRootsByHost[hostID]?.isEmpty == true {
        detachedHostedSubtreeRootsByHost.removeValue(forKey: hostID)
      }
    }

    let lifecycleMetadata =
      if !node.previousLifecycleMetadata.isEmpty {
        node.previousLifecycleMetadata
      } else if !node.lifecycleMetadata.isEmpty {
        node.lifecycleMetadata
      } else {
        snapshot.lifecycleMetadata
      }

    let emitsOwnLifecycleEvents = node.participatesInStructuralLifecycle

    if emitsOwnLifecycleEvents {
      for task in lifecycleMetadata.tasks {
        appendTaskCancelEvent(
          identity: snapshot.identity,
          task: task,
          isStructural: true
        )
      }
    }
    if emitsOwnLifecycleEvents,
      !lifecycleMetadata.disappearHandlerIDs.isEmpty
    {
      structuralDisappearEvents.append(
        .init(
          identity: node.identity,
          operation: .disappear(
            handlerIDs: lifecycleMetadata.disappearHandlerIDs
          )
        )
      )
    }

    node.setLifecycleState(.disappearing)
    node.setCommittedPresence(false)
    node.recordCheckpointMutation()
    node.parent = nil
    removeDependencyEdges(for: node)
    liveNodeIDs.remove(node.viewNodeID)
    invalidatedNodeIDs.remove(node.viewNodeID)
    graphLocalDirtyNodeIDs.remove(node.viewNodeID)

    if let owner = lifecycleEvaluationOwnersByNodeID.removeValue(forKey: node.viewNodeID) {
      lifecycleEvaluationTargetsByOwner[owner]?.remove(node.viewNodeID)
      if lifecycleEvaluationTargetsByOwner[owner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: owner)
      }
    }
    if let targets = lifecycleEvaluationTargetsByOwner.removeValue(forKey: node.viewNodeID) {
      for target in targets {
        lifecycleEvaluationOwnersByNodeID.removeValue(forKey: target)
      }
    }
    lifecycleEvaluationTargetsRecordedByOwner.removeValue(forKey: node.viewNodeID)

    nodeIDsByStructuralPath[node.committed.structuralPath]?.remove(node.viewNodeID)
    if nodeIDsByStructuralPath[node.committed.structuralPath]?.isEmpty == true {
      nodeIDsByStructuralPath.removeValue(forKey: node.committed.structuralPath)
    }
    taskDescriptorNodeSlots = taskDescriptorNodeSlots.filter { $0.key.node != node.viewNodeID }
    if nodeIDByIdentity[node.identity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.resolvedIdentity)
    }
    entityRoutingTable.release(node.viewNodeID)
    identityByNodeID.removeValue(forKey: node.viewNodeID)
    nodesByNodeID.removeValue(forKey: node.viewNodeID)
  }

  private func removeResolvedNodeReuseCaches(
    rootedAt identity: Identity
  ) {
    resolvedNodeReuseCache = resolvedNodeReuseCache.filter { key, entry in
      let ownerMatches = key.owner == identity || key.owner.isDescendant(of: identity)
      let nodeMatches =
        entry.node.identity == identity || entry.node.identity.isDescendant(of: identity)
      return !ownerMatches && !nodeMatches
    }
  }

  private func removeResolvedSubtree(
    _ resolved: ResolvedNode,
    sparingVisitedNodes: Bool = false,
    walk: SubtreeRemovalWalk? = nil
  ) {
    let walk = walk ?? SubtreeRemovalWalk()
    let nodes = nodeIDsForResolvedNode(resolved)
      .compactMap { nodeIfExists(for: $0) }
      .sorted { lhs, rhs in
        if lhs.identity == rhs.identity {
          return lhs.viewNodeID < rhs.viewNodeID
        }
        return lhs.identity < rhs.identity
      }
    if !nodes.isEmpty {
      for node in nodes {
        removeSubtree(
          rootedAt: node,
          committedSnapshot: resolved,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
      return
    }

    if let node = nodeIfExists(for: resolved.identity) {
      removeSubtree(
        rootedAt: node,
        committedSnapshot: resolved,
        sparingVisitedNodes: sparingVisitedNodes,
        isSubtreeDescent: true,
        walk: walk
      )
      return
    }

    for child in resolved.children {
      removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
    }
  }

  private func reindexDependencies(
    for node: ViewNode,
    previous: DependencySet
  ) {
    recordCheckpointGraphMutation()
    ViewGraphDependencyIndex.reindex(
      viewNodeID: node.viewNodeID,
      previous: previous,
      current: node.dependencies,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
  }

  private func removeDependencyEdges(
    for node: ViewNode
  ) {
    recordCheckpointGraphMutation()
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
    placed: PlacedNode?
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

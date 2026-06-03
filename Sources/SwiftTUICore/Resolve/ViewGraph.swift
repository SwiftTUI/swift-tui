extension ViewGraph {
  package func makeCheckpoint() -> Checkpoint {
    return Checkpoint(
      root: root,
      nodesByNodeID: nodesByNodeID,
      nodeIDByIdentity: nodeIDByIdentity,
      identityByNodeID: identityByNodeID,
      nodeIDsByStructuralPath: nodeIDsByStructuralPath,
      nextViewNodeIDRawValue: nextViewNodeIDRawValue,
      rootEvaluator: rootEvaluator,
      evaluationRootIdentity: evaluationRootIdentity,
      viewportLifecycleNodesByKey: viewportLifecycleNodesByKey,
      viewportLifecycleOrder: viewportLifecycleOrder,
      frameOrder: frameOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents,
      requiresRootEvaluation: requiresRootEvaluation,
      invalidatedNodeIDs: invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
      latestLifecycleEvents: latestLifecycleEvents,
      stateMutationKeys: stateMutationKeys,
      stateMutationNodeIDsByKey: stateMutationNodeIDsByKey,
      lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID,
      lifecycleEvaluationTargetsByOwner: lifecycleEvaluationTargetsByOwner,
      lifecycleEvaluationTargetsRecordedByOwner: lifecycleEvaluationTargetsRecordedByOwner,
      taskDescriptorNodeSlots: taskDescriptorNodeSlots,
      nextTaskDescriptorIdentityToken: nextTaskDescriptorIdentityToken,
      stateSlotDependents: stateSlotDependents,
      environmentDependents: environmentDependents,
      observableDependents: observableDependents,
      currentFrameID: currentFrameID,
      liveNodeIDs: liveNodeIDs,
      nodeCheckpoints: ViewGraphNodeCheckpointing.makeNodeCheckpoints(
        nodesByNodeID
      )
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    root = checkpoint.root
    nodesByNodeID = checkpoint.nodesByNodeID
    nodeIDByIdentity = checkpoint.nodeIDByIdentity
    identityByNodeID = checkpoint.identityByNodeID
    nodeIDsByStructuralPath = checkpoint.nodeIDsByStructuralPath
    nextViewNodeIDRawValue = checkpoint.nextViewNodeIDRawValue
    rootEvaluator = checkpoint.rootEvaluator
    evaluationRootIdentity = checkpoint.evaluationRootIdentity
    viewportLifecycleNodesByKey = checkpoint.viewportLifecycleNodesByKey
    viewportLifecycleOrder = checkpoint.viewportLifecycleOrder
    frameOrder = checkpoint.frameOrder
    stableTaskCancelEvents = checkpoint.stableTaskCancelEvents
    stableTaskStartEvents = checkpoint.stableTaskStartEvents
    structuralAppearEvents = checkpoint.structuralAppearEvents
    structuralTaskCancelEvents = checkpoint.structuralTaskCancelEvents
    structuralDisappearEvents = checkpoint.structuralDisappearEvents
    requiresRootEvaluation = checkpoint.requiresRootEvaluation
    invalidatedNodeIDs = checkpoint.invalidatedNodeIDs
    graphLocalDirtyNodeIDs = checkpoint.graphLocalDirtyNodeIDs
    latestLifecycleEvents = checkpoint.latestLifecycleEvents
    stateMutationKeys = checkpoint.stateMutationKeys
    stateMutationNodeIDsByKey = checkpoint.stateMutationNodeIDsByKey
    lifecycleEvaluationOwnersByNodeID = checkpoint.lifecycleEvaluationOwnersByNodeID
    lifecycleEvaluationTargetsByOwner = checkpoint.lifecycleEvaluationTargetsByOwner
    lifecycleEvaluationTargetsRecordedByOwner = checkpoint.lifecycleEvaluationTargetsRecordedByOwner
    taskDescriptorNodeSlots = checkpoint.taskDescriptorNodeSlots
    nextTaskDescriptorIdentityToken = checkpoint.nextTaskDescriptorIdentityToken
    stateSlotDependents = checkpoint.stateSlotDependents
    environmentDependents = checkpoint.environmentDependents
    observableDependents = checkpoint.observableDependents
    currentFrameID = checkpoint.currentFrameID
    liveNodeIDs = checkpoint.liveNodeIDs

    ViewGraphNodeCheckpointing.restoreNodeCheckpoints(
      checkpoint.nodeCheckpoints,
      nodesByNodeID: checkpoint.nodesByNodeID
    )
  }
}

@MainActor
package final class ViewGraph {
  // CHECKPOINT TOTALITY CONTRACT (audit finding F4):
  // Every mutable stored property declared below MUST appear in
  // ViewGraph.Checkpoint and DebugTotalStateSnapshot. The source-level
  // ViewGraphCheckpointTotalityTests guard fails when a new mutable field
  // escapes checkpoint coverage.
  package private(set) var root: ViewNode?

  private var nodesByNodeID: [ViewNodeID: ViewNode]
  private var nodeIDByIdentity: [Identity: ViewNodeID]
  private var identityByNodeID: [ViewNodeID: Identity]
  private var nodeIDsByStructuralPath: [StructuralPath: Set<ViewNodeID>]
  private var nextViewNodeIDRawValue: UInt64
  private var rootEvaluator: (@MainActor () -> Void)?
  private var evaluationRootIdentity: Identity?
  private var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
  private var viewportLifecycleOrder: [ViewportLifecycleKey]
  private var frameOrder: [ViewNodeID]
  private var stableTaskCancelEvents: [LifecycleEvent]
  private var stableTaskStartEvents: [LifecycleEvent]
  private var structuralAppearEvents: [LifecycleEvent]
  private var structuralTaskCancelEvents: [LifecycleEvent]
  private var structuralDisappearEvents: [LifecycleEvent]
  private var requiresRootEvaluation: Bool
  private var invalidatedNodeIDs: Set<ViewNodeID>
  private var graphLocalDirtyNodeIDs: Set<ViewNodeID>
  private var latestLifecycleEvents: [LifecycleEvent]
  private var stateMutationKeys: Set<StateSlotKey>
  private var stateMutationNodeIDsByKey: [StateSlotKey: Set<ViewNodeID>]
  private var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
  private var lifecycleEvaluationTargetsByOwner: [ViewNodeID: Set<ViewNodeID>]
  private var lifecycleEvaluationTargetsRecordedByOwner: [ViewNodeID: Set<ViewNodeID>]
  private var taskDescriptorNodeSlots: [ViewNodeID: TaskDescriptorIdentitySlot]
  private var nextTaskDescriptorIdentityToken: UInt64
  private var stateSlotDependents: [StateSlotKey: Set<ViewNodeID>]
  private var environmentDependents: [ObjectIdentifier: Set<ViewNodeID>]
  private var observableDependents: [ObjectIdentifier: Set<ViewNodeID>]
  private var currentFrameID: UInt64
  private var liveNodeIDs: Set<ViewNodeID>

  private var nodesByIdentity: [Identity: ViewNode] {
    Dictionary(
      uniqueKeysWithValues: nodeIDByIdentity.compactMap { identity, viewNodeID in
        guard let node = nodesByNodeID[viewNodeID] else {
          return nil
        }
        return (identity, node)
      }
    )
  }

  private func nodeIfExists(
    for identity: Identity
  ) -> ViewNode? {
    guard let viewNodeID = nodeIDByIdentity[identity] else {
      return nil
    }
    return nodesByNodeID[viewNodeID]
  }

  private func nodeIfExists(
    for viewNodeID: ViewNodeID
  ) -> ViewNode? {
    nodesByNodeID[viewNodeID]
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
    var viewNodeIDs = nodeIDsByStructuralPath[resolved.structuralPath] ?? []
    if let viewNodeID = resolved.viewNodeID {
      viewNodeIDs.insert(viewNodeID)
    }
    return viewNodeIDs
  }

  private func viewNodeID(
    for identity: Identity
  ) -> ViewNodeID? {
    nodeIDByIdentity[identity]
  }

  private func identities(
    for viewNodeIDs: Set<ViewNodeID>
  ) -> Set<Identity> {
    Set(viewNodeIDs.compactMap { identityByNodeID[$0] })
  }

  private func nodeIDs(
    for identities: Set<Identity>
  ) -> Set<ViewNodeID> {
    Set(identities.compactMap { nodeIDByIdentity[$0] })
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

  private func nodeIDsForInvalidation(
    _ identities: Set<Identity>
  ) -> Set<ViewNodeID> {
    let viewNodeIDs = nodeIDs(for: identities)
    if viewNodeIDs.count != identities.count {
      requiresRootEvaluation = true
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
    nodesByNodeID = [:]
    nodeIDByIdentity = [:]
    identityByNodeID = [:]
    nodeIDsByStructuralPath = [:]
    nextViewNodeIDRawValue = 0
    rootEvaluator = nil
    evaluationRootIdentity = nil
    viewportLifecycleNodesByKey = [:]
    viewportLifecycleOrder = []
    frameOrder = []
    stableTaskCancelEvents = []
    stableTaskStartEvents = []
    structuralAppearEvents = []
    structuralTaskCancelEvents = []
    structuralDisappearEvents = []
    requiresRootEvaluation = false
    invalidatedNodeIDs = []
    graphLocalDirtyNodeIDs = []
    latestLifecycleEvents = []
    stateMutationKeys = []
    stateMutationNodeIDsByKey = [:]
    lifecycleEvaluationOwnersByNodeID = [:]
    lifecycleEvaluationTargetsByOwner = [:]
    lifecycleEvaluationTargetsRecordedByOwner = [:]
    taskDescriptorNodeSlots = [:]
    nextTaskDescriptorIdentityToken = 0
    stateSlotDependents = [:]
    environmentDependents = [:]
    observableDependents = [:]
    currentFrameID = 0
    liveNodeIDs = []
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
      nextViewNodeIDRawValue: nextViewNodeIDRawValue,
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
      requiresRootEvaluation: requiresRootEvaluation,
      invalidatedNodeIDs: invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
      latestLifecycleEvents: latestLifecycleEvents,
      stateMutationKeys: stateMutationKeys,
      stateMutationNodeIDsByKey: stateMutationNodeIDsByKey,
      lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID,
      lifecycleEvaluationTargetsByOwner: lifecycleEvaluationTargetsByOwner,
      lifecycleEvaluationTargetsRecordedByOwner: lifecycleEvaluationTargetsRecordedByOwner,
      taskDescriptorNodeSlots: taskDescriptorNodeSlots.mapValues(\.label),
      nextTaskDescriptorIdentityToken: nextTaskDescriptorIdentityToken,
      stateSlotDependents: stateSlotDependents,
      environmentDependents: debugObjectDependencySnapshot(environmentDependents),
      observableDependents: debugObjectDependencySnapshot(observableDependents),
      currentFrameID: currentFrameID,
      liveNodeIDs: liveNodeIDs
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

  package func containsNode(
    for identity: Identity
  ) -> Bool {
    nodeIfExists(for: identity) != nil
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
    let ownerNodeID = viewNodeID(for: key.identity)
    stateMutationKeys.insert(key)
    if let ownerNodeID {
      stateMutationNodeIDsByKey[key, default: []].insert(ownerNodeID)
    }
    ViewGraphInvalidationPlanner.queueDirty(
      ViewGraphInvalidationPlanner.stateChangeDirtyNodeIDs(
        for: key,
        ownerNodeID: ownerNodeID,
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
            viewNodeID: viewNodeID,
            identity: key.identity,
            ordinal: key.ordinal
          )
        ] = slot
        capturedSlot = true
      }
      guard !capturedSlot,
        let slot = nodeIfExists(for: key.identity)?.stateSlotStorage(
          ordinal: key.ordinal
        )
      else {
        continue
      }
      stateSlots[
        StateMutationSlotKey(
          viewNodeID: nil,
          identity: key.identity,
          ordinal: key.ordinal
        )
      ] = slot
    }
    return StateMutationOverlay(
      stateSlots: stateSlots,
      requiresRootEvaluation: requiresRootEvaluation,
      invalidatedNodeIDs: invalidatedNodeIDs,
      graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
      stateMutationKeys: stateMutationKeys,
      stateMutationNodeIDsByKey: stateMutationNodeIDsByKey
    )
  }

  package func applyStateMutationOverlay(
    _ overlay: StateMutationOverlay
  ) {
    for (key, slot) in overlay.stateSlots {
      let node =
        key.viewNodeID.flatMap { nodeIfExists(for: $0) }
        ?? nodeIfExists(for: key.identity)
      guard let node else {
        continue
      }
      node.restoreStateSlot(ordinal: key.ordinal, slot: slot)
      node.markDirty()
    }
    requiresRootEvaluation = requiresRootEvaluation || overlay.requiresRootEvaluation
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
        observedBy: viewNodeID,
        nodesByNodeID: nodesByNodeID,
        observableDependents: observableDependents
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
    value: ID
  ) -> String {
    let viewNodeID = nodeForIdentity(for: identity).viewNodeID
    return taskDescriptorIdentityLabel(
      for: viewNodeID,
      value: value
    )
  }

  package func taskDescriptorIdentityLabel<ID: Equatable>(
    for viewNodeID: ViewNodeID,
    value: ID
  ) -> String {
    if let slot = taskDescriptorNodeSlots[viewNodeID],
      slot.matches(value)
    {
      return slot.label
    }

    nextTaskDescriptorIdentityToken &+= 1
    let label = "id:\(nextTaskDescriptorIdentityToken)"
    taskDescriptorNodeSlots[viewNodeID] = TaskDescriptorIdentitySlot(
      label: label,
      value: value
    )
    return label
  }

  package func selectiveDirtyEvaluationPlan() -> DirtyEvaluationPlan? {
    guard !requiresRootEvaluation else {
      return nil
    }
    guard
      let targetPlan = ViewGraphDirtyEvaluationPlanner.targetPlan(
        input: ViewGraphDirtyEvaluationPlanningInput(
          hasRoot: root != nil,
          invalidatedNodeIDs: invalidatedNodeIDs,
          graphLocalDirtyNodeIDs: graphLocalDirtyNodeIDs,
          nodesByNodeID: nodesByNodeID,
          lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID
        )
      )
    else {
      return nil
    }

    for target in targetPlan.targetNodes {
      target.markDirty()
    }

    guard !targetPlan.targetNodes.isEmpty,
      targetPlan.targetNodes.allSatisfy(\.hasEvaluator)
    else {
      return nil
    }

    return DirtyEvaluationPlan(
      frontierNodeIDs: targetPlan.targetNodes.map(\.viewNodeID),
      frontierIdentities: targetPlan.targetNodes.map(\.identity)
    )
  }

  /// Whether any identities are dirty and need evaluation this frame.
  package var hasDirtyWork: Bool {
    requiresRootEvaluation || !invalidatedNodeIDs.isEmpty || !graphLocalDirtyNodeIDs.isEmpty
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
    currentFrameID &+= 1
    frameOrder.removeAll(keepingCapacity: true)
    stableTaskCancelEvents.removeAll(keepingCapacity: true)
    stableTaskStartEvents.removeAll(keepingCapacity: true)
    structuralAppearEvents.removeAll(keepingCapacity: true)
    structuralTaskCancelEvents.removeAll(keepingCapacity: true)
    structuralDisappearEvents.removeAll(keepingCapacity: true)
    latestLifecycleEvents.removeAll(keepingCapacity: true)
  }

  package func beginEvaluation(
    identity: Identity,
    invalidator: (any Invalidating)?,
    suppressesStructuralLifecycle: Bool = false
  ) -> ViewNode {
    let node = nodeForIdentity(for: identity)
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

    let resolved = resolvedPreservingLayoutDependentChildren(
      resolved,
      for: node
    )
    pruneDetachedResolvedRootIfNeeded(
      previousResolvedIdentity: previousResolvedIdentity,
      replacedBy: resolved.identity,
      for: node
    )
    let childNodes = resolved.children.map(nodeForResolvedNode)
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
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task,
        emitsOwnLifecycleEvents
      {
        let removedTaskAcrossResolvedIdentityChange =
          didChangeResolvedIdentity && node.lifecycleMetadata.task == nil
        if !didChangeResolvedIdentity || removedTaskAcrossResolvedIdentityChange {
          appendTaskCancelEvent(
            identity: removedTaskAcrossResolvedIdentityChange
              ? node.resolvedIdentity : previousResolvedIdentity,
            task: previousTask,
            isStructural: false
          )
        }
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        emitsOwnLifecycleEvents,
        !didChangeResolvedIdentity
      {
        appendTaskStartEvent(
          identity: node.resolvedIdentity,
          task: currentTask
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
      if emitsOwnLifecycleEvents,
        let task = node.lifecycleMetadata.task
      {
        appendTaskStartEvent(
          identity: node.resolvedIdentity,
          task: task
        )
      }
      node.setLifecycleState(.appearing)
    }
    pruneLifecycleEvaluationOwners(ownedBy: node.identity)
    return node.committed
  }

  package func installLayoutDependentChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
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
    node?.refreshResolvedMetadata(from: resolved)
  }

  private func resolvedPreservingLayoutDependentChildren(
    _ resolved: ResolvedNode,
    for node: ViewNode
  ) -> ResolvedNode {
    guard resolved.layoutDependentContent != nil,
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
      // `ViewNode.apply` takes its same-children fast path; the structural diff is
      // a no-op (no structural intersection) and is skipped with the recursion.
      applyResolvedNode(
        node,
        resolved: subtree,
        children: node.children
      )
    } else {
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
      if emitsOwnLifecycleEvents,
        let task = node.lifecycleMetadata.task
      {
        appendTaskStartEvent(
          identity: node.resolvedIdentity,
          task: task
        )
      }
      node.setLifecycleState(.appearing)
    } else {
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task,
        emitsOwnLifecycleEvents
      {
        let removedTaskAcrossResolvedIdentityChange =
          didChangeResolvedIdentity && node.lifecycleMetadata.task == nil
        if !didChangeResolvedIdentity || removedTaskAcrossResolvedIdentityChange {
          appendTaskCancelEvent(
            identity: removedTaskAcrossResolvedIdentityChange
              ? node.resolvedIdentity : previousResolvedIdentity,
            task: previousTask,
            isStructural: false
          )
        }
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        emitsOwnLifecycleEvents,
        !didChangeResolvedIdentity
      {
        appendTaskStartEvent(
          identity: node.resolvedIdentity,
          task: currentTask
        )
      }
      node.setLifecycleState(.alive)
    }
  }

  package func reusableSnapshot(
    for identity: Identity,
    invalidatedIdentities: Set<Identity>,
    invalidationSummary: InvalidationSummary? = nil,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot,
    invalidator: (any Invalidating)?
  ) -> ResolvedNode? {
    guard let node = nodeIfExists(for: identity) else {
      return nil
    }
    guard !invalidatedIdentities.isEmpty else {
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

    let conflictsWithInvalidation = invalidatedIdentities.contains { invalidatedIdentity in
      invalidatedIdentity == identity
        || invalidatedIdentity.isDescendant(of: identity)
        || identity.isDescendant(of: invalidatedIdentity)
        || invalidatedIdentity == resolvedIdentity
        || invalidatedIdentity.isDescendant(of: resolvedIdentity)
        || resolvedIdentity.isDescendant(of: invalidatedIdentity)
    }
    guard !conflictsWithInvalidation,
      !structurallyIntersectsInvalidation
    else {
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
    frameLifecycleEventPlan(
      resolved: resolved,
      placed: placed
    ).events
  }

  package func finalizeFrame(
    rootIdentity: Identity,
    resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
    root = nodeIfExists(for: rootIdentity)

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

    liveNodeIDs.formUnion(frameOrder)
    requiresRootEvaluation = false
    invalidatedNodeIDs.removeAll(keepingCapacity: true)
    graphLocalDirtyNodeIDs.removeAll(keepingCapacity: true)
    stateMutationKeys.removeAll(keepingCapacity: true)
    stateMutationNodeIDsByKey.removeAll(keepingCapacity: true)
    return latestLifecycleEvents
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

  /// Scoped counterpart to ``restoreCurrentFrameRuntimeRegistrations``: restores
  /// runtime registrations for ONLY the live subtrees rooted at `roots`, walking
  /// each root's ViewNode subtree (O(subtree)) instead of the full live-identity
  /// set. Used on `.subtrees` publication frames, where the preceding
  /// `removeSubtrees(rootedAt:)` cleared exactly these subtrees and untouched
  /// subtrees' registrations remain valid in place — so re-publishing the whole
  /// tree (the former behavior) is redundant O(tree) work.
  package func restoreRuntimeRegistrationSubtrees(
    rootedAt roots: [Identity],
    into registrations: RuntimeRegistrationSet
  ) {
    for root in roots {
      nodeIfExists(for: root)?.restoreRuntimeRegistrations(into: registrations)
    }
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

  private func appendTaskCancelEvent(
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

  private func nodeForIdentity(
    for identity: Identity
  ) -> ViewNode {
    if let existing = nodeIfExists(for: identity) {
      return existing
    }

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
    return node
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

      removeSubtree(
        rootedAt: removedNode,
        committedSnapshot: removal.committedSnapshot
      )
    }
  }

  private func removeSubtree(
    rootedAt node: ViewNode,
    committedSnapshot: ResolvedNode? = nil
  ) {
    guard let current = nodesByNodeID[node.viewNodeID],
      current === node
    else {
      return
    }

    node.prepareForFrame(currentFrameID)
    let snapshot = committedSnapshot ?? node.committed
    if snapshot.children.isEmpty {
      for child in node.children {
        removeSubtree(rootedAt: child)
      }
    } else {
      for child in snapshot.children {
        removeResolvedSubtree(child)
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

    if emitsOwnLifecycleEvents,
      let task = lifecycleMetadata.task
    {
      appendTaskCancelEvent(
        identity: snapshot.identity,
        task: task,
        isStructural: true
      )
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
    taskDescriptorNodeSlots.removeValue(forKey: node.viewNodeID)
    if nodeIDByIdentity[node.identity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.resolvedIdentity)
    }
    identityByNodeID.removeValue(forKey: node.viewNodeID)
    nodesByNodeID.removeValue(forKey: node.viewNodeID)
  }

  private func removeResolvedSubtree(
    _ resolved: ResolvedNode
  ) {
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
          committedSnapshot: resolved
        )
      }
      return
    }

    if let node = nodeIfExists(for: resolved.identity) {
      removeSubtree(
        rootedAt: node,
        committedSnapshot: resolved
      )
      return
    }

    for child in resolved.children {
      removeResolvedSubtree(child)
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

  private func removeDependencyEdges(
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

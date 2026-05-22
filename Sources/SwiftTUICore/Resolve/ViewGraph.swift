extension ViewGraph {
  package func makeCheckpoint() -> Checkpoint {
    return Checkpoint(
      root: root,
      nodesByIdentity: nodesByIdentity,
      rootEvaluator: rootEvaluator,
      evaluationRootIdentity: evaluationRootIdentity,
      viewportLifecycleNodesByIdentity: viewportLifecycleNodesByIdentity,
      viewportLifecycleOrder: viewportLifecycleOrder,
      frameOrder: frameOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents,
      invalidatedIdentities: invalidatedIdentities,
      graphLocalDirtyIdentities: graphLocalDirtyIdentities,
      latestLifecycleEvents: latestLifecycleEvents,
      stateMutationKeys: stateMutationKeys,
      registrationAliasesByIdentity: registrationAliasesByIdentity,
      registrationAliasTargets: registrationAliasTargets,
      registrationAliasDiagnostics: registrationAliasDiagnostics,
      lifecycleEvaluationOwnersByIdentity: lifecycleEvaluationOwnersByIdentity,
      lifecycleEvaluationTargetsByOwner: lifecycleEvaluationTargetsByOwner,
      lifecycleEvaluationTargetsRecordedByOwner: lifecycleEvaluationTargetsRecordedByOwner,
      taskDescriptorIdentitySlots: taskDescriptorIdentitySlots,
      nextTaskDescriptorIdentityToken: nextTaskDescriptorIdentityToken,
      stateSlotDependents: stateSlotDependents,
      environmentDependents: environmentDependents,
      observableDependents: observableDependents,
      currentFrameID: currentFrameID,
      liveIdentities: liveIdentities,
      nodeCheckpoints: ViewGraphNodeCheckpointing.makeNodeCheckpoints(
        nodesByIdentity
      )
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    root = checkpoint.root
    nodesByIdentity = checkpoint.nodesByIdentity
    rootEvaluator = checkpoint.rootEvaluator
    evaluationRootIdentity = checkpoint.evaluationRootIdentity
    viewportLifecycleNodesByIdentity = checkpoint.viewportLifecycleNodesByIdentity
    viewportLifecycleOrder = checkpoint.viewportLifecycleOrder
    frameOrder = checkpoint.frameOrder
    stableTaskCancelEvents = checkpoint.stableTaskCancelEvents
    stableTaskStartEvents = checkpoint.stableTaskStartEvents
    structuralAppearEvents = checkpoint.structuralAppearEvents
    structuralTaskCancelEvents = checkpoint.structuralTaskCancelEvents
    structuralDisappearEvents = checkpoint.structuralDisappearEvents
    invalidatedIdentities = checkpoint.invalidatedIdentities
    graphLocalDirtyIdentities = checkpoint.graphLocalDirtyIdentities
    latestLifecycleEvents = checkpoint.latestLifecycleEvents
    stateMutationKeys = checkpoint.stateMutationKeys
    registrationAliasesByIdentity = checkpoint.registrationAliasesByIdentity
    registrationAliasTargets = checkpoint.registrationAliasTargets
    registrationAliasDiagnostics = checkpoint.registrationAliasDiagnostics
    lifecycleEvaluationOwnersByIdentity = checkpoint.lifecycleEvaluationOwnersByIdentity
    lifecycleEvaluationTargetsByOwner = checkpoint.lifecycleEvaluationTargetsByOwner
    lifecycleEvaluationTargetsRecordedByOwner = checkpoint.lifecycleEvaluationTargetsRecordedByOwner
    taskDescriptorIdentitySlots = checkpoint.taskDescriptorIdentitySlots
    nextTaskDescriptorIdentityToken = checkpoint.nextTaskDescriptorIdentityToken
    stateSlotDependents = checkpoint.stateSlotDependents
    environmentDependents = checkpoint.environmentDependents
    observableDependents = checkpoint.observableDependents
    currentFrameID = checkpoint.currentFrameID
    liveIdentities = checkpoint.liveIdentities

    ViewGraphNodeCheckpointing.restoreNodeCheckpoints(
      checkpoint.nodeCheckpoints,
      nodesByIdentity: checkpoint.nodesByIdentity
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

  private var nodesByIdentity: [Identity: ViewNode]
  private var rootEvaluator: (@MainActor () -> Void)?
  private var evaluationRootIdentity: Identity?
  private var viewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode]
  private var viewportLifecycleOrder: [Identity]
  private var frameOrder: [Identity]
  private var stableTaskCancelEvents: [LifecycleEvent]
  private var stableTaskStartEvents: [LifecycleEvent]
  private var structuralAppearEvents: [LifecycleEvent]
  private var structuralTaskCancelEvents: [LifecycleEvent]
  private var structuralDisappearEvents: [LifecycleEvent]
  private var invalidatedIdentities: Set<Identity>
  private var graphLocalDirtyIdentities: Set<Identity>
  private var latestLifecycleEvents: [LifecycleEvent]
  private var stateMutationKeys: Set<StateSlotKey>
  private var registrationAliasesByIdentity: [Identity: Set<Identity>]
  private var registrationAliasTargets: [Identity: Identity]
  private var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
  private var lifecycleEvaluationTargetsByOwner: [Identity: Set<Identity>]
  private var lifecycleEvaluationTargetsRecordedByOwner: [Identity: Set<Identity>]
  private var taskDescriptorIdentitySlots: [Identity: TaskDescriptorIdentitySlot]
  private var nextTaskDescriptorIdentityToken: UInt64
  /// Instrumentation that tracks non-trivial `recordRegistrationAlias`
  /// calls so the alias layer's
  /// actual workload can be measured against the architecture doc's
  /// hypothesis that divergences come from a small, enumerable set of
  /// view patterns.  Always on, bounded memory — safe to leave enabled
  /// in production.
  package private(set) var registrationAliasDiagnostics: RegistrationAliasDiagnostics
  private var stateSlotDependents: [StateSlotKey: Set<Identity>]
  private var environmentDependents: [ObjectIdentifier: Set<Identity>]
  private var observableDependents: [ObjectIdentifier: Set<Identity>]
  private var currentFrameID: UInt64
  private var liveIdentities: Set<Identity>

  package init() {
    nodesByIdentity = [:]
    rootEvaluator = nil
    evaluationRootIdentity = nil
    viewportLifecycleNodesByIdentity = [:]
    viewportLifecycleOrder = []
    frameOrder = []
    stableTaskCancelEvents = []
    stableTaskStartEvents = []
    structuralAppearEvents = []
    structuralTaskCancelEvents = []
    structuralDisappearEvents = []
    invalidatedIdentities = []
    graphLocalDirtyIdentities = []
    latestLifecycleEvents = []
    stateMutationKeys = []
    registrationAliasesByIdentity = [:]
    registrationAliasTargets = [:]
    lifecycleEvaluationOwnersByIdentity = [:]
    lifecycleEvaluationTargetsByOwner = [:]
    lifecycleEvaluationTargetsRecordedByOwner = [:]
    taskDescriptorIdentitySlots = [:]
    nextTaskDescriptorIdentityToken = 0
    registrationAliasDiagnostics = .init()
    stateSlotDependents = [:]
    environmentDependents = [:]
    observableDependents = [:]
    currentFrameID = 0
    liveIdentities = []
  }

  package func debugTotalStateSnapshot() -> DebugTotalStateSnapshot {
    DebugTotalStateSnapshot(
      root: root?.identity,
      nodesByIdentity: nodesByIdentity.mapValues { node in
        node.debugTotalStateSnapshot()
      },
      rootEvaluator: rootEvaluator != nil,
      evaluationRootIdentity: evaluationRootIdentity,
      viewportLifecycleNodesByIdentity: viewportLifecycleNodesByIdentity,
      viewportLifecycleOrder: viewportLifecycleOrder,
      frameOrder: frameOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents,
      invalidatedIdentities: invalidatedIdentities,
      graphLocalDirtyIdentities: graphLocalDirtyIdentities,
      latestLifecycleEvents: latestLifecycleEvents,
      stateMutationKeys: stateMutationKeys,
      registrationAliasesByIdentity: registrationAliasesByIdentity,
      registrationAliasTargets: registrationAliasTargets,
      lifecycleEvaluationOwnersByIdentity: lifecycleEvaluationOwnersByIdentity,
      lifecycleEvaluationTargetsByOwner: lifecycleEvaluationTargetsByOwner,
      lifecycleEvaluationTargetsRecordedByOwner: lifecycleEvaluationTargetsRecordedByOwner,
      taskDescriptorIdentitySlots: taskDescriptorIdentitySlots.mapValues(\.label),
      nextTaskDescriptorIdentityToken: nextTaskDescriptorIdentityToken,
      registrationAliasDiagnostics: registrationAliasDiagnostics,
      stateSlotDependents: stateSlotDependents,
      environmentDependents: debugObjectDependencySnapshot(environmentDependents),
      observableDependents: debugObjectDependencySnapshot(observableDependents),
      currentFrameID: currentFrameID,
      liveIdentities: liveIdentities
    )
  }

  package func invalidate(_ identities: Set<Identity>) {
    ViewGraphInvalidationPlanner.invalidate(
      identities,
      invalidatedIdentities: &invalidatedIdentities,
      nodesByIdentity: nodesByIdentity
    )
  }

  /// Returns the graph node for the given identity, if any.
  ///
  /// Used by view modifiers such as ``ValueAnimationModifier`` that need
  /// to reach into per-node state slot storage without triggering
  /// invalidation.
  package func nodeForIdentity(_ identity: Identity) -> ViewNode? {
    nodesByIdentity[identity]
  }

  package func containsNode(
    for identity: Identity
  ) -> Bool {
    nodesByIdentity[identity] != nil
  }

  /// Invalidates identities AND queues them as graph-local dirty so that
  /// `selectiveDirtyEvaluationPlan()` can include them in the dirty frontier
  /// instead of falling back to full root re-evaluation.  Only identities
  /// with existing graph nodes are queued.
  package func invalidateAndQueueDirty(_ identities: Set<Identity>) {
    ViewGraphInvalidationPlanner.invalidateAndQueueDirty(
      identities,
      invalidatedIdentities: &invalidatedIdentities,
      graphLocalDirtyIdentities: &graphLocalDirtyIdentities,
      nodesByIdentity: nodesByIdentity
    )
  }

  package func queueDirty(
    _ identities: Set<Identity>
  ) {
    ViewGraphInvalidationPlanner.queueDirty(
      identities,
      graphLocalDirtyIdentities: &graphLocalDirtyIdentities,
      nodesByIdentity: nodesByIdentity
    )
  }

  package func queueDirtyForStateChange(
    _ key: StateSlotKey
  ) {
    stateMutationKeys.insert(key)
    queueDirty(
      ViewGraphInvalidationPlanner.stateChangeDirtyIdentities(
        for: key,
        stateSlotDependents: stateSlotDependents
      )
    )
  }

  package func stateMutationOverlay() -> StateMutationOverlay {
    var stateSlots: [StateSlotKey: AnyStateSlot] = [:]
    for key in stateMutationKeys {
      guard
        let slot = nodesByIdentity[key.identity]?.stateSlotStorage(
          ordinal: key.ordinal
        )
      else {
        continue
      }
      stateSlots[key] = slot
    }
    return StateMutationOverlay(
      stateSlots: stateSlots,
      invalidatedIdentities: invalidatedIdentities,
      graphLocalDirtyIdentities: graphLocalDirtyIdentities,
      stateMutationKeys: stateMutationKeys
    )
  }

  package func applyStateMutationOverlay(
    _ overlay: StateMutationOverlay
  ) {
    for (key, slot) in overlay.stateSlots {
      guard let node = nodesByIdentity[key.identity] else {
        continue
      }
      node.restoreStateSlot(ordinal: key.ordinal, slot: slot)
      node.markDirty()
    }
    invalidatedIdentities.formUnion(overlay.invalidatedIdentities)
    graphLocalDirtyIdentities.formUnion(overlay.graphLocalDirtyIdentities)
    stateMutationKeys.formUnion(overlay.stateMutationKeys)
  }

  package func queueDirtyForObservationChange(
    observedBy identity: Identity
  ) {
    let dirtyIdentities =
      ViewGraphInvalidationPlanner.observationChangeDirtyIdentities(
        observedBy: identity,
        nodesByIdentity: nodesByIdentity,
        observableDependents: observableDependents
      )
    queueDirty(dirtyIdentities)
  }

  package func invalidateEnvironmentReaders(
    within identities: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>
  ) {
    let dirtyIdentities = ViewGraphInvalidationPlanner.environmentReaderDirtyIdentities(
      within: identities,
      changedKeys: changedKeys,
      environmentDependents: environmentDependents
    )
    guard !dirtyIdentities.isEmpty else {
      invalidate(identities)
      return
    }

    invalidatedIdentities.formUnion(dirtyIdentities)
    queueDirty(dirtyIdentities)
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

  package func recordRegistrationAlias(
    from aliasIdentity: Identity,
    to identity: Identity,
    resolvedKind: NodeKind
  ) {
    if let previousTarget = registrationAliasTargets[aliasIdentity],
      previousTarget != identity
    {
      registrationAliasesByIdentity[previousTarget]?.remove(aliasIdentity)
      if registrationAliasesByIdentity[previousTarget]?.isEmpty == true {
        registrationAliasesByIdentity.removeValue(forKey: previousTarget)
      }
    }

    if aliasIdentity == identity {
      registrationAliasTargets.removeValue(forKey: aliasIdentity)
      registrationAliasesByIdentity[identity]?.remove(aliasIdentity)
      if registrationAliasesByIdentity[identity]?.isEmpty == true {
        registrationAliasesByIdentity.removeValue(forKey: identity)
      }
      return
    }

    // Instrumentation for Item 7: record the divergence so the alias
    // layer's actual workload is observable.  This is the only place
    // in the codebase that reaches the "from != to" branch, so it's
    // the authoritative point of measurement.
    registrationAliasDiagnostics.record(
      from: aliasIdentity,
      to: identity,
      resolvedKind: resolvedKind
    )

    registrationAliasTargets[aliasIdentity] = identity
    registrationAliasesByIdentity[identity, default: []].insert(aliasIdentity)
  }

  package func recordLifecycleEvaluationOwner(
    target targetIdentity: Identity,
    owner ownerIdentity: Identity
  ) {
    if let previousOwner = lifecycleEvaluationOwnersByIdentity[targetIdentity],
      previousOwner != ownerIdentity
    {
      lifecycleEvaluationTargetsByOwner[previousOwner]?.remove(targetIdentity)
      if lifecycleEvaluationTargetsByOwner[previousOwner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: previousOwner)
      }
    }

    lifecycleEvaluationOwnersByIdentity[targetIdentity] = ownerIdentity
    lifecycleEvaluationTargetsByOwner[ownerIdentity, default: []].insert(targetIdentity)
    if lifecycleEvaluationTargetsRecordedByOwner[ownerIdentity] != nil {
      lifecycleEvaluationTargetsRecordedByOwner[ownerIdentity, default: []].insert(targetIdentity)
    }
  }

  package func taskDescriptorIdentityLabel<ID: Equatable>(
    for identity: Identity,
    value: ID
  ) -> String {
    if let slot = taskDescriptorIdentitySlots[identity],
      slot.matches(value)
    {
      return slot.label
    }

    nextTaskDescriptorIdentityToken &+= 1
    let label = "id:\(nextTaskDescriptorIdentityToken)"
    taskDescriptorIdentitySlots[identity] = TaskDescriptorIdentitySlot(
      label: label,
      value: value
    )
    return label
  }

  package func selectiveDirtyEvaluationPlan() -> DirtyEvaluationPlan? {
    guard
      let targetPlan = ViewGraphDirtyEvaluationPlanner.targetPlan(
        input: ViewGraphDirtyEvaluationPlanningInput(
          hasRoot: root != nil,
          invalidatedIdentities: invalidatedIdentities,
          graphLocalDirtyIdentities: graphLocalDirtyIdentities,
          nodesByIdentity: nodesByIdentity,
          lifecycleEvaluationOwnersByIdentity: lifecycleEvaluationOwnersByIdentity
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
      frontierIdentities: targetPlan.targetNodes.map(\.identity)
    )
  }

  /// Whether any identities are dirty and need evaluation this frame.
  package var hasDirtyWork: Bool {
    !invalidatedIdentities.isEmpty || !graphLocalDirtyIdentities.isEmpty
  }

  package func evaluateDirtyNodes(
    using plan: DirtyEvaluationPlan? = nil
  ) -> Bool {
    guard let plan = plan ?? selectiveDirtyEvaluationPlan() else {
      rootEvaluator?()
      if let evaluationRootIdentity {
        root = nodesByIdentity[evaluationRootIdentity]
      }
      return false
    }

    for identity in plan.frontierIdentities {
      nodesByIdentity[identity]?.evaluate()
    }
    if let evaluationRootIdentity {
      root = nodesByIdentity[evaluationRootIdentity]
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
      frameOrder.append(identity)
    }
    node.beginEvaluation(
      frameID: currentFrameID,
      invalidator: invalidator,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle
    )
    if node.isAtOutermostEvaluationDepth {
      lifecycleEvaluationTargetsRecordedByOwner[identity] = []
    }
    return node
  }

  package func setSuppressesStructuralLifecycle(
    _ suppressesStructuralLifecycle: Bool,
    for identity: Identity
  ) {
    nodesByIdentity[identity]?.setSuppressesStructuralLifecycle(suppressesStructuralLifecycle)
  }

  package func finishEvaluation(
    _ node: ViewNode,
    resolved: ResolvedNode,
    accessedStateSlots: Int
  ) {
    let previousDependencies = node.dependencies
    let previousResolvedIdentity = node.resolvedIdentity
    guard node.finishEvaluation(accessedStateSlots: accessedStateSlots) else {
      return
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
    let childNodes = resolved.children.map { child in
      nodeForIdentity(for: child.identity)
    }
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
    node.apply(
      resolved: resolved,
      children: childNodes
    )
    reindexDependencies(
      for: node,
      previous: previousDependencies
    )

    let emitsOwnLifecycleEvents = nodeEmitsOwnLifecycleEvents(node)

    if node.wasPresentAtFrameStart {
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task,
        emitsOwnLifecycleEvents
      {
        appendTaskCancelEvent(
          identity: previousResolvedIdentity,
          task: previousTask,
          isStructural: false
        )
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        emitsOwnLifecycleEvents
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
  }

  package func installLayoutDependentChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
    guard let node = nodesByIdentity[identity] else {
      return
    }

    var resolved = node.snapshot()
    resolved.children = children
    let childNodes = children.map { child in
      nodeForIdentity(for: child.identity)
    }
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
    node.apply(
      resolved: resolved,
      children: childNodes
    )
  }

  package func prepareStructuralChildren(
    for identity: Identity,
    children: [ResolvedNode]
  ) {
    guard let node = nodesByIdentity[identity] else {
      return
    }

    var resolved = node.snapshot()
    resolved.children = children
    applyStructuralChildDiff(
      for: node,
      resolved: resolved
    )
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
    guard let previousResolvedRoot = nodesByIdentity[previousResolvedIdentity] else {
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
    let staleNodes = nodesByIdentity.values
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
      guard nodesByIdentity[node.identity] != nil else {
        continue
      }
      removeSubtree(rootedAt: node)
    }
  }

  package func recordReusedSubtree(
    _ subtree: ResolvedNode,
    invalidator: (any Invalidating)?
  ) {
    let node = nodeForIdentity(for: subtree.identity)
    node.prepareForFrame(currentFrameID)

    if node.wasVisitedThisFrame {
      return
    }
    frameOrder.append(subtree.identity)
    node.beginReuse(
      frameID: currentFrameID,
      invalidator: invalidator
    )
    let previousResolvedIdentity = node.resolvedIdentity
    let childNodes = subtree.children.map { child -> ViewNode in
      recordReusedSubtree(
        child,
        invalidator: invalidator
      )
      return nodeForIdentity(for: child.identity)
    }
    applyStructuralChildDiff(
      for: node,
      resolved: subtree
    )
    node.apply(
      resolved: subtree,
      children: childNodes
    )
    let emitsOwnLifecycleEvents = nodeEmitsOwnLifecycleEvents(node)

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
        appendTaskCancelEvent(
          identity: previousResolvedIdentity,
          task: previousTask,
          isStructural: false
        )
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        emitsOwnLifecycleEvents
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
    guard let node = nodesByIdentity[identity] else {
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
        invalidator: invalidator
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
      invalidator: invalidator
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
      self.root = nodesByIdentity[rootIdentity]
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
    root = nodesByIdentity[rootIdentity]

    for identity in frameOrder {
      guard let node = nodesByIdentity[identity] else {
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
    viewportLifecycleNodesByIdentity = lifecyclePlan.viewportLifecycleNodesByIdentity
    viewportLifecycleOrder = lifecyclePlan.viewportLifecycleOrder

    liveIdentities.formUnion(frameOrder)
    invalidatedIdentities.removeAll(keepingCapacity: true)
    graphLocalDirtyIdentities.removeAll(keepingCapacity: true)
    stateMutationKeys.removeAll(keepingCapacity: true)
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
    guard let root = nodesByIdentity[rootIdentity] else {
      fatalError("View graph has no node for root identity \(rootIdentity).")
    }
    self.root = root
    return root.snapshot()
  }

  package func dependencies(
    for identity: Identity
  ) -> DependencySet? {
    nodesByIdentity[identity]?.dependencies
  }

  package func stateDependentIdentities(
    for key: StateSlotKey
  ) -> Set<Identity> {
    stateSlotDependents[key] ?? []
  }

  package func environmentDependentIdentities(
    for key: ObjectIdentifier
  ) -> Set<Identity> {
    environmentDependents[key] ?? []
  }

  package func observableDependentIdentities(
    for key: ObjectIdentifier
  ) -> Set<Identity> {
    observableDependents[key] ?? []
  }

  package func liveIdentitySnapshot() -> Set<Identity> {
    liveIdentities
  }

  package func restoreRuntimeRegistrations(
    for resolved: ResolvedNode,
    into registrations: RuntimeRegistrationSet
  ) {
    ViewGraphRuntimeRegistrationRestorer.restoreResolvedSubtree(
      resolved,
      into: registrations,
      nodesByIdentity: nodesByIdentity,
      registrationAliasesByIdentity: registrationAliasesByIdentity
    )
  }

  package func restoreCurrentFrameRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    ViewGraphRuntimeRegistrationRestorer.restoreLiveIdentities(
      liveIdentities,
      into: registrations,
      nodesByIdentity: nodesByIdentity
    )
  }

  private func pruneLifecycleEvaluationOwners(
    ownedBy ownerIdentity: Identity
  ) {
    guard
      let recordedTargets = lifecycleEvaluationTargetsRecordedByOwner.removeValue(
        forKey: ownerIdentity
      )
    else {
      return
    }
    guard let targets = lifecycleEvaluationTargetsByOwner[ownerIdentity] else {
      return
    }
    let staleTargets = targets.subtracting(recordedTargets)
    for target in staleTargets {
      lifecycleEvaluationOwnersByIdentity.removeValue(forKey: target)
    }
    if recordedTargets.isEmpty {
      lifecycleEvaluationTargetsByOwner.removeValue(forKey: ownerIdentity)
    } else {
      lifecycleEvaluationTargetsByOwner[ownerIdentity] = recordedTargets
    }
  }

  private func nodeEmitsOwnLifecycleEvents(
    _ node: ViewNode
  ) -> Bool {
    let ownerIdentity = lifecycleEvaluationOwnersByIdentity[node.identity]
    return ViewGraphLifecycleEventCollector.nodeEmitsOwnLifecycleEvents(
      node,
      ownerIdentity: ownerIdentity,
      ownerExists: ownerIdentity.map { nodesByIdentity[$0] != nil } ?? false
    )
  }

  private func appendTaskCancelEvent(
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool
  ) {
    ViewGraphLifecycleEventCollector.appendTaskCancelEvent(
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
      guard let invalidatedNode = nodesByIdentity[invalidatedIdentity] else {
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
    if let existing = nodesByIdentity[identity] {
      return existing
    }

    let node = ViewNode(identity: identity)
    node.ownerGraph = self
    nodesByIdentity[identity] = node
    return node
  }

  private func applyStructuralChildDiff(
    for node: ViewNode,
    resolved: ResolvedNode
  ) {
    let plan = ViewGraphStructuralReconciler.removalPlan(
      oldChildDescriptors: node.childDescriptors,
      currentChildCount: node.children.count,
      committedChildren: node.committed.children,
      newChildren: resolved.children
    )

    for removal in plan.removedChildren {
      guard node.children.indices.contains(removal.oldIndex)
      else {
        continue
      }

      removeSubtree(
        rootedAt: node.children[removal.oldIndex],
        committedSnapshot: removal.committedSnapshot
      )
    }
  }

  private func removeSubtree(
    rootedAt node: ViewNode,
    committedSnapshot: ResolvedNode? = nil
  ) {
    guard let current = nodesByIdentity[node.identity],
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
    liveIdentities.remove(node.identity)

    if let owner = lifecycleEvaluationOwnersByIdentity.removeValue(forKey: node.identity) {
      lifecycleEvaluationTargetsByOwner[owner]?.remove(node.identity)
      if lifecycleEvaluationTargetsByOwner[owner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: owner)
      }
    }
    if let targets = lifecycleEvaluationTargetsByOwner.removeValue(forKey: node.identity) {
      for target in targets {
        lifecycleEvaluationOwnersByIdentity.removeValue(forKey: target)
      }
    }

    if let target = registrationAliasTargets.removeValue(forKey: node.identity) {
      registrationAliasesByIdentity[target]?.remove(node.identity)
      if registrationAliasesByIdentity[target]?.isEmpty == true {
        registrationAliasesByIdentity.removeValue(forKey: target)
      }
    }
    registrationAliasesByIdentity.removeValue(forKey: node.identity)
    taskDescriptorIdentitySlots.removeValue(forKey: node.identity)
    nodesByIdentity.removeValue(forKey: node.identity)
  }

  private func removeResolvedSubtree(
    _ resolved: ResolvedNode
  ) {
    if let node = nodesByIdentity[resolved.identity] {
      removeSubtree(
        rootedAt: node,
        committedSnapshot: resolved
      )
      return
    }

    let aliasNodes = (registrationAliasesByIdentity[resolved.identity] ?? [])
      .compactMap { nodesByIdentity[$0] }
      .sorted { $0.identity < $1.identity }
    if let node = aliasNodes.first {
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
      identity: node.identity,
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
      identity: node.identity,
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
      nodesByIdentity: nodesByIdentity,
      frameOrder: frameOrder,
      viewportLifecycleNodesByIdentity: viewportLifecycleNodesByIdentity,
      viewportLifecycleOrder: viewportLifecycleOrder,
      stableTaskCancelEvents: stableTaskCancelEvents,
      stableTaskStartEvents: stableTaskStartEvents,
      structuralAppearEvents: structuralAppearEvents,
      structuralTaskCancelEvents: structuralTaskCancelEvents,
      structuralDisappearEvents: structuralDisappearEvents
    )
  }
}

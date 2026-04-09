package struct LifecycleStateNode: Equatable, Sendable {
  var identity: Identity
  var appearHandlerIDs: [String]
  var disappearHandlerIDs: [String]
  var task: TaskDescriptor?
}

package struct DirtyEvaluationPlan: Equatable, Sendable {
  package let frontierIdentities: [Identity]
}

@MainActor
package final class ViewGraph {
  package private(set) var root: ViewNode?

  private var nodesByIdentity: [Identity: ViewNode]
  private var rootEvaluator: (@MainActor () -> Void)?
  private var evaluationRootIdentity: Identity?
  private var viewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode]
  private var viewportLifecycleOrder: [Identity]
  private var frameOrder: [Identity]
  private var stableTaskCancelEvents: [LifecycleEvent]
  private var stableTaskStartIdentities: [Identity]
  private var structuralAppearEvents: [LifecycleEvent]
  private var structuralTaskCancelEvents: [LifecycleEvent]
  private var structuralDisappearEvents: [LifecycleEvent]
  private var invalidatedIdentities: Set<Identity>
  private var graphLocalDirtyIdentities: Set<Identity>
  private var latestLifecycleEvents: [LifecycleEvent]
  private var registrationAliasesByIdentity: [Identity: Set<Identity>]
  private var registrationAliasTargets: [Identity: Identity]
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
    stableTaskStartIdentities = []
    structuralAppearEvents = []
    structuralTaskCancelEvents = []
    structuralDisappearEvents = []
    invalidatedIdentities = []
    graphLocalDirtyIdentities = []
    latestLifecycleEvents = []
    registrationAliasesByIdentity = [:]
    registrationAliasTargets = [:]
    stateSlotDependents = [:]
    environmentDependents = [:]
    observableDependents = [:]
    currentFrameID = 0
    liveIdentities = []
  }

  package func invalidate(_ identities: Set<Identity>) {
    invalidatedIdentities.formUnion(identities)
    for identity in identities {
      nodesByIdentity[identity]?.markDirty()
    }
  }

  /// Returns the graph node for the given identity, if any.
  ///
  /// Used by view modifiers such as ``ValueAnimationModifier`` that need
  /// to reach into per-node state slot storage without triggering
  /// invalidation.
  package func nodeForIdentity(_ identity: Identity) -> ViewNode? {
    nodesByIdentity[identity]
  }

  /// Invalidates identities AND queues them as graph-local dirty so that
  /// `selectiveDirtyEvaluationPlan()` can include them in the dirty frontier
  /// instead of falling back to full root re-evaluation.  Only identities
  /// with existing graph nodes are queued.
  package func invalidateAndQueueDirty(_ identities: Set<Identity>) {
    invalidatedIdentities.formUnion(identities)
    for identity in identities {
      if let node = nodesByIdentity[identity] {
        node.markDirty()
        graphLocalDirtyIdentities.insert(identity)
      }
    }
  }

  package func queueDirty(
    _ identities: Set<Identity>
  ) {
    graphLocalDirtyIdentities.formUnion(identities)
    for identity in identities {
      nodesByIdentity[identity]?.markDirty()
    }
  }

  package func queueDirtyForStateChange(
    _ key: StateSlotKey
  ) {
    queueDirty(Set([key.identity]).union(stateSlotDependents[key] ?? []))
  }

  package func queueDirtyForObservationChange(
    observedBy identity: Identity
  ) {
    let dirtyIdentities =
      Set([identity]).union(observableDependencyIdentities(triggeredBy: identity))
    queueDirty(dirtyIdentities)
  }

  package func invalidateEnvironmentReaders(
    within identities: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>
  ) {
    let dirtyIdentities = environmentDependencyIdentities(
      within: identities,
      changedKeys: changedKeys
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
    to identity: Identity
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

    registrationAliasTargets[aliasIdentity] = identity
    registrationAliasesByIdentity[identity, default: []].insert(aliasIdentity)
  }

  package func selectiveDirtyEvaluationPlan() -> DirtyEvaluationPlan? {
    guard root != nil,
      !graphLocalDirtyIdentities.isEmpty,
      !invalidatedIdentities.isEmpty
    else {
      return nil
    }

    // Every invalidated identity that has a node in the graph must be
    // tracked as graph-local dirty.  Identities without graph nodes
    // (e.g. scheduler-provided identities for views not yet rendered)
    // cannot produce a dirty frontier and are safe to ignore.
    let graphKnownInvalidated = invalidatedIdentities.filter {
      nodesByIdentity[$0] != nil
    }
    guard graphKnownInvalidated.isSubset(of: graphLocalDirtyIdentities) else {
      return nil
    }

    let dirtyFrontier = dirtyFrontierNodes()

    if dirtyFrontier.isEmpty {
      return nil
    }

    // Promote frontier nodes without evaluators to their nearest ancestor
    // that has one.  This is safe because the caller has already verified
    // that the view builder's state and environment haven't changed, so
    // ancestor evaluators (including root) hold valid captured content.
    var promotedFrontier: [ViewNode] = []
    var promotedIdentities: Set<Identity> = []
    for node in dirtyFrontier {
      let target = node.hasEvaluator ? node : nearestEvaluatorAncestor(of: node)
      guard let target, promotedIdentities.insert(target.identity).inserted else {
        continue
      }
      target.markDirty()
      promotedFrontier.append(target)
    }

    guard !promotedFrontier.isEmpty, promotedFrontier.allSatisfy(\.hasEvaluator) else {
      return nil
    }

    return DirtyEvaluationPlan(
      frontierIdentities: promotedFrontier.map(\.identity)
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
    stableTaskStartIdentities.removeAll(keepingCapacity: true)
    structuralAppearEvents.removeAll(keepingCapacity: true)
    structuralTaskCancelEvents.removeAll(keepingCapacity: true)
    structuralDisappearEvents.removeAll(keepingCapacity: true)
    latestLifecycleEvents.removeAll(keepingCapacity: true)
  }

  package func beginEvaluation(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) -> ViewNode {
    let node = nodeForIdentity(for: identity)
    node.prepareForFrame(currentFrameID)
    if !node.wasVisitedThisFrame {
      frameOrder.append(identity)
    }
    node.beginEvaluation(
      frameID: currentFrameID,
      invalidator: invalidator
    )
    return node
  }

  package func finishEvaluation(
    _ node: ViewNode,
    resolved: ResolvedNode,
    accessedStateSlots: Int
  ) {
    let previousDependencies = node.dependencies
    guard node.finishEvaluation(accessedStateSlots: accessedStateSlots) else {
      return
    }

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

    if node.wasPresentAtFrameStart {
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task,
        node.participatesInStructuralLifecycle
      {
        stableTaskCancelEvents.append(
          .init(
            identity: node.identity,
            operation: .taskCancel(previousTask)
          )
        )
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        node.participatesInStructuralLifecycle
      {
        stableTaskStartIdentities.append(node.identity)
      }
      node.setLifecycleState(.alive)
    } else {
      if node.participatesInStructuralLifecycle,
        !node.lifecycleMetadata.appearHandlerIDs.isEmpty
      {
        structuralAppearEvents.append(
          .init(
            identity: node.identity,
            operation: .appear(handlerIDs: node.lifecycleMetadata.appearHandlerIDs)
          )
        )
      }
      if node.participatesInStructuralLifecycle,
        node.lifecycleMetadata.task != nil
      {
        stableTaskStartIdentities.append(node.identity)
      }
      node.setLifecycleState(.appearing)
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
    if !node.wasPresentAtFrameStart {
      if node.participatesInStructuralLifecycle,
        !node.lifecycleMetadata.appearHandlerIDs.isEmpty
      {
        structuralAppearEvents.append(
          .init(
            identity: node.identity,
            operation: .appear(handlerIDs: node.lifecycleMetadata.appearHandlerIDs)
          )
        )
      }
      if node.participatesInStructuralLifecycle,
        node.lifecycleMetadata.task != nil
      {
        stableTaskStartIdentities.append(node.identity)
      }
      node.setLifecycleState(.appearing)
    } else {
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task,
        node.participatesInStructuralLifecycle
      {
        stableTaskCancelEvents.append(
          .init(
            identity: node.identity,
            operation: .taskCancel(previousTask)
          )
        )
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task,
        node.participatesInStructuralLifecycle
      {
        stableTaskStartIdentities.append(node.identity)
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

    guard node.canReuse(
      frameID: currentFrameID,
      environment: environment,
      transaction: transaction
    ) else {
      return nil
    }

    let invalidationSummary = invalidationSummary
      ?? .init(invalidatedIdentities: invalidatedIdentities)
    if !invalidationSummary.intersectsSubtree(at: identity) {
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
    }
    guard !conflictsWithInvalidation else {
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

    let viewportLifecycleEvents = viewportLifecycleEvents(
      from: resolved,
      placed: placed
    )
    let (viewportTaskCancels, viewportDisappears, viewportAppears, viewportTaskStarts) =
      partitionLifecycleEvents(viewportLifecycleEvents)
    let structuralTaskStarts = stableTaskStartIdentities.compactMap { identity -> LifecycleEvent? in
      guard let task = nodesByIdentity[identity]?.lifecycleMetadata.task else {
        return nil
      }
      return .init(
        identity: identity,
        operation: .taskStart(task)
      )
    }

    latestLifecycleEvents =
      stableTaskCancelEvents
      + structuralTaskCancelEvents
      + viewportTaskCancels
      + structuralDisappearEvents
      + viewportDisappears
      + structuralAppearEvents
      + viewportAppears
      + structuralTaskStarts
      + viewportTaskStarts

    liveIdentities.formUnion(frameOrder)
    invalidatedIdentities.removeAll(keepingCapacity: true)
    graphLocalDirtyIdentities.removeAll(keepingCapacity: true)
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
    restoreRuntimeRegistrations(
      for: resolved,
      registrations: registrations
    )
  }

  private func restoreRuntimeRegistrations(
    for resolved: ResolvedNode,
    registrations: RuntimeRegistrationSet
  ) {
    guard let node = nodesByIdentity[resolved.identity] else {
      return
    }

    node.restoreOwnRuntimeRegistrations(
      into: registrations
    )
    for aliasIdentity in registrationAliasesByIdentity[resolved.identity] ?? [] {
      nodesByIdentity[aliasIdentity]?.restoreOwnRuntimeRegistrations(
        into: registrations
      )
    }

    for child in resolved.children {
      restoreRuntimeRegistrations(
        for: child,
        registrations: registrations
      )
    }
  }

  private func nearestEvaluatorAncestor(
    of node: ViewNode
  ) -> ViewNode? {
    var current = node.parent
    var visited: Set<ObjectIdentifier> = []
    while let ancestor = current {
      let id = ObjectIdentifier(ancestor)
      guard visited.insert(id).inserted else {
        return nil
      }
      if ancestor.hasEvaluator {
        return ancestor
      }
      current = ancestor.parent
    }
    return nil
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

  private func dirtyFrontierNodes() -> [ViewNode] {
    var frontier: [ViewNode] = []
    var frontierIdentities: Set<Identity> = []

    for identity in graphLocalDirtyIdentities {
      guard let node = nodesByIdentity[identity], node.isDirty else {
        continue
      }

      var ancestor = node.parent
      var hasDirtyAncestor = false
      var visitedAncestors: Set<ObjectIdentifier> = []

      while let current = ancestor {
        let currentID = ObjectIdentifier(current)
        guard visitedAncestors.insert(currentID).inserted else {
          break
        }
        if current.isDirty {
          hasDirtyAncestor = true
          break
        }
        ancestor = current.parent
      }

      guard !hasDirtyAncestor,
        frontierIdentities.insert(node.identity).inserted
      else {
        continue
      }

      frontier.append(node)
    }

    return frontier.sorted { lhs, rhs in
      if lhs.identity.components.count == rhs.identity.components.count {
        return lhs.identity < rhs.identity
      }
      return lhs.identity.components.count < rhs.identity.components.count
    }
  }

  private func applyStructuralChildDiff(
    for node: ViewNode,
    resolved: ResolvedNode
  ) {
    let operations = diffChildren(
      old: node.childDescriptors,
      new: resolved.children.map(ChildDescriptor.init)
    )

    for operation in operations {
      guard case .removed(let oldIndex) = operation,
        node.children.indices.contains(oldIndex)
      else {
        continue
      }

      removeSubtree(
        rootedAt: node.children[oldIndex]
      )
    }
  }

  private func removeSubtree(
    rootedAt node: ViewNode
  ) {
    node.prepareForFrame(currentFrameID)

    for child in node.children {
      removeSubtree(rootedAt: child)
    }

    if node.participatesInStructuralLifecycle,
      let task = node.previousLifecycleMetadata.task
    {
      structuralTaskCancelEvents.append(
        .init(
          identity: node.identity,
          operation: .taskCancel(task)
        )
      )
    }
    if node.participatesInStructuralLifecycle,
      !node.previousLifecycleMetadata.disappearHandlerIDs.isEmpty
    {
      structuralDisappearEvents.append(
        .init(
          identity: node.identity,
          operation: .disappear(
            handlerIDs: node.previousLifecycleMetadata.disappearHandlerIDs
          )
        )
      )
    }

    node.setLifecycleState(.disappearing)
    node.setCommittedPresence(false)
    node.parent = nil
    removeDependencyEdges(for: node)
    liveIdentities.remove(node.identity)

    if let target = registrationAliasTargets.removeValue(forKey: node.identity) {
      registrationAliasesByIdentity[target]?.remove(node.identity)
      if registrationAliasesByIdentity[target]?.isEmpty == true {
        registrationAliasesByIdentity.removeValue(forKey: target)
      }
    }
    registrationAliasesByIdentity.removeValue(forKey: node.identity)
    nodesByIdentity.removeValue(forKey: node.identity)
  }

  private func reindexDependencies(
    for node: ViewNode,
    previous: DependencySet
  ) {
    removeDependencyEdges(
      for: node.identity,
      dependencies: previous
    )
    insertDependencyEdges(
      for: node.identity,
      dependencies: node.dependencies
    )
  }

  private func removeDependencyEdges(
    for node: ViewNode
  ) {
    removeDependencyEdges(
      for: node.identity,
      dependencies: node.dependencies
    )
  }

  private func removeDependencyEdges(
    for identity: Identity,
    dependencies: DependencySet
  ) {
    for key in dependencies.stateSlotReads {
      stateSlotDependents[key]?.remove(identity)
      if stateSlotDependents[key]?.isEmpty == true {
        stateSlotDependents.removeValue(forKey: key)
      }
    }
    for key in dependencies.environmentReads {
      environmentDependents[key]?.remove(identity)
      if environmentDependents[key]?.isEmpty == true {
        environmentDependents.removeValue(forKey: key)
      }
    }
    for key in dependencies.observableReads {
      observableDependents[key]?.remove(identity)
      if observableDependents[key]?.isEmpty == true {
        observableDependents.removeValue(forKey: key)
      }
    }
  }

  private func insertDependencyEdges(
    for identity: Identity,
    dependencies: DependencySet
  ) {
    for key in dependencies.stateSlotReads {
      stateSlotDependents[key, default: []].insert(identity)
    }
    for key in dependencies.environmentReads {
      environmentDependents[key, default: []].insert(identity)
    }
    for key in dependencies.observableReads {
      observableDependents[key, default: []].insert(identity)
    }
  }

  private func observableDependencyIdentities(
    triggeredBy identity: Identity
  ) -> Set<Identity> {
    guard let dependencies = nodesByIdentity[identity]?.dependencies,
      !dependencies.observableReads.isEmpty
    else {
      return []
    }

    return dependencies.observableReads.reduce(into: Set<Identity>()) { partial, key in
      partial.formUnion(observableDependents[key] ?? [])
    }
  }

  private func environmentDependencyIdentities(
    within roots: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>
  ) -> Set<Identity> {
    changedKeys.reduce(into: Set<Identity>()) { partial, key in
      let dependents = environmentDependents[key] ?? []
      partial.formUnion(
        dependents.filter { dependent in
          roots.contains { root in
            dependent == root || dependent.isDescendant(of: root)
          }
        }
      )
    }
  }

  private func collectViewportLifecycleEvents(
    from resolved: ResolvedNode,
    placed: PlacedNode?,
    seenIdentities: inout Set<Identity>,
    order: inout [Identity],
    taskCancels: inout [LifecycleEvent],
    appears: inout [LifecycleEvent],
    taskStarts: inout [LifecycleEvent]
  ) {
    if resolved.usesIndexedChildSource,
      let placed
    {
      recordViewportLifecycleVisibility(
        of: placed,
        seenIdentities: &seenIdentities,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
      return
    }

    for (index, child) in resolved.children.enumerated() {
      collectViewportLifecycleEvents(
        from: child,
        placed: placed?.children.indices.contains(index) == true
          ? placed?.children[index]
          : nil,
        seenIdentities: &seenIdentities,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }

  private func viewportLifecycleEvents(
    from resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
    var seenIdentities: Set<Identity> = []
    var order: [Identity] = []
    var taskCancels: [LifecycleEvent] = []
    var disappears: [LifecycleEvent] = []
    var appears: [LifecycleEvent] = []
    var taskStarts: [LifecycleEvent] = []

    collectViewportLifecycleEvents(
      from: resolved,
      placed: placed,
      seenIdentities: &seenIdentities,
      order: &order,
      taskCancels: &taskCancels,
      appears: &appears,
      taskStarts: &taskStarts
    )

    for identity in viewportLifecycleOrder.reversed() where !seenIdentities.contains(identity) {
      guard let previousNode = viewportLifecycleNodesByIdentity.removeValue(forKey: identity) else {
        continue
      }
      if let task = previousNode.task {
        taskCancels.append(
          .init(
            identity: previousNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
      if !previousNode.disappearHandlerIDs.isEmpty {
        disappears.append(
          .init(
            identity: previousNode.identity,
            operation: .disappear(handlerIDs: previousNode.disappearHandlerIDs)
          )
        )
      }
    }

    viewportLifecycleOrder = order
    return taskCancels + disappears + appears + taskStarts
  }

  private func partitionLifecycleEvents(
    _ events: [LifecycleEvent]
  ) -> (
    taskCancels: [LifecycleEvent],
    disappears: [LifecycleEvent],
    appears: [LifecycleEvent],
    taskStarts: [LifecycleEvent]
  ) {
    var taskCancels: [LifecycleEvent] = []
    var disappears: [LifecycleEvent] = []
    var appears: [LifecycleEvent] = []
    var taskStarts: [LifecycleEvent] = []

    for event in events {
      switch event.operation {
      case .taskCancel:
        taskCancels.append(event)
      case .disappear:
        disappears.append(event)
      case .appear:
        appears.append(event)
      case .taskStart:
        taskStarts.append(event)
      }
    }

    return (
      taskCancels,
      disappears,
      appears,
      taskStarts
    )
  }

  private func recordViewportLifecycleVisibility(
    of node: PlacedNode,
    seenIdentities: inout Set<Identity>,
    order: inout [Identity],
    taskCancels: inout [LifecycleEvent],
    appears: inout [LifecycleEvent],
    taskStarts: inout [LifecycleEvent]
  ) {
    if !node.lifecycleMetadata.isEmpty {
      let currentNode = LifecycleStateNode(
        identity: node.identity,
        appearHandlerIDs: node.lifecycleMetadata.appearHandlerIDs,
        disappearHandlerIDs: node.lifecycleMetadata.disappearHandlerIDs,
        task: node.lifecycleMetadata.task
      )
      let previousNode = viewportLifecycleNodesByIdentity[node.identity]
      seenIdentities.insert(node.identity)
      order.append(node.identity)

      if previousNode == nil, !currentNode.appearHandlerIDs.isEmpty {
        appears.append(
          .init(
            identity: currentNode.identity,
            operation: .appear(handlerIDs: currentNode.appearHandlerIDs)
          )
        )
      }
      if previousNode?.task != currentNode.task, let task = previousNode?.task {
        taskCancels.append(
          .init(
            identity: currentNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
      if previousNode?.task != currentNode.task, let task = currentNode.task {
        taskStarts.append(
          .init(
            identity: currentNode.identity,
            operation: .taskStart(task)
          )
        )
      }

      viewportLifecycleNodesByIdentity[node.identity] = currentNode
    }

    for child in node.children {
      recordViewportLifecycleVisibility(
        of: child,
        seenIdentities: &seenIdentities,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }
}

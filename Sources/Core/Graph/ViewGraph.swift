package struct LifecycleStateNode: Equatable, Sendable {
  var identity: Identity
  var appearHandlerIDs: [String]
  var disappearHandlerIDs: [String]
  var task: TaskDescriptor?
}

private struct LifecycleStateSnapshot: Equatable {
  var nodes: [LifecycleStateNode]

  init(nodes: [LifecycleStateNode] = []) {
    self.nodes = nodes
  }
}

@MainActor
package final class ViewGraph {
  package private(set) var root: ViewNode?

  private var nodesByIdentity: [Identity: ViewNode]
  private var rootEvaluator: (@MainActor () -> Void)?
  private var evaluationRootIdentity: Identity?
  private var committedViewportLifecycleState: LifecycleStateSnapshot
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

  package init() {
    nodesByIdentity = [:]
    rootEvaluator = nil
    evaluationRootIdentity = nil
    committedViewportLifecycleState = .init()
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
  }

  package func invalidate(_ identities: Set<Identity>) {
    invalidatedIdentities.formUnion(identities)
    for identity in identities {
      nodesByIdentity[identity]?.markDirty()
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

  package func evaluateDirtyNodes() -> Bool {
    let canEvaluateDirtyFrontier =
      !graphLocalDirtyIdentities.isEmpty
      && !invalidatedIdentities.isEmpty
      && invalidatedIdentities.isSubset(of: graphLocalDirtyIdentities)

    if root == nil || !canEvaluateDirtyFrontier {
      rootEvaluator?()
      if let evaluationRootIdentity {
        root = nodesByIdentity[evaluationRootIdentity]
      }
      return false
    }

    let dirtyFrontier = nodesByIdentity.values
      .filter { $0.isDirty && !$0.hasDirtyAncestor }
      .sorted { lhs, rhs in
        if lhs.identity.components.count == rhs.identity.components.count {
          return lhs.identity < rhs.identity
        }
        return lhs.identity.components.count < rhs.identity.components.count
      }

    if dirtyFrontier.isEmpty {
      if let evaluationRootIdentity {
        root = nodesByIdentity[evaluationRootIdentity]
      }
      return false
    }

    let reevaluationPlan = selectiveReevaluationPlan(
      for: dirtyFrontier
    )

    let reevaluatesRootDirectly = dirtyFrontier.contains { $0.identity == evaluationRootIdentity }

    if reevaluationPlan == nil || reevaluatesRootDirectly {
      rootEvaluator?()
      if let evaluationRootIdentity {
        root = nodesByIdentity[evaluationRootIdentity]
      }
      return false
    } else {
      for node in reevaluationPlan ?? [] {
        node.evaluate()
      }
    }
    if let evaluationRootIdentity {
      root = nodesByIdentity[evaluationRootIdentity]
    }
    return true
  }

  package func beginFrame() {
    frameOrder.removeAll(keepingCapacity: true)
    stableTaskCancelEvents.removeAll(keepingCapacity: true)
    stableTaskStartIdentities.removeAll(keepingCapacity: true)
    structuralAppearEvents.removeAll(keepingCapacity: true)
    structuralTaskCancelEvents.removeAll(keepingCapacity: true)
    structuralDisappearEvents.removeAll(keepingCapacity: true)
    latestLifecycleEvents.removeAll(keepingCapacity: true)

    for node in nodesByIdentity.values {
      node.prepareForFrame()
    }
  }

  package func beginEvaluation(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) -> ViewNode {
    let node = nodeForIdentity(for: identity)
    if !node.wasVisitedThisFrame {
      frameOrder.append(identity)
    }
    node.beginEvaluation(invalidator: invalidator)
    return node
  }

  package func finishEvaluation(
    _ node: ViewNode,
    resolved: ResolvedNode,
    accessedStateSlots: Int
  ) {
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
    if !node.wasVisitedThisFrame {
      frameOrder.append(subtree.identity)
    }
    node.beginReuse(invalidator: invalidator)
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

    let snapshot = node.snapshot()
    let conflictsWithInvalidation = invalidatedIdentities.contains { invalidatedIdentity in
      if invalidatedIdentity == identity {
        return true
      }
      if subtree(snapshot, contains: invalidatedIdentity) {
        return true
      }
      let invalidatedSubtreeContainsIdentity =
        nodesByIdentity[invalidatedIdentity].map { invalidatedNode in
          subtree(invalidatedNode.snapshot(), contains: identity)
        } ?? false
      return invalidatedSubtreeContainsIdentity
        || invalidatedIdentity.isDescendant(of: identity)
        || identity.isDescendant(of: invalidatedIdentity)
    }
    guard !conflictsWithInvalidation else {
      return nil
    }
    guard node.canReuse(
      environment: environment,
      transaction: transaction
    ) else {
      return nil
    }
    recordReusedSubtree(
      snapshot,
      invalidator: invalidator
    )
    return snapshot
  }

  private func subtree(
    _ node: ResolvedNode,
    contains identity: Identity
  ) -> Bool {
    if node.identity == identity {
      return true
    }

    for child in node.children where subtree(child, contains: identity) {
      return true
    }

    return false
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
      guard let node = nodesByIdentity[identity], !node.wasPresentAtFrameStart else {
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

  package func restoreRuntimeRegistrations(
    for resolved: ResolvedNode,
    into actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    hotkeyRegistry: HotkeyRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil
  ) {
    restoreRuntimeRegistrations(
      for: resolved,
      actionRegistry: actionRegistry,
      keyHandlerRegistry: keyHandlerRegistry,
      pointerHandlerRegistry: pointerHandlerRegistry,
      focusBindingRegistry: focusBindingRegistry,
      focusedValuesRegistry: focusedValuesRegistry,
      hotkeyRegistry: hotkeyRegistry,
      lifecycleRegistry: lifecycleRegistry,
      taskRegistry: taskRegistry,
      preferenceObservationRegistry: preferenceObservationRegistry
    )
  }

  private func restoreRuntimeRegistrations(
    for resolved: ResolvedNode,
    actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    hotkeyRegistry: HotkeyRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil
  ) {
    nodesByIdentity[resolved.identity]?.restoreOwnRuntimeRegistrations(
      into: actionRegistry,
      keyHandlerRegistry: keyHandlerRegistry,
      pointerHandlerRegistry: pointerHandlerRegistry,
      focusBindingRegistry: focusBindingRegistry,
      focusedValuesRegistry: focusedValuesRegistry,
      hotkeyRegistry: hotkeyRegistry,
      lifecycleRegistry: lifecycleRegistry,
      taskRegistry: taskRegistry,
      preferenceObservationRegistry: preferenceObservationRegistry
    )
    for aliasIdentity in registrationAliasesByIdentity[resolved.identity] ?? [] {
      nodesByIdentity[aliasIdentity]?.restoreOwnRuntimeRegistrations(
        into: actionRegistry,
        keyHandlerRegistry: keyHandlerRegistry,
        pointerHandlerRegistry: pointerHandlerRegistry,
        focusBindingRegistry: focusBindingRegistry,
        focusedValuesRegistry: focusedValuesRegistry,
        hotkeyRegistry: hotkeyRegistry,
        lifecycleRegistry: lifecycleRegistry,
        taskRegistry: taskRegistry,
        preferenceObservationRegistry: preferenceObservationRegistry
      )
    }

    for child in resolved.children {
      restoreRuntimeRegistrations(
        for: child,
        actionRegistry: actionRegistry,
        keyHandlerRegistry: keyHandlerRegistry,
        pointerHandlerRegistry: pointerHandlerRegistry,
        focusBindingRegistry: focusBindingRegistry,
        focusedValuesRegistry: focusedValuesRegistry,
        hotkeyRegistry: hotkeyRegistry,
        lifecycleRegistry: lifecycleRegistry,
        taskRegistry: taskRegistry,
        preferenceObservationRegistry: preferenceObservationRegistry
      )
    }
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

  private func selectiveReevaluationPlan(
    for dirtyFrontier: [ViewNode]
  ) -> [ViewNode]? {
    var plannedNodes: [ViewNode] = []
    var plannedNodeIDs: Set<ObjectIdentifier> = []

    for node in dirtyFrontier {
      guard let chain = evaluationChain(for: node) else {
        return nil
      }

      for chainedNode in chain {
        let nodeID = ObjectIdentifier(chainedNode)
        guard plannedNodeIDs.insert(nodeID).inserted else {
          continue
        }
        plannedNodes.append(chainedNode)
      }
    }

    return plannedNodes.sorted { lhs, rhs in
      let lhsDepth = lhs.identity.components.count
      let rhsDepth = rhs.identity.components.count
      if lhsDepth == rhsDepth {
        return lhs.identity < rhs.identity
      }
      return lhsDepth > rhsDepth
    }
  }

  private func evaluationChain(
    for node: ViewNode
  ) -> [ViewNode]? {
    var chain: [ViewNode] = []
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []

    while let currentNode = current {
      let nodeID = ObjectIdentifier(currentNode)
      guard visited.insert(nodeID).inserted else {
        return nil
      }
      guard currentNode.hasEvaluator else {
        return nil
      }

      chain.append(currentNode)
      if currentNode.identity == evaluationRootIdentity {
        return chain
      }

      current = currentNode.parent
    }

    return nil
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
    node.parent = nil

    if let target = registrationAliasTargets.removeValue(forKey: node.identity) {
      registrationAliasesByIdentity[target]?.remove(node.identity)
      if registrationAliasesByIdentity[target]?.isEmpty == true {
        registrationAliasesByIdentity.removeValue(forKey: target)
      }
    }
    registrationAliasesByIdentity.removeValue(forKey: node.identity)
    nodesByIdentity.removeValue(forKey: node.identity)
  }

  private func viewportLifecycleState(
    from resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> LifecycleStateSnapshot {
    var nodes: [LifecycleStateNode] = []
    collectViewportLifecycleNodes(
      from: resolved,
      placed: placed,
      into: &nodes
    )
    return .init(nodes: nodes)
  }

  private func collectViewportLifecycleNodes(
    from resolved: ResolvedNode,
    placed: PlacedNode?,
    into nodes: inout [LifecycleStateNode]
  ) {
    if resolved.usesIndexedChildSource,
      let placed
    {
      placed.collectLifecycleNodes(into: &nodes)
      return
    }

    for (index, child) in resolved.children.enumerated() {
      collectViewportLifecycleNodes(
        from: child,
        placed: placed?.children.indices.contains(index) == true
          ? placed?.children[index]
          : nil,
        into: &nodes
      )
    }
  }

  private func viewportLifecycleEvents(
    from resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> [LifecycleEvent] {
    let nextLifecycleState = viewportLifecycleState(
      from: resolved,
      placed: placed
    )
    let events = lifecycleDiff(
      previous: committedViewportLifecycleState,
      next: nextLifecycleState
    )
    committedViewportLifecycleState = nextLifecycleState
    return events
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

  private func lifecycleDiff(
    previous: LifecycleStateSnapshot,
    next: LifecycleStateSnapshot
  ) -> [LifecycleEvent] {
    let previousByIdentity = Dictionary(
      uniqueKeysWithValues: previous.nodes.map { ($0.identity, $0) }
    )
    let nextByIdentity = Dictionary(
      uniqueKeysWithValues: next.nodes.map { ($0.identity, $0) }
    )

    var events: [LifecycleEvent] = []

    for previousNode in previous.nodes.reversed() {
      guard let nextNode = nextByIdentity[previousNode.identity] else {
        if let task = previousNode.task {
          events.append(
            .init(
              identity: previousNode.identity,
              operation: .taskCancel(task)
            )
          )
        }
        if !previousNode.disappearHandlerIDs.isEmpty {
          events.append(
            .init(
              identity: previousNode.identity,
              operation: .disappear(handlerIDs: previousNode.disappearHandlerIDs)
            )
          )
        }
        continue
      }

      if previousNode.task != nextNode.task, let task = previousNode.task {
        events.append(
          .init(
            identity: previousNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
    }

    for nextNode in next.nodes {
      if previousByIdentity[nextNode.identity] == nil,
        !nextNode.appearHandlerIDs.isEmpty
      {
        events.append(
          .init(
            identity: nextNode.identity,
            operation: .appear(handlerIDs: nextNode.appearHandlerIDs)
          )
        )
      }
    }

    for nextNode in next.nodes {
      let previousTask = previousByIdentity[nextNode.identity]?.task
      if previousTask != nextNode.task, let task = nextNode.task {
        events.append(
          .init(
            identity: nextNode.identity,
            operation: .taskStart(task)
          )
        )
      }
    }

    return events
  }
}

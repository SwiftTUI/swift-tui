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
  private var committedLifecycleState: LifecycleStateSnapshot
  private var frameOrder: [Identity]
  private var stableTaskCancelEvents: [LifecycleEvent]
  private var stableTaskStartIdentities: [Identity]
  private var invalidatedIdentities: Set<Identity>
  private var previousRootIdentity: Identity?
  private var latestLifecycleEvents: [LifecycleEvent]

  package init() {
    nodesByIdentity = [:]
    committedLifecycleState = .init()
    frameOrder = []
    stableTaskCancelEvents = []
    stableTaskStartIdentities = []
    invalidatedIdentities = []
    previousRootIdentity = nil
    latestLifecycleEvents = []
  }

  package func invalidate(_ identities: Set<Identity>) {
    invalidatedIdentities.formUnion(identities)
    for identity in identities {
      nodesByIdentity[identity]?.isDirty = true
    }
  }

  package func evaluateDirtyNodes() {}

  package func beginFrame() {
    previousRootIdentity = root?.identity
    frameOrder.removeAll(keepingCapacity: true)
    stableTaskCancelEvents.removeAll(keepingCapacity: true)
    stableTaskStartIdentities.removeAll(keepingCapacity: true)
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
    node.finishEvaluation(accessedStateSlots: accessedStateSlots)

    let childNodes = resolved.children.map { child in
      nodeForIdentity(for: child.identity)
    }
    node.apply(
      resolved: resolved,
      children: childNodes
    )

    if node.wasPresentAtFrameStart {
      if let previousTask = node.previousLifecycleMetadata.task,
        previousTask != node.lifecycleMetadata.task
      {
        stableTaskCancelEvents.append(
          .init(
            identity: node.identity,
            operation: .taskCancel(previousTask)
          )
        )
      }
      if let currentTask = node.lifecycleMetadata.task,
        currentTask != node.previousLifecycleMetadata.task
      {
        stableTaskStartIdentities.append(node.identity)
      }
      node.setLifecycleState(.alive)
    } else {
      node.setLifecycleState(.appearing)
    }
  }

  package func recordReusedSubtree(
    _ subtree: ResolvedNode,
    invalidator: (any Invalidating)?
  ) {
    let node = beginEvaluation(
      identity: subtree.identity,
      invalidator: invalidator
    )
    let childNodes = subtree.children.map { child -> ViewNode in
      recordReusedSubtree(
        child,
        invalidator: invalidator
      )
      return nodeForIdentity(for: child.identity)
    }
    node.apply(
      resolved: subtree,
      children: childNodes
    )
    if !node.wasPresentAtFrameStart {
      node.setLifecycleState(.appearing)
    } else {
      node.setLifecycleState(.alive)
    }
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
    let rootIdentity = resolved.identity
    root = nodesByIdentity[rootIdentity]

    var removedIdentities: Set<Identity> = []
    if let previousRootIdentity {
      collectRemovedIdentities(
        from: previousRootIdentity,
        removedIdentities: &removedIdentities
      )
    }

    for identity in removedIdentities {
      nodesByIdentity.removeValue(forKey: identity)
    }

    for identity in frameOrder {
      guard let node = nodesByIdentity[identity], !node.wasPresentAtFrameStart else {
        continue
      }
      node.setLifecycleState(.alive)
    }

    let nextLifecycleState = lifecycleState(
      from: resolved,
      placed: placed
    )
    latestLifecycleEvents = lifecycleDiff(
      previous: committedLifecycleState,
      next: nextLifecycleState
    )
    committedLifecycleState = nextLifecycleState

    invalidatedIdentities.removeAll(keepingCapacity: true)
    return latestLifecycleEvents
  }

  package func snapshot() -> ResolvedNode {
    guard let root else {
      fatalError("View graph has no root snapshot.")
    }
    return root.snapshot()
  }

  private func collectRemovedIdentities(
    from identity: Identity,
    removedIdentities: inout Set<Identity>
  ) {
    guard let node = nodesByIdentity[identity], node.wasPresentAtFrameStart else {
      return
    }

    for childIdentity in node.previousChildrenIdentities {
      collectRemovedIdentities(
        from: childIdentity,
        removedIdentities: &removedIdentities
      )
    }

    guard !node.wasVisitedThisFrame else {
      return
    }

    node.setLifecycleState(.disappearing)
    removedIdentities.insert(identity)
  }

  private func nodeForIdentity(
    for identity: Identity
  ) -> ViewNode {
    if let existing = nodesByIdentity[identity] {
      return existing
    }

    let node = ViewNode(identity: identity)
    nodesByIdentity[identity] = node
    return node
  }

  private func lifecycleState(
    from resolved: ResolvedNode,
    placed: PlacedNode?
  ) -> LifecycleStateSnapshot {
    var nodes: [LifecycleStateNode] = []
    collectLifecycleNodes(
      from: resolved,
      placed: placed,
      into: &nodes
    )
    return .init(nodes: nodes)
  }

  private func collectLifecycleNodes(
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

    if !resolved.lifecycleMetadata.isEmpty {
      nodes.append(
        LifecycleStateNode(
          identity: resolved.identity,
          appearHandlerIDs: resolved.lifecycleMetadata.appearHandlerIDs,
          disappearHandlerIDs: resolved.lifecycleMetadata.disappearHandlerIDs,
          task: resolved.lifecycleMetadata.task
        )
      )
    }

    for (index, child) in resolved.children.enumerated() {
      collectLifecycleNodes(
        from: child,
        placed: placed?.children.indices.contains(index) == true
          ? placed?.children[index]
          : nil,
        into: &nodes
      )
    }
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

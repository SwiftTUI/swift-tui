@MainActor
package final class ViewGraph {
  package private(set) var root: ViewNode?

  private var nodesByIdentity: [Identity: ViewNode]
  private var frameOrder: [Identity]
  private var stableTaskCancelEvents: [LifecycleEvent]
  private var stableTaskStartIdentities: [Identity]
  private var invalidatedIdentities: Set<Identity>
  private var previousRootIdentity: Identity?
  private var latestLifecycleEvents: [LifecycleEvent]

  package init() {
    nodesByIdentity = [:]
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
    invalidator: (any Invalidating)? = nil
  ) -> [LifecycleEvent] {
    beginFrame()
    recordReusedSubtree(
      resolved,
      invalidator: invalidator
    )
    return finalizeFrame(rootIdentity: resolved.identity)
  }

  package func finalizeFrame(
    rootIdentity: Identity
  ) -> [LifecycleEvent] {
    root = nodesByIdentity[rootIdentity]

    var removedIdentities: Set<Identity> = []
    var removedEvents: [LifecycleEvent] = []
    if let previousRootIdentity {
      collectRemovedEvents(
        from: previousRootIdentity,
        removedIdentities: &removedIdentities,
        into: &removedEvents
      )
    }

    for identity in removedIdentities {
      nodesByIdentity.removeValue(forKey: identity)
    }

    var insertedAppearEvents: [LifecycleEvent] = []
    var insertedTaskStartEvents: [LifecycleEvent] = []
    for identity in frameOrder {
      guard let node = nodesByIdentity[identity], !node.wasPresentAtFrameStart else {
        continue
      }
      if !node.lifecycleMetadata.appearHandlerIDs.isEmpty {
        insertedAppearEvents.append(
          .init(
            identity: identity,
            operation: .appear(handlerIDs: node.lifecycleMetadata.appearHandlerIDs)
          )
        )
      }
      if let task = node.lifecycleMetadata.task {
        insertedTaskStartEvents.append(
          .init(
            identity: identity,
            operation: .taskStart(task)
          )
        )
      }
      node.setLifecycleState(.alive)
    }

    let stableTaskStartEvents = stableTaskStartIdentities.compactMap { identity in
      nodesByIdentity[identity]?.lifecycleMetadata.task.map { task in
        LifecycleEvent(
          identity: identity,
          operation: .taskStart(task)
        )
      }
    }

    latestLifecycleEvents =
      removedEvents
      + stableTaskCancelEvents
      + insertedAppearEvents
      + stableTaskStartEvents
      + insertedTaskStartEvents

    invalidatedIdentities.removeAll(keepingCapacity: true)
    return latestLifecycleEvents
  }

  package func snapshot() -> ResolvedNode {
    guard let root else {
      fatalError("View graph has no root snapshot.")
    }
    return root.snapshot()
  }

  private func collectRemovedEvents(
    from identity: Identity,
    removedIdentities: inout Set<Identity>,
    into events: inout [LifecycleEvent]
  ) {
    guard let node = nodesByIdentity[identity], node.wasPresentAtFrameStart else {
      return
    }

    for childIdentity in node.previousChildrenIdentities {
      collectRemovedEvents(
        from: childIdentity,
        removedIdentities: &removedIdentities,
        into: &events
      )
    }

    guard !node.wasVisitedThisFrame else {
      return
    }

    if let task = node.previousLifecycleMetadata.task {
      events.append(
        .init(
          identity: identity,
          operation: .taskCancel(task)
        )
      )
    }

    if !node.previousLifecycleMetadata.disappearHandlerIDs.isEmpty {
      events.append(
        .init(
          identity: identity,
          operation: .disappear(handlerIDs: node.previousLifecycleMetadata.disappearHandlerIDs)
        )
      )
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
}

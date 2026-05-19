private struct ViewGraphViewportLifecycleEventPlan {
  var events: [LifecycleEvent]
  var nodesByIdentity: [Identity: LifecycleStateNode]
  var order: [Identity]
}

@MainActor
enum ViewGraphLifecyclePlanner {
  static func plan(
    resolved: ResolvedNode,
    placed: PlacedNode?,
    input: ViewGraphLifecyclePlanningInput
  ) -> ViewGraphFrameLifecycleEventPlan {
    let viewportPlan = viewportLifecycleEventPlan(
      from: resolved,
      placed: placed,
      previousViewportLifecycleNodesByIdentity: input.viewportLifecycleNodesByIdentity,
      previousViewportLifecycleOrder: input.viewportLifecycleOrder
    )
    let (
      viewportTaskCancels,
      viewportDisappears,
      viewportAppears,
      viewportChanges,
      viewportTaskStarts
    ) =
      partitionLifecycleEvents(viewportPlan.events)
    let changeEvents = input.changeHandlerIDsByIdentity.map { identity, handlerIDs in
      LifecycleEvent(
        identity: identity,
        operation: .change(handlerIDs: handlerIDs)
      )
    }

    return ViewGraphFrameLifecycleEventPlan(
      events:
        input.stableTaskCancelEvents
        + input.structuralTaskCancelEvents
        + viewportTaskCancels
        + input.structuralDisappearEvents
        + viewportDisappears
        + input.structuralAppearEvents
        + viewportAppears
        + changeEvents
        + viewportChanges
        + input.stableTaskStartEvents
        + viewportTaskStarts,
      viewportLifecycleNodesByIdentity: viewportPlan.nodesByIdentity,
      viewportLifecycleOrder: viewportPlan.order
    )
  }

  private static func collectViewportLifecycleEvents(
    from resolved: ResolvedNode,
    placed: PlacedNode?,
    viewportLifecycleNodesByIdentity: inout [Identity: LifecycleStateNode],
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
        viewportLifecycleNodesByIdentity: &viewportLifecycleNodesByIdentity,
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
        viewportLifecycleNodesByIdentity: &viewportLifecycleNodesByIdentity,
        seenIdentities: &seenIdentities,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }

  private static func viewportLifecycleEventPlan(
    from resolved: ResolvedNode,
    placed: PlacedNode?,
    previousViewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode],
    previousViewportLifecycleOrder: [Identity]
  ) -> ViewGraphViewportLifecycleEventPlan {
    var nodesByIdentity = previousViewportLifecycleNodesByIdentity
    var seenIdentities: Set<Identity> = []
    var order: [Identity] = []
    var taskCancels: [LifecycleEvent] = []
    var disappears: [LifecycleEvent] = []
    var appears: [LifecycleEvent] = []
    var taskStarts: [LifecycleEvent] = []

    collectViewportLifecycleEvents(
      from: resolved,
      placed: placed,
      viewportLifecycleNodesByIdentity: &nodesByIdentity,
      seenIdentities: &seenIdentities,
      order: &order,
      taskCancels: &taskCancels,
      appears: &appears,
      taskStarts: &taskStarts
    )

    for identity in previousViewportLifecycleOrder.reversed()
    where !seenIdentities.contains(identity) {
      guard let previousNode = nodesByIdentity.removeValue(forKey: identity) else {
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

    return ViewGraphViewportLifecycleEventPlan(
      events: taskCancels + disappears + appears + taskStarts,
      nodesByIdentity: nodesByIdentity,
      order: order
    )
  }

  private static func partitionLifecycleEvents(
    _ events: [LifecycleEvent]
  ) -> (
    taskCancels: [LifecycleEvent],
    disappears: [LifecycleEvent],
    appears: [LifecycleEvent],
    changes: [LifecycleEvent],
    taskStarts: [LifecycleEvent]
  ) {
    var taskCancels: [LifecycleEvent] = []
    var disappears: [LifecycleEvent] = []
    var appears: [LifecycleEvent] = []
    var changes: [LifecycleEvent] = []
    var taskStarts: [LifecycleEvent] = []

    for event in events {
      switch event.operation {
      case .taskCancel:
        taskCancels.append(event)
      case .disappear:
        disappears.append(event)
      case .appear:
        appears.append(event)
      case .change:
        changes.append(event)
      case .taskStart:
        taskStarts.append(event)
      }
    }

    return (
      taskCancels,
      disappears,
      appears,
      changes,
      taskStarts
    )
  }

  private static func recordViewportLifecycleVisibility(
    of node: PlacedNode,
    viewportLifecycleNodesByIdentity: inout [Identity: LifecycleStateNode],
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
        viewportLifecycleNodesByIdentity: &viewportLifecycleNodesByIdentity,
        seenIdentities: &seenIdentities,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }
}

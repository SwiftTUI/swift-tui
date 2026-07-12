private struct ViewGraphViewportLifecycleEventPlan {
  var events: [LifecycleEvent]
  var nodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
  var order: [ViewportLifecycleKey]
}

@MainActor
enum ViewGraphLifecyclePlanner {
  static func plan(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?,
    input: ViewGraphLifecyclePlanningInput
  ) -> ViewGraphFrameLifecycleEventPlan {
    let viewportPlan = viewportLifecycleEventPlan(
      from: resolved,
      placed: placed,
      previousViewportLifecycleNodesByKey: input.viewportLifecycleNodesByKey,
      previousViewportLifecycleOrder: input.viewportLifecycleOrder,
      nodeIDByIdentity: input.nodeIDByIdentity
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
        viewNodeID: input.nodeIDByIdentity[identity],
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
      viewportLifecycleNodesByKey: viewportPlan.nodesByKey,
      viewportLifecycleOrder: viewportPlan.order
    )
  }

  private static func collectViewportLifecycleEvents(
    from resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?,
    viewportLifecycleNodesByKey: inout [ViewportLifecycleKey: LifecycleStateNode],
    seenKeys: inout Set<ViewportLifecycleKey>,
    order: inout [ViewportLifecycleKey],
    nodeIDByIdentity: [Identity: ViewNodeID],
    taskCancels: inout [LifecycleEvent],
    appears: inout [LifecycleEvent],
    taskStarts: inout [LifecycleEvent]
  ) {
    if resolved.usesIndexedChildSource,
      let placed
    {
      recordViewportLifecycleVisibility(
        of: placed,
        viewportLifecycleNodesByKey: &viewportLifecycleNodesByKey,
        seenKeys: &seenKeys,
        nodeIDByIdentity: nodeIDByIdentity,
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
        viewportLifecycleNodesByKey: &viewportLifecycleNodesByKey,
        seenKeys: &seenKeys,
        order: &order,
        nodeIDByIdentity: nodeIDByIdentity,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }

  private static func viewportLifecycleEventPlan(
    from resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?,
    previousViewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode],
    previousViewportLifecycleOrder: [ViewportLifecycleKey],
    nodeIDByIdentity: [Identity: ViewNodeID]
  ) -> ViewGraphViewportLifecycleEventPlan {
    var nodesByKey = previousViewportLifecycleNodesByKey
    var seenKeys: Set<ViewportLifecycleKey> = []
    var order: [ViewportLifecycleKey] = []
    var taskCancels: [LifecycleEvent] = []
    var disappears: [LifecycleEvent] = []
    var appears: [LifecycleEvent] = []
    var taskStarts: [LifecycleEvent] = []

    collectViewportLifecycleEvents(
      from: resolved,
      placed: placed,
      viewportLifecycleNodesByKey: &nodesByKey,
      seenKeys: &seenKeys,
      order: &order,
      nodeIDByIdentity: nodeIDByIdentity,
      taskCancels: &taskCancels,
      appears: &appears,
      taskStarts: &taskStarts
    )

    for key in previousViewportLifecycleOrder.reversed()
    where !seenKeys.contains(key) {
      guard let previousNode = nodesByKey.removeValue(forKey: key) else {
        continue
      }
      for task in previousNode.tasks {
        taskCancels.append(
          .init(
            viewNodeID: previousNode.viewNodeID,
            identity: previousNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
      if !previousNode.disappearHandlerIDs.isEmpty {
        disappears.append(
          .init(
            viewNodeID: previousNode.viewNodeID,
            identity: previousNode.identity,
            operation: .disappear(handlerIDs: previousNode.disappearHandlerIDs)
          )
        )
      }
    }

    return ViewGraphViewportLifecycleEventPlan(
      events: taskCancels + disappears + appears + taskStarts,
      nodesByKey: nodesByKey,
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
    of node: ViewportVisibilitySummary,
    viewportLifecycleNodesByKey: inout [ViewportLifecycleKey: LifecycleStateNode],
    seenKeys: inout Set<ViewportLifecycleKey>,
    nodeIDByIdentity: [Identity: ViewNodeID],
    order: inout [ViewportLifecycleKey],
    taskCancels: inout [LifecycleEvent],
    appears: inout [LifecycleEvent],
    taskStarts: inout [LifecycleEvent]
  ) {
    if !node.lifecycleMetadata.isEmpty {
      let key: ViewportLifecycleKey =
        if let viewNodeID = nodeIDByIdentity[node.identity] {
          .viewNode(viewNodeID)
        } else {
          .identity(node.identity)
        }
      let currentNode = LifecycleStateNode(
        viewNodeID: nodeIDByIdentity[node.identity],
        identity: node.identity,
        appearHandlerIDs: node.lifecycleMetadata.appearHandlerIDs,
        disappearHandlerIDs: node.lifecycleMetadata.disappearHandlerIDs,
        tasks: node.lifecycleMetadata.tasks
      )
      let previousNode: LifecycleStateNode?
      if case .viewNode = key,
        viewportLifecycleNodesByKey[key] == nil,
        let identityNode = viewportLifecycleNodesByKey.removeValue(
          forKey: .identity(node.identity)
        )
      {
        previousNode = identityNode
      } else {
        previousNode = viewportLifecycleNodesByKey[key]
      }
      seenKeys.insert(key)
      order.append(key)

      if previousNode == nil, !currentNode.appearHandlerIDs.isEmpty {
        appears.append(
          .init(
            viewNodeID: currentNode.viewNodeID,
            identity: currentNode.identity,
            operation: .appear(handlerIDs: currentNode.appearHandlerIDs)
          )
        )
      }
      // Viewport keying is identity-stable by construction (`ViewportLifecycleKey`
      // tracks the node, not the resolved identity), so the diff runs without the
      // stable arm's identity-churn suppression.
      let diff = TaskLifecycleDiff.between(
        previous: previousNode?.tasks ?? [],
        current: currentNode.tasks
      )
      for task in diff.cancels {
        taskCancels.append(
          .init(
            viewNodeID: currentNode.viewNodeID,
            identity: currentNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
      for task in diff.starts {
        taskStarts.append(
          .init(
            viewNodeID: currentNode.viewNodeID,
            identity: currentNode.identity,
            operation: .taskStart(task)
          )
        )
      }

      viewportLifecycleNodesByKey[key] = currentNode
    }

    for child in node.children {
      recordViewportLifecycleVisibility(
        of: child,
        viewportLifecycleNodesByKey: &viewportLifecycleNodesByKey,
        seenKeys: &seenKeys,
        nodeIDByIdentity: nodeIDByIdentity,
        order: &order,
        taskCancels: &taskCancels,
        appears: &appears,
        taskStarts: &taskStarts
      )
    }
  }
}

@MainActor
enum ViewGraphLifecycleEventCollector {
  static func appendTaskCancelEvent(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool,
    stableTaskCancelEvents: inout [LifecycleEvent],
    structuralTaskCancelEvents: inout [LifecycleEvent],
    stableTaskStartEvents: [LifecycleEvent]
  ) {
    let event = LifecycleEvent(
      viewNodeID: viewNodeID,
      identity: identity,
      operation: .taskCancel(task)
    )
    guard
      !taskLifecycleEventExists(
        event,
        stableTaskCancelEvents: stableTaskCancelEvents,
        structuralTaskCancelEvents: structuralTaskCancelEvents,
        stableTaskStartEvents: stableTaskStartEvents
      )
    else {
      return
    }
    if isStructural {
      structuralTaskCancelEvents.append(event)
    } else {
      stableTaskCancelEvents.append(event)
    }
  }

  static func appendTaskStartEvent(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    task: TaskDescriptor,
    stableTaskCancelEvents: [LifecycleEvent],
    structuralTaskCancelEvents: [LifecycleEvent],
    stableTaskStartEvents: inout [LifecycleEvent]
  ) {
    let event = LifecycleEvent(
      viewNodeID: viewNodeID,
      identity: identity,
      operation: .taskStart(task)
    )
    guard
      !taskLifecycleEventExists(
        event,
        stableTaskCancelEvents: stableTaskCancelEvents,
        structuralTaskCancelEvents: structuralTaskCancelEvents,
        stableTaskStartEvents: stableTaskStartEvents
      )
    else {
      return
    }
    stableTaskStartEvents.append(event)
  }

  static func nodeEmitsOwnLifecycleEvents(
    _ node: ViewNode,
    ownerNodeID: ViewNodeID?,
    ownerExists: Bool
  ) -> Bool {
    guard node.participatesInStructuralLifecycle else {
      return false
    }
    guard let ownerNodeID,
      ownerNodeID != node.viewNodeID,
      ownerExists
    else {
      return true
    }
    return false
  }

  static func frameLifecycleEventPlan(
    resolved: ResolvedNode,
    placed: ViewportVisibilitySummary?,
    nodesByNodeID: [ViewNodeID: ViewNode],
    nodeIDByIdentity: [Identity: ViewNodeID],
    frameOrder: [ViewNodeID],
    viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode],
    viewportLifecycleOrder: [ViewportLifecycleKey],
    stableTaskCancelEvents: [LifecycleEvent],
    stableTaskStartEvents: [LifecycleEvent],
    structuralAppearEvents: [LifecycleEvent],
    structuralTaskCancelEvents: [LifecycleEvent],
    structuralDisappearEvents: [LifecycleEvent]
  ) -> ViewGraphFrameLifecycleEventPlan {
    ViewGraphLifecyclePlanner.plan(
      resolved: resolved,
      placed: placed,
      input: ViewGraphLifecyclePlanningInput(
        viewportLifecycleNodesByKey: viewportLifecycleNodesByKey,
        viewportLifecycleOrder: viewportLifecycleOrder,
        nodeIDByIdentity: nodeIDByIdentity,
        changeHandlerIDsByIdentity: frameOrder.compactMap { viewNodeID in
          guard let node = nodesByNodeID[viewNodeID],
            !node.pendingChangeHandlerIDs.isEmpty
          else {
            return nil
          }
          return (
            identity: node.identity,
            handlerIDs: node.pendingChangeHandlerIDs
          )
        },
        stableTaskCancelEvents: stableTaskCancelEvents,
        stableTaskStartEvents: stableTaskStartEvents,
        structuralAppearEvents: structuralAppearEvents,
        structuralTaskCancelEvents: structuralTaskCancelEvents,
        structuralDisappearEvents: structuralDisappearEvents
      )
    )
  }

  private static func taskLifecycleEventExists(
    _ event: LifecycleEvent,
    stableTaskCancelEvents: [LifecycleEvent],
    structuralTaskCancelEvents: [LifecycleEvent],
    stableTaskStartEvents: [LifecycleEvent]
  ) -> Bool {
    stableTaskCancelEvents.contains(event)
      || structuralTaskCancelEvents.contains(event)
      || stableTaskStartEvents.contains(event)
  }
}

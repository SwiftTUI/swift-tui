@MainActor
enum ViewGraphLifecycleEventCollector {
  static func appendTaskCancelEvent(
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool,
    stableTaskCancelEvents: inout [LifecycleEvent],
    structuralTaskCancelEvents: inout [LifecycleEvent],
    stableTaskStartEvents: [LifecycleEvent]
  ) {
    let event = LifecycleEvent(
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
    identity: Identity,
    task: TaskDescriptor,
    stableTaskCancelEvents: [LifecycleEvent],
    structuralTaskCancelEvents: [LifecycleEvent],
    stableTaskStartEvents: inout [LifecycleEvent]
  ) {
    let event = LifecycleEvent(
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
    ownerIdentity: Identity?,
    ownerExists: Bool
  ) -> Bool {
    guard node.participatesInStructuralLifecycle else {
      return false
    }
    guard let ownerIdentity,
      ownerIdentity != node.identity,
      ownerExists
    else {
      return true
    }
    return false
  }

  static func frameLifecycleEventPlan(
    resolved: ResolvedNode,
    placed: PlacedNode?,
    nodesByIdentity: [Identity: ViewNode],
    frameOrder: [Identity],
    viewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode],
    viewportLifecycleOrder: [Identity],
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
        viewportLifecycleNodesByIdentity: viewportLifecycleNodesByIdentity,
        viewportLifecycleOrder: viewportLifecycleOrder,
        changeHandlerIDsByIdentity: frameOrder.compactMap { identity in
          guard let node = nodesByIdentity[identity],
            !node.pendingChangeHandlerIDs.isEmpty
          else {
            return nil
          }
          return (
            identity: identity,
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

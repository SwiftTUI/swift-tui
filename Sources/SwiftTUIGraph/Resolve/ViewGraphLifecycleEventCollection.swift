@MainActor
enum ViewGraphLifecycleEventCollector {
  // The stable and structural cancel buffers cross as ONE `inout` group value:
  // they live in the caller's single stored `LifecycleEventBuffers` property,
  // and two simultaneous `inout` projections of one class ivar are a dynamic
  // exclusivity violation under the `_modify` field accessors.
  static func appendTaskCancelEvent(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    task: TaskDescriptor,
    isStructural: Bool,
    buffers: inout ViewGraph.LifecycleEventBuffers
  ) {
    let event = LifecycleEvent(
      viewNodeID: viewNodeID,
      identity: identity,
      operation: .taskCancel(task)
    )
    guard
      !taskLifecycleEventExists(
        event,
        stableTaskCancelEvents: buffers.stableTaskCancelEvents,
        structuralTaskCancelEvents: buffers.structuralTaskCancelEvents,
        stableTaskStartEvents: buffers.stableTaskStartEvents
      )
    else {
      return
    }
    if isStructural {
      buffers.structuralTaskCancelEvents.append(event)
    } else {
      buffers.stableTaskCancelEvents.append(event)
    }
  }

  /// One start per (identity, descriptor) per frame plan. Two nodes emit the
  /// same task start when a host node's committed root aliases a descendant
  /// branch node's identity (`.background { if flag { Pane() } }`: the branch
  /// node's structural appearing arm fires while the host's stable diff also
  /// sees the task appear). The two events differ only in `viewNodeID` — the
  /// identity index re-aliases from the branch node to the host during the
  /// host's apply — so whole-event dedupe missed them, the commit plan
  /// carried both, and the second dispatch restarted the one-shot task 0-1ms
  /// after its first run (counter-demo RippleLayer, 2026-08-06; SwiftUI
  /// starts it once). Merge instead of append: keep one entry and refresh
  /// its node key to the latest non-nil claimant, which matches the
  /// end-of-frame index state that subsequent cancels resolve against. The
  /// cancel arm keeps whole-event identity: its double dispatch is what
  /// reaches a run keyed to either aliased node.
  static func appendTaskStartEvent(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    task: TaskDescriptor,
    stableTaskStartEvents: inout [LifecycleEvent]
  ) {
    if let existingIndex = stableTaskStartEvents.firstIndex(where: {
      $0.identity == identity && $0.operation == .taskStart(task)
    }) {
      if let viewNodeID {
        stableTaskStartEvents[existingIndex].viewNodeID = viewNodeID
      }
      return
    }
    stableTaskStartEvents.append(
      LifecycleEvent(
        viewNodeID: viewNodeID,
        identity: identity,
        operation: .taskStart(task)
      )
    )
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

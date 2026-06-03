// Input and output contract types for `ViewGraphLifecyclePlanner`.
//
// Kept apart from `ViewGraphLifecyclePlanning.swift` so that file holds only
// the planning algorithm. The planner's own private intermediate type
// (`ViewGraphViewportLifecycleEventPlan`) stays beside the algorithm.

/// The lifecycle events a frame should emit, plus the viewport-lifecycle
/// bookkeeping the graph carries forward to the next frame.
struct ViewGraphFrameLifecycleEventPlan {
  var events: [LifecycleEvent]
  var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
  var viewportLifecycleOrder: [ViewportLifecycleKey]
}

/// Everything the planner needs to derive a frame's lifecycle event plan:
/// prior viewport-lifecycle state, this frame's change handlers, and the
/// already-collected stable and structural event streams.
struct ViewGraphLifecyclePlanningInput {
  var viewportLifecycleNodesByKey: [ViewportLifecycleKey: LifecycleStateNode]
  var viewportLifecycleOrder: [ViewportLifecycleKey]
  var nodeIDByIdentity: [Identity: ViewNodeID]
  var changeHandlerIDsByIdentity: [(identity: Identity, handlerIDs: [String])]
  var stableTaskCancelEvents: [LifecycleEvent]
  var stableTaskStartEvents: [LifecycleEvent]
  var structuralAppearEvents: [LifecycleEvent]
  var structuralTaskCancelEvents: [LifecycleEvent]
  var structuralDisappearEvents: [LifecycleEvent]
}

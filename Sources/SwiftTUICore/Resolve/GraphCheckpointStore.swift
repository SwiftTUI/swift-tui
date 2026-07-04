/// The checkpoint-assembly operator for ``ViewGraph``'s checkpoint cluster,
/// lifted off the god class into one cohesive, testable place.
///
/// This is a **stateless operator**, deliberately a caseless `enum` of static
/// funcs rather than a value type that owns state: the reconciliation field
/// groups (`GraphIndex`/`DirtyState`/…) stay on ``ViewGraph`` — they sit on the
/// per-frame hot path that reads `nodesByNodeID` thousands of times a frame, and
/// the source-level checkpoint-totality guard pins `ViewGraph`'s stored
/// properties. The operator reads the groups through parameters and never holds
/// or mutates any, so it adds zero stored state and changes no checkpoint bytes.
/// (The stateful per-node image cache is ``NodeCheckpointImageStore``; the
/// checkpoint **write** path, `restoreCheckpointGraphFields`, stays on
/// ``ViewGraph``.)
@MainActor
package enum GraphCheckpointStore {
  /// Assembles a whole-field-group checkpoint around prebuilt per-node images.
  /// Pure read of the passed groups; the images come from the caller's
  /// ``NodeCheckpointImageStore`` (F29) so an unchanged graph hands out an O(1)
  /// COW copy instead of rebuilding the node dictionary.
  package static func makeCheckpoint(
    root: ViewNode?,
    index: ViewGraph.GraphIndex,
    rootEvaluation: ViewGraph.RootEvaluation,
    viewportLifecycle: ViewGraph.ViewportLifecycleState,
    eventBuffers: ViewGraph.LifecycleEventBuffers,
    dirtyState: ViewGraph.DirtyState,
    lifecycleEvaluation: ViewGraph.LifecycleEvaluationOwnership,
    taskDescriptors: ViewGraph.TaskDescriptorState,
    dependencyIndex: ViewGraph.DependencyIndex,
    frameCommit: ViewGraph.FrameCommitState,
    nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  ) -> ViewGraph.Checkpoint {
    ViewGraph.Checkpoint(
      root: root,
      index: index,
      rootEvaluation: rootEvaluation,
      viewportLifecycle: viewportLifecycle,
      eventBuffers: eventBuffers,
      dirtyState: dirtyState,
      lifecycleEvaluation: lifecycleEvaluation,
      taskDescriptors: taskDescriptors,
      dependencyIndex: dependencyIndex,
      frameCommit: frameCommit,
      nodeCheckpoints: nodeCheckpoints
    )
  }
}

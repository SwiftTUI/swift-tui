/// The snapshot/restore-comparison operators for ``ViewGraph``'s checkpoint
/// cluster, lifted off the god class into one cohesive, testable place.
///
/// This is a **stateless operator**, deliberately a caseless `enum` of static
/// funcs rather than a value type that owns state: the reconciliation field
/// groups (`GraphIndex`/`DirtyState`/…) stay on ``ViewGraph`` — they sit on the
/// per-frame hot path that reads `nodesByNodeID` thousands of times a frame, and
/// the source-level checkpoint-totality guard asserts `ViewGraph`'s stored
/// properties are *exactly* the nine groups plus `root`. The store reads those
/// groups through parameters and never holds or mutates any, so it adds zero
/// stored state and changes no checkpoint bytes.
///
/// Scope (the proposal's "clean first slice" for #10): it carves the
/// *snapshot* and *mutation-state comparison* reads. The checkpoint **write**
/// path (`restoreCheckpointGraphFields`) and the mutation-tracker cross-cut
/// (`recordCheckpointGraphMutation` and its call sites, which own the mutation
/// epoch) stay on ``ViewGraph`` for a later, separately-gated pass.
@MainActor
package enum GraphCheckpointStore {
  /// Assembles a whole-field-group checkpoint plus per-node snapshots. Pure read
  /// of the passed groups; node snapshots delegate to the unchanged
  /// ``ViewGraphNodeCheckpointing``.
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
    checkpointMutationEpoch: UInt64,
    nodesByNodeID: [ViewNodeID: ViewNode]
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
      checkpointMutationEpoch: checkpointMutationEpoch,
      nodeCheckpoints: ViewGraphNodeCheckpointing.makeNodeCheckpoints(nodesByNodeID)
    )
  }

  /// Captures the mutation-tracking state (epoch + per-node generations) used to
  /// decide whether a delta restore matches a full restore.
  package static func checkpointMutationStateSnapshot(
    epoch: UInt64,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) -> ViewGraph.CheckpointMutationState {
    ViewGraph.CheckpointMutationState(
      checkpointMutationEpoch: epoch,
      nodeMutationGenerations: nodesByNodeID.mapValues {
        $0.currentCheckpointMutationGeneration
      }
    )
  }

  /// Whether the live mutation state (`epoch` + each node's current generation)
  /// still matches the captured `state` — i.e. nothing has mutated the graph
  /// since the snapshot.
  package static func checkpointMutationStateMatches(
    epoch: UInt64,
    nodesByNodeID: [ViewNodeID: ViewNode],
    against state: ViewGraph.CheckpointMutationState
  ) -> Bool {
    guard epoch == state.checkpointMutationEpoch,
      Set(nodesByNodeID.keys) == Set(state.nodeMutationGenerations.keys)
    else {
      return false
    }

    for (viewNodeID, expectedGeneration) in state.nodeMutationGenerations {
      guard
        nodesByNodeID[viewNodeID]?.currentCheckpointMutationGeneration
          == expectedGeneration
      else {
        return false
      }
    }
    return true
  }
}

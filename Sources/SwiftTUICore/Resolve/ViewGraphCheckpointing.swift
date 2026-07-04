@MainActor
enum ViewGraphNodeCheckpointing {
  static func makeNodeCheckpoints(
    _ nodesByNodeID: [ViewNodeID: ViewNode]
  ) -> [ViewNodeID: ViewNode.Checkpoint] {
    Dictionary(
      uniqueKeysWithValues: nodesByNodeID.map { viewNodeID, node in
        (viewNodeID, node.makeCheckpoint())
      }
    )
  }

  /// Restores node images onto the live nodes, skipping nodes whose live
  /// checkpoint-mutation generation equals the image's captured generation —
  /// under monotonic generations (F29 slice 1: every mutation and every
  /// restore bumps, nothing rewinds) an equal generation proves the node's
  /// state already equals the image, unconditionally. Returns the number of
  /// nodes actually rewritten.
  @discardableResult
  static func restoreNodeCheckpoints(
    _ nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint],
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) -> Int {
    var restoredNodeCount = 0
    for (viewNodeID, node) in nodesByNodeID {
      guard let nodeCheckpoint = nodeCheckpoints[viewNodeID],
        node.currentCheckpointMutationGeneration
          != nodeCheckpoint.checkpointMutationGeneration
      else {
        continue
      }
      node.restoreCheckpoint(nodeCheckpoint)
      restoredNodeCount += 1
    }
    return restoredNodeCount
  }

  /// The ungated ground truth: rewrites every node from its image regardless
  /// of generations. This is what the soundness oracles compare against — a
  /// stale image is precisely a node whose generation matches while its state
  /// does not, so the gated path above would (correctly per its contract,
  /// wrongly in effect) skip it; only an unconditional rewrite can surface
  /// the divergence.
  static func restoreNodeCheckpointsUngated(
    _ nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint],
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    for (viewNodeID, node) in nodesByNodeID {
      guard let nodeCheckpoint = nodeCheckpoints[viewNodeID] else {
        continue
      }
      node.restoreCheckpoint(nodeCheckpoint)
    }
  }
}

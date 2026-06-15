@MainActor
package struct ViewGraphDeltaCheckpointShadow {
  private let baselineGraphMutationEpoch: UInt64
  private let baselineNodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  private(set) package var baselineNodeCount: Int
  private(set) package var preparedNodeCount: Int?
  private(set) package var touchedNodeIDs: Set<ViewNodeID>
  private(set) package var createdNodeIDs: Set<ViewNodeID>
  private(set) package var removedNodeIDs: Set<ViewNodeID>
  private(set) package var graphMutationEpochDelta: UInt64?

  package init(baseline checkpoint: ViewGraph.Checkpoint) {
    baselineGraphMutationEpoch = checkpoint.checkpointMutationEpoch
    baselineNodeCheckpoints = checkpoint.nodeCheckpoints
    baselineNodeCount = checkpoint.nodeCheckpoints.count
    preparedNodeCount = nil
    touchedNodeIDs = []
    createdNodeIDs = []
    removedNodeIDs = []
    graphMutationEpochDelta = nil
  }

  package mutating func recordPreparedCheckpoint(_ checkpoint: ViewGraph.Checkpoint) {
    let baselineNodeIDs = Set(baselineNodeCheckpoints.keys)
    let preparedNodeIDs = Set(checkpoint.nodeCheckpoints.keys)
    let commonNodeIDs = baselineNodeIDs.intersection(preparedNodeIDs)

    createdNodeIDs = preparedNodeIDs.subtracting(baselineNodeIDs)
    removedNodeIDs = baselineNodeIDs.subtracting(preparedNodeIDs)
    let mutatedNodeIDs = commonNodeIDs.filter { nodeID in
      baselineNodeCheckpoints[nodeID]?.checkpointMutationGeneration
        != checkpoint.nodeCheckpoints[nodeID]?.checkpointMutationGeneration
    }
    touchedNodeIDs = Set(mutatedNodeIDs)
      .union(createdNodeIDs)
      .union(removedNodeIDs)

    preparedNodeCount = checkpoint.nodeCheckpoints.count
    graphMutationEpochDelta =
      checkpoint.checkpointMutationEpoch &- baselineGraphMutationEpoch
  }

  package var summary: ViewGraphDeltaCheckpointSummary {
    ViewGraphDeltaCheckpointSummary(
      touchedNodeIDs: touchedNodeIDs,
      createdNodeIDs: createdNodeIDs,
      removedNodeIDs: removedNodeIDs,
      baselineNodeCount: baselineNodeCount,
      preparedNodeCount: preparedNodeCount,
      touchedNodeCount: touchedNodeIDs.count,
      createdNodeCount: createdNodeIDs.count,
      removedNodeCount: removedNodeIDs.count,
      graphMutationEpochDelta: graphMutationEpochDelta
    )
  }
}

package struct ViewGraphDeltaCheckpointSummary: Equatable, Sendable {
  package var touchedNodeIDs: Set<ViewNodeID>
  package var createdNodeIDs: Set<ViewNodeID>
  package var removedNodeIDs: Set<ViewNodeID>
  package var baselineNodeCount: Int
  package var preparedNodeCount: Int?
  package var touchedNodeCount: Int
  package var createdNodeCount: Int
  package var removedNodeCount: Int
  package var graphMutationEpochDelta: UInt64?
}

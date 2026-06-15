@MainActor
package struct ViewGraphDeltaCheckpointShadow {
  package enum RestoreTarget: String, Equatable, Sendable {
    case baseline
    case prepared
  }

  package enum FallbackReason: String, Equatable, Sendable {
    case missingPreparedCheckpoint = "missing_prepared_checkpoint"
    case currentCheckpointMismatch = "current_checkpoint_mismatch"
    case incompleteTouchedCheckpoints = "incomplete_touched_checkpoints"
    case debugOracleMismatch = "debug_oracle_mismatch"
  }

  package enum RestorePlan {
    case delta(target: RestoreTarget, nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint])
    case full(target: RestoreTarget, reason: FallbackReason)
  }

  package enum RestoreResult: Equatable, Sendable {
    case delta(target: RestoreTarget)
    case full(target: RestoreTarget, reason: FallbackReason)

    package var strategyName: String {
      switch self {
      case .delta:
        return "delta_node"
      case .full:
        return "full_fallback"
      }
    }

    package var fallbackReasonName: String? {
      switch self {
      case .delta:
        return nil
      case .full(_, let reason):
        return reason.rawValue
      }
    }
  }

  private let baselineGraphMutationEpoch: UInt64
  private let baselineNodeMutationGenerations: [ViewNodeID: UInt64]
  private(set) package var baselineNodeCount: Int
  private(set) package var preparedNodeCount: Int?
  private(set) package var touchedNodeIDs: Set<ViewNodeID>
  private(set) package var createdNodeIDs: Set<ViewNodeID>
  private(set) package var removedNodeIDs: Set<ViewNodeID>
  private(set) package var graphMutationEpochDelta: UInt64?
  private(set) package var baselineTouchedNodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]
  private(set) package var preparedTouchedNodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]

  package init(baseline checkpoint: ViewGraph.Checkpoint) {
    baselineGraphMutationEpoch = checkpoint.checkpointMutationEpoch
    baselineNodeMutationGenerations = checkpoint.nodeCheckpoints.mapValues {
      $0.checkpointMutationGeneration
    }
    baselineNodeCount = checkpoint.nodeCheckpoints.count
    preparedNodeCount = nil
    touchedNodeIDs = []
    createdNodeIDs = []
    removedNodeIDs = []
    graphMutationEpochDelta = nil
    baselineTouchedNodeCheckpoints = [:]
    preparedTouchedNodeCheckpoints = [:]
  }

  package mutating func recordPreparedCheckpoint(
    _ checkpoint: ViewGraph.Checkpoint,
    baseline baselineCheckpoint: ViewGraph.Checkpoint
  ) {
    let baselineNodeIDs = Set(baselineNodeMutationGenerations.keys)
    let preparedNodeIDs = Set(checkpoint.nodeCheckpoints.keys)
    let commonNodeIDs = baselineNodeIDs.intersection(preparedNodeIDs)

    createdNodeIDs = preparedNodeIDs.subtracting(baselineNodeIDs)
    removedNodeIDs = baselineNodeIDs.subtracting(preparedNodeIDs)
    let mutatedNodeIDs = commonNodeIDs.filter { nodeID in
      baselineNodeMutationGenerations[nodeID]
        != checkpoint.nodeCheckpoints[nodeID]?.checkpointMutationGeneration
    }
    touchedNodeIDs = Set(mutatedNodeIDs)
      .union(createdNodeIDs)
      .union(removedNodeIDs)

    baselineTouchedNodeCheckpoints = Dictionary(
      uniqueKeysWithValues: touchedNodeIDs.compactMap { nodeID in
        baselineCheckpoint.nodeCheckpoints[nodeID].map { (nodeID, $0) }
      }
    )
    preparedTouchedNodeCheckpoints = Dictionary(
      uniqueKeysWithValues: touchedNodeIDs.compactMap { nodeID in
        checkpoint.nodeCheckpoints[nodeID].map { (nodeID, $0) }
      }
    )
    preparedNodeCount = checkpoint.nodeCheckpoints.count
    graphMutationEpochDelta =
      checkpoint.checkpointMutationEpoch &- baselineGraphMutationEpoch
  }

  package func restorePlan(
    target: RestoreTarget,
    in viewGraph: ViewGraph,
    baseline: ViewGraph.Checkpoint,
    prepared: ViewGraph.Checkpoint?
  ) -> RestorePlan {
    guard let prepared else {
      return .full(target: target, reason: .missingPreparedCheckpoint)
    }

    let sourceCheckpoint: ViewGraph.Checkpoint
    let requiredNodeIDs: Set<ViewNodeID>
    let nodeCheckpoints: [ViewNodeID: ViewNode.Checkpoint]

    switch target {
    case .baseline:
      sourceCheckpoint = prepared
      requiredNodeIDs = touchedNodeIDs.subtracting(createdNodeIDs)
      nodeCheckpoints = baselineTouchedNodeCheckpoints
    case .prepared:
      sourceCheckpoint = baseline
      requiredNodeIDs = touchedNodeIDs.subtracting(removedNodeIDs)
      nodeCheckpoints = preparedTouchedNodeCheckpoints
    }

    guard viewGraph.checkpointMutationStateMatches(sourceCheckpoint) else {
      return .full(target: target, reason: .currentCheckpointMismatch)
    }

    guard requiredNodeIDs.isSubset(of: Set(nodeCheckpoints.keys)) else {
      return .full(target: target, reason: .incompleteTouchedCheckpoints)
    }

    return .delta(
      target: target,
      nodeCheckpoints: nodeCheckpoints.filter { requiredNodeIDs.contains($0.key) }
    )
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

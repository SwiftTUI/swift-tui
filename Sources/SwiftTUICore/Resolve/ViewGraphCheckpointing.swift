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

  static func restoreNodeCheckpoints(
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

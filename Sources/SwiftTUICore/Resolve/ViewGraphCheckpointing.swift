@MainActor
enum ViewGraphNodeCheckpointing {
  static func makeNodeCheckpoints(
    _ nodesByIdentity: [Identity: ViewNode]
  ) -> [Identity: ViewNode.Checkpoint] {
    Dictionary(
      uniqueKeysWithValues: nodesByIdentity.map { identity, node in
        (identity, node.makeCheckpoint())
      }
    )
  }

  static func restoreNodeCheckpoints(
    _ nodeCheckpoints: [Identity: ViewNode.Checkpoint],
    nodesByIdentity: [Identity: ViewNode]
  ) {
    for (identity, node) in nodesByIdentity {
      guard let nodeCheckpoint = nodeCheckpoints[identity] else {
        continue
      }
      node.restoreCheckpoint(nodeCheckpoint)
    }
  }
}

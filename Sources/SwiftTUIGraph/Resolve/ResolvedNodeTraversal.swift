extension ResolvedNode {
  package func descendant(
    with identity: Identity
  ) -> ResolvedNode? {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      if node.identity == identity {
        return node
      }
      for child in node.children.reversed() {
        stack.append(child)
      }
    }
    return nil
  }

  package func path(
    to identity: Identity
  ) -> [Identity]? {
    var stack: [(node: ResolvedNode, isExiting: Bool)] = [(self, false)]
    var path: [Identity] = []

    while let frame = stack.popLast() {
      if frame.isExiting {
        path.removeLast()
        continue
      }

      path.append(frame.node.identity)
      if frame.node.identity == identity {
        return path
      }

      stack.append((frame.node, true))
      for child in frame.node.children.reversed() {
        stack.append((child, false))
      }
    }

    return nil
  }

  package func collectIdentities(into identities: inout [Identity]) {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      identities.append(node.identity)
      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }

  package func collectIdentities() -> [Identity] {
    var identities: [Identity] = []
    collectIdentities(into: &identities)
    return identities
  }

  package func collectLifecycleNodes(
    into nodes: inout [LifecycleStateNode]
  ) {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      if !node.lifecycleMetadata.isEmpty {
        nodes.append(
          LifecycleStateNode(
            identity: node.identity,
            appearHandlerIDs: node.lifecycleMetadata.appearHandlerIDs,
            disappearHandlerIDs: node.lifecycleMetadata.disappearHandlerIDs,
            tasks: node.lifecycleMetadata.tasks
          )
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }

  package func collectLifecycleHandlerIDs(
    appearIDs: inout [String],
    disappearIDs: inout [String]
  ) {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      appearIDs.append(contentsOf: node.lifecycleMetadata.appearHandlerIDs)
      disappearIDs.append(contentsOf: node.lifecycleMetadata.disappearHandlerIDs)

      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }
}

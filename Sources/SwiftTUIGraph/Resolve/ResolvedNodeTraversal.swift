extension ResolvedNode {
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
}

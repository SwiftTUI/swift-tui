package struct StructuralNodeKey: Hashable, Sendable {
  package let rawValue: UInt64

  package init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

package struct StructuralFrameIndex: Equatable, Sendable {
  package let root: StructuralNodeKey?
  package let parentByNode: [StructuralNodeKey: StructuralNodeKey]
  package let childrenByNode: [StructuralNodeKey: [StructuralNodeKey]]
  package let runtimeIdentityByNode: [StructuralNodeKey: Identity]
  package let nodeByRuntimeIdentity: [Identity: [StructuralNodeKey]]
  package let subtreeRangeByNode: [StructuralNodeKey: Range<Int>]
  package let subtreeSignatureByNode: [StructuralNodeKey: Int]
  package let postorder: [StructuralNodeKey]

  package var runtimeIdentities: Set<Identity> {
    Set(nodeByRuntimeIdentity.keys)
  }

  package init(root resolvedRoot: ResolvedNode) {
    var builder = Builder()
    root = builder.index(resolvedRoot, parent: nil)
    parentByNode = builder.parentByNode
    childrenByNode = builder.childrenByNode
    runtimeIdentityByNode = builder.runtimeIdentityByNode
    nodeByRuntimeIdentity = builder.nodeByRuntimeIdentity
    subtreeRangeByNode = builder.subtreeRangeByNode
    subtreeSignatureByNode = builder.subtreeSignatureByNode
    postorder = builder.postorder
  }

  package func nodes(
    for identity: Identity
  ) -> [StructuralNodeKey] {
    nodeByRuntimeIdentity[identity] ?? []
  }

  package func uniqueNode(
    for identity: Identity
  ) -> StructuralNodeKey? {
    let matches = nodes(for: identity)
    return matches.count == 1 ? matches[0] : nil
  }

  package func runtimeIdentity(
    for node: StructuralNodeKey
  ) -> Identity? {
    runtimeIdentityByNode[node]
  }

  package func parentIdentity(
    of node: StructuralNodeKey
  ) -> Identity? {
    guard let parent = parentByNode[node] else {
      return nil
    }
    return runtimeIdentityByNode[parent]
  }

  package func hasInvalidatedAncestor(
    of identity: Identity,
    invalidatedIdentities: Set<Identity>
  ) -> Bool? {
    let keys = nodes(for: identity)
    guard !keys.isEmpty else {
      return nil
    }
    let invalidatedNodes = nodeKeys(for: invalidatedIdentities)
    for key in keys {
      var parent = parentByNode[key]
      while let current = parent {
        if invalidatedNodes.contains(current) {
          return true
        }
        if let parentIdentity = runtimeIdentityByNode[current],
          invalidatedIdentities.contains(parentIdentity)
        {
          return true
        }
        parent = parentByNode[current]
      }
    }
    return false
  }

  package func containsInvalidatedDescendant(
    of identity: Identity,
    invalidatedIdentities: Set<Identity>
  ) -> Bool? {
    let keys = nodes(for: identity)
    guard !keys.isEmpty else {
      return nil
    }
    let invalidatedNodes = nodeKeys(for: invalidatedIdentities)
    for key in keys {
      guard let range = subtreeRangeByNode[key] else {
        continue
      }
      for descendant in postorder[range] where descendant != key {
        if invalidatedNodes.contains(descendant) {
          return true
        }
        if let descendantIdentity = runtimeIdentityByNode[descendant],
          invalidatedIdentities.contains(descendantIdentity)
        {
          return true
        }
      }
    }
    return false
  }

  package func intersectsSubtree(
    at identity: Identity,
    invalidatedIdentities: Set<Identity>
  ) -> Bool? {
    if invalidatedIdentities.contains(identity) {
      return true
    }
    guard !nodes(for: identity).isEmpty else {
      return nil
    }
    if containsInvalidatedDescendant(
      of: identity,
      invalidatedIdentities: invalidatedIdentities
    ) == true {
      return true
    }
    if hasInvalidatedAncestor(
      of: identity,
      invalidatedIdentities: invalidatedIdentities
    ) == true {
      return true
    }
    return false
  }

  private func nodeKeys(
    for identities: Set<Identity>
  ) -> Set<StructuralNodeKey> {
    var keys: Set<StructuralNodeKey> = []
    for identity in identities {
      keys.formUnion(nodes(for: identity))
    }
    return keys
  }

  private struct Builder {
    var nextRawValue: UInt64 = 0
    var parentByNode: [StructuralNodeKey: StructuralNodeKey] = [:]
    var childrenByNode: [StructuralNodeKey: [StructuralNodeKey]] = [:]
    var runtimeIdentityByNode: [StructuralNodeKey: Identity] = [:]
    var nodeByRuntimeIdentity: [Identity: [StructuralNodeKey]] = [:]
    var subtreeRangeByNode: [StructuralNodeKey: Range<Int>] = [:]
    var subtreeSignatureByNode: [StructuralNodeKey: Int] = [:]
    var postorder: [StructuralNodeKey] = []

    mutating func index(
      _ node: ResolvedNode,
      parent: StructuralNodeKey?
    ) -> StructuralNodeKey {
      let key = StructuralNodeKey(rawValue: nextRawValue)
      nextRawValue += 1
      runtimeIdentityByNode[key] = node.identity
      nodeByRuntimeIdentity[node.identity, default: []].append(key)
      if let parent {
        parentByNode[key] = parent
        childrenByNode[parent, default: []].append(key)
      }

      let subtreeStart = postorder.count
      var childSignatures: [Int] = []
      for child in node.children {
        let childKey = index(child, parent: key)
        childSignatures.append(subtreeSignatureByNode[childKey] ?? 0)
      }
      postorder.append(key)
      subtreeRangeByNode[key] = subtreeStart..<postorder.count
      subtreeSignatureByNode[key] = Self.signature(
        identity: node.identity,
        kind: node.kind,
        childSignatures: childSignatures
      )
      childrenByNode[key] = childrenByNode[key] ?? []
      return key
    }

    private static func signature(
      identity: Identity,
      kind: NodeKind,
      childSignatures: [Int]
    ) -> Int {
      var hasher = Hasher()
      hasher.combine(identity)
      switch kind {
      case .root:
        hasher.combine("root")
      case .scene(let name):
        hasher.combine("scene")
        hasher.combine(name)
      case .view(let name):
        hasher.combine("view")
        hasher.combine(name)
      }
      hasher.combine(childSignatures.count)
      for childSignature in childSignatures {
        hasher.combine(childSignature)
      }
      return hasher.finalize()
    }
  }
}

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
  /// Each node's own index in `postorder`. Together with `subtreeRangeByNode`
  /// this answers ancestor/descendant queries by range containment in O(1)
  /// per pair, letting the invalidation queries below iterate the (tiny)
  /// invalidated set instead of scanning whole subtrees.
  package let postorderPositionByNode: [StructuralNodeKey: Int]

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
    postorderPositionByNode = Dictionary(
      uniqueKeysWithValues: builder.postorder.enumerated().map { ($1, $0) }
    )
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

  // The invalidation queries below iterate the invalidated node-key set and
  // answer ancestry by postorder-range containment — O(|invalidated|) per
  // call — instead of scanning subtrees or ancestor chains. Invalidation sets
  // are tiny (median 2 post-F08) while subtrees run to hundreds of nodes.
  // Key membership subsumes the old per-node identity re-check: the key set
  // is resolved from the SAME identity set through `nodeByRuntimeIdentity`,
  // the exact inverse of `runtimeIdentityByNode`, so an identity match at a
  // node implies that node's key is in the set; identities absent from the
  // frame resolve to no keys and can never match a frame-resident node.
  // Every query preserves the `nil` (identity unknown to this frame) vs
  // `false` (known, no intersection) distinction — the unindexed-invalidation
  // fallback chain in `RetainedInvalidationSummary` depends on it.

  package func hasInvalidatedAncestor(
    of identity: Identity,
    invalidatedIdentities: Set<Identity>
  ) -> Bool? {
    hasInvalidatedAncestor(
      of: identity,
      invalidatedNodes: nodeKeys(for: invalidatedIdentities)
    )
  }

  package func hasInvalidatedAncestor(
    of identity: Identity,
    invalidatedNodes: Set<StructuralNodeKey>
  ) -> Bool? {
    let keys = nodes(for: identity)
    guard !keys.isEmpty else {
      return nil
    }
    guard !invalidatedNodes.isEmpty else {
      return false
    }
    for key in keys {
      guard let position = postorderPositionByNode[key] else {
        continue
      }
      for invalidated in invalidatedNodes where invalidated != key {
        if let range = subtreeRangeByNode[invalidated], range.contains(position) {
          return true
        }
      }
    }
    return false
  }

  package func containsInvalidatedDescendant(
    of identity: Identity,
    invalidatedIdentities: Set<Identity>
  ) -> Bool? {
    containsInvalidatedDescendant(
      of: identity,
      invalidatedNodes: nodeKeys(for: invalidatedIdentities)
    )
  }

  package func containsInvalidatedDescendant(
    of identity: Identity,
    invalidatedNodes: Set<StructuralNodeKey>
  ) -> Bool? {
    let keys = nodes(for: identity)
    guard !keys.isEmpty else {
      return nil
    }
    guard !invalidatedNodes.isEmpty else {
      return false
    }
    for key in keys {
      guard let range = subtreeRangeByNode[key] else {
        continue
      }
      for invalidated in invalidatedNodes where invalidated != key {
        if let position = postorderPositionByNode[invalidated], range.contains(position) {
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
    intersectsSubtree(
      at: identity,
      invalidatedNodes: nodeKeys(for: invalidatedIdentities),
      invalidatedIdentities: invalidatedIdentities
    )
  }

  package func intersectsSubtree(
    at identity: Identity,
    invalidatedNodes: Set<StructuralNodeKey>,
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
      invalidatedNodes: invalidatedNodes
    ) == true {
      return true
    }
    if hasInvalidatedAncestor(
      of: identity,
      invalidatedNodes: invalidatedNodes
    ) == true {
      return true
    }
    return false
  }

  /// Resolves an identity set to its frame node keys. Frame-constant callers
  /// (`RetainedInvalidationSummary`) resolve once and reuse the set across
  /// every per-candidate query.
  package func nodeKeys(
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
        structuralPath: node.structuralPath,
        kind: node.kind,
        childSignatures: childSignatures
      )
      childrenByNode[key] = childrenByNode[key] ?? []
      return key
    }

    private static func signature(
      identity: Identity,
      structuralPath: StructuralPath,
      kind: NodeKind,
      childSignatures: [Int]
    ) -> Int {
      var hasher = Hasher()
      hasher.combine(identity)
      hasher.combine(structuralPath)
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

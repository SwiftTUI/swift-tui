import SwiftTUICore

enum AnimationTreeQueries {
  /// Walks the placed tree and records the bounds and identity of
  /// every node tagged with a ``MatchedGeometryKey``. Nodes whose
  /// config is `isSource: false` never contribute their bounds:
  /// they still receive match translations on frames where their
  /// key is swapped to another identity, but a non-source instance
  /// cannot make another instance animate by disappearing.
  ///
  /// If multiple source-contributing nodes carry the same key in
  /// one frame, the last-walked entry wins.
  static func collectMatchedGeometry(
    _ node: PlacedNode,
    bounds: inout [MatchedGeometryKey: CellRect],
    identities: inout [MatchedGeometryKey: Identity]
  ) {
    if let config = node.matchedGeometry, config.isSource {
      bounds[config.key] = node.bounds
      identities[config.key] = node.identity
    }
    for child in node.children {
      collectMatchedGeometry(child, bounds: &bounds, identities: &identities)
    }
  }

  static func findBounds(
    in node: PlacedNode,
    identity: Identity
  ) -> CellRect? {
    if node.identity == identity { return node.bounds }
    for child in node.children {
      if let found = findBounds(in: child, identity: identity) {
        return found
      }
    }
    return nil
  }

  /// Recursively searches a resolved tree for the subtree rooted at
  /// `identity` and returns a copy of it.
  static func findResolvedSubtree(
    in root: ResolvedNode,
    identity: Identity
  ) -> ResolvedNode? {
    if root.identity == identity { return root }
    for child in root.children {
      if let match = findResolvedSubtree(in: child, identity: identity) {
        return match
      }
    }
    return nil
  }

  /// Same lookup semantics as ``findResolvedSubtree(in:identity:)`` with a
  /// name for call sites that only need to inspect the found node.
  static func findResolvedNode(
    in root: ResolvedNode,
    identity: Identity
  ) -> ResolvedNode? {
    findResolvedSubtree(in: root, identity: identity)
  }

  /// Recursively searches a placed tree for the subtree rooted at
  /// `identity` and returns a copy of it. Used to capture the frozen
  /// bounds of a disappearing subtree for draw-only overlay injection.
  static func findPlacedSubtree(
    in root: PlacedNode,
    identity: Identity
  ) -> PlacedNode? {
    if root.identity == identity { return root }
    for child in root.children {
      if let match = findPlacedSubtree(in: child, identity: identity) {
        return match
      }
    }
    return nil
  }

  /// Returns the set of every identity in a subtree, including the root.
  static func collectIdentities(in subtree: ResolvedNode) -> Set<Identity> {
    var result: Set<Identity> = [subtree.identity]
    for child in subtree.children {
      result.formUnion(collectIdentities(in: child))
    }
    return result
  }
}

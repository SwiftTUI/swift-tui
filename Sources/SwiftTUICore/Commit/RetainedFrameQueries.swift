// Read-only query surface over the previous committed frame.
//
// Incremental layout reuses the last frame's pipeline products instead of
// recomputing untouched subtrees. Three value types make that retained state
// queryable, from raw to refined:
//
//  - `RetainedFrameIndex` — flat identity → node lookup tables built once per
//    committed frame.
//  - `RetainedInvalidationSummary` — classifies this frame's invalidations
//    against the previous index (synthetic ancestors, affected indexed child
//    sources, subtree intersection).
//  - `RetainedLayoutSession` — pairs an index with a summary and re-derives the
//    summary whenever `invalidatedIdentities` changes; this is what the layout
//    engine actually consults.
//
// All three are `Sendable` and side-effect free. They previously lived in
// `RetainedResolveFrame.swift` alongside the mutable `LayoutPassContext`.

/// Identity index of the previous committed frame's canonical pipeline products.
///
/// When this index is produced by frame-tail retained state, `placedByIdentity`
/// is expected to come from the baseline placed tree stored before animation
/// overlays were injected. That keeps retained placement keyed to canonical
/// layout, while overlays are re-applied from animation state each frame.
package struct RetainedFrameIndex: Sendable {
  package let resolvedByIdentity: [Identity: ResolvedNode]
  package let measuredByIdentity: [Identity: MeasuredNode]
  package let placedByIdentity: [Identity: PlacedNode]

  package init(frame: FrameArtifacts) {
    var resolvedByIdentity: [Identity: ResolvedNode] = [:]
    Self.index(frame.resolvedTree, into: &resolvedByIdentity)
    self.resolvedByIdentity = resolvedByIdentity

    var measuredByIdentity: [Identity: MeasuredNode] = [:]
    Self.index(frame.measuredTree, into: &measuredByIdentity)
    self.measuredByIdentity = measuredByIdentity

    var placedByIdentity: [Identity: PlacedNode] = [:]
    Self.index(frame.placedTree, into: &placedByIdentity)
    self.placedByIdentity = placedByIdentity
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    resolvedByIdentity[identity]
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    measuredByIdentity[identity]
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    placedByIdentity[identity]
  }

  private static func index(
    _ node: ResolvedNode,
    into storage: inout [Identity: ResolvedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      index(child, into: &storage)
    }
  }

  private static func index(
    _ node: MeasuredNode,
    into storage: inout [Identity: MeasuredNode]
  ) {
    storage[node.identity] = node
    for child in node.childMeasurements {
      index(child, into: &storage)
    }
  }

  private static func index(
    _ node: PlacedNode,
    into storage: inout [Identity: PlacedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      index(child, into: &storage)
    }
  }
}

package struct RetainedInvalidationSummary: Sendable {
  private let base: InvalidationSummary
  package let identitiesWithSyntheticInvalidatedAncestors: Set<Identity>
  package let affectedIndexedChildSourceRoots: Set<Identity>

  package var directlyInvalidated: Set<Identity> {
    base.directlyInvalidated
  }

  package var identitiesWithInvalidatedDescendants: Set<Identity> {
    base.identitiesWithInvalidatedDescendants
  }

  package init(
    invalidatedIdentities: Set<Identity>,
    previousFrameIndex: RetainedFrameIndex?
  ) {
    let base = InvalidationSummary(
      invalidatedIdentities: invalidatedIdentities
    )
    self.base = base

    guard let previousFrameIndex else {
      identitiesWithSyntheticInvalidatedAncestors = []
      affectedIndexedChildSourceRoots = []
      return
    }

    let previousResolvedIdentities = Set(previousFrameIndex.resolvedByIdentity.keys)
    let syntheticInvalidatedIdentities = invalidatedIdentities.subtracting(
      previousResolvedIdentities)

    var identitiesWithSyntheticInvalidatedAncestors: Set<Identity> = []
    if !syntheticInvalidatedIdentities.isEmpty {
      for identity in previousResolvedIdentities {
        var ancestor = identity.parent
        while let current = ancestor {
          if syntheticInvalidatedIdentities.contains(current) {
            identitiesWithSyntheticInvalidatedAncestors.insert(identity)
            break
          }
          ancestor = current.parent
        }
      }
    }
    self.identitiesWithSyntheticInvalidatedAncestors = identitiesWithSyntheticInvalidatedAncestors

    var affectedIndexedChildSourceRoots: Set<Identity> = []
    if !invalidatedIdentities.isEmpty {
      for resolvedNode in previousFrameIndex.resolvedByIdentity.values {
        guard let source = resolvedNode.indexedChildSource else {
          continue
        }
        if base.intersectsSubtree(at: source.identityRoot) {
          affectedIndexedChildSourceRoots.insert(source.identityRoot)
        }
      }
    }
    self.affectedIndexedChildSourceRoots = affectedIndexedChildSourceRoots
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    base.isDirectlyInvalidated(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    base.containsInvalidatedDescendant(of: identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    identitiesWithSyntheticInvalidatedAncestors.contains(identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    affectedIndexedChildSourceRoots.contains(identityRoot)
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    base.intersectsSubtree(at: identity)
  }
}

package struct RetainedLayoutSession: Sendable {
  package var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities,
        previousFrameIndex: previousFrameIndex
      )
    }
  }
  package let previousFrameIndex: RetainedFrameIndex?
  package var invalidationSummary: RetainedInvalidationSummary

  package init(
    previousFrameIndex: RetainedFrameIndex?,
    invalidatedIdentities: Set<Identity>
  ) {
    self.invalidatedIdentities = invalidatedIdentities
    self.previousFrameIndex = previousFrameIndex
    invalidationSummary = RetainedInvalidationSummary(
      invalidatedIdentities: invalidatedIdentities,
      previousFrameIndex: previousFrameIndex
    )
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    previousFrameIndex?.resolvedNode(for: identity)
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    previousFrameIndex?.measuredNode(for: identity)
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    previousFrameIndex?.placedNode(for: identity)
  }

  package func invalidationAffectsSubtree(
    at identity: Identity
  ) -> Bool {
    invalidationSummary.intersectsSubtree(at: identity)
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.isDirectlyInvalidated(identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.hasSyntheticInvalidatedAncestor(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    invalidationSummary.containsInvalidatedDescendant(of: identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    invalidationSummary.affectsIndexedChildSource(root: identityRoot)
  }
}

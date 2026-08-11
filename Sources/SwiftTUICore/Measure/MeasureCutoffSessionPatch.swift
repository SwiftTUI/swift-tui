/// The derived-session patch that turns a certificate into a serve (plan
/// 2026-08-11-002 D3/D4).
///
/// Lifting a certified subtree's invalidation is not enough on its own: every
/// spine serve runs `previousResolved.isEquivalentForMeasurement(to:)`, whose
/// walk reaches the changed leaf and fails on content. The patch therefore
/// replaces the session's *view* of the previous frame at each certified root
/// — previous resolved subtree by the current one, previous measured subtree
/// by the fresh pre-pass product — so the equivalence walk compares current
/// against current and the served spine product already carries the fresh
/// subtree. `retainedMeasurement` itself is untouched; with the patched
/// session its existing guards pass naturally at every spine node.
///
/// The measure pass alone reads the patched copy
/// (`LayoutPassContext.measureSessionForReuse`); the place pass, the damage
/// resolver, and diagnostics keep the original session, so placement stays
/// conservative (D5) and damage still sees the real invalidation set.
extension RetainedLayoutSession {
  package func patchingCertifiedSubtrees(
    _ certificates: [MeasureCutoffCertificate]
  ) -> RetainedLayoutSession? {
    guard let index = previousFrameIndex, !certificates.isEmpty else {
      return nil
    }
    // Identity-keyed surgery is only sound when runtime identities are
    // unique — the same guard the shape-stable index patcher takes.
    guard
      index.structuralFrame.nodeByRuntimeIdentity.count
        == index.structuralFrame.postorder.count
    else {
      return nil
    }

    var resolvedIndex = index.resolvedStructuralIndex
    var measuredIndex = index.measuredStructuralIndex
    guard var patchedResolvedRoot = resolvedIndex[index.placedRoot.identity],
      var patchedMeasuredRoot = measuredIndex[index.placedRoot.identity]
    else {
      return nil
    }

    var liftedInvalidations = invalidatedIdentities
    for certificate in certificates {
      guard
        stitch(
          certificate: certificate,
          resolvedRoot: &patchedResolvedRoot,
          measuredRoot: &patchedMeasuredRoot,
          resolvedIndex: &resolvedIndex,
          measuredIndex: &measuredIndex
        )
      else {
        return nil
      }
      liftedInvalidations = liftedInvalidations.filter {
        !($0 == certificate.rootIdentity
          || $0.isDescendant(of: certificate.rootIdentity))
      }
    }

    let derivedIndex = RetainedFrameIndex(
      resolvedByNodeID: index.resolvedByNodeID,
      measuredByNodeID: index.measuredByNodeID,
      placedByNodeID: index.placedByNodeID,
      structuralFrame: index.structuralFrame,
      resolvedStructuralIndex: resolvedIndex,
      measuredStructuralIndex: measuredIndex,
      placedStructuralIndex: index.placedStructuralIndex,
      placedRoot: index.placedRoot,
      placedParentByStructuralIdentity: index.placedParentByStructuralIdentity,
      placedFrameEntries: index.placedFrameEntries,
      placedFrameEntryRangesByNodeID: index.placedFrameEntryRangesByNodeID,
      placedFrameEntryRangesByStructuralIdentity:
        index.placedFrameEntryRangesByStructuralIdentity,
      derivedByPatching: true
    )
    return RetainedLayoutSession(
      previousFrameIndex: derivedIndex,
      invalidatedIdentities: liftedInvalidations
    )
  }

  /// Path-copies the certified root's spine in both value trees, swaps the
  /// certified subtree in, and rewrites the touched identity-keyed entries:
  /// spine ancestors get their stitched values, the previous subtree's
  /// identities leave the tables, the fresh subtree's identities enter.
  private func stitch(
    certificate: MeasureCutoffCertificate,
    resolvedRoot: inout ResolvedNode,
    measuredRoot: inout MeasuredNode,
    resolvedIndex: inout [Identity: ResolvedNode],
    measuredIndex: inout [Identity: MeasuredNode],
  ) -> Bool {
    let root = certificate.rootIdentity

    // Locate the spine in the previous resolved tree (child indexes per
    // level), pairing the measured spine by identity at each hop.
    var resolvedSpine: [(node: ResolvedNode, childIndex: Int)] = []
    var measuredSpine: [(node: MeasuredNode, childIndex: Int)] = []
    var resolvedCursor = resolvedRoot
    var measuredCursor = measuredRoot
    while resolvedCursor.identity != root {
      guard
        let resolvedChildIndex = resolvedCursor.children.firstIndex(where: {
          $0.identity == root || $0.identity.isAncestor(of: root)
        })
      else {
        return false
      }
      let nextIdentity = resolvedCursor.children[resolvedChildIndex].identity
      guard
        let measuredChildIndex = measuredCursor.childMeasurements.firstIndex(where: {
          $0.identity == nextIdentity
        })
      else {
        return false
      }
      resolvedSpine.append((resolvedCursor, resolvedChildIndex))
      measuredSpine.append((measuredCursor, measuredChildIndex))
      resolvedCursor = resolvedCursor.children[resolvedChildIndex]
      measuredCursor = measuredCursor.childMeasurements[measuredChildIndex]
    }

    // Retire the previous subtree's identity entries before the fresh
    // subtree's enter (internal identities may differ arbitrarily — same-size
    // subtrees with different internal layout are the certified win).
    var retire: [ResolvedNode] = [resolvedCursor]
    while let node = retire.popLast() {
      resolvedIndex.removeValue(forKey: node.identity)
      measuredIndex.removeValue(forKey: node.identity)
      retire.append(contentsOf: node.children)
    }
    var enroll: [ResolvedNode] = [certificate.currentResolvedSubtree]
    while let node = enroll.popLast() {
      resolvedIndex[node.identity] = node
      enroll.append(contentsOf: node.children)
    }
    var enrollMeasured: [MeasuredNode] = [certificate.freshMeasuredAtRetainedProposal]
    while let node = enrollMeasured.popLast() {
      measuredIndex[node.identity] = node
      enrollMeasured.append(contentsOf: node.childMeasurements)
    }

    // Bottom-up path copy: swap the subtree into each spine level and refresh
    // the ancestors' index entries with their stitched values.
    var replacementResolved = certificate.currentResolvedSubtree
    var replacementMeasured = certificate.freshMeasuredAtRetainedProposal
    for level in stride(from: resolvedSpine.count - 1, through: 0, by: -1) {
      var resolvedNode = resolvedSpine[level].node
      var measuredNode = measuredSpine[level].node
      resolvedNode.children[resolvedSpine[level].childIndex] = replacementResolved
      measuredNode.childMeasurements[measuredSpine[level].childIndex] = replacementMeasured
      resolvedIndex[resolvedNode.identity] = resolvedNode
      measuredIndex[measuredNode.identity] = measuredNode
      replacementResolved = resolvedNode
      replacementMeasured = measuredNode
    }
    resolvedRoot = replacementResolved
    measuredRoot = replacementMeasured
    return true
  }
}

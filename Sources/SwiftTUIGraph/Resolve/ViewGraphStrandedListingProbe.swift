// The stranded-listing oracle: nodes whose ``CommittedFreshness`` stamps claim
// they still own every child they list, while one of those children is seated
// under a DIFFERENT live parent.
//
// Such a node can no longer hear the child's subtree change — the upward
// staleness walks follow the child's single `parent` slot — so serving it
// commits superseded interior content and stamps (the divergent-resolvedIdentity
// capture-host orphaning seam behind the gallery Tab-wrap stamp-coherence
// crash).
//
// Stranded listings themselves are ordinary: a later apply steals a child from
// an earlier lister every time a collapse or a route absorb re-seats a payload.
// What must never happen is a stranded listing on a node that still *claims* to
// own it — `reclaimForeignParentedChildren` notifies the abandoned parent, and
// that mark is what withdraws the claim. This oracle is the totality check on
// that notification: a live-object walk over the whole graph, run at the
// finalize barrier on sampled frames.

extension ViewGraph {
  /// Every node in the graph whose freshness stamps claim ownership of a child
  /// that is seated under another parent.
  ///
  /// The walk is over live nodes rather than a `debugTotalStateSnapshot()`
  /// mirror, and that is load-bearing rather than an optimization. The mirror
  /// names a lister by `identityByNodeID` — keyed on `resolvedIdentity`, the
  /// alias-remapped name — while a child's parent is named by that parent
  /// object's own authored `identity`. Comparing the two naming systems
  /// reports every child of every alias-remapped node as foreign-parented,
  /// including children parented to the lister itself: the sweep read 13–14
  /// "co-listings" on a healthy graph, which is what made the invariant look
  /// un-assertable graph-wide. Comparing the objects the staleness walk
  /// actually follows reads zero.
  package func strandedFreshServableViolations() -> [String] {
    var violations: [String] = []
    for (nodeID, node) in nodesByNodeID {
      guard node.claimsOwnershipOfListedChildren else {
        continue
      }
      for child in node.children where child !== node {
        guard let childParent = child.parent, childParent !== node else {
          continue
        }
        violations.append(
          "stranded listing: \(nodeID) at \(node.identity.path) claims child "
            + "\(child.viewNodeID) at \(child.identity.path) whose live parent "
            + "is \(childParent.viewNodeID) at \(childParent.identity.path)"
        )
      }
    }
    return violations.sorted()
  }
}

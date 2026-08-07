// The reader-scoped environment toleration: what the reuse door consults in
// place of whole-snapshot environment equality.
//
// Whole-snapshot equality (`committed.environmentSnapshot == environment`) is
// correct but blunt. An authored `.environment(K, v)` whose value changes
// denies EVERY reuse door beneath the writer, so the writer's whole cone
// re-descends even though only actual readers of `K` can observe the change.
// This narrows the denial to the keys a candidate subtree can actually
// observe, and repays the staleness a serve leaves behind (see
// "Drift", below).
//
// The soundness argument has exactly two legs, and both are load-bearing:
//
//  1. **Attribution is complete for the tolerated keys.** Outside this
//     framework's own modules an environment value is reachable only through
//     attributed surfaces (`@Environment` and the wrappers composed on it),
//     each of which records a read. Framework-declared keys are excluded
//     wholesale by `EnvironmentKeyReuseClassification` because framework
//     resolve/draw code also reads them *without* attribution
//     (`EnvironmentValues[untracked:]`, style extraction, stack-axis reads),
//     so no reader-set argument holds for them.
//  2. **The subtree contains no interior writer of a changed key.** An
//     interior `.environment(K, …)` makes its subtree's value for `K`
//     authored rather than inherited, which decouples it from the boundary's
//     change — including the case no diff can see, where the interior write
//     happens to author the boundary's *prior* value. Denying on any interior
//     writer also makes the repair uniform: a served subtree is
//     writer-free by construction, so there is no interior boundary at which
//     a repair would have to stop.

/// The environment half of a reuse decision at one door.
package enum EnvironmentReuseVerdict {
  /// Snapshots compare equal — the historic path. Nothing is tolerated and
  /// nothing is owed.
  case equal
  /// Snapshots differ *only* in reader-attributed-only typed keys that no node
  /// in the candidate subtree reads or writes. The payload names those keys; a
  /// serve owes them a drift record so a later frontier re-entry inside the
  /// served subtree observes current values.
  case tolerated(Set<ObjectIdentifier>)
  /// The difference is not reader-attributed, or the subtree can observe it.
  case denied
}

extension ViewGraph {
  /// Classifies the environment difference between a candidate node's
  /// committed snapshot and the environment the caller is resolving under.
  ///
  /// Ordered cheapest-first so the common paths stay at their historic cost:
  /// whole-snapshot equality (unchanged), then the typed diff, then the
  /// per-key classification (a cached dictionary lookup that bails on the
  /// first framework key), and only then the two index scans.
  func environmentReuseVerdict(
    node: ViewNode,
    environment: EnvironmentSnapshot
  ) -> EnvironmentReuseVerdict {
    let committed = node.committed.environmentSnapshot
    if committed == environment {
      return .equal
    }
    let diff = environment.typedDiff(from: committed)
    // A key present on one side only, an untyped-value difference, a style
    // difference, or a signature difference: none of these are
    // reader-attributed, so none can be argued away by a reader set.
    guard !diff.hasNonTypedDivergence else {
      return .denied
    }
    // `typedDiff` mirrors `==` input for input, so an empty changed set here
    // is unreachable while the snapshots compare unequal. Deny rather than
    // serve a difference no one examined, in case that ever stops holding.
    guard !diff.changedTypedKeys.isEmpty else {
      return .denied
    }
    for key in diff.changedTypedKeys {
      guard let keyType = environment.typedValues[key]?.environmentKeyType,
        EnvironmentKeyReuseClassification.isReaderAttributedOnly(keyType)
      else {
        return .denied
      }
    }
    // Readers first: a subtree that reads a changed key is the common denial
    // and the cheaper of the two scans to hit.
    guard
      !subtreeContainsIndexedNode(
        of: node,
        keys: diff.changedTypedKeys,
        index: environmentDependents
      ),
      !subtreeContainsIndexedNode(
        of: node,
        keys: diff.changedTypedKeys,
        index: environmentKeyWriters
      )
    else {
      return .denied
    }
    return .tolerated(diff.changedTypedKeys)
  }

  /// Whether any node indexed under `keys` lies at or below `node`.
  ///
  /// Scoping runs over the **`ViewNode` parent chain**, not identity ancestry:
  /// `isDescendantBridgingIslandSeams` is the same relation the memo gate's
  /// descendant-invalidation arm trusts, and it crosses the island seams
  /// (style bodies, captured subviews) where identity paths restart. An
  /// identity-path scan would silently miss a reader sitting inside such an
  /// island and serve it stale.
  ///
  /// Iterating the index (rather than walking the subtree) keeps this
  /// proportional to the number of readers/writers of the *changed* keys
  /// instead of the size of the subtree being served — the subtree is the
  /// thing reuse exists to avoid touching.
  private func subtreeContainsIndexedNode(
    of node: ViewNode,
    keys: Set<ObjectIdentifier>,
    index: [ObjectIdentifier: Set<ViewNodeID>]
  ) -> Bool {
    for key in keys {
      for viewNodeID in index[key] ?? [] {
        guard let candidate = nodesByNodeID[viewNodeID] else {
          continue
        }
        if candidate === node || candidate.isDescendantBridgingIslandSeams(of: node) {
          return true
        }
      }
    }
    return false
  }
}

// MARK: - Drift

// A tolerated serve leaves the subtree's stored environment behind: every node
// under the boundary keeps the snapshot it was resolved with, and — the part
// that matters for correctness — every evaluator closure captured inside it
// keeps the `ResolveContext.environmentValues` of the frame it was captured
// on. A later dirty-frontier re-run of such a closure whose body *newly* reads
// a tolerated key (a conditional read that did not fire on the resolve that
// recorded the dependency, so no reader edge exists to deny the serve) would
// observe the stale value. SwiftUI semantics require the current one.
//
// "Drift" is the repair: the boundary records the tolerated keys' current
// values, and a frontier re-entry inside that boundary folds them into its
// captured context before the body runs.
//
// Drift is only ever *read* on a re-entry path, because it is cleared before
// any fresh descent can reach it: `beginEvaluation` drops drift at the
// evaluating node and everything below it, and a fresh descent to a drifted
// node necessarily passes through an ancestor's `beginEvaluation` first.
extension ViewGraph {
  /// Records the current values of `keys` as drift owed by `node`'s subtree.
  ///
  /// Recording also drops these keys from any drift held by a *descendant*
  /// boundary: this record is both outer and newer, so pruning keeps at most
  /// one drift value per key on any root-to-leaf path and lets lookup merge
  /// without worrying about which entry is fresher.
  func recordEnvironmentDrift(
    at node: ViewNode,
    keys: Set<ObjectIdentifier>,
    from environment: EnvironmentSnapshot
  ) {
    var recorded: [ObjectIdentifier: EnvironmentSnapshotValue] = [:]
    recorded.reserveCapacity(keys.count)
    for key in keys {
      guard let value = environment.typedValues[key] else {
        continue
      }
      recorded[key] = value
    }
    guard !recorded.isEmpty else {
      return
    }
    for (boundaryNodeID, drift) in environmentDriftByBoundary {
      guard let boundary = nodesByNodeID[boundaryNodeID],
        boundary !== node,
        boundary.isDescendantBridgingIslandSeams(of: node)
      else {
        continue
      }
      let pruned = drift.filter { key, _ in recorded[key] == nil }
      if pruned.isEmpty {
        environmentDriftByBoundary.removeValue(forKey: boundaryNodeID)
      } else {
        environmentDriftByBoundary[boundaryNodeID] = pruned
      }
    }
    environmentDriftByBoundary[node.viewNodeID, default: [:]].merge(recorded) { _, new in new }
  }

  /// Whether any boundary currently owes an environment repair. The resolve
  /// path checks this before asking for drift, so a graph with nothing owing
  /// pays one dictionary `isEmpty` per `resolveView` and no identity lookup.
  package var hasEnvironmentDrift: Bool {
    !environmentDriftByBoundary.isEmpty
  }

  /// The identities of the boundaries currently owing an environment repair —
  /// i.e. exactly the nodes whose subtrees a tolerated serve has covered.
  ///
  /// Diagnostic surface: this is the only externally visible evidence that a
  /// door *tolerated* rather than plainly matched, so tests assert serve/deny
  /// against it instead of inferring intent from reuse counts (a denied
  /// boundary's read-free siblings are still tolerated, so aggregate counts
  /// cannot distinguish the two).
  package var environmentDriftBoundaryIdentities: Set<Identity> {
    Set(environmentDriftByBoundary.keys.compactMap { identityByNodeID[$0] })
  }

  /// The drift a re-entry at `node` must fold into its captured environment:
  /// every boundary at or above it, merged. Per-key uniqueness along the
  /// ancestor chain is guaranteed by ``recordEnvironmentDrift(at:keys:from:)``'s
  /// descendant pruning, so merge order is irrelevant.
  package func environmentDrift(
    for identity: Identity
  ) -> [ObjectIdentifier: EnvironmentSnapshotValue] {
    guard !environmentDriftByBoundary.isEmpty,
      let node = nodeIfExists(for: identity)
    else {
      return [:]
    }
    var merged: [ObjectIdentifier: EnvironmentSnapshotValue] = [:]
    for (boundaryNodeID, drift) in environmentDriftByBoundary {
      guard let boundary = nodesByNodeID[boundaryNodeID],
        boundary === node || node.isDescendantBridgingIslandSeams(of: boundary)
      else {
        continue
      }
      merged.merge(drift) { existing, _ in existing }
    }
    return merged
  }

  /// Drops drift at `node` and everything below it — the repayment a genuine
  /// re-resolve performs. The descent that follows rebuilds every context
  /// below `node` from current values, so nothing under it is stale any more.
  func clearEnvironmentDriftAtAndBelow(_ node: ViewNode) {
    guard !environmentDriftByBoundary.isEmpty else {
      return
    }
    environmentDriftByBoundary = environmentDriftByBoundary.filter { boundaryNodeID, _ in
      guard let boundary = nodesByNodeID[boundaryNodeID] else {
        // The boundary node is gone; its drift can never be owed again.
        return false
      }
      return !(boundary === node || boundary.isDescendantBridgingIslandSeams(of: node))
    }
  }

  /// Drops drift at a boundary whose environment has come back into agreement
  /// with its committed snapshot — the key reverted, so the contexts captured
  /// inside are correct again and the recorded value is now the stale one.
  ///
  /// Called from the door for both reuse layers: `.equal` can be served by the
  /// value-blind layer without the memo gate (and its verdict) ever running.
  func repayEnvironmentDriftIfEnvironmentMatches(
    _ identity: Identity,
    environment: EnvironmentSnapshot
  ) {
    guard !environmentDriftByBoundary.isEmpty,
      let node = nodeIfExists(for: identity),
      environmentDriftByBoundary[node.viewNodeID] != nil,
      node.committed.environmentSnapshot == environment
    else {
      return
    }
    environmentDriftByBoundary.removeValue(forKey: node.viewNodeID)
  }
}

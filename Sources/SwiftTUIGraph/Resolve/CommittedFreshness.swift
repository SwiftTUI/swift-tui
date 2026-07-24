// The committed-snapshot freshness module: the per-node stamps that decide
// whether a retained committed snapshot may be served in place of a body
// re-run, owned behind named transitions so every writer states *what
// happened* and the stamp semantics live in exactly one place.

/// Freshness verdicts for one node's `committed` snapshot.
///
/// Three stamps, three distinct set-rules:
///
/// - `isCommittedSnapshotFresh` — the committed snapshot still mirrors the
///   live descendants. Cleared along live `parent` links by the upward
///   staleness walk; restored by the node's own apply or by a
///   snapshot-rebuild/retained write-back.
/// - `hasStaleIslandDescendant` — a descendant behind an island seam (a node
///   reachable only via `evaluationHost`) changed. Kept separate from
///   freshness deliberately: `snapshot()`'s rebuild-from-live-children cannot
///   span an island seam, so clearing freshness above one would graft a
///   structurally truncated tree and launder it as fresh.
/// - `hasForeignParentedChild` — a child this node still lists was adopted
///   under a DIFFERENT live parent, so the upward walks can never reach this
///   node through that child again and its committed snapshot may silently
///   age (the divergent-resolvedIdentity capture-host orphaning class).
///
/// The two service queries encode which gates honor which stamps. The memo
/// exemption — ``canServeMemo`` ignores `hasForeignParentedChild` — is
/// deliberate: the memo gate's view-value equality is an independent
/// freshness proof for the served subtree, and `.equatable()` boundaries
/// routinely have their single child absorbed into an ancestor's pairing.
package struct CommittedFreshness: Equatable {
  package private(set) var isCommittedSnapshotFresh = false
  package private(set) var hasStaleIslandDescendant = false
  package private(set) var hasForeignParentedChild = false

  package init() {}

  // MARK: Transitions

  /// The node's own apply committed a resolved value and (re-)seated every
  /// listed child: the snapshot is fresh, island verdicts are re-captured by
  /// the body that produced it, and no listed child is foreign-parented.
  package mutating func commitApplied() {
    isCommittedSnapshotFresh = true
    hasStaleIslandDescendant = false
    hasForeignParentedChild = false
  }

  /// The committed mirror was refreshed from an authoritative source without
  /// a body re-run: a retained-reuse write-back (`applyRetainedSnapshot`) or
  /// a `snapshot()` rebuild from live children. Restores freshness only —
  /// the island and foreign-parented verdicts are NOT re-adjudicated by a
  /// refresh, so they carry forward unchanged.
  package mutating func snapshotRefreshed() {
    isCommittedSnapshotFresh = true
  }

  /// A child this node still lists was adopted under a different live
  /// parent. Sticky until the node's own next apply re-owns its children
  /// (``commitApplied()``): no other event can prove the listing sound.
  package mutating func markChildReseated() {
    hasForeignParentedChild = true
  }

  /// The upward staleness walk reached this node: a descendant changed.
  /// Along live `parent` links the committed mirror is stale (rebuildable
  /// from live children); once the walk has crossed an island seam the
  /// mirror must stay servable-for-rebuild and only the island verdict
  /// records the change.
  package mutating func markDescendantChanged(crossingIslandSeam: Bool) {
    if crossingIslandSeam {
      hasStaleIslandDescendant = true
    } else {
      isCommittedSnapshotFresh = false
    }
  }

  // MARK: Service queries

  /// Whether value-blind Layer-A retained reuse may serve the committed
  /// snapshot, as far as freshness is concerned. All three stamps deny.
  package var canServeValueBlind: Bool {
    isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
      && !hasForeignParentedChild
  }

  /// Whether the memoized (value-verified) gate may serve, as far as
  /// freshness is concerned. Foreign-parented children are exempt — the
  /// gate's view-value equality independently proves the served subtree.
  package var canServeMemo: Bool {
    isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
  }

  /// Whether `snapshot()` may return `committed` without a rebuild.
  package var hasFreshCommittedSnapshot: Bool {
    isCommittedSnapshotFresh
  }

  /// Diagnostic mirror of ``canServeValueBlind``: the first denying stamp as
  /// a `ReuseDenialTrace` label, or `nil` when freshness would serve.
  /// Label strings and check order are load-bearing for trace stability.
  package var valueBlindDenialReason: String? {
    if !isCommittedSnapshotFresh { return "stale-snapshot" }
    if hasStaleIslandDescendant { return "stale-island-descendant" }
    if hasForeignParentedChild { return "foreign-parented-child" }
    return nil
  }
}

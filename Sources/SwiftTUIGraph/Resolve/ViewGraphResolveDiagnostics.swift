/// Per-frame tallies for the committed-value anchor projection walk
/// (serve-path plan 2026-08-12-003: the Stage-0 attribution counter for M2
/// and the Stage-4 ratchet currency).
///
/// Reference storage on ``ViewGraph``, deliberately outside the checkpointed
/// field groups: these are frame diagnostics, not graph state, and a
/// checkpoint restore must not rewind them. Always-on (not `#if DEBUG`) —
/// the committed bench ratchet reads the derived `frames.tsv` columns in
/// both configurations, and each record is a bare integer add on a path
/// that already does dictionary work per node.
package struct LifetimeAnchorProjectionTallies: Equatable, Sendable {
  /// Nodes visited by `replaceCommittedValueAnchors` walks — the sum of
  /// committed-subtree sizes over computed-node epilogues and retained
  /// serves this frame.
  package var nodesWalked = 0
  /// Committed-value `replaceTargets` calls those walks issued.
  package var replaceCalls = 0
  /// The subset that changed nothing (the equality early-out fired).
  package var replaceNoops = 0

  package init() {}
}

@MainActor
package final class ViewGraphResolveDiagnostics {
  package private(set) var lifetimeAnchorTallies = LifetimeAnchorProjectionTallies()

  package init() {}

  func recordAnchorWalk(
    nodesWalked: Int,
    replaceCalls: Int,
    replaceNoops: Int
  ) {
    lifetimeAnchorTallies.nodesWalked += nodesWalked
    lifetimeAnchorTallies.replaceCalls += replaceCalls
    lifetimeAnchorTallies.replaceNoops += replaceNoops
  }

  /// Returns the accumulated tallies and resets them — one consumer per
  /// frame head, after its last resolve pass.
  package func takeLifetimeAnchorTallies() -> LifetimeAnchorProjectionTallies {
    defer { lifetimeAnchorTallies = LifetimeAnchorProjectionTallies() }
    return lifetimeAnchorTallies
  }
}

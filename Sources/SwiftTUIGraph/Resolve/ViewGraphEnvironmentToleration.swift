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
      EnvironmentTolerationCensus.recordNonTypedDenial()
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
        EnvironmentTolerationCensus.recordFrameworkKeyDenial(
          key: environment.typedValues[key]?.keyDebugName
        )
        return .denied
      }
    }
    // Readers first: a subtree that reads a changed key is the common denial
    // and the cheaper of the two scans to hit.
    if subtreeContainsIndexedNode(
      of: node,
      keys: diff.changedTypedKeys,
      index: environmentDependents
    ) {
      EnvironmentTolerationCensus.recordReaderDenial(cone: node.committed.subtreeNodeCount)
      return .denied
    }
    if subtreeContainsIndexedNode(
      of: node,
      keys: diff.changedTypedKeys,
      index: environmentKeyWriters
    ) {
      EnvironmentTolerationCensus.recordWriterDenial()
      return .denied
    }
    EnvironmentTolerationCensus.recordTolerated(cone: node.committed.subtreeNodeCount)
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

// MARK: - Census

/// Counts why the environment verdict landed where it did, so the value of a
/// further stage can be sized from real trees instead of argued from a plan.
///
/// The population that matters for reader-scoped re-entry (plan
/// 2026-08-07-002 Stage 3) is `readerDenials`: boundaries that would have been
/// served but for a reader of a changed key somewhere inside. A stage that
/// serves those and re-runs exactly the readers is only worth its risk if that
/// count is materially non-zero on real trees.
///
/// DEBUG-only and off unless `SWIFTTUI_ENV_TOLERATION_CENSUS` is set; the
/// counters are plain statics on the main actor, like the reuse trace's.
@MainActor
package enum EnvironmentTolerationCensus {
  #if DEBUG
    // `FeatureFlags.environmentValue` is the Foundation-free `getenv` funnel;
    // this layer must not import Foundation.
    package static var isEnabled: Bool =
      FeatureFlags.environmentValue(named: "SWIFTTUI_ENV_TOLERATION_CENSUS") != nil
    package static var tolerated = 0
    package static var readerDenials = 0
    package static var writerDenials = 0
    package static var frameworkKeyDenials = 0
    package static var nonTypedDenials = 0
    /// Committed subtree nodes behind each verdict — frequency alone cannot
    /// size a stage, since one denial at a high boundary re-descends far more
    /// than many denials at leaves.
    package static var toleratedConeNodes = 0
    package static var readerDeniedConeNodes = 0
    package static var frameworkKeyDenialsByKey: [String: Int] = [:]
  #endif

  static func recordTolerated(cone: Int) {
    #if DEBUG
      if isEnabled {
        tolerated += 1
        toleratedConeNodes += cone
      }
    #endif
  }

  static func recordReaderDenial(cone: Int) {
    #if DEBUG
      if isEnabled {
        readerDenials += 1
        readerDeniedConeNodes += cone
      }
    #endif
  }

  static func recordWriterDenial() {
    #if DEBUG
      if isEnabled { writerDenials += 1 }
    #endif
  }

  static func recordFrameworkKeyDenial(key: String?) {
    #if DEBUG
      if isEnabled {
        frameworkKeyDenials += 1
        // Which framework keys actually drive the denials decides whether
        // attribution is a narrow fix or a sweep across every framework read
        // path. Reflecting the name here is fine: census-only, off by default.
        frameworkKeyDenialsByKey[key ?? "<unknown>", default: 0] += 1
      }
    #endif
  }

  static func recordNonTypedDenial() {
    #if DEBUG
      if isEnabled { nonTypedDenials += 1 }
    #endif
  }

  #if DEBUG
    /// Framework keys ranked by how many denials each caused.
    private static var frameworkKeyBreakdown: String {
      guard !frameworkKeyDenialsByKey.isEmpty else {
        return ""
      }
      let ranked = frameworkKeyDenialsByKey
        .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
      return " | framework-keys: " + ranked
    }
  #endif

  /// One-line census summary, or `nil` when disabled or nothing was recorded.
  package static var summary: String? {
    #if DEBUG
      guard isEnabled,
        tolerated + readerDenials + writerDenials + frameworkKeyDenials + nonTypedDenials > 0
      else {
        return nil
      }
      return """
        [ENV-TOLERATION] tolerated=\(tolerated) reader-denied=\(readerDenials) \
        writer-denied=\(writerDenials) framework-key-denied=\(frameworkKeyDenials) \
        non-typed-denied=\(nonTypedDenials) \
        tolerated-cone-nodes=\(toleratedConeNodes) \
        reader-denied-cone-nodes=\(readerDeniedConeNodes)\(frameworkKeyBreakdown)
        """
    #else
      return nil
    #endif
  }
}

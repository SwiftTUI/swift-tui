import SwiftTUIPrimitives

package enum ReuseDenialReason: String, CaseIterable, Sendable {
  case cacheCanReuseDenied = "cache-can-reuse-denied"
  case cacheDirty = "cache-dirty"
  case cacheEnvMismatch = "cache-env-mismatch"
  case cacheEnvironmentMismatch = "cache-environment-mismatch"
  case cacheForeignParentedChild = "cache-foreign-parented-child"
  case cacheMiss = "cache-miss"
  case cacheNoRetainedSupport = "cache-no-retained-support"
  case cacheNodeDeparted = "cache-node-departed"
  case cacheNotPresent = "cache-not-present"
  case cacheStaleIslandDescendant = "cache-stale-island-descendant"
  case cacheStaleSignature = "cache-stale-signature"
  case cacheStaleSnapshot = "cache-stale-snapshot"
  case cacheTransaction = "cache-transaction"
  case cacheTransactionMismatch = "cache-transaction-mismatch"
  case cacheVisited = "cache-visited"
  case canReuseDenied = "can-reuse-denied"
  case dirty = "dirty"
  case dynamicPropertyChanged = "dynamic-property-changed"
  case dynamicPropertyUncertified = "dynamic-property-uncertified"
  case envMismatch = "env-mismatch"
  case foreignParentedChild = "foreign-parented-child"
  case invalidatedEmpty = "invalidated-empty"
  case invalidationConflict = "invalidation-conflict"
  case noNode = "no-node"
  case noRetainedSupport = "no-retained-support"
  case notPresent = "not-present"
  case staleIslandDescendant = "stale-island-descendant"
  case staleSnapshot = "stale-snapshot"
  case suppressed = "suppressed"
  case transaction = "transaction"
  case visited = "visited"

  /// Records a node-level denial reached through the resolved-node cache.
  package var cached: Self {
    switch self {
    case .canReuseDenied: .cacheCanReuseDenied
    case .dirty: .cacheDirty
    case .envMismatch: .cacheEnvMismatch
    case .foreignParentedChild: .cacheForeignParentedChild
    case .noRetainedSupport: .cacheNoRetainedSupport
    case .notPresent: .cacheNotPresent
    case .staleIslandDescendant: .cacheStaleIslandDescendant
    case .staleSnapshot: .cacheStaleSnapshot
    case .transaction: .cacheTransaction
    case .visited: .cacheVisited
    default: self
    }
  }
}

/// Diagnostic-only trace of **why retained reuse was denied** per node, gated by
/// `SWIFTTUI_REUSE_TRACE` (default off). Inert and zero-cost when disabled.
///
/// Each resolve pass that recomputes a node instead of reusing it records the
/// reason (suppressed / env-mismatch / dirty / invalidation-conflict / …); for
/// `env-mismatch` it also records which environment keys differ. ``ViewGraph``
/// dumps and resets the per-frame histogram to stderr at `beginFrame`, so the
/// stream shows one `[REUSE-TRACE]` line per frame. Used to find what re-resolves
/// the background on sheet/palette open.
/// Process-global by design (F119): this subsystem's state is `@MainActor`
/// statics keyed by per-`ViewGraph` frame IDs, so two live graphs in one
/// process would interleave counters and misattribute trace lines. Note-only
/// until multi-scene hosting is real; the fix shape is scoping to the
/// `ViewGraph` instance (or task-locals, the animation-sink storages' shape).
@MainActor
package enum ReuseDenialTrace {
  package static let environmentVariableName = SwiftTUIEnvironmentVariable.reuseTrace.rawValue

  /// Optional file sink. When `SWIFTTUI_REUSE_TRACE_FILE` names a writable path,
  /// each `[REUSE-TRACE]` line is appended there instead of stderr. The trace is
  /// otherwise stderr-only, where it is easily lost among build/runtime output
  /// (this is why it was previously misread as silent on the release perf path).
  /// A file sink makes the diagnostic a durable, run-correlated artifact.
  /// `nil` keeps the historical stderr behavior. Settable for tests.
  package static let fileEnvironmentVariableName = SwiftTUIEnvironmentVariable.reuseTraceFile
    .rawValue

  package static var isEnabled: Bool = environmentDefault()

  /// Resolved once on first emit. When set, trace lines append to this path
  /// (created if missing); when `nil`, they go to stderr.
  package static var outputFilePath: String? = environmentValue(
    named: fileEnvironmentVariableName
  )

  package private(set) static var reasonCounts: [ReuseDenialReason: Int] = [:]
  package private(set) static var environmentKeyDiffCounts: [String: Int] = [:]
  package private(set) static var invalidatedIdentityPaths: Set<String> = []
  package private(set) static var suppressionScopeDescriptions: [String] = []

  package static func record(_ reason: ReuseDenialReason) {
    guard isEnabled else { return }
    reasonCounts[reason, default: 0] += 1
  }

  /// Identity paths denied for `suppressed` this frame (capped), so a
  /// multi-hundred-node `suppressed=` count can be decomposed by subtree —
  /// e.g. tab-strip chrome vs content payload on a focus-move frame.
  package private(set) static var suppressedIdentityPaths: [String] = []

  private static let maxRecordedSuppressedIdentityPaths = 512

  package static func recordSuppressedIdentity(_ path: String) {
    guard isEnabled,
      suppressedIdentityPaths.count < maxRecordedSuppressedIdentityPaths
    else { return }
    suppressedIdentityPaths.append(path)
  }

  package static func recordEnvironmentKeyDiff(_ key: String) {
    guard isEnabled else { return }
    environmentKeyDiffCounts[key, default: 0] += 1
  }

  /// Records the set of invalidated identity paths seen on a conflict (deduped),
  /// to reveal which dirty ancestor blocks the background's descendants.
  package static func recordInvalidatedIdentity(_ path: String) {
    guard isEnabled else { return }
    invalidatedIdentityPaths.insert(path)
  }

  /// Identity paths denied for `invalidation-conflict` this frame (capped) —
  /// the `suppressed-paths` counterpart for the conflict reason, so a
  /// multi-hundred-node `invalidation-conflict=` count can be decomposed into
  /// the denied nodes themselves, not just the invalidated identities that
  /// caused the denials.
  package private(set) static var conflictIdentityPaths: [String] = []

  private static let maxRecordedConflictIdentityPaths = 512

  package static func recordConflictIdentity(_ path: String) {
    guard isEnabled,
      conflictIdentityPaths.count < maxRecordedConflictIdentityPaths
    else { return }
    conflictIdentityPaths.append(path)
  }

  /// Identity paths denied for `no-node` this frame (capped) — the door
  /// consulted an identity with no live graph node, so the resolve minted a
  /// fresh subtree there. Decomposes a `no-node=` storm into the identities
  /// that failed to map (the coalesced flip+scroll seam's signature: a
  /// selective frame re-minting a committed subtree wholesale).
  package private(set) static var noNodeIdentityPaths: [String] = []

  private static let maxRecordedNoNodeIdentityPaths = 512

  package static func recordNoNodeIdentity(_ path: String) {
    guard isEnabled,
      noNodeIdentityPaths.count < maxRecordedNoNodeIdentityPaths
    else { return }
    noNodeIdentityPaths.append(path)
  }

  /// Test seam: observes each frame's reason histogram at `dumpAndReset`,
  /// before the per-frame reset erases it. Lets a deterministic fixture pin a
  /// specific frame's counter (e.g. the palette dismissal frame's
  /// `invalidation-conflict`) without parsing the emitted trace text.
  package static var onFrameSummary:
    ((_ frameID: UInt64, _ reasonCounts: [ReuseDenialReason: Int]) -> Void)?

  /// Records a description of one leg of the frame's retained-reuse
  /// suppression scope (focus or press moves), so a
  /// multi-hundred-node `suppressed=` count can be attributed to the member
  /// identities whose ancestor/descendant matching produced it. Recorded by
  /// the run loop when it composes the scope; appears as a `| scope:` segment
  /// on the frame's trace line.
  package static func recordSuppressionScopeDescription(_ description: String) {
    guard isEnabled else { return }
    suppressionScopeDescriptions.append(description)
  }

  /// Records one dirty-plan's frontier target identities (per resolve pass),
  /// so overlapping-target multiplicity — the same subtree resolved by more
  /// than one frontier evaluator in a frame — is attributable from the trace.
  package private(set) static var planTargetDescriptions: [String] = []

  package static func recordPlanTargets(_ paths: [String]) {
    guard isEnabled else { return }
    planTargetDescriptions.append(paths.joined(separator: "+"))
  }

  package static func reset() {
    reasonCounts.removeAll(keepingCapacity: true)
    environmentKeyDiffCounts.removeAll(keepingCapacity: true)
    invalidatedIdentityPaths.removeAll(keepingCapacity: true)
    suppressionScopeDescriptions.removeAll(keepingCapacity: true)
    suppressedIdentityPaths.removeAll(keepingCapacity: true)
    conflictIdentityPaths.removeAll(keepingCapacity: true)
    noNodeIdentityPaths.removeAll(keepingCapacity: true)
    planTargetDescriptions.removeAll(keepingCapacity: true)
  }

  /// Writes the accumulated histogram to stderr (if non-empty) and resets it.
  /// Called at `ViewGraph.beginFrame`, so each line summarizes the frame that
  /// just finished resolving.
  package static func dumpAndReset(frameID: UInt64) {
    if isEnabled, !reasonCounts.isEmpty {
      onFrameSummary?(frameID, reasonCounts)
    }
    guard isEnabled, !reasonCounts.isEmpty || !suppressionScopeDescriptions.isEmpty
    else {
      reset()
      return
    }
    var line = "[REUSE-TRACE] frame=\(frameID) recompute-reasons:"
    for (reason, count) in reasonCounts.sorted(by: { $0.value > $1.value }) {
      line += " \(reason.rawValue)=\(count)"
    }
    if !environmentKeyDiffCounts.isEmpty {
      line += " | env-diffs:"
      for (key, count) in environmentKeyDiffCounts.sorted(by: { $0.value > $1.value }) {
        line += " \(key)=\(count)"
      }
    }
    if !invalidatedIdentityPaths.isEmpty {
      line += " | invalidated: " + invalidatedIdentityPaths.sorted().joined(separator: ",")
    }
    if !suppressionScopeDescriptions.isEmpty {
      line += " | scope: " + suppressionScopeDescriptions.joined(separator: ";")
    }
    if !suppressedIdentityPaths.isEmpty {
      line += " | suppressed-paths: " + suppressedIdentityPaths.joined(separator: ",")
    }
    if !conflictIdentityPaths.isEmpty {
      line += " | conflict-paths: " + conflictIdentityPaths.joined(separator: ",")
    }
    if !noNodeIdentityPaths.isEmpty {
      line += " | no-node-paths: " + noNodeIdentityPaths.joined(separator: ",")
    }
    if !planTargetDescriptions.isEmpty {
      line += " | plan-targets: " + planTargetDescriptions.joined(separator: ";")
    }
    line += "\n"
    emit(line)
    reset()
  }

  /// Routes a trace line to the configured file sink (when `outputFilePath`
  /// is set and writable), else the debug bundle, otherwise stderr — see
  /// ``DebugLogRouter``.
  private static func emit(_ message: String) {
    DebugLogRouter.emit(
      message,
      toFileAt: DebugLogRouter.resolvedFilePath(
        override: outputFilePath, bundleFileName: "reuse.log"
      )
    )
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return DebugTraceSelection.current.isArmed(.reuse)
    }
    return FeatureFlags.booleanValue(rawValue) ?? false
  }

  private static func environmentValue(named name: String) -> String? {
    FeatureFlags.environmentValue(named: name)
  }
}

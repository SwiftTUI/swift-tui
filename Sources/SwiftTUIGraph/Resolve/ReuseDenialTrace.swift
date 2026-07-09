#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// Diagnostic-only trace of **why retained reuse was denied** per node, gated by
/// `SWIFTTUI_REUSE_TRACE` (default off). Inert and zero-cost when disabled.
///
/// Each resolve pass that recomputes a node instead of reusing it records the
/// reason (suppressed / env-mismatch / dirty / invalidation-conflict / …); for
/// `env-mismatch` it also records which environment keys differ. ``ViewGraph``
/// dumps and resets the per-frame histogram to stderr at `beginFrame`, so the
/// stream shows one `[REUSE-TRACE]` line per frame. Used to find what re-resolves
/// the background on sheet/palette open.
@MainActor
package enum ReuseDenialTrace {
  package static let environmentVariableName = "SWIFTTUI_REUSE_TRACE"

  /// Optional file sink. When `SWIFTTUI_REUSE_TRACE_FILE` names a writable path,
  /// each `[REUSE-TRACE]` line is appended there instead of stderr. The trace is
  /// otherwise stderr-only, where it is easily lost among build/runtime output
  /// (this is why it was previously misread as silent on the release perf path).
  /// A file sink makes the diagnostic a durable, run-correlated artifact.
  /// `nil` keeps the historical stderr behavior. Settable for tests.
  package static let fileEnvironmentVariableName = "SWIFTTUI_REUSE_TRACE_FILE"

  package static var isEnabled: Bool = environmentDefault()

  /// Resolved once on first emit. When set, trace lines append to this path
  /// (created if missing); when `nil`, they go to stderr.
  package static var outputFilePath: String? = environmentValue(
    named: fileEnvironmentVariableName
  )

  package private(set) static var reasonCounts: [String: Int] = [:]
  package private(set) static var environmentKeyDiffCounts: [String: Int] = [:]
  package private(set) static var invalidatedIdentityPaths: Set<String> = []
  package private(set) static var suppressionScopeDescriptions: [String] = []

  package static func record(_ reason: String) {
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

  /// Records a description of one leg of the frame's retained-reuse
  /// suppression scope (focus move, press move, animation cones), so a
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
    planTargetDescriptions.removeAll(keepingCapacity: true)
  }

  /// Writes the accumulated histogram to stderr (if non-empty) and resets it.
  /// Called at `ViewGraph.beginFrame`, so each line summarizes the frame that
  /// just finished resolving.
  package static func dumpAndReset(frameID: UInt64) {
    guard isEnabled, !reasonCounts.isEmpty || !suppressionScopeDescriptions.isEmpty
    else {
      reset()
      return
    }
    var line = "[REUSE-TRACE] frame=\(frameID) recompute-reasons:"
    for (reason, count) in reasonCounts.sorted(by: { $0.value > $1.value }) {
      line += " \(reason)=\(count)"
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
    if !planTargetDescriptions.isEmpty {
      line += " | plan-targets: " + planTargetDescriptions.joined(separator: ";")
    }
    line += "\n"
    emit(line)
    reset()
  }

  /// Routes a trace line to the configured file sink (when `outputFilePath` is
  /// set and writable) otherwise to stderr — see ``DiagnosticTraceSink``.
  private static func emit(_ message: String) {
    DiagnosticTraceSink.emit(message, toFileAt: outputFilePath)
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return false
    }
    return !rawValue.isEmpty && rawValue != "0"
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}

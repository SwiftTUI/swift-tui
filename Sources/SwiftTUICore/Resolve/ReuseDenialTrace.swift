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

  package static var isEnabled: Bool = environmentDefault()

  package private(set) static var reasonCounts: [String: Int] = [:]
  package private(set) static var environmentKeyDiffCounts: [String: Int] = [:]
  package private(set) static var invalidatedIdentityPaths: Set<String> = []

  package static func record(_ reason: String) {
    guard isEnabled else { return }
    reasonCounts[reason, default: 0] += 1
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

  package static func reset() {
    reasonCounts.removeAll(keepingCapacity: true)
    environmentKeyDiffCounts.removeAll(keepingCapacity: true)
    invalidatedIdentityPaths.removeAll(keepingCapacity: true)
  }

  /// Writes the accumulated histogram to stderr (if non-empty) and resets it.
  /// Called at `ViewGraph.beginFrame`, so each line summarizes the frame that
  /// just finished resolving.
  package static func dumpAndReset(frameID: UInt64) {
    guard isEnabled, !reasonCounts.isEmpty else {
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
    line += "\n"
    unsafe line.withCString { pointer in
      _ = unsafe fputs(pointer, stderr)
    }
    reset()
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

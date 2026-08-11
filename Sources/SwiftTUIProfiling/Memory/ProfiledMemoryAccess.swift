import SwiftTUICore

/// Coordination-only occupancy data for out-of-package performance tooling (TermUIPerf).
/// The collector, registry, and snapshot types have `package` scope.
/// Thus, an external tool cannot read them directly.
/// This public `@_spi(Runners)` data transfer object exposes the occupancy data to the harness.
/// It does not use the process-wide timer and sink in the activation layer.
@_spi(Runners)
public struct ProfiledMemorySnapshot: Sendable {
  public let name: String
  public let count: Int
  public let approxBytes: Int?
  /// Provider-specific counters carried alongside the occupancy figure: for a
  /// cache, its `lookups`/`hits`/`misses`.
  ///
  /// Entry count alone does not show whether a cache serves its lookups.
  /// A cache at 20 entries can serve all lookups or miss all lookups.
  /// These counters distinguish the two cases.
  public let detail: [String: Int]?

  public init(name: String, count: Int, approxBytes: Int?, detail: [String: Int]? = nil) {
    self.name = name
    self.count = count
    self.approxBytes = approxBytes
    self.detail = detail
  }
}

@_spi(Runners)
public enum ProfiledMemory {
  /// Snapshots every registered occupancy provider once. Includes the synthetic
  /// `MemoryMetricRegistry.providerCount` meta metric.
  @MainActor
  public static func snapshot() -> [ProfiledMemorySnapshot] {
    MemoryMetricCollector().collect().map {
      ProfiledMemorySnapshot(
        name: $0.name,
        count: $0.count,
        approxBytes: $0.approxBytes,
        detail: $0.detail
      )
    }
  }
}

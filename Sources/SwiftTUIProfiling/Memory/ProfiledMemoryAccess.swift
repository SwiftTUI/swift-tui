import SwiftTUICore

/// Coordination-only: an on-demand occupancy read for out-of-package perf
/// tooling (TermUIPerf). The collector, registry, and snapshot types are all
/// `package`-scoped, so an external tool cannot poll them directly. This exposes
/// the read step through an `@_spi(Runners)` public DTO so the harness can
/// sample occupancy itself, without the activation layer's timer + sink
/// machinery (which is a process-wide singleton and awkward to drive per-run).
@_spi(Runners)
public struct ProfiledMemorySnapshot: Sendable {
  public let name: String
  public let count: Int
  public let approxBytes: Int?
  /// Provider-specific counters carried alongside the occupancy figure — for a
  /// cache, its `lookups`/`hits`/`misses`.
  ///
  /// Entry count alone cannot answer "is this cache working": a cache that
  /// plateaus at 20 entries looks identical whether it is serving every lookup
  /// from those 20 or missing on all of them. Dropping this payload is what
  /// made the steady-state wrap-count condition unassertable in the 2026-07-28
  /// deep-dive close-out (plan 2026-07-30-002, Wave B).
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

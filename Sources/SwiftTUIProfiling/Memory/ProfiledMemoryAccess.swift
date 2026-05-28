package import SwiftTUICore

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

  public init(name: String, count: Int, approxBytes: Int?) {
    self.name = name
    self.count = count
    self.approxBytes = approxBytes
  }
}

@_spi(Runners)
public enum ProfiledMemory {
  /// Snapshots every registered occupancy provider once. Includes the synthetic
  /// `MemoryMetricRegistry.providerCount` meta metric.
  @MainActor
  public static func snapshot() -> [ProfiledMemorySnapshot] {
    MemoryMetricCollector().collect().map {
      ProfiledMemorySnapshot(name: $0.name, count: $0.count, approxBytes: $0.approxBytes)
    }
  }
}

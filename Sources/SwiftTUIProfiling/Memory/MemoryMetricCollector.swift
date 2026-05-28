package import SwiftTUICore

/// Reads the runtime's occupancy registry on demand. Each call snapshots every
/// registered ``MemoryMetricProvider`` and appends a synthetic
/// `MemoryMetricRegistry.providerCount` metric — a meta signal whose steady
/// growth reveals graph-scoped providers that never deregistered (a retained
/// graph).
///
/// The cadence (a periodic timer) and emission to sinks are owned by the
/// activation layer; this type is the pure read step.
package struct MemoryMetricCollector: Sendable {
  package init() {}

  package func collect() -> [MemoryMetricSnapshot] {
    var snapshots = MemoryMetricRegistry.shared.snapshotAll()
    snapshots.append(
      MemoryMetricSnapshot(
        name: "MemoryMetricRegistry.providerCount",
        count: MemoryMetricRegistry.shared.providerCount
      )
    )
    return snapshots
  }
}

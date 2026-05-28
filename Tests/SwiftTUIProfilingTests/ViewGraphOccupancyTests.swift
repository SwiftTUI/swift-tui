import Testing

@testable import SwiftTUICore
@testable import SwiftTUIProfiling

@MainActor
@Suite
struct ViewGraphOccupancyTests {
  @Test("An empty ViewGraph reports a zero-count occupancy snapshot")
  func emptyGraphSnapshot() {
    let snapshot = ViewGraph().memoryMetricSnapshot
    #expect(snapshot.name == "ViewGraph.nodesByIdentity")
    #expect(snapshot.count == 0)
    #expect(snapshot.detail?["liveIdentities"] == 0)
  }

  @Test("A MainActor-isolated provider is surfaced by the collector")
  func mainActorProviderCollected() {
    let graph = ViewGraph()
    let token = MemoryMetricRegistry.shared.register(
      ClosureMemoryMetricProvider { [weak graph] in
        graph?.memoryMetricSnapshot
          ?? MemoryMetricSnapshot(name: "ViewGraph.nodesByIdentity", count: 0)
      }
    )
    withExtendedLifetime(token) {
      let snapshots = MemoryMetricCollector().collect()
      #expect(snapshots.contains { $0.name == "ViewGraph.nodesByIdentity" })
    }
  }
}

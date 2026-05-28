import Testing

@testable import SwiftTUICore
@testable import SwiftTUIProfiling

@Suite
struct MemoryMetricCollectorTests {
  @Test("Collector reports the shared TextLayoutCache plus the providerCount meta metric")
  func collectsTextLayoutCacheAndProviderCount() {
    // Touching the shared cache triggers its permanent provider registration.
    _ = TextLayoutCache.shared

    let snapshots = MemoryMetricCollector().collect()

    let textLayout = snapshots.first { $0.name == "TextLayoutCache.entries" }
    #expect(textLayout != nil)
    #expect(textLayout?.detail?["order"] != nil)

    let providerCount = snapshots.first { $0.name == "MemoryMetricRegistry.providerCount" }
    #expect(providerCount != nil)
    // At least the TextLayoutCache provider is registered after touching shared.
    #expect((providerCount?.count ?? 0) >= 1)
  }
}

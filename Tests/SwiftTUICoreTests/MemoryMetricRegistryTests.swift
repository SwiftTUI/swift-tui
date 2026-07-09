import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

private struct StubProvider: MemoryMetricProvider {
  let value: MemoryMetricSnapshot
  @MainActor func snapshot() -> MemoryMetricSnapshot { value }
}

@MainActor
@Suite
struct MemoryMetricRegistryTests {
  @Test("A registered provider is counted and snapshotted")
  func registersAndSnapshots() {
    let registry = MemoryMetricRegistry()
    #expect(registry.providerCount == 0)

    let token = registry.register(
      StubProvider(
        value: .init(name: "Cache.entries", count: 3, approxBytes: 12, detail: ["hits": 2])
      )
    )
    withExtendedLifetime(token) {
      #expect(registry.providerCount == 1)
      let snapshots = registry.snapshotAll()
      #expect(snapshots.count == 1)
      #expect(
        snapshots.first
          == MemoryMetricSnapshot(
            name: "Cache.entries",
            count: 3,
            approxBytes: 12,
            detail: ["hits": 2]
          )
      )
    }
  }

  @Test("Releasing the token deregisters the provider")
  func tokenReleaseDeregisters() {
    let registry = MemoryMetricRegistry()
    var token: MemoryMetricRegistry.Token? = registry.register(
      StubProvider(value: .init(name: "Cache.entries", count: 1))
    )
    #expect(token != nil)
    #expect(registry.providerCount == 1)

    token = nil
    #expect(registry.providerCount == 0)
    #expect(registry.snapshotAll().isEmpty)
  }

  @Test("Tokens are independent; releasing one leaves the rest registered")
  func independentTokens() {
    let registry = MemoryMetricRegistry()
    let keep = registry.register(StubProvider(value: .init(name: "A", count: 1)))
    var drop: MemoryMetricRegistry.Token? = registry.register(
      StubProvider(value: .init(name: "B", count: 2))
    )
    #expect(drop != nil)
    #expect(registry.providerCount == 2)

    drop = nil
    withExtendedLifetime(keep) {
      #expect(registry.providerCount == 1)
      #expect(registry.snapshotAll().map(\.name) == ["A"])
    }
  }
}

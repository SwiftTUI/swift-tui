import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

private struct StressCacheCost: BoundedLRUCost, Equatable {
  var entries: Int
  var bytes: Int

  static let zero = StressCacheCost(entries: 0, bytes: 0)
  static func + (lhs: Self, rhs: Self) -> Self {
    .init(entries: lhs.entries + rhs.entries, bytes: lhs.bytes + rhs.bytes)
  }
  static func - (lhs: Self, rhs: Self) -> Self {
    .init(entries: lhs.entries - rhs.entries, bytes: lhs.bytes - rhs.bytes)
  }
  func violates(_ policy: Self) -> Bool {
    entries > policy.entries || bytes > policy.bytes
  }
}

private func stressCacheEntry(_ bytes: Int) -> StressCacheCost {
  .init(entries: 1, bytes: bytes)
}

@Suite("SwiftTUI cache state-machine stress behavior", .serialized)
struct FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 001 replacing LRU promotes it before eviction")
  func cacheState001ReplacingLRUPromotesItBeforeEviction() {
    // Hypothesis: updating the LRU node can leave its old links in place and evict it next.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 2, bytes: .max)
    cache.upsert("a", value: 1, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("a", value: 10, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("c", value: 3, cost: stressCacheEntry(1), policy: policy)
    #expect(cache.peek("a") == 10)
    #expect(cache.peek("b") == nil)
    #expect(cache.peek("c") == 3)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 002 removing LRU preserves neighbor chain")
  func cacheState002RemovingLRUPreservesNeighborChain() {
    // Hypothesis: unlinking the head can leave the next node's previous pointer dangling.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 2, bytes: .max)
    cache.upsert("a", value: 1, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(1), policy: policy)
    cache.removeValue(forKey: "a")
    cache.upsert("c", value: 3, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("d", value: 4, cost: stressCacheEntry(1), policy: policy)
    #expect(cache.peek("b") == nil)
    #expect(cache.peek("c") == 3)
    #expect(cache.peek("d") == 4)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 003 removing MRU keeps survivor promotable")
  func cacheState003RemovingMRUKeepsSurvivorPromotable() {
    // Hypothesis: unlinking the tail can strand mruKey on the removed node.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 2, bytes: .max)
    cache.upsert("a", value: 1, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(1), policy: policy)
    cache.removeValue(forKey: "b")
    #expect(cache.recordAccess("a") == 1)
    cache.upsert("c", value: 3, cost: stressCacheEntry(1), policy: policy)
    cache.upsert("d", value: 4, cost: stressCacheEntry(1), policy: policy)
    #expect(cache.peek("a") == nil)
    #expect(cache.peek("c") == 3)
    #expect(cache.peek("d") == 4)
  }
}

// NEXT CACHE STRESS TEST

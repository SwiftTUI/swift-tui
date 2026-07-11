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

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 004 tightening policy evicts from live recency")
  func cacheState004TighteningPolicyEvictsFromLiveRecency() {
    // Hypothesis: an upsert under a tighter policy can evict in insertion instead of recency order.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let wide = StressCacheCost(entries: 4, bytes: 100)
    cache.upsert("a", value: 1, cost: stressCacheEntry(10), policy: wide)
    cache.upsert("b", value: 2, cost: stressCacheEntry(10), policy: wide)
    cache.upsert("c", value: 3, cost: stressCacheEntry(10), policy: wide)
    cache.recordAccess("a")
    cache.upsert("d", value: 4, cost: stressCacheEntry(10), policy: .init(entries: 2, bytes: 25))
    #expect(cache.peek("a") == 1)
    #expect(cache.peek("d") == 4)
    #expect(cache.count == 2)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 005 zero policy protects only latest entry")
  func cacheState005ZeroPolicyProtectsOnlyLatestEntry() {
    // Hypothesis: a policy that every entry violates can loop or preserve an older neighbor.
    var cache = BoundedLRUCache<Int, Int, StressCacheCost>()
    let zero = StressCacheCost.zero
    for value in 0..<40 {
      cache.upsert(value, value: value, cost: stressCacheEntry(1), policy: zero)
      #expect(cache.count == 1)
      #expect(cache.peek(value) == value)
    }
    #expect(cache.evictionCount == 39)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 006 oversized replacement evicts peers not itself")
  func cacheState006OversizedReplacementEvictsPeersNotItself() {
    // Hypothesis: replacing a protected key with a larger cost can stop before older peers drain.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 3, bytes: 30)
    cache.upsert("a", value: 1, cost: stressCacheEntry(10), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(10), policy: policy)
    cache.upsert("c", value: 3, cost: stressCacheEntry(10), policy: policy)
    cache.upsert("b", value: 20, cost: stressCacheEntry(100), policy: policy)
    #expect(cache.count == 1)
    #expect(cache.peek("b") == 20)
    #expect(cache.totalCost == stressCacheEntry(100))
  }
}

// NEXT CACHE STRESS TEST

import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

private struct TestCost: BoundedLRUCost {
  var entries: Int
  var bytes: Int

  static let zero = TestCost(entries: 0, bytes: 0)

  static func + (lhs: TestCost, rhs: TestCost) -> TestCost {
    TestCost(entries: lhs.entries + rhs.entries, bytes: lhs.bytes + rhs.bytes)
  }

  static func - (lhs: TestCost, rhs: TestCost) -> TestCost {
    TestCost(entries: lhs.entries - rhs.entries, bytes: lhs.bytes - rhs.bytes)
  }

  func violates(_ policy: TestCost) -> Bool {
    entries > policy.entries || bytes > policy.bytes
  }
}

@Suite
struct BoundedLRUCacheTests {
  private func entry(_ bytes: Int) -> TestCost {
    TestCost(entries: 1, bytes: bytes)
  }

  private let unlimited = TestCost(entries: .max, bytes: .max)

  @Test("evicts the least-recently-used entry past the entry cap")
  func evictsLeastRecentlyUsed() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    let policy = TestCost(entries: 2, bytes: .max)
    cache.upsert("a", value: 1, cost: entry(1), policy: policy)
    cache.upsert("b", value: 2, cost: entry(1), policy: policy)
    // Touch "a" so "b" becomes the least-recently-used.
    cache.recordAccess("a")
    cache.upsert("c", value: 3, cost: entry(1), policy: policy)

    #expect(cache.count == 2)
    #expect(cache.evictionCount == 1)
    #expect(cache.peek("b") == nil)  // evicted
    #expect(cache.peek("a") == 1)
    #expect(cache.peek("c") == 3)
  }

  @Test("running cost total tracks inserts, replaces, and evictions")
  func runningCostTotal() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    cache.upsert("a", value: 1, cost: entry(10), policy: unlimited)
    cache.upsert("b", value: 2, cost: entry(20), policy: unlimited)
    #expect(cache.totalCost == TestCost(entries: 2, bytes: 30))

    // Replace "a" with a larger cost.
    cache.upsert("a", value: 1, cost: entry(100), policy: unlimited)
    #expect(cache.totalCost == TestCost(entries: 2, bytes: 120))

    cache.removeValue(forKey: "b")
    #expect(cache.totalCost == TestCost(entries: 1, bytes: 100))
  }

  @Test("byte budget evicts until satisfied without touching the new key")
  func byteBudgetEviction() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    let policy = TestCost(entries: .max, bytes: 100)
    cache.upsert("a", value: 1, cost: entry(60), policy: policy)
    cache.upsert("b", value: 2, cost: entry(60), policy: policy)  // evicts "a" (120 > 100)

    #expect(cache.count == 1)
    #expect(cache.peek("a") == nil)
    #expect(cache.peek("b") == 2)
    #expect(cache.totalCost.bytes == 60)
    #expect(cache.evictionCount == 1)
  }

  @Test("an oversize new entry is retained rather than evicting itself")
  func oversizeEntryRetained() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    let policy = TestCost(entries: .max, bytes: 50)
    cache.upsert("big", value: 1, cost: entry(1000), policy: policy)
    #expect(cache.count == 1)
    #expect(cache.peek("big") == 1)
    #expect(cache.evictionCount == 0)
  }

  @Test("removeAll clears entries and cost but preserves the lifetime eviction count")
  func removeAllPreservesEvictionCount() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    let policy = TestCost(entries: 1, bytes: .max)
    cache.upsert("a", value: 1, cost: entry(1), policy: policy)
    cache.upsert("b", value: 2, cost: entry(1), policy: policy)  // evicts "a"
    #expect(cache.evictionCount == 1)

    cache.removeAll()
    #expect(cache.count == 0)
    #expect(cache.totalCost == .zero)
    #expect(cache.evictionCount == 1)
    #expect(cache.peek("b") == nil)

    // Still usable after clearing.
    cache.upsert("c", value: 3, cost: entry(1), policy: policy)
    #expect(cache.peek("c") == 3)
  }

  @Test("recordAccess on a missing key is a no-op returning nil")
  func recordAccessMissingKey() {
    var cache = BoundedLRUCache<String, Int, TestCost>()
    #expect(cache.recordAccess("nope") == nil)
    cache.upsert("a", value: 1, cost: entry(1), policy: unlimited)
    #expect(cache.recordAccess("a") == 1)
  }

  @Test("repeated eviction keeps the list consistent under churn")
  func churnConsistency() {
    var cache = BoundedLRUCache<Int, Int, TestCost>()
    let policy = TestCost(entries: 8, bytes: .max)
    for i in 0..<200 {
      cache.upsert(i, value: i, cost: entry(1), policy: policy)
      if i % 3 == 0 {
        cache.recordAccess(max(0, i - 1))
      }
    }
    #expect(cache.count == 8)
    #expect(cache.totalCost.entries == 8)
    // The most recent insert must survive.
    #expect(cache.peek(199) == 199)
  }
}

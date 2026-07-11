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

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 007 missing removals leave cost and recency unchanged")
  func cacheState007MissingRemovalsLeaveCostAndRecencyUnchanged() {
    // Hypothesis: a miss on remove can accidentally advance or sever a recency anchor.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 2, bytes: 20)
    cache.upsert("a", value: 1, cost: stressCacheEntry(5), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(5), policy: policy)
    for index in 0..<50 { cache.removeValue(forKey: "missing-\(index)") }
    cache.upsert("c", value: 3, cost: stressCacheEntry(5), policy: policy)
    #expect(cache.peek("a") == nil)
    #expect(cache.peek("b") == 2)
    #expect(cache.totalCost == .init(entries: 2, bytes: 10))
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 008 alternating touches select the true victim")
  func cacheState008AlternatingTouchesSelectTheTrueVictim() {
    // Hypothesis: repeated nonadjacent promotions can duplicate links and evict the wrong key.
    var cache = BoundedLRUCache<Int, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 4, bytes: .max)
    for key in 0..<4 { cache.upsert(key, value: key, cost: stressCacheEntry(1), policy: policy) }
    for key in [0, 2, 1, 0, 3, 2] { cache.recordAccess(key) }
    cache.upsert(4, value: 4, cost: stressCacheEntry(1), policy: policy)
    #expect(cache.peek(1) == nil)
    #expect([0, 2, 3, 4].allSatisfy { cache.peek($0) == $0 })
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 009 either budget dimension drains enough victims")
  func cacheState009EitherBudgetDimensionDrainsEnoughVictims() {
    // Hypothesis: satisfying the entry cap can stop eviction while bytes still exceed policy.
    var cache = BoundedLRUCache<String, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 3, bytes: 12)
    cache.upsert("a", value: 1, cost: stressCacheEntry(6), policy: policy)
    cache.upsert("b", value: 2, cost: stressCacheEntry(6), policy: policy)
    cache.upsert("c", value: 3, cost: stressCacheEntry(6), policy: policy)
    #expect(cache.count == 2)
    #expect(cache.totalCost.bytes == 12)
    #expect(cache.peek("a") == nil)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 010 repeated clear cycles rebuild both anchors")
  func cacheState010RepeatedClearCyclesRebuildBothAnchors() {
    // Hypothesis: removeAll can leave a stale list endpoint after repeated eviction history.
    var cache = BoundedLRUCache<Int, Int, StressCacheCost>()
    let policy = StressCacheCost(entries: 3, bytes: .max)
    for cycle in 0..<30 {
      for offset in 0..<8 {
        let key = cycle * 10 + offset
        cache.upsert(key, value: key, cost: stressCacheEntry(1), policy: policy)
      }
      cache.removeAll()
      #expect(cache.count == 0)
      #expect(cache.totalCost == .zero)
    }
    cache.upsert(999, value: 999, cost: stressCacheEntry(1), policy: policy)
    #expect(cache.peek(999) == 999)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 011 capacity one admits a repeated bypassed key")
  func cacheState011CapacityOneAdmitsRepeatedBypassedKey() {
    // Hypothesis: a one-entry cache can never promote a twice-seen bypass candidate.
    let cache = TextLayoutCache(capacity: 1)
    let options = TextLayoutOptions(width: 4)
    _ = cache.layout(for: "alpha", options: options)
    _ = cache.layout(for: "beta", options: options)
    _ = cache.layout(for: "alpha", options: options)
    let beta = cache.layout(for: "beta", options: options)
    #expect(beta.lines.map(\.text) == ["beta"])
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.stores == 2)
    #expect(cache.metrics.evictions == 1)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 012 old admission candidates expire under churn")
  func cacheState012OldAdmissionCandidatesExpireUnderChurn() {
    // Hypothesis: candidate compaction can keep the oldest key forever and admit it too eagerly.
    let cache = TextLayoutCache(capacity: 2)
    let options = TextLayoutOptions(width: nil)
    _ = cache.layout(for: "warm-a", options: options)
    _ = cache.layout(for: "warm-b", options: options)
    _ = cache.layout(for: "old-candidate", options: options)
    for index in 0..<30 { _ = cache.layout(for: "one-shot-\(index)", options: options) }
    let before = cache.metrics
    _ = cache.layout(for: "old-candidate", options: options)
    #expect(cache.metrics.stores == before.stores)
    #expect(cache.metrics.bypassedStores == before.bypassedStores + 1)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 013 reset clears admission history")
  func cacheState013ResetClearsAdmissionHistory() {
    // Hypothesis: reset can clear entries but leave a bypass candidate ready for immediate admission.
    let cache = TextLayoutCache(capacity: 1)
    let options = TextLayoutOptions(width: nil)
    _ = cache.layout(for: "alpha", options: options)
    _ = cache.layout(for: "beta", options: options)
    cache.reset()
    _ = cache.layout(for: "gamma", options: options)
    _ = cache.layout(for: "beta", options: options)
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.stores == 1)
    #expect(cache.metrics.bypassedStores == 1)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 014 reset restarts every public metric")
  func cacheState014ResetRestartsEveryPublicMetric() {
    // Hypothesis: hit-heavy access-log state can leak counters into the next epoch.
    let cache = TextLayoutCache(capacity: 4)
    let options = TextLayoutOptions(width: 5)
    for _ in 0..<20 { _ = cache.layout(for: "alpha beta", options: options) }
    cache.reset()
    #expect(cache.metrics == .init())
    #expect(cache.accessLogDepth == 0)
    _ = cache.layout(for: "fresh", options: options)
    #expect(cache.metrics == .init(entries: 1, lookups: 1, hits: 0, misses: 1, stores: 1))
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 015 bounded and unbounded widths never alias")
  func cacheState015BoundedAndUnboundedWidthsNeverAlias() {
    // Hypothesis: nil width and a large finite width can collide after key normalization.
    let cache = TextLayoutCache(capacity: 4)
    let content = "alpha beta gamma"
    let bounded = cache.layout(for: content, options: .init(width: 5))
    let unbounded = cache.layout(for: content, options: .init(width: nil))
    #expect(bounded != unbounded)
    #expect(cache.metrics.entries == 2)
    _ = cache.layout(for: content, options: .init(width: 5))
    _ = cache.layout(for: content, options: .init(width: nil))
    #expect(cache.metrics.hits == 2)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 016 zero and one line limits remain separate keys")
  func cacheState016ZeroAndOneLineLimitsRemainSeparateKeys() {
    // Hypothesis: equal clamped output can collapse distinct authored option keys.
    let cache = TextLayoutCache(capacity: 4)
    let content = "alpha beta gamma"
    let zero = cache.layout(for: content, options: .init(width: 5, lineLimit: 0))
    let one = cache.layout(for: content, options: .init(width: 5, lineLimit: 1))
    #expect(zero == one)
    #expect(cache.metrics.entries == 2)
    #expect(cache.metrics.misses == 2)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 017 three truncation modes retain independent entries")
  func cacheState017ThreeTruncationModesRetainIndependentEntries() {
    // Hypothesis: revisiting a mode after two siblings can return the last computed truncation.
    let cache = TextLayoutCache(capacity: 4)
    let content = "abcdefghijk"
    let head = cache.layout(for: content, options: .init(width: 5, lineLimit: 1, truncationMode: .head))
    let middle = cache.layout(for: content, options: .init(width: 5, lineLimit: 1, truncationMode: .middle))
    let tail = cache.layout(for: content, options: .init(width: 5, lineLimit: 1, truncationMode: .tail))
    #expect(Set([head.lines[0].text, middle.lines[0].text, tail.lines[0].text]).count == 3)
    #expect(cache.layout(for: content, options: .init(width: 5, lineLimit: 1, truncationMode: .head)) == head)
    #expect(cache.metrics.entries == 3)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 018 canonical Unicode spellings converge safely")
  func cacheState018CanonicalUnicodeSpellingsConvergeSafely() {
    // Hypothesis: canonically equal String keys can return incompatible cluster geometry.
    let cache = TextLayoutCache(capacity: 4)
    let composed = cache.layout(for: "é", options: .init(width: nil))
    let decomposed = cache.layout(for: "e\u{301}", options: .init(width: nil))
    #expect(composed.lines[0].text == "é")
    #expect(decomposed.lines[0].text == "e\u{301}")
    #expect(decomposed == composed)
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.hits == 1)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 019 newline and whitespace topology never alias")
  func cacheState019NewlineAndWhitespaceTopologyNeverAlias() {
    // Hypothesis: equal scalar counts can share a key while explicit line topology differs.
    let cache = TextLayoutCache(capacity: 4)
    let newline = cache.layout(for: "ab\ncd", options: .init(width: 8))
    let spaces = cache.layout(for: "ab cd", options: .init(width: 8))
    #expect(newline.lines.count == 2)
    #expect(spaces.lines.count == 1)
    #expect(cache.layout(for: "ab\ncd", options: .init(width: 8)) == newline)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 020 wide glyph revisits preserve cell geometry")
  func cacheState020WideGlyphRevisitsPreserveCellGeometry() {
    // Hypothesis: an equal character count ASCII lookup can poison a later wide-glyph hit.
    let cache = TextLayoutCache(capacity: 4)
    let wide = cache.layout(for: "界界", options: .init(width: 3))
    _ = cache.layout(for: "abcd", options: .init(width: 3))
    let revisited = cache.layout(for: "界界", options: .init(width: 3))
    #expect(revisited == wide)
    #expect(revisited.size == wide.size)
    #expect(cache.metrics.hits == 1)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 021 zero and negative widths retain authored keys")
  func cacheState021ZeroAndNegativeWidthsRetainAuthoredKeys() {
    // Hypothesis: nonpositive widths can normalize during layout but collide in cache bookkeeping.
    let cache = TextLayoutCache(capacity: 4)
    let zero = cache.layout(for: "alpha", options: .init(width: 0))
    let negative = cache.layout(for: "alpha", options: .init(width: -1))
    #expect(cache.metrics.entries == 2)
    #expect(cache.layout(for: "alpha", options: .init(width: 0)) == zero)
    #expect(cache.layout(for: "alpha", options: .init(width: -1)) == negative)
    #expect(cache.metrics.hits == 2)
  }
}

extension FrameworkStressCacheStateMachineTests {
  @Test("stress cache state machine 022 hot hits stay bounded beside cold misses")
  func cacheState022HotHitsStayBoundedBesideColdMisses() {
    // Hypothesis: cold admission logging can prevent compaction of the hot-entry access log.
    let cache = TextLayoutCache(capacity: 4)
    let options = TextLayoutOptions(width: nil)
    for label in ["hot-a", "hot-b", "hot-c", "hot-d"] {
      _ = cache.layout(for: label, options: options)
    }
    for generation in 0..<2_000 {
      _ = cache.layout(for: generation.isMultiple(of: 2) ? "hot-a" : "hot-b", options: options)
      _ = cache.layout(for: "cold-\(generation)", options: options)
    }
    #expect(cache.metrics.entries == 4)
    #expect(cache.accessLogDepth <= 16)
  }
}

// NEXT CACHE STRESS TEST

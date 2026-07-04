/// Additive cost of a cache entry along one or more budgeted dimensions (entry
/// count, decoded pixels, encoded bytes, ...). `violates(_:)` compares a running
/// total against a policy expressed in the same type, returning true if any
/// dimension exceeds its cap. Because the total is maintained incrementally, the
/// check is O(1) — the terminal image caches previously recomputed full-cache
/// aggregates on every store (O(n) per store, O(n^2) when a store evicted many).
protocol BoundedLRUCost: AdditiveArithmetic, Sendable {
  /// The cache's own budget type (e.g. `ImageBlendCompositorCachePolicy`). Kept
  /// separate from the cost so a cache can budget several cost dimensions under
  /// one cap (the blend cache's `encoded + metadata` bytes vs `maxEncodedBytes`).
  associatedtype Policy: Sendable
  func violates(_ policy: Policy) -> Bool
}

/// A generic bounded cache with least-recently-used eviction and O(1) amortized
/// touch/insert/evict, shared by the terminal image subsystem's decode, blend,
/// and payload caches (F52). Recency is an intrusive doubly-linked list threaded
/// through the entry dictionary — no per-store min-scan or aggregate recompute.
/// Not thread-safe; callers hold it inside their own lock (as the image caches
/// already do).
struct BoundedLRUCache<Key: Hashable & Sendable, Value: Sendable, Cost: BoundedLRUCost> {
  private struct Node {
    var value: Value
    var cost: Cost
    /// Neighbor toward the least-recently-used end (`lruKey`).
    var previous: Key?
    /// Neighbor toward the most-recently-used end (`mruKey`).
    var next: Key?
  }

  private var nodes: [Key: Node] = [:]
  private var lruKey: Key?
  private var mruKey: Key?
  private(set) var totalCost: Cost = .zero
  private(set) var evictionCount = 0

  var count: Int {
    nodes.count
  }

  /// Returns the value without changing recency (no move-to-MRU). Callers that
  /// count a lookup as an access follow up with `recordAccess`.
  func peek(_ key: Key) -> Value? {
    nodes[key]?.value
  }

  /// Promotes `key` to most-recently-used and returns its value, or nil if
  /// absent.
  @discardableResult
  mutating func recordAccess(_ key: Key) -> Value? {
    guard let value = nodes[key]?.value else {
      return nil
    }
    moveToMRU(key)
    return value
  }

  /// Inserts or replaces `key`, promotes it to most-recently-used, then evicts
  /// least-recently-used entries until `policy` is satisfied. The just-written
  /// key is never evicted, so an entry that alone exceeds a budget is retained
  /// (matching the prior caches' `protecting:` behavior).
  mutating func upsert(
    _ key: Key,
    value: Value,
    cost: Cost,
    policy: Cost.Policy
  ) {
    if var existing = nodes[key] {
      totalCost = totalCost - existing.cost + cost
      existing.value = value
      existing.cost = cost
      nodes[key] = existing
      moveToMRU(key)
    } else {
      totalCost = totalCost + cost
      nodes[key] = Node(value: value, cost: cost, previous: mruKey, next: nil)
      if let mruKey {
        nodes[mruKey]?.next = key
      }
      mruKey = key
      if lruKey == nil {
        lruKey = key
      }
    }
    evictToPolicy(protecting: key, policy: policy)
  }

  mutating func removeValue(forKey key: Key) {
    guard let node = nodes[key] else {
      return
    }
    totalCost = totalCost - node.cost
    unlink(key, node)
    nodes.removeValue(forKey: key)
  }

  mutating func removeAll() {
    nodes.removeAll()
    lruKey = nil
    mruKey = nil
    totalCost = .zero
    // evictionCount is a lifetime counter and is intentionally preserved.
  }

  private mutating func evictToPolicy(
    protecting protectedKey: Key,
    policy: Cost.Policy
  ) {
    while totalCost.violates(policy), let victim = lruKey, victim != protectedKey {
      guard let node = nodes[victim] else {
        break
      }
      totalCost = totalCost - node.cost
      unlink(victim, node)
      nodes.removeValue(forKey: victim)
      evictionCount += 1
    }
  }

  /// Detaches `node` (already read for `key`) from the recency list, fixing its
  /// neighbors and the head/tail anchors. Does not touch `nodes[key]` itself.
  private mutating func unlink(_ key: Key, _ node: Node) {
    if let previous = node.previous {
      nodes[previous]?.next = node.next
    } else {
      lruKey = node.next
    }
    if let next = node.next {
      nodes[next]?.previous = node.previous
    } else {
      mruKey = node.previous
    }
  }

  private mutating func moveToMRU(_ key: Key) {
    guard mruKey != key, var node = nodes[key] else {
      return
    }
    unlink(key, node)
    node.previous = mruKey
    node.next = nil
    nodes[key] = node
    if let mruKey {
      nodes[mruKey]?.next = key
    }
    mruKey = key
    if lruKey == nil {
      lruKey = key
    }
  }
}

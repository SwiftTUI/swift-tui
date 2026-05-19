import DequeModule

package final class TextLayoutCache: Sendable {
  private struct Key: Hashable, Sendable {
    let content: String
    let options: TextLayoutOptions
  }

  private struct CacheEntry: Sendable {
    var result: TextLayoutResult
    var generation: UInt64
  }

  private struct AccessRecord: Sendable {
    let key: Key
    let generation: UInt64
  }

  package struct Metrics: Equatable, Sendable {
    package var entries: Int
    package var lookups: Int
    package var hits: Int
    package var misses: Int
    package var stores: Int
    package var evictions: Int

    package init(
      entries: Int = 0,
      lookups: Int = 0,
      hits: Int = 0,
      misses: Int = 0,
      stores: Int = 0,
      evictions: Int = 0
    ) {
      self.entries = entries
      self.lookups = lookups
      self.hits = hits
      self.misses = misses
      self.stores = stores
      self.evictions = evictions
    }
  }

  private struct Storage {
    var entries: [Key: CacheEntry] = [:]
    var order: Deque<AccessRecord> = []
    var lookups = 0
    var hits = 0
    var misses = 0
    var stores = 0
    var evictions = 0
    var nextGeneration: UInt64 = 0
  }

  package static let shared = TextLayoutCache()

  private let capacity: Int
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init(capacity: Int = 256) {
    self.capacity = max(1, capacity)
  }

  package var metrics: Metrics {
    storage.withLock { storage in
      Metrics(
        entries: storage.entries.count,
        lookups: storage.lookups,
        hits: storage.hits,
        misses: storage.misses,
        stores: storage.stores,
        evictions: storage.evictions
      )
    }
  }

  package func reset() {
    storage.withLock { storage in
      storage.entries.removeAll(keepingCapacity: true)
      storage.order.removeAll(keepingCapacity: true)
      storage.lookups = 0
      storage.hits = 0
      storage.misses = 0
      storage.stores = 0
      storage.evictions = 0
      storage.nextGeneration = 0
    }
  }

  package func layout(
    for content: String,
    options: TextLayoutOptions
  ) -> TextLayoutResult {
    let key = Key(content: content, options: options)

    if let cached = storage.withLock({ storage -> TextLayoutResult? in
      storage.lookups += 1
      guard var cached = storage.entries[key] else {
        storage.misses += 1
        return nil
      }
      storage.hits += 1
      let generation = nextGeneration(in: &storage)
      cached.generation = generation
      storage.entries[key] = cached
      storage.order.append(.init(key: key, generation: generation))
      return cached.result
    }) {
      return cached
    }

    let result = uncachedTextLayout(
      for: content,
      options: options
    )

    return storage.withLock { storage in
      if var cached = storage.entries[key] {
        storage.hits += 1
        let generation = nextGeneration(in: &storage)
        cached.generation = generation
        storage.entries[key] = cached
        storage.order.append(.init(key: key, generation: generation))
        return cached.result
      }

      storage.stores += 1
      let generation = nextGeneration(in: &storage)
      storage.entries[key] = .init(
        result: result,
        generation: generation
      )
      storage.order.append(.init(key: key, generation: generation))
      evictIfNeeded(in: &storage)
      return result
    }
  }

  private func nextGeneration(
    in storage: inout Storage
  ) -> UInt64 {
    storage.nextGeneration &+= 1
    return storage.nextGeneration
  }

  private func evictIfNeeded(
    in storage: inout Storage
  ) {
    while storage.entries.count > capacity {
      guard let victim = storage.order.popFirst() else {
        break
      }
      guard let entry = storage.entries[victim.key] else {
        continue
      }
      guard entry.generation == victim.generation else {
        continue
      }
      storage.entries.removeValue(forKey: victim.key)
      storage.evictions += 1
    }
  }
}

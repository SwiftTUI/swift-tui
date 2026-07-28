import DequeModule

/// A bounded process-wide cache of bounds-specialized mesh preparation.
package final class PreparedMeshGradientCache: Sendable {
  package struct Key: Hashable, Sendable {
    package let input: MeshGradientRasterInput
    package let bounds: CellRect

    package init(input: MeshGradientRasterInput, bounds: CellRect) {
      self.input = input
      self.bounds = bounds
    }
  }

  private struct CacheEntry: Sendable {
    var prepared: PreparedMeshGradient
    var generation: UInt64
    var lookups: Int
    var hits: Int
    var misses: Int
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
    package var bypassedStores: Int

    package init(
      entries: Int = 0,
      lookups: Int = 0,
      hits: Int = 0,
      misses: Int = 0,
      stores: Int = 0,
      evictions: Int = 0,
      bypassedStores: Int = 0
    ) {
      self.entries = entries
      self.lookups = lookups
      self.hits = hits
      self.misses = misses
      self.stores = stores
      self.evictions = evictions
      self.bypassedStores = bypassedStores
    }
  }

  package struct EntryMetrics: Equatable, Sendable {
    package var lookups: Int
    package var hits: Int
    package var misses: Int

    package init(
      lookups: Int,
      hits: Int,
      misses: Int
    ) {
      self.lookups = lookups
      self.hits = hits
      self.misses = misses
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
    var bypassedStores = 0
    var nextGeneration: UInt64 = 0
    var admissionCandidates: [Key: UInt64] = [:]
    var admissionOrder: Deque<AccessRecord> = []
  }

  package static let shared: PreparedMeshGradientCache = {
    let cache = PreparedMeshGradientCache()
    MemoryMetricRegistry.shared.registerPermanent(
      ClosureMemoryMetricProvider { [weak cache] in
        cache?.memoryMetricSnapshot
          ?? MemoryMetricSnapshot(name: "PreparedMeshGradientCache.entries", count: 0)
      }
    )
    return cache
  }()

  private let capacity: Int
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init(capacity: Int = 8) {
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
        evictions: storage.evictions,
        bypassedStores: storage.bypassedStores
      )
    }
  }

  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    storage.withLock { storage in
      MemoryMetricSnapshot(
        name: "PreparedMeshGradientCache.entries",
        count: storage.entries.count,
        detail: [
          "order": storage.order.count,
          "triangles": storage.entries.values.reduce(0) {
            $0 + $1.prepared.diagnostics.triangleCount
          },
          "lookups": storage.lookups,
          "hits": storage.hits,
          "misses": storage.misses,
          "evictions": storage.evictions,
          "bypassedStores": storage.bypassedStores,
        ]
      )
    }
  }

  /// Test-facing depth of the generation-stamped LRU access log.
  var accessLogDepth: Int {
    storage.withLock { $0.order.count }
  }

  /// Test-facing key-local counters that remain deterministic while unrelated
  /// raster work uses other entries in the process-wide cache.
  package func entryMetrics(
    for input: MeshGradientRasterInput,
    bounds: CellRect
  ) -> EntryMetrics? {
    let key = Key(input: input, bounds: bounds)
    return storage.withLock { storage in
      guard let entry = storage.entries[key] else {
        return nil
      }
      return EntryMetrics(
        lookups: entry.lookups,
        hits: entry.hits,
        misses: entry.misses
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
      storage.bypassedStores = 0
      storage.nextGeneration = 0
      storage.admissionCandidates.removeAll(keepingCapacity: true)
      storage.admissionOrder.removeAll(keepingCapacity: true)
    }
  }

  package func prepared(
    for input: MeshGradientRasterInput,
    bounds: CellRect
  ) -> PreparedMeshGradient {
    let key = Key(input: input, bounds: bounds)

    if let cached = storage.withLock({ storage -> PreparedMeshGradient? in
      storage.lookups += 1
      guard var cached = storage.entries[key] else {
        storage.misses += 1
        return nil
      }
      storage.hits += 1
      let generation = nextGeneration(in: &storage)
      cached.generation = generation
      cached.lookups += 1
      cached.hits += 1
      storage.entries[key] = cached
      recordAccess(key, generation: generation, in: &storage)
      return cached.prepared
    }) {
      return cached
    }

    let result = PreparedMeshGradient(input: input, bounds: bounds)

    return storage.withLock { storage in
      if var cached = storage.entries[key] {
        storage.hits += 1
        let generation = nextGeneration(in: &storage)
        cached.generation = generation
        cached.lookups += 1
        cached.hits += 1
        storage.entries[key] = cached
        recordAccess(key, generation: generation, in: &storage)
        return cached.prepared
      }

      if shouldBypassStore(for: key, in: &storage) {
        storage.bypassedStores += 1
        recordAdmissionCandidate(key, in: &storage)
        return result
      }

      storage.stores += 1
      let generation = nextGeneration(in: &storage)
      storage.entries[key] = .init(
        prepared: result,
        generation: generation,
        lookups: 1,
        hits: 0,
        misses: 1
      )
      recordAccess(key, generation: generation, in: &storage)
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

  private func recordAccess(
    _ key: Key,
    generation: UInt64,
    in storage: inout Storage
  ) {
    storage.order.append(.init(key: key, generation: generation))
    compactAccessLogIfNeeded(in: &storage)
  }

  private func shouldBypassStore(
    for key: Key,
    in storage: inout Storage
  ) -> Bool {
    guard storage.entries.count >= capacity else {
      return false
    }
    if storage.admissionCandidates.removeValue(forKey: key) != nil {
      return false
    }
    return true
  }

  private func recordAdmissionCandidate(
    _ key: Key,
    in storage: inout Storage
  ) {
    let generation = nextGeneration(in: &storage)
    storage.admissionCandidates[key] = generation
    storage.admissionOrder.append(.init(key: key, generation: generation))
    compactAdmissionCandidatesIfNeeded(in: &storage)
  }

  private func compactAdmissionCandidatesIfNeeded(
    in storage: inout Storage
  ) {
    let limit = max(1, capacity * 2)
    while storage.admissionCandidates.count > limit {
      guard let victim = storage.admissionOrder.popFirst() else {
        storage.admissionCandidates.removeAll(keepingCapacity: true)
        return
      }
      guard storage.admissionCandidates[victim.key] == victim.generation else {
        continue
      }
      storage.admissionCandidates.removeValue(forKey: victim.key)
    }
    guard storage.admissionOrder.count > limit * 2 else {
      return
    }
    var compacted: Deque<AccessRecord> = []
    compacted.reserveCapacity(storage.admissionCandidates.count)
    for record in storage.admissionOrder
    where storage.admissionCandidates[record.key] == record.generation {
      compacted.append(record)
    }
    storage.admissionOrder = compacted
  }

  private func compactAccessLogIfNeeded(
    in storage: inout Storage
  ) {
    let liveCount = storage.entries.count
    guard storage.order.count > max(capacity, liveCount) * 2 else {
      return
    }
    var compacted: Deque<AccessRecord> = []
    compacted.reserveCapacity(liveCount)
    for record in storage.order
    where storage.entries[record.key]?.generation == record.generation {
      compacted.append(record)
    }
    storage.order = compacted
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

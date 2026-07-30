import DequeModule

package final class TextLayoutCache: Sendable {
  /// What the cached layout was computed from.
  ///
  /// Rich text is keyed on its **run texts**, not on the payload: `TextStyle`
  /// holds an `AnyShapeStyle?` and is Equatable-only, so a `RichTextPayload`
  /// cannot be hashed at all. It does not need to be. `explicitClusterLines`
  /// reads `run.text` and assigns a *positional* `runIndex`; styles and link
  /// destinations never influence a cluster or a wrap point. The array of run
  /// texts therefore captures everything the layout depends on — including the
  /// run split, which is what `runIndex` is assigned from — while letting two
  /// payloads that differ only in styling (a link hover restyle, say) share one
  /// entry. Paint reads the styles from the payload, never from the cache.
  ///
  /// If wrapping ever becomes style-sensitive, this key silently goes stale;
  /// `richLayoutSharesAnEntryAcrossStyles` in the cache tests fails the day
  /// that assumption breaks.
  private enum Source: Hashable, Sendable {
    case plain(String)
    case rich([String])
  }

  private struct Key: Hashable, Sendable {
    let source: Source
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

  package static let shared: TextLayoutCache = {
    let cache = TextLayoutCache()
    // Only the shared cache is counted; non-shared instances (tests) never
    // register, so the occupancy signal tracks the real process-lived cache.
    MemoryMetricRegistry.shared.registerPermanent(
      ClosureMemoryMetricProvider { [weak cache] in
        guard let cache else {
          return MemoryMetricSnapshot(name: "TextLayoutCache.entries", count: 0)
        }
        let metrics = cache.metrics
        return MemoryMetricSnapshot(
          name: "TextLayoutCache.entries",
          count: metrics.entries,
          detail: [
            "order": cache.accessLogDepth,
            "lookups": metrics.lookups,
            "hits": metrics.hits,
            "misses": metrics.misses,
            "evictions": metrics.evictions,
            "bypassedStores": metrics.bypassedStores,
          ]
        )
      }
    )
    return cache
  }()

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
        evictions: storage.evictions,
        bypassedStores: storage.bypassedStores
      )
    }
  }

  // Test-facing: depth of the LRU access log. The regression suite uses this to
  // assert the log stays bounded under warm, hit-dominated workloads.
  var accessLogDepth: Int {
    storage.withLock { $0.order.count }
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

  package func layout(
    for content: String,
    options: TextLayoutOptions
  ) -> TextLayoutResult {
    layout(key: Key(source: .plain(content), options: options)) {
      uncachedTextLayout(for: content, options: options)
    }
  }

  /// Serves rich-text layout from the same store as plain text.
  ///
  /// Without this, `layoutRichText` recomputed the wrap on **every** raster of
  /// every `.richText` command and again on every semantics extraction for link
  /// regions — twice per frame for a payload that had not changed.
  package func layoutRich(
    for payload: RichTextPayload,
    options: TextLayoutOptions
  ) -> TextLayoutResult {
    layout(key: Key(source: .rich(payload.runs.map(\.text)), options: options)) {
      uncachedRichTextLayout(for: payload, options: options)
    }
  }

  private func layout(
    key: Key,
    computeOnMiss: () -> TextLayoutResult
  ) -> TextLayoutResult {
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
      recordAccess(key, generation: generation, in: &storage)
      return cached.result
    }) {
      return cached
    }

    let result = computeOnMiss()

    return storage.withLock { storage in
      if var cached = storage.entries[key] {
        storage.hits += 1
        let generation = nextGeneration(in: &storage)
        cached.generation = generation
        storage.entries[key] = cached
        recordAccess(key, generation: generation, in: &storage)
        return cached.result
      }

      if shouldBypassStore(for: key, in: &storage) {
        storage.bypassedStores += 1
        recordAdmissionCandidate(key, in: &storage)
        return result
      }

      storage.stores += 1
      let generation = nextGeneration(in: &storage)
      storage.entries[key] = .init(
        result: result,
        generation: generation
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

  /// Rebuilds `order` from the live, current-generation records once it
  /// materially outgrows the entry map.
  ///
  /// `order` gains a record on every access (hit or store) but is only drained
  /// by `evictIfNeeded`, which runs solely on the store path and only while the
  /// entry map is over capacity. A warm, hit-dominated workload — e.g. an
  /// animation re-laying out the same text every frame — keeps the entry map
  /// under capacity, so eviction never fires and `order` would otherwise grow
  /// without bound. Compaction keeps exactly one record per live entry (the
  /// most recent access), preserving recency order, so the log stays O(live).
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

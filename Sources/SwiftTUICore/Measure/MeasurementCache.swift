import DequeModule
import Synchronization

/// A retained cache of measured subtrees keyed by identity and proposal.
public final class MeasurementCache: Sendable {
  private struct CachedMeasurement: Sendable {
    let resolved: ResolvedNode
    let node: MeasuredNode
    let generation: UInt64
  }

  private struct AccessRecord: Sendable {
    let proposal: ProposedSize
    let generation: UInt64
  }

  private struct IdentityStorage {
    var entries: [ProposedSize: CachedMeasurement] = [:]
    var order: Deque<AccessRecord> = []
  }

  private static let maxProposalVariantsPerIdentity = 4

  private struct Storage {
    var entriesByIdentity: [Identity: IdentityStorage] = [:]
    var entryCount = 0
    var epochGeneration = 0
    var accessGeneration: UInt64 = 0
    var lookups = 0
    var hits = 0
    var misses = 0
    var invalidations = 0
    var stores = 0
  }

  private let storage: Mutex<Storage> = .init(.init())

  /// Creates an empty measurement cache.
  public init() {}

  /// The number of cached entries.
  public var count: Int {
    storage.withLock { $0.entryCount }
  }

  /// Snapshot metrics describing cache usage.
  public var metrics: MeasurementCacheMetrics {
    storage.withLock { storage in
      MeasurementCacheMetrics(
        generation: storage.epochGeneration,
        entries: storage.entryCount,
        lookups: storage.lookups,
        hits: storage.hits,
        misses: storage.misses,
        invalidations: storage.invalidations,
        stores: storage.stores
      )
    }
  }

  /// Returns a cached measurement for `resolved` and `proposal` when the
  /// structural inputs still match.
  public func lookup(
    resolved: ResolvedNode,
    proposal: ProposedSize
  ) -> MeasuredNode? {
    storage.withLock { storage in
      storage.lookups += 1
      guard var identityStorage = storage.entriesByIdentity[resolved.identity] else {
        storage.misses += 1
        return nil
      }

      guard let cached = identityStorage.entries[proposal] else {
        storage.entriesByIdentity[resolved.identity] = identityStorage
        storage.misses += 1
        return nil
      }

      // Verify equivalence before touching LRU bookkeeping.  If the cached
      // entry is stale we evict it here so subsequent lookups don't keep
      // re-fetching and re-rejecting the same mismatching cache line.
      guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
        identityStorage.entries.removeValue(forKey: proposal)
        storage.entryCount -= 1
        if identityStorage.entries.isEmpty {
          storage.entriesByIdentity.removeValue(forKey: resolved.identity)
        } else {
          storage.entriesByIdentity[resolved.identity] = identityStorage
        }
        storage.invalidations += 1
        return nil
      }

      let generation = nextGeneration(in: &storage)
      identityStorage.entries[proposal] = .init(
        resolved: cached.resolved,
        node: cached.node,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)
      storage.entriesByIdentity[resolved.identity] = identityStorage
      storage.hits += 1
      return cached.node
    }
  }

  /// Stores `node` as the cached measurement for `resolved`.
  public func store(
    _ node: MeasuredNode,
    for resolved: ResolvedNode
  ) {
    storage.withLock { storage in
      storage.stores += 1
      var identityStorage = storage.entriesByIdentity[node.identity] ?? .init()
      let generation = nextGeneration(in: &storage)

      if identityStorage.entries[node.proposal] == nil {
        storage.entryCount += 1
      }

      identityStorage.entries[node.proposal] = CachedMeasurement(
        resolved: resolved,
        node: node,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: node.proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)
      let shouldKeepIdentity = evictIfNeeded(
        for: node.identity,
        in: &identityStorage,
        storage: &storage
      )
      if shouldKeepIdentity {
        storage.entriesByIdentity[node.identity] = identityStorage
      }
    }
  }

  package func prune(
    keeping identities: Set<Identity>
  ) {
    storage.withLock { storage in
      let retained = storage.entriesByIdentity.filter { identities.contains($0.key) }
      storage.entriesByIdentity = retained
      storage.entryCount = retained.reduce(0) { $0 + $1.value.entries.count }
    }
  }

  /// Clears the cache and advances its generation counter.
  public func reset() {
    storage.withLock { storage in
      storage.epochGeneration += 1
      storage.accessGeneration = 0
      storage.entriesByIdentity.removeAll(keepingCapacity: true)
      storage.entryCount = 0
      storage.lookups = 0
      storage.hits = 0
      storage.misses = 0
      storage.invalidations = 0
      storage.stores = 0
    }
  }

  private func nextGeneration(
    in storage: inout Storage
  ) -> UInt64 {
    storage.accessGeneration &+= 1
    return storage.accessGeneration
  }

  private func evictIfNeeded(
    for identity: Identity,
    in identityStorage: inout IdentityStorage,
    storage: inout Storage
  ) -> Bool {
    guard identityStorage.entries.count > Self.maxProposalVariantsPerIdentity else {
      return true
    }

    while identityStorage.entries.count > Self.maxProposalVariantsPerIdentity {
      guard let victim = identityStorage.order.popFirst() else {
        break
      }
      guard let cached = identityStorage.entries[victim.proposal] else {
        continue
      }
      guard cached.generation == victim.generation else {
        continue
      }

      identityStorage.entries.removeValue(forKey: victim.proposal)
      storage.entryCount -= 1
    }

    if identityStorage.entries.isEmpty {
      storage.entriesByIdentity.removeValue(forKey: identity)
      return false
    }

    return true
  }

  private func compactOrderIfNeeded(
    in identityStorage: inout IdentityStorage
  ) {
    guard !identityStorage.entries.isEmpty else {
      identityStorage.order.removeAll(keepingCapacity: true)
      return
    }

    let threshold = max(16, identityStorage.entries.count * 8)
    guard identityStorage.order.count > threshold else {
      return
    }

    var compacted: Deque<AccessRecord> = []
    let liveEntries = identityStorage.entries.sorted { lhs, rhs in
      lhs.value.generation < rhs.value.generation
    }
    for (proposal, entry) in liveEntries {
      compacted.append(.init(proposal: proposal, generation: entry.generation))
    }
    identityStorage.order = compacted
  }
}

/// Measures and places resolved nodes under SwiftUI-style layout rules.

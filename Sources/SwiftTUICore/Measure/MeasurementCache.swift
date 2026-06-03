import DequeModule
import Synchronization

/// A retained cache of measured subtrees keyed by runtime node id and proposal.
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

  private struct NodeStorage {
    var entries: [ProposedSize: CachedMeasurement] = [:]
    var order: Deque<AccessRecord> = []
  }

  private static let maxProposalVariantsPerNode = 4

  private struct Storage {
    var entriesByNodeID: [ViewNodeID: NodeStorage] = [:]
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
      guard let viewNodeID = resolved.viewNodeID else {
        storage.misses += 1
        return nil
      }
      guard var nodeStorage = storage.entriesByNodeID[viewNodeID] else {
        storage.misses += 1
        return nil
      }

      guard let cached = nodeStorage.entries[proposal] else {
        storage.entriesByNodeID[viewNodeID] = nodeStorage
        storage.misses += 1
        return nil
      }

      // Verify equivalence before touching LRU bookkeeping.  If the cached
      // entry is stale we evict it here so subsequent lookups don't keep
      // re-fetching and re-rejecting the same mismatching cache line.
      guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
        nodeStorage.entries.removeValue(forKey: proposal)
        storage.entryCount -= 1
        if nodeStorage.entries.isEmpty {
          storage.entriesByNodeID.removeValue(forKey: viewNodeID)
        } else {
          storage.entriesByNodeID[viewNodeID] = nodeStorage
        }
        storage.invalidations += 1
        return nil
      }

      let generation = nextGeneration(in: &storage)
      nodeStorage.entries[proposal] = .init(
        resolved: cached.resolved,
        node: cached.node,
        generation: generation
      )
      nodeStorage.order.append(.init(proposal: proposal, generation: generation))
      compactOrderIfNeeded(in: &nodeStorage)
      storage.entriesByNodeID[viewNodeID] = nodeStorage
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
      guard let viewNodeID = node.viewNodeID ?? resolved.viewNodeID else {
        return
      }
      var nodeStorage = storage.entriesByNodeID[viewNodeID] ?? .init()
      let generation = nextGeneration(in: &storage)

      if nodeStorage.entries[node.proposal] == nil {
        storage.entryCount += 1
      }

      nodeStorage.entries[node.proposal] = CachedMeasurement(
        resolved: resolved,
        node: node,
        generation: generation
      )
      nodeStorage.order.append(.init(proposal: node.proposal, generation: generation))
      compactOrderIfNeeded(in: &nodeStorage)
      let shouldKeepNode = evictIfNeeded(
        for: viewNodeID,
        in: &nodeStorage,
        storage: &storage
      )
      if shouldKeepNode {
        storage.entriesByNodeID[viewNodeID] = nodeStorage
      }
    }
  }

  package func prune(
    keeping viewNodeIDs: Set<ViewNodeID>
  ) {
    storage.withLock { storage in
      let retained = storage.entriesByNodeID.filter { viewNodeIDs.contains($0.key) }
      storage.entriesByNodeID = retained
      storage.entryCount = retained.reduce(0) { $0 + $1.value.entries.count }
    }
  }

  /// Clears the cache and advances its generation counter.
  public func reset() {
    storage.withLock { storage in
      storage.epochGeneration += 1
      storage.accessGeneration = 0
      storage.entriesByNodeID.removeAll(keepingCapacity: true)
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
    for viewNodeID: ViewNodeID,
    in nodeStorage: inout NodeStorage,
    storage: inout Storage
  ) -> Bool {
    guard nodeStorage.entries.count > Self.maxProposalVariantsPerNode else {
      return true
    }

    while nodeStorage.entries.count > Self.maxProposalVariantsPerNode {
      guard let victim = nodeStorage.order.popFirst() else {
        break
      }
      guard let cached = nodeStorage.entries[victim.proposal] else {
        continue
      }
      guard cached.generation == victim.generation else {
        continue
      }

      nodeStorage.entries.removeValue(forKey: victim.proposal)
      storage.entryCount -= 1
    }

    if nodeStorage.entries.isEmpty {
      storage.entriesByNodeID.removeValue(forKey: viewNodeID)
      return false
    }

    return true
  }

  private func compactOrderIfNeeded(
    in nodeStorage: inout NodeStorage
  ) {
    guard !nodeStorage.entries.isEmpty else {
      nodeStorage.order.removeAll(keepingCapacity: true)
      return
    }

    let threshold = max(16, nodeStorage.entries.count * 8)
    guard nodeStorage.order.count > threshold else {
      return
    }

    var compacted: Deque<AccessRecord> = []
    let liveEntries = nodeStorage.entries.sorted { lhs, rhs in
      lhs.value.generation < rhs.value.generation
    }
    for (proposal, entry) in liveEntries {
      compacted.append(.init(proposal: proposal, generation: entry.generation))
    }
    nodeStorage.order = compacted
  }
}

/// Measures and places resolved nodes under SwiftUI-style layout rules.

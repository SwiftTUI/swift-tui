import DequeModule
import Synchronization

/// Cross-frame persistence for author `Layout.Cache` values (plan
/// 2026-08-11-004 Stage 2), closing the register gap "`Layout` caches are
/// pass-local scratch."
///
/// Owned by the renderer beside `MeasurementCache` and reachable through
/// `LayoutPassContext`. Entries are keyed by container identity with
/// per-proposal variants — the same shape and bounds as the measurement
/// cache — each holding the author cache value, the `ResolvedNode` it was
/// built against, and the layout's debug-name discriminator (a stale entry
/// from a different layout type at a reused identity must miss, not cast).
///
/// Reads happen in the worker proxy's cache preparation; `updateCache`
/// still runs on every read, preserving the SwiftUI contract that caches
/// refresh when subviews change. Writes never land from inside a pass:
/// placement records the final value through the
/// `WorkerCustomLayoutCacheUpdate` channel and the renderer applies it on
/// the main actor only when the frame commits, so abandoned frame
/// candidates and probe passes never mutate the store.
package final class CustomLayoutCacheStore: Sendable {
  private struct CachedValue: Sendable {
    let cacheValue: any Sendable
    let resolved: ResolvedNode
    let layoutDebugName: String
    let generation: UInt64
  }

  private struct AccessRecord: Sendable {
    let proposal: ProposedSize
    let generation: UInt64
  }

  private struct IdentityStorage {
    var entries: [ProposedSize: CachedValue] = [:]
    var order: Deque<AccessRecord> = []
  }

  /// Mirrors `MeasurementCache.maxProposalVariantsPerNode` exactly.
  private static let maxProposalVariantsPerIdentity = 4

  private struct Storage {
    var entriesByIdentity: [Identity: IdentityStorage] = [:]
    var entryCount = 0
    var accessGeneration: UInt64 = 0
    var lookups = 0
    var serves = 0
    var misses = 0
    var invalidations = 0
    var stores = 0
  }

  private let storage: Mutex<Storage> = .init(.init())

  package init() {}

  package var count: Int {
    storage.withLock { $0.entryCount }
  }

  package var isEmpty: Bool {
    storage.withLock { $0.entryCount == 0 }
  }

  /// Snapshot counters for tests and the memory metric row.
  package var metrics: (lookups: Int, serves: Int, misses: Int, invalidations: Int, stores: Int) {
    storage.withLock {
      ($0.lookups, $0.serves, $0.misses, $0.invalidations, $0.stores)
    }
  }

  /// Returns the persisted author cache for `resolved` at `proposal` when
  /// the stored resolved node is still equivalent for measurement and came
  /// from the same layout type. A stale entry is evicted on sight, exactly
  /// like the measurement cache, so repeated lookups do not re-reject the
  /// same line. Invalidation-set validity is the CALLER's guard: it needs
  /// the pass context, which this engine-level store deliberately does not
  /// hold.
  package func lookup(
    resolved: ResolvedNode,
    proposal: ProposedSize,
    layoutDebugName: String
  ) -> (any Sendable)? {
    storage.withLock { storage in
      storage.lookups += 1
      guard var identityStorage = storage.entriesByIdentity[resolved.identity] else {
        storage.misses += 1
        return nil
      }
      guard let cached = identityStorage.entries[proposal] else {
        storage.misses += 1
        return nil
      }
      guard
        cached.layoutDebugName == layoutDebugName,
        cached.resolved.isEquivalentForMeasurement(to: resolved)
      else {
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

      storage.accessGeneration &+= 1
      let generation = storage.accessGeneration
      identityStorage.entries[proposal] = CachedValue(
        cacheValue: cached.cacheValue,
        resolved: cached.resolved,
        layoutDebugName: cached.layoutDebugName,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)
      storage.entriesByIdentity[resolved.identity] = identityStorage
      storage.serves += 1
      return cached.cacheValue
    }
  }

  /// Stores the placement-final author cache for `resolved` at `proposal`.
  /// Called only through the commit-applied update channel.
  package func store(
    _ cacheValue: any Sendable,
    resolved: ResolvedNode,
    proposal: ProposedSize,
    layoutDebugName: String
  ) {
    storage.withLock { storage in
      storage.stores += 1
      var identityStorage = storage.entriesByIdentity[resolved.identity] ?? .init()
      storage.accessGeneration &+= 1
      let generation = storage.accessGeneration

      if identityStorage.entries[proposal] == nil {
        storage.entryCount += 1
      }
      identityStorage.entries[proposal] = CachedValue(
        cacheValue: cacheValue,
        resolved: resolved,
        layoutDebugName: layoutDebugName,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)

      while identityStorage.entries.count > Self.maxProposalVariantsPerIdentity {
        guard let victim = identityStorage.order.popFirst() else {
          break
        }
        guard let cached = identityStorage.entries[victim.proposal],
          cached.generation == victim.generation
        else {
          continue
        }
        identityStorage.entries.removeValue(forKey: victim.proposal)
        storage.entryCount -= 1
      }

      if identityStorage.entries.isEmpty {
        storage.entriesByIdentity.removeValue(forKey: resolved.identity)
      } else {
        storage.entriesByIdentity[resolved.identity] = identityStorage
      }
    }
  }

  /// Drops entries whose identity is no longer live, alongside the
  /// measurement-cache prune on committed frames. Same
  /// nothing-departed short-circuit.
  package func prune(
    keeping identities: Set<Identity>
  ) {
    storage.withLock { storage in
      let hasDepartedIdentity = storage.entriesByIdentity.keys.contains { identity in
        !identities.contains(identity)
      }
      guard hasDepartedIdentity else {
        return
      }
      let retained = storage.entriesByIdentity.filter { identities.contains($0.key) }
      storage.entriesByIdentity = retained
      storage.entryCount = retained.reduce(0) { $0 + $1.value.entries.count }
    }
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

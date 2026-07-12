import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("SwiftTUI measurement-cache stress behavior", .serialized)
struct FrameworkStressMeasurementCacheTests {
  @Test("stress measurement cache 001 unspecified and infinity stay distinct")
  func measurementCache001UnspecifiedAndInfinityStayDistinct() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("001", id: 1)
    let unspecified = ProposedSize.unspecified
    let infinite = ProposedSize(width: .infinity, height: .infinity)

    measurementCacheStore(
      cache, node: node, proposal: unspecified, size: .init(width: 3, height: 1))
    measurementCacheStore(cache, node: node, proposal: infinite, size: .init(width: 9, height: 4))

    #expect(
      cache.lookup(resolved: node, proposal: unspecified)?.measuredSize
        == .init(width: 3, height: 1))
    #expect(
      cache.lookup(resolved: node, proposal: infinite)?.measuredSize == .init(width: 9, height: 4))
    #expect(cache.count == 2)
  }

  @Test("stress measurement cache 002 zero and negative finite proposals stay distinct")
  func measurementCache002ZeroAndNegativeStayDistinct() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("002", id: 2)
    let zero = ProposedSize(width: 0, height: 0)
    let negative = ProposedSize(width: -1, height: -1)

    measurementCacheStore(cache, node: node, proposal: zero, size: .zero)
    measurementCacheStore(cache, node: node, proposal: negative, size: .init(width: -1, height: -1))

    #expect(cache.lookup(resolved: node, proposal: zero)?.proposal == zero)
    #expect(cache.lookup(resolved: node, proposal: negative)?.proposal == negative)
    #expect(cache.count == 2)
  }

  @Test("stress measurement cache 003 infinite width and infinite height never alias")
  func measurementCache003InfiniteAxesNeverAlias() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("003", id: 3)
    let wide = ProposedSize(width: .infinity, height: 2)
    let tall = ProposedSize(width: 2, height: .infinity)

    measurementCacheStore(cache, node: node, proposal: wide, size: .init(width: 20, height: 2))
    measurementCacheStore(cache, node: node, proposal: tall, size: .init(width: 2, height: 20))

    #expect(
      cache.lookup(resolved: node, proposal: wide)?.measuredSize == .init(width: 20, height: 2))
    #expect(
      cache.lookup(resolved: node, proposal: tall)?.measuredSize == .init(width: 2, height: 20))
  }

  @Test("stress measurement cache 004 swapped finite axes never alias")
  func measurementCache004SwappedFiniteAxesNeverAlias() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("004", id: 4)
    let landscape = ProposedSize(width: 11, height: 3)
    let portrait = ProposedSize(width: 3, height: 11)

    measurementCacheStore(cache, node: node, proposal: landscape, size: .init(width: 11, height: 3))
    measurementCacheStore(cache, node: node, proposal: portrait, size: .init(width: 3, height: 11))

    #expect(cache.lookup(resolved: node, proposal: landscape)?.proposal == landscape)
    #expect(cache.lookup(resolved: node, proposal: portrait)?.proposal == portrait)
  }

  @Test("stress measurement cache 005 proposal caps are independent per node")
  func measurementCache005ProposalCapsAreIndependentPerNode() {
    let cache = MeasurementCache()
    let first = measurementCacheNode("005-first", id: 5)
    let second = measurementCacheNode("005-second", id: 6)

    for width in 1...4 {
      let proposal = ProposedSize(width: .finite(width), height: 1)
      measurementCacheStore(
        cache, node: first, proposal: proposal, size: .init(width: width, height: 1))
      measurementCacheStore(
        cache, node: second, proposal: proposal, size: .init(width: width, height: 1))
    }

    #expect(cache.count == 8)
    #expect(cache.metrics.entries == 8)
  }

  @Test("stress measurement cache 006 hot proposal survives access-log compaction")
  func measurementCache006HotProposalSurvivesAccessLogCompaction() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("006", id: 7)
    let proposals = measurementCacheFiniteWidthProposals(1...5)

    for proposal in proposals.prefix(4) {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }
    for _ in 0..<96 {
      #expect(cache.lookup(resolved: node, proposal: proposals[0]) != nil)
    }
    measurementCacheStore(cache, node: node, proposal: proposals[4])

    #expect(cache.lookup(resolved: node, proposal: proposals[0]) != nil)
    #expect(cache.lookup(resolved: node, proposal: proposals[1]) == nil)
    #expect(cache.count == 4)
  }

  @Test("stress measurement cache 007 alternating hits retain the true LRU order")
  func measurementCache007AlternatingHitsRetainTrueLRUOrder() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("007", id: 8)
    let proposals = measurementCacheFiniteWidthProposals(1...5)

    for proposal in proposals.prefix(4) {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }
    for generation in 0..<96 {
      let hot = generation.isMultiple(of: 2) ? proposals[0] : proposals[1]
      #expect(cache.lookup(resolved: node, proposal: hot) != nil)
    }
    #expect(cache.lookup(resolved: node, proposal: proposals[2]) != nil)
    measurementCacheStore(cache, node: node, proposal: proposals[4])

    #expect(cache.lookup(resolved: node, proposal: proposals[3]) == nil)
    #expect(cache.lookup(resolved: node, proposal: proposals[2]) != nil)
  }

  @Test("stress measurement cache 008 repeated stores keep one newest proposal entry")
  func measurementCache008RepeatedStoresKeepOneNewestEntry() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("008", id: 9)
    let proposal = ProposedSize(width: 8, height: 2)

    for generation in 0..<64 {
      measurementCacheStore(
        cache,
        node: node,
        proposal: proposal,
        size: .init(width: generation, height: 2)
      )
    }

    #expect(cache.count == 1)
    #expect(cache.metrics.stores == 64)
    #expect(cache.lookup(resolved: node, proposal: proposal)?.measuredSize.width == 63)
  }

  @Test("stress measurement cache 009 replacement store promotes before eviction")
  func measurementCache009ReplacementStorePromotesBeforeEviction() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("009", id: 10)
    let proposals = measurementCacheFiniteWidthProposals(1...5)

    for proposal in proposals.prefix(4) {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }
    measurementCacheStore(
      cache, node: node, proposal: proposals[0], size: .init(width: 100, height: 1))
    measurementCacheStore(cache, node: node, proposal: proposals[4])

    #expect(cache.lookup(resolved: node, proposal: proposals[0])?.measuredSize.width == 100)
    #expect(cache.lookup(resolved: node, proposal: proposals[1]) == nil)
  }

  @Test("stress measurement cache 010 one overwrite preserves peer variants")
  func measurementCache010OneOverwritePreservesPeerVariants() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("010", id: 11)
    let proposals = measurementCacheFiniteWidthProposals(1...4)

    for proposal in proposals {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }
    measurementCacheStore(
      cache, node: node, proposal: proposals[1], size: .init(width: 22, height: 1))

    #expect(cache.lookup(resolved: node, proposal: proposals[0])?.measuredSize.width == 1)
    #expect(cache.lookup(resolved: node, proposal: proposals[1])?.measuredSize.width == 22)
    #expect(cache.lookup(resolved: node, proposal: proposals[2])?.measuredSize.width == 3)
    #expect(cache.lookup(resolved: node, proposal: proposals[3])?.measuredSize.width == 4)
  }

  @Test("stress measurement cache 011 stale invalidation leaves another node untouched")
  func measurementCache011StaleInvalidationLeavesAnotherNodeUntouched() {
    let cache = MeasurementCache()
    let first = measurementCacheNode("011-first", id: 12, size: .init(width: 4, height: 1))
    let second = measurementCacheNode("011-second", id: 13, size: .init(width: 5, height: 1))
    let proposal = ProposedSize.unspecified
    measurementCacheStore(cache, node: first, proposal: proposal)
    measurementCacheStore(cache, node: second, proposal: proposal)

    let staleFirst = measurementCacheNode("011-first", id: 12, size: .init(width: 40, height: 1))
    #expect(cache.lookup(resolved: staleFirst, proposal: proposal) == nil)

    #expect(cache.lookup(resolved: second, proposal: proposal) != nil)
    #expect(cache.count == 1)
  }

  @Test("stress measurement cache 012 updated store replaces an invalidated entry")
  func measurementCache012UpdatedStoreReplacesInvalidatedEntry() {
    let cache = MeasurementCache()
    let original = measurementCacheNode("012", id: 14, size: .init(width: 4, height: 1))
    let updated = measurementCacheNode("012", id: 14, size: .init(width: 12, height: 1))
    measurementCacheStore(cache, node: original, proposal: .unspecified)

    #expect(cache.lookup(resolved: updated, proposal: .unspecified) == nil)
    measurementCacheStore(
      cache, node: updated, proposal: .unspecified, size: .init(width: 12, height: 1))

    #expect(cache.lookup(resolved: updated, proposal: .unspecified)?.measuredSize.width == 12)
    #expect(cache.metrics.invalidations == 1)
    #expect(cache.count == 1)
  }

  @Test("stress measurement cache 013 every stale variant invalidates independently")
  func measurementCache013EveryStaleVariantInvalidatesIndependently() {
    let cache = MeasurementCache()
    let original = measurementCacheNode("013", id: 15, size: .init(width: 4, height: 1))
    let updated = measurementCacheNode("013", id: 15, size: .init(width: 40, height: 1))
    let proposals = measurementCacheFiniteWidthProposals(1...4)
    for proposal in proposals {
      measurementCacheStore(cache, node: original, proposal: proposal)
    }

    for proposal in proposals {
      #expect(cache.lookup(resolved: updated, proposal: proposal) == nil)
    }

    #expect(cache.count == 0)
    #expect(cache.metrics.invalidations == 4)
    #expect(cache.metrics.misses == 0)
  }

  @Test("stress measurement cache 014 stale order records cannot evict a restated proposal")
  func measurementCache014StaleOrderRecordsCannotEvictRestatedProposal() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("014", id: 16)
    let proposals = measurementCacheFiniteWidthProposals(1...5)
    for proposal in proposals.prefix(4) {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }
    for generation in 0..<48 {
      measurementCacheStore(
        cache,
        node: node,
        proposal: proposals[0],
        size: .init(width: 100 + generation, height: 1)
      )
    }

    measurementCacheStore(cache, node: node, proposal: proposals[4])

    #expect(cache.lookup(resolved: node, proposal: proposals[0])?.measuredSize.width == 147)
    #expect(cache.lookup(resolved: node, proposal: proposals[1]) == nil)
  }

  @Test("stress measurement cache 015 empty keep set prunes every entry")
  func measurementCache015EmptyKeepSetPrunesEveryEntry() {
    let cache = MeasurementCache()
    for id in 20..<24 {
      let node = measurementCacheNode("015-\(id)", id: UInt64(id))
      for proposal in measurementCacheFiniteWidthProposals(1...3) {
        measurementCacheStore(cache, node: node, proposal: proposal)
      }
    }
    #expect(cache.count == 12)

    cache.prune(keeping: [])

    #expect(cache.count == 0)
    #expect(cache.metrics.entries == 0)
  }

  @Test("stress measurement cache 016 subset prune preserves all survivor variants")
  func measurementCache016SubsetPrunePreservesAllSurvivorVariants() {
    let cache = MeasurementCache()
    let first = measurementCacheNode("016-first", id: 24)
    let second = measurementCacheNode("016-second", id: 25)
    let third = measurementCacheNode("016-third", id: 26)
    let proposals = measurementCacheFiniteWidthProposals(1...4)
    for node in [first, second, third] {
      for proposal in proposals {
        measurementCacheStore(cache, node: node, proposal: proposal)
      }
    }

    cache.prune(keeping: [first.viewNodeID!, third.viewNodeID!])

    #expect(cache.count == 8)
    for proposal in proposals {
      #expect(cache.lookup(resolved: first, proposal: proposal) != nil)
      #expect(cache.lookup(resolved: third, proposal: proposal) != nil)
      #expect(cache.lookup(resolved: second, proposal: proposal) == nil)
    }
  }

  @Test("stress measurement cache 017 prune leaves activity counters unchanged")
  func measurementCache017PruneLeavesActivityCountersUnchanged() {
    let cache = MeasurementCache()
    let kept = measurementCacheNode("017-kept", id: 27)
    let removed = measurementCacheNode("017-removed", id: 28)
    measurementCacheStore(cache, node: kept, proposal: .unspecified)
    measurementCacheStore(cache, node: removed, proposal: .unspecified)
    _ = cache.lookup(resolved: kept, proposal: .unspecified)
    _ = cache.lookup(resolved: kept, proposal: .init(width: 99, height: 1))
    let before = cache.metrics

    cache.prune(keeping: [kept.viewNodeID!])
    let after = cache.metrics

    #expect(after.lookups == before.lookups)
    #expect(after.hits == before.hits)
    #expect(after.misses == before.misses)
    #expect(after.invalidations == before.invalidations)
    #expect(after.stores == before.stores)
    #expect(after.entries == 1)
  }

  @Test("stress measurement cache 018 pruned node returns through a cold path")
  func measurementCache018PrunedNodeReturnsThroughColdPath() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("018", id: 29)
    measurementCacheStore(cache, node: node, proposal: .unspecified)
    cache.prune(keeping: [])
    let before = cache.metrics

    #expect(cache.lookup(resolved: node, proposal: .unspecified) == nil)
    measurementCacheStore(
      cache, node: node, proposal: .unspecified, size: .init(width: 18, height: 1))

    #expect(cache.metrics.misses == before.misses + 1)
    #expect(cache.lookup(resolved: node, proposal: .unspecified)?.measuredSize.width == 18)
  }

  @Test("stress measurement cache 019 reset advances epoch and clears every counter")
  func measurementCache019ResetAdvancesEpochAndClearsEveryCounter() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("019", id: 30)
    measurementCacheStore(cache, node: node, proposal: .unspecified)
    _ = cache.lookup(resolved: node, proposal: .unspecified)
    _ = cache.lookup(resolved: node, proposal: .init(width: 7, height: 1))
    let generation = cache.metrics.generation

    cache.reset()

    #expect(cache.metrics == MeasurementCacheMetrics(generation: generation + 1))
    #expect(cache.count == 0)
  }

  @Test("stress measurement cache 020 repeated empty resets advance monotonically")
  func measurementCache020RepeatedEmptyResetsAdvanceMonotonically() {
    let cache = MeasurementCache()

    for expectedGeneration in 1...32 {
      cache.reset()
      #expect(cache.metrics == MeasurementCacheMetrics(generation: expectedGeneration))
    }
  }

  @Test("stress measurement cache 021 reset discards all prior LRU history")
  func measurementCache021ResetDiscardsAllPriorLRUHistory() {
    let cache = MeasurementCache()
    let node = measurementCacheNode("021", id: 31)
    let old = measurementCacheFiniteWidthProposals(20...23)
    for proposal in old {
      measurementCacheStore(cache, node: node, proposal: proposal)
      for _ in 0..<12 {
        _ = cache.lookup(resolved: node, proposal: proposal)
      }
    }
    cache.reset()

    let fresh = measurementCacheFiniteWidthProposals(1...5)
    for proposal in fresh {
      measurementCacheStore(cache, node: node, proposal: proposal)
    }

    #expect(cache.lookup(resolved: node, proposal: fresh[0]) == nil)
    #expect(cache.lookup(resolved: node, proposal: fresh[1]) != nil)
    #expect(cache.count == 4)
  }

  @Test("stress measurement cache 022 nodes without runtime IDs stay uncacheable")
  func measurementCache022NodesWithoutRuntimeIDsStayUncacheable() {
    let cache = MeasurementCache()
    let resolved = ResolvedNode(
      identity: testIdentity("022"),
      kind: .view("NoRuntimeID"),
      intrinsicSize: .init(width: 2, height: 1)
    )
    let measured = MeasuredNode(
      identity: resolved.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 2, height: 1)
    )

    cache.store(measured, for: resolved)
    #expect(cache.lookup(resolved: resolved, proposal: .unspecified) == nil)

    #expect(cache.count == 0)
    #expect(cache.metrics.stores == 1)
    #expect(cache.metrics.lookups == 1)
    #expect(cache.metrics.misses == 1)
  }

  @Test("stress measurement cache 023 concurrent identical stores converge")
  func measurementCache023ConcurrentIdenticalStoresConverge() async {
    let cache = MeasurementCache()
    let node = measurementCacheNode("023", id: 32)
    let proposal = ProposedSize(width: 8, height: 2)

    await withTaskGroup(of: Void.self) { group in
      for generation in 0..<128 {
        group.addTask {
          measurementCacheStore(
            cache,
            node: node,
            proposal: proposal,
            size: .init(width: generation, height: 2)
          )
        }
      }
    }

    #expect(cache.count == 1)
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.stores == 128)
    #expect(cache.lookup(resolved: node, proposal: proposal) != nil)
  }

  @Test("stress measurement cache 024 concurrent hot lookups preserve exact metrics")
  func measurementCache024ConcurrentHotLookupsPreserveExactMetrics() async {
    let cache = MeasurementCache()
    let node = measurementCacheNode("024", id: 33)
    let proposal = ProposedSize(width: 9, height: 3)
    measurementCacheStore(cache, node: node, proposal: proposal)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<128 {
        group.addTask {
          #expect(cache.lookup(resolved: node, proposal: proposal) != nil)
        }
      }
    }

    #expect(cache.metrics.lookups == 128)
    #expect(cache.metrics.hits == 128)
    #expect(cache.metrics.misses == 0)
    #expect(cache.count == 1)
  }

  @Test("stress measurement cache 025 concurrent proposal swarm respects the cap")
  func measurementCache025ConcurrentProposalSwarmRespectsTheCap() async {
    let cache = MeasurementCache()
    let node = measurementCacheNode("025", id: 34)
    let proposals = measurementCacheFiniteWidthProposals(1...6)

    await withTaskGroup(of: Void.self) { group in
      for generation in 0..<240 {
        let proposal = proposals[generation % proposals.count]
        group.addTask {
          measurementCacheStore(cache, node: node, proposal: proposal)
        }
      }
    }

    #expect(cache.count == 4)
    #expect(cache.metrics.stores == 240)
    var hits = 0
    for proposal in proposals {
      if cache.lookup(resolved: node, proposal: proposal) != nil {
        hits += 1
      }
    }
    #expect(hits == 4)
    #expect(cache.metrics.entries == 4)
  }
}

private func measurementCacheNode(
  _ name: String,
  id: UInt64,
  size: CellSize = .init(width: 8, height: 2)
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: ViewNodeID(rawValue: id),
    identity: testIdentity(name),
    kind: .view("MeasurementCacheStress"),
    intrinsicSize: size
  )
}

private func measurementCacheStore(
  _ cache: MeasurementCache,
  node: ResolvedNode,
  proposal: ProposedSize,
  size: CellSize? = nil
) {
  cache.store(
    MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: proposal,
      measuredSize: size ?? measurementCacheSize(for: proposal)
    ),
    for: node
  )
}

private func measurementCacheSize(for proposal: ProposedSize) -> CellSize {
  func value(_ dimension: ProposedDimension) -> Int {
    switch dimension {
    case .finite(let value): value
    case .infinity: 100
    case .unspecified: 8
    }
  }
  return .init(width: value(proposal.width), height: value(proposal.height))
}

private func measurementCacheFiniteWidthProposals(
  _ widths: ClosedRange<Int>
) -> [ProposedSize] {
  widths.map { .init(width: .finite($0), height: 1) }
}

import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct LayoutEngineTests {
  @Test("measure leaf node with intrinsic size")
  func measureLeafWithIntrinsicSize() {
    let engine = LayoutEngine()
    let resolved = leaf("leaf", size: .init(width: 10, height: 3))

    let measured = engine.measure(resolved, proposal: .unspecified)
    #expect(measured.measuredSize == .init(width: 10, height: 3))
  }

  @Test("measure with explicit proposal clamps size")
  func measureWithExplicitProposal() {
    let engine = LayoutEngine()
    let resolved = leaf("leaf", size: .init(width: 100, height: 50))

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 10)
    )
    #expect(measured.measuredSize == .init(width: 20, height: 10))
  }

  @Test("place node at origin")
  func placeNodeAtOrigin() {
    let engine = LayoutEngine()
    let resolved = leaf("leaf", size: .init(width: 10, height: 3))

    let measured = engine.measure(resolved)
    let placed = engine.place(resolved, measured: measured, origin: .zero)
    #expect(placed.bounds.origin == .zero)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("measurement cache returns cached result for same input")
  func measurementCacheHit() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let resolved = leaf("cached", size: .init(width: 5, height: 2))

    _ = engine.measure(resolved)
    let metrics1 = cache.metrics
    _ = engine.measure(resolved)
    let metrics2 = cache.metrics

    #expect(metrics2.hits == metrics1.hits + 1)
  }

  @Test("measurement cache keeps at most four proposal variants per node")
  func measurementCacheCapsProposalVariantsPerNode() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let resolved = leaf("capped", size: .init(width: 6, height: 1))

    _ = engine.measure(resolved, proposal: .init(width: 1, height: nil))
    _ = engine.measure(resolved, proposal: .init(width: 2, height: nil))
    _ = engine.measure(resolved, proposal: .init(width: 3, height: nil))
    _ = engine.measure(resolved, proposal: .init(width: 4, height: nil))
    let primedMetrics = cache.metrics

    _ = engine.measure(resolved, proposal: .init(width: 2, height: nil))
    let afterRecentHit = cache.metrics

    _ = engine.measure(resolved, proposal: .init(width: 5, height: nil))
    let afterEviction = cache.metrics

    _ = engine.measure(resolved, proposal: .init(width: 2, height: nil))
    let afterRetainedHit = cache.metrics

    _ = engine.measure(resolved, proposal: .init(width: 1, height: nil))
    let afterEvictedLookup = cache.metrics

    #expect(primedMetrics.entries == 4)
    #expect(cache.count == 4)
    #expect(afterRecentHit.hits == primedMetrics.hits + 1)
    #expect(afterEviction.entries == 4)
    #expect(afterRetainedHit.hits == afterEviction.hits + 1)
    #expect(afterEvictedLookup.entries == 4)
    #expect(afterEvictedLookup.misses == afterRetainedHit.misses + 1)
    #expect(afterEvictedLookup.stores == afterRetainedHit.stores + 1)
  }

  @Test("measurement cache prunes dead node ids")
  func measurementCachePrunesDeadNodeIDs() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let kept = leaf("kept", size: .init(width: 4, height: 1))
    let pruned = leaf("pruned", size: .init(width: 5, height: 1))

    _ = engine.measure(kept, proposal: .unspecified)
    _ = engine.measure(kept, proposal: .init(width: 2, height: nil))
    _ = engine.measure(pruned, proposal: .unspecified)
    let beforePrune = cache.metrics

    cache.prune(keeping: [kept.viewNodeID!])
    let afterPrune = cache.metrics

    _ = engine.measure(kept, proposal: .unspecified)
    let afterKeptHit = cache.metrics

    _ = engine.measure(pruned, proposal: .unspecified)
    let afterPrunedMiss = cache.metrics

    #expect(beforePrune.entries == 3)
    #expect(afterPrune.entries == 2)
    #expect(afterKeptHit.hits == afterPrune.hits + 1)
    #expect(afterPrunedMiss.misses == afterKeptHit.misses + 1)
    #expect(afterPrunedMiss.stores == afterKeptHit.stores + 1)
    #expect(afterPrunedMiss.entries == 3)
  }

  @Test("measurement cache evicts stale entries on equivalence mismatch")
  func measurementCacheEvictsStaleEntries() {
    let cache = MeasurementCache()
    let original = leaf("stale", size: .init(width: 10, height: 5))
    let measured = MeasuredNode(
      identity: original.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 10, height: 5)
    )
    cache.store(measured, for: original)
    #expect(cache.count == 1)

    // Rebuild the resolved node with a different intrinsic size.  The
    // identity is the same, so the cache will hit-find-mismatch and must
    // evict the stale entry instead of silently leaving it in place.
    let updated = leaf("stale", size: .init(width: 20, height: 5))

    let result = cache.lookup(resolved: updated, proposal: .unspecified)

    #expect(result == nil)
    #expect(cache.count == 0)

    let metrics = cache.metrics
    // Stale evictions are distinct from cold misses — they report through
    // the dedicated `invalidations` counter so observability dashboards can
    // distinguish structural invalidation from true cache misses.
    #expect(metrics.invalidations == 1)
    #expect(metrics.misses == 0)
    #expect(metrics.hits == 0)
  }

  @Test("stale cache eviction preserves other proposal variants for the same node")
  func staleCacheEvictionPreservesSiblingProposals() {
    let cache = MeasurementCache()
    let original = leaf("shared", size: .init(width: 10, height: 5))
    let proposalA = ProposedSize.unspecified
    let proposalB = ProposedSize(width: 4, height: nil)
    let measuredA = MeasuredNode(
      identity: original.identity,
      proposal: proposalA,
      measuredSize: .init(width: 10, height: 5)
    )
    let measuredB = MeasuredNode(
      identity: original.identity,
      proposal: proposalB,
      measuredSize: .init(width: 4, height: 5)
    )
    cache.store(measuredA, for: original)
    cache.store(measuredB, for: original)
    #expect(cache.count == 2)

    // Stale lookup at proposalA must evict only that variant, leaving the
    // proposalB entry intact.
    let updated = leaf("shared", size: .init(width: 20, height: 5))
    _ = cache.lookup(resolved: updated, proposal: proposalA)

    #expect(cache.count == 1)

    let survivingHit = cache.lookup(resolved: original, proposal: proposalB)
    #expect(survivingHit?.measuredSize == .init(width: 4, height: 5))
  }

  @Test("measurement cache reset clears the invalidations counter")
  func measurementCacheResetClearsInvalidations() {
    let cache = MeasurementCache()
    let original = leaf("resettable", size: .init(width: 10, height: 5))
    let measured = MeasuredNode(
      identity: original.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 10, height: 5)
    )
    cache.store(measured, for: original)

    let updated = leaf("resettable", size: .init(width: 20, height: 5))
    _ = cache.lookup(resolved: updated, proposal: .unspecified)
    #expect(cache.metrics.invalidations == 1)

    cache.reset()
    #expect(cache.metrics.invalidations == 0)
  }

  @Test("stack with spacers spreads remainder across the range")
  func stackWithSpacersSpreadsRemainderAcrossRange() {
    let engine = LayoutEngine()
    let resolved = stack(
      "stack",
      axis: .horizontal,
      children: [
        spacer("leading"),
        leaf("first", size: .init(width: 1, height: 1)),
        spacer("middle"),
        leaf("second", size: .init(width: 1, height: 1)),
        spacer("trailing"),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 10, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [3, 1, 2, 1, 3])
  }

  @Test("stack compression honors layout priority before reducing higher-priority children")
  func stackCompressionHonorsLayoutPriority() {
    let engine = LayoutEngine()
    let resolved = stack(
      "compression",
      axis: .horizontal,
      children: [
        leaf("low", size: .init(width: 4, height: 1)),
        leaf(
          "high",
          size: .init(width: 4, height: 1),
          layoutMetadata: .init(layoutPriority: 1)
        ),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 6, height: 1)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.measuredSize == .init(width: 6, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [2, 4])
    #expect(placed.children.map(\.bounds.origin.x) == [0, 2])
  }

  @Test("stack surplus is shared between a Spacer and a flexible sibling")
  func stackSurplusSharesBetweenSpacerAndFlexibleSibling() {
    let engine = LayoutEngine()
    let resolved = stack(
      "mixed",
      axis: .horizontal,
      children: [
        leaf("rigid", size: .init(width: 2, height: 1)),
        spacer("spacer"),
        flexibleWidthFrame(
          "flexible",
          maxWidth: .infinity,
          child: leaf("flexible-content", size: .init(width: 1, height: 1))
        ),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 10, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [2, 4, 4])
  }

  @Test("stack surplus honors layout priority before lower-priority flexibles")
  func stackSurplusHonorsLayoutPriority() {
    let engine = LayoutEngine()
    let resolved = stack(
      "priority-surplus",
      axis: .horizontal,
      children: [
        flexibleWidthFrame(
          "high",
          maxWidth: .infinity,
          child: leaf("high-content", size: .init(width: 1, height: 1)),
          layoutMetadata: .init(layoutPriority: 1)
        ),
        flexibleWidthFrame(
          "low",
          maxWidth: .infinity,
          child: leaf("low-content", size: .init(width: 1, height: 1))
        ),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 12, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 12, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [12, 0])
  }

  @Test("stack surplus flows past a max-capped flexible to its siblings")
  func stackSurplusRedistributesAboveMaxCaps() {
    let engine = LayoutEngine()
    let resolved = stack(
      "capped",
      axis: .horizontal,
      children: [
        flexibleWidthFrame(
          "capped-frame",
          maxWidth: 4,
          child: leaf("capped-content", size: .init(width: 1, height: 1))
        ),
        flexibleWidthFrame(
          "unbounded",
          maxWidth: .infinity,
          child: leaf("unbounded-content", size: .init(width: 1, height: 1))
        ),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 20, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [4, 16])
  }

  @Test("stack surplus skips fixedSize subtrees instead of losing their share")
  func stackSurplusSkipsFixedSizeSubtrees() {
    let engine = LayoutEngine()
    let resolved = stack(
      "fixed-size",
      axis: .horizontal,
      children: [
        flexibleWidthFrame(
          "pinned",
          maxWidth: .infinity,
          child: leaf("pinned-content", size: .init(width: 1, height: 1)),
          layoutMetadata: .init(fixedSizeHorizontal: true)
        ),
        flexibleWidthFrame(
          "absorbing",
          maxWidth: .infinity,
          child: leaf("absorbing-content", size: .init(width: 1, height: 1))
        ),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 10, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [1, 9])
  }

  @Test("stack compression divides space equally within a priority tier")
  func stackCompressionDividesEquallyWithinPriorityTier() {
    let engine = LayoutEngine()
    let resolved = stack(
      "equal-compression",
      axis: .horizontal,
      children: [
        leaf("wide", size: .init(width: 30, height: 1)),
        leaf("narrow", size: .init(width: 10, height: 1)),
      ]
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 1)
    )

    #expect(measured.measuredSize == .init(width: 20, height: 1))
    #expect(measured.childMeasurements.map(\.measuredSize.width) == [10, 10])
  }

  @Test("lazy stack measurement matches eager stack measurement")
  func lazyStackMeasurementMatchesEagerStackMeasurement() {
    let engine = LayoutEngine()
    let eager = stack(
      "eager",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
      ]
    )
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: eager.children,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let eagerMeasured = engine.measure(eager, proposal: .init(width: 8, height: 4))
    let lazyMeasured = engine.measure(lazy, proposal: .init(width: 8, height: 4))

    #expect(lazyMeasured.measuredSize == eagerMeasured.measuredSize)
    #expect(
      lazyMeasured.childMeasurements.map(\.measuredSize)
        == eagerMeasured.childMeasurements.map(\.measuredSize))
  }

  @Test("lazy stack placement falls back without viewport context")
  func lazyStackPlacementFallsBackWithoutViewportContext() {
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
      ],
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 4))
    let placed = engine.place(lazy, measured: measured, origin: .zero)

    #expect(placed.children.count == 3)
    #expect(placed.children.map(\.bounds.origin.y) == [0, 1, 2])
  }

  @Test("lazy stack ignores viewport context on the wrong axis")
  func lazyStackIgnoresViewportContextOnWrongAxis() {
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
      ],
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 4))
    let passContext = LayoutPassContext(
      retainedLayout: nil,
      scrollViewportContext: .init(
        axes: [.horizontal],
        viewportRect: .init(origin: .zero, size: .init(width: 1, height: 4)),
        contentOffset: .init(x: 1, y: 0)
      )
    )
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )

    #expect(placed.children.count == 3)
    #expect(placed.children.map(\.bounds.origin.y) == [0, 1, 2])
  }

  @Test("lazy vertical stack places only the visible viewport range")
  func lazyVerticalStackPlacesVisibleViewportRange() {
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
        leaf("row-3", size: .init(width: 4, height: 1)),
        leaf("row-4", size: .init(width: 2, height: 1)),
      ],
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 4))
    // Production-shaped geometry: the scroll layout places its content
    // translated by the clamped offset, so a stack scrolled down by 1 sits
    // at absolute y = -1 while the viewport rect stays put. The window math
    // intersects the two absolute ranges (`contentOffset` no longer feeds
    // the range directly).
    let passContext = LayoutPassContext(
      retainedLayout: nil,
      scrollViewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 1)),
        contentOffset: .init(x: 0, y: 1)
      )
    )
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .init(x: 0, y: -1), size: measured.measuredSize),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("row-0"),
        testIdentity("row-1"),
        testIdentity("row-2"),
      ])
    #expect(placed.children.map(\.bounds.origin.y) == [-1, 0, 1])
  }

  @Test("lazy horizontal stack places only the visible viewport range")
  func lazyHorizontalStackPlacesVisibleViewportRange() {
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .horizontal,
      children: [
        leaf("column-0", size: .init(width: 1, height: 2)),
        leaf("column-1", size: .init(width: 1, height: 3)),
        leaf("column-2", size: .init(width: 1, height: 1)),
        leaf("column-3", size: .init(width: 1, height: 4)),
        leaf("column-4", size: .init(width: 1, height: 2)),
      ],
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let measured = engine.measure(lazy, proposal: .init(width: 4, height: 8))
    // Production-shaped: scrolled right by 1 means the stack sits at
    // absolute x = -1 (see the vertical variant's comment).
    let passContext = LayoutPassContext(
      retainedLayout: nil,
      scrollViewportContext: .init(
        axes: [.horizontal],
        viewportRect: .init(origin: .zero, size: .init(width: 1, height: 8)),
        contentOffset: .init(x: 1, y: 0)
      )
    )
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .init(x: -1, y: 0), size: measured.measuredSize),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("column-0"),
        testIdentity("column-1"),
        testIdentity("column-2"),
      ])
    #expect(placed.children.map(\.bounds.origin.x) == [-1, 0, 1])
  }

  @Test("indexed lazy stacks retain sizing metadata without storing off-screen child measurements")
  func indexedLazyStacksRetainSizingMetadataWithoutChildMeasurements() throws {
    let engine = LayoutEngine()
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
        leaf("row-3", size: .init(width: 4, height: 1)),
      ]
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 4))
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)

    #expect(measured.childMeasurements.isEmpty)
    #expect(snapshot.contentMainLength == 4)
    #expect(snapshot.childMainOffsets == [0, 1, 2, 3])
    #expect(measured.containerAllocationSnapshot?.childSizes.map(\.size.height) == [1, 1, 1, 1])
  }

  @Test("indexed lazy stacks materialize only the visible placement range")
  func indexedLazyStacksPlaceOnlyVisibleRange() {
    let engine = LayoutEngine()
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf("row-1", size: .init(width: 3, height: 1)),
        leaf("row-2", size: .init(width: 1, height: 1)),
        leaf("row-3", size: .init(width: 4, height: 1)),
        leaf("row-4", size: .init(width: 2, height: 1)),
      ]
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 4))
    // Production-shaped: scrolled down by 1 -> stack absolute origin y = -1;
    // the visible row is row-1, which lands at absolute y = 0.
    let passContext = LayoutPassContext(
      retainedLayout: nil,
      scrollViewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 1)),
        contentOffset: .init(x: 0, y: 1)
      )
    )
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .init(x: 0, y: -1), size: .init(width: 8, height: 4)),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("row-1")
      ])
    #expect(placed.children.map(\.bounds.origin.y) == [0])
  }

  @Test("lazy stack offset inside scrolled content windows against its own bounds")
  func lazyStackOffsetInsideScrolledContentWindowsAgainstOwnBounds() {
    // A 2-row header sits above the stack inside the scrolled content and the
    // viewport is scrolled down by 2: the stack's translated origin is back
    // at absolute 0, so rows 0..1 are the visible band. The old
    // `contentOffset`-based math read the SCROLL offset (2) as the stack's
    // own scroll position and would window rows [1, 5) — dropping visible
    // row 0 (the header height exceeds the overscan allowance).
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: (0..<6).map { index in
        leaf("row-\(index)", size: .init(width: 2, height: 1))
      },
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let measured = engine.measure(lazy, proposal: .init(width: 8, height: 6))
    let passContext = LayoutPassContext(
      retainedLayout: nil,
      scrollViewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 2)),
        contentOffset: .init(x: 0, y: 2)
      )
    )
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("row-0"),
        testIdentity("row-1"),
        testIdentity("row-2"),
      ])
    #expect(placed.children.map(\.bounds.origin.y) == [0, 1, 2])
  }

  @Test("viewport context survives a wrapper between scroll content and the lazy stack")
  func viewportContextSurvivesWrapperAboveLazyStack() {
    // Production shape: the scroll layout hands the context to its DIRECT
    // content child's placement entry; any wrapper below must inherit it
    // down to the lazy stack (children previously reset to the pass-context
    // global — nil in the composed pipeline — so only a lazy stack that WAS
    // the direct content ever windowed). The pass context here carries NO
    // global, exactly like production; the context arrives only through the
    // top-level placement entry.
    let engine = LayoutEngine()
    let lazy = lazyStack(
      "lazy",
      axis: .vertical,
      children: (0..<5).map { index in
        leaf("row-\(index)", size: .init(width: 2, height: 1))
      },
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )
    let wrapper = stack(
      "wrapper",
      axis: .vertical,
      children: [lazy]
    )

    let measured = engine.measure(wrapper, proposal: .init(width: 8, height: 5))
    let placed = engine.place(
      wrapper,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      viewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 1)),
        contentOffset: .zero
      ),
      passContext: LayoutPassContext(retainedLayout: nil)
    )

    let placedLazy = placed.children[0]
    #expect(placedLazy.identity == testIdentity("lazy"))
    #expect(
      placedLazy.children.map(\.identity) == [
        testIdentity("row-0"),
        testIdentity("row-1"),
      ])
  }

  @Test("windowed measure realizes only the visible band plus overscan")
  func windowedMeasureRealizesOnlyVisibleBand() throws {
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 1))
    }
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: rows,
      realizationCounter: counter
    )
    let passContext = LayoutPassContext(retainedLayout: nil)
    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 10),
        viewportSize: .init(width: 8, height: 5)
      )
    )
    defer { passContext.popMeasureViewportHint() }

    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)

    // stride 1 (unit rows, spacing 0), offset 10, viewport 5 -> anchor 10,
    // window [10-1, 10+5+1+1) = 9..<17.
    #expect(snapshot.measuredWindow == 9..<17)
    #expect(snapshot.estimatedRowStride == 1)
    // Realizations: the probe (element 0) plus the 8 window rows.
    #expect(counter.count == 9)
    // Estimated tails keep the full-length arrays and the content extent.
    #expect(snapshot.childMainOffsets.count == 100)
    #expect(snapshot.childIdentities.count == 100)
    #expect(measured.containerAllocationSnapshot?.childSizes.count == 100)
    #expect(snapshot.contentMainLength == 100)
    #expect(measured.measuredSize == CellSize(width: 4, height: 100))
    #expect(snapshot.childIdentities[50] == testIdentity("row-50"))
    #expect(measured.childMeasurements.isEmpty)
  }

  @Test("windowed measure needs a hint: without one the source realizes exhaustively")
  func windowedMeasureFallsBackWithoutHint() throws {
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<20).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 1))
    }
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: rows,
      realizationCounter: counter
    )

    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: LayoutPassContext(retainedLayout: nil)
    )
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)

    #expect(snapshot.measuredWindow == nil)
    #expect(counter.count >= 20)
  }

  @Test("windowed placement realizes only the visible rows of a windowed product")
  func windowedPlacementRealizesOnlyVisibleRows() throws {
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 1))
    }
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: rows,
      realizationCounter: counter
    )
    let passContext = LayoutPassContext(retainedLayout: nil)
    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 10),
        viewportSize: .init(width: 8, height: 5)
      )
    )
    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    passContext.popMeasureViewportHint()
    let measureRealizations = counter.count

    // Production-shaped absolute geometry: scrolled down by 10 -> the stack
    // sits at absolute y = -10; the viewport shows rows 10..14.
    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .init(x: 0, y: -10), size: measured.measuredSize),
      viewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 5)),
        contentOffset: .init(x: 0, y: 10)
      ),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == (10..<15).map { testIdentity("row-\($0)") }
    )
    #expect(placed.children.map(\.bounds.origin.y) == [0, 1, 2, 3, 4])
    // Placement realized exactly the visible rows on demand.
    #expect(counter.count - measureRealizations == 5)
  }

  @Test("windowed placement keeps estimated visible rows adjacent at their measured heights")
  func windowedPlacementReflowsEstimatedVisibleRows() throws {
    // Measurement and placement can temporarily select different row bands
    // after a heterogeneous band's mean changes. Model that boundary directly:
    // measure far below the top, then place the top rows from the resulting
    // estimated allocation.
    let engine = LayoutEngine()
    let prefixHeights = [2, 3, 3, 2, 1, 11]
    let rows = (0..<100).map { index in
      leaf(
        "row-\(index)",
        size: .init(width: 4, height: index < prefixHeights.count ? prefixHeights[index] : 9)
      )
    }
    let lazy = indexedLazyStack("lazy", axis: .vertical, children: rows)
    let measureContext = LayoutPassContext(retainedLayout: nil)
    measureContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 90),
        viewportSize: .init(width: 8, height: 30)
      )
    )
    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: measureContext
    )
    measureContext.popMeasureViewportHint()
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)

    // The measured band is far below the top, so rows 0...3 carry the
    // band's synthetic 9-row extent in the allocation snapshot.
    #expect(snapshot.measuredWindow?.contains(0) == false)
    #expect(snapshot.childMainLengths[0..<4] == [9, 9, 9, 9])

    let placed = engine.place(
      lazy,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      viewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 60)),
        contentOffset: .zero
      ),
      passContext: LayoutPassContext(retainedLayout: nil)
    )

    // The refined (real) heights pack the estimated-visible run down to
    // y 31 in a 60-row viewport, so placement extends the run with rows
    // 7–10 until the refined geometry covers the viewport (org report
    // 2026-08-03-003: the bottom-edge blank-region defect). Rows stay
    // adjacent at their measured heights throughout.
    #expect(
      placed.children.map(\.identity) == (0..<11).map { testIdentity("row-\($0)") }
    )
    #expect(
      placed.children.map(\.bounds.origin.y) == [0, 2, 5, 8, 10, 11, 22, 31, 40, 49, 58]
    )
    #expect(
      placed.children.map(\.bounds.size.height) == [2, 3, 3, 2, 1, 11, 9, 9, 9, 9, 9]
    )
  }

  @Test("visible-range boundary changes keep common rows moving with the viewport")
  func windowedPlacementKeepsAStableMeasuredBandAnchor() throws {
    // Rows before the measured window are synthetic 3-cell allocations, but
    // row 3 is really 1 cell tall. Moving the viewport from 11 to 12 drops
    // row 3 from the visible placement run. If each run starts at its own
    // synthetic offset, every remaining row jumps down by 2 cells while the
    // viewport moves down by 1.
    let engine = LayoutEngine()
    let rows = (0..<37).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: index == 3 ? 1 : 3))
    }
    let lazy = indexedLazyStack("lazy", axis: .vertical, children: rows)
    let measureContext = LayoutPassContext(retainedLayout: nil)
    measureContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 18),
        viewportSize: .init(width: 8, height: 48)
      )
    )
    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: measureContext
    )
    measureContext.popMeasureViewportHint()
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)
    #expect(snapshot.measuredWindow == 5..<24)
    #expect(snapshot.childMainLengths[3] == 3)

    func place(at offset: Int) -> PlacedNode {
      engine.place(
        lazy,
        measured: measured,
        in: .init(
          origin: .init(x: 0, y: -offset),
          size: measured.measuredSize
        ),
        viewportContext: .init(
          axes: [.vertical],
          viewportRect: .init(origin: .zero, size: .init(width: 8, height: 48)),
          contentOffset: .init(x: 0, y: offset)
        ),
        passContext: LayoutPassContext(retainedLayout: nil)
      )
    }

    let before = place(at: 11)
    let after = place(at: 12)
    let beforeRow = try #require(before.children.first { $0.identity == testIdentity("row-5") })
    let afterRow = try #require(after.children.first { $0.identity == testIdentity("row-5") })

    #expect(afterRow.bounds.origin.y == beforeRow.bounds.origin.y - 1)
  }

  @Test("window movement replaces estimates with real measurements (drift correction)")
  func windowMovementCorrectsEstimates() throws {
    // Rows 0..49 are 1 cell tall; rows 50..99 are 3 cells. The probe row (0)
    // estimates every out-of-window entry at 1 cell, so a product windowed
    // near the top under-estimates the tail. Scrolling the hint into the
    // tall band re-windows: the new product measures the tall rows for real
    // and its content estimate grows — the correction mechanic Stage 2.4
    // relies on (the scroll registry re-anchors on content-size change).
    let engine = LayoutEngine()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: index < 50 ? 1 : 3))
    }
    let lazy = indexedLazyStack("lazy", axis: .vertical, children: rows)
    let passContext = LayoutPassContext(retainedLayout: nil)

    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .zero,
        viewportSize: .init(width: 8, height: 5)
      )
    )
    let topProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    passContext.popMeasureViewportHint()
    let topSnapshot = try #require(topProduct.containerAllocationSnapshot?.lazyStack)
    // Every row estimated at the probe's 1 cell: 100 total.
    #expect(topSnapshot.contentMainLength == 100)

    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 60),
        viewportSize: .init(width: 8, height: 5)
      )
    )
    let tallProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    passContext.popMeasureViewportHint()
    let tallSnapshot = try #require(tallProduct.containerAllocationSnapshot?.lazyStack)
    let tallWindow = try #require(tallSnapshot.measuredWindow)

    // The re-windowed product measured the tall rows for real...
    for index in tallWindow where index >= 50 {
      #expect(tallSnapshot.childMainLengths[index] == 3)
    }
    // ...so its content estimate grew past the all-1-cell estimate.
    #expect(tallSnapshot.contentMainLength > topSnapshot.contentMainLength)
  }

  @Test("estimated visible window anchors, spans, and clamps at dataset edges")
  func estimatedVisibleWindowClampsAtDatasetEdges() {
    let engine = LayoutEngine()
    let hint = { (offset: Int, viewport: Int) in
      MeasureViewportHint(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: offset),
        viewportSize: .init(width: 8, height: viewport)
      )
    }

    #expect(
      engine.lazyStackEstimatedVisibleWindow(
        hint: hint(0, 5), axis: .vertical, count: 100, rowStride: 1
      ) == 0..<7
    )
    #expect(
      engine.lazyStackEstimatedVisibleWindow(
        hint: hint(1_000, 5), axis: .vertical, count: 20, rowStride: 1
      ) == 18..<20
    )
    #expect(
      engine.lazyStackEstimatedVisibleWindow(
        hint: hint(10, 0), axis: .vertical, count: 100, rowStride: 1
      ) == nil
    )
    // Taller rows shrink the index band for the same pixel viewport.
    #expect(
      engine.lazyStackEstimatedVisibleWindow(
        hint: hint(12, 6), axis: .vertical, count: 100, rowStride: 3
      ) == 3..<8
    )
  }

  // MARK: - Windowing eligibility inversion + heterogeneous estimator
  // (scroll-latency program Stage 2, plan 2026-07-31-002)

  @Test("a frame-head worker snapshot source windows exactly like its live twin")
  func snapshotSourceWindowsUnderHint() throws {
    // The old `!source.canRunOnWorker` gate refused snapshots on the premise
    // that windowing an already-realized source saves nothing — but the
    // measure phase was the Stage-0-measured wall, so an under-budget
    // document was exhaustively measured every frame while an over-budget
    // one was windowed. Both source kinds must now produce the same product.
    let engine = LayoutEngine()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 1))
    }
    let live = indexedLazyStack("lazy", axis: .vertical, children: rows)
    var snapshotted = live
    snapshotted.indexedChildSource = IndexedChildSourceSnapshot(
      identityRoot: testIdentity("lazy"),
      measurementSignature: .init(elementPaths: rows.map(\.identity.path)),
      children: rows
    )

    func windowedProduct(_ node: ResolvedNode) -> MeasuredNode {
      let passContext = LayoutPassContext(retainedLayout: nil)
      passContext.pushMeasureViewportHint(
        .init(
          axes: [.vertical],
          contentOffset: .init(x: 0, y: 10),
          viewportSize: .init(width: 8, height: 5)
        )
      )
      defer { passContext.popMeasureViewportHint() }
      return engine.measure(
        node,
        proposal: ProposedSize(width: .finite(8), height: .unspecified),
        passContext: passContext
      )
    }

    let liveProduct = windowedProduct(live)
    let snapshotProduct = windowedProduct(snapshotted)

    let snapshotLazy = try #require(
      snapshotProduct.containerAllocationSnapshot?.lazyStack
    )
    #expect(snapshotLazy.measuredWindow == 9..<17)
    #expect(snapshotProduct.measuredSize == liveProduct.measuredSize)
    #expect(
      snapshotProduct.containerAllocationSnapshot?.lazyStack
        == liveProduct.containerAllocationSnapshot?.lazyStack
    )
  }

  @Test("a nested indexed stack cannot window against the outer scroll's claimed hint")
  func nestedIndexedStackDeclinesClaimedHint() throws {
    // The hint's contentOffset is meaningful only at the scroll content's
    // origin. A nested stack anchoring `offset / ownStride` at its own
    // origin parks its window at its end once the outer offset exceeds
    // `count × stride` — so the outer stack claims the hint and the nested
    // one must measure exhaustively (every nested row realized).
    let engine = LayoutEngine()
    let nestedCounter = RealizationCounter()
    let nestedRows = (0..<50).map { index in
      leaf("nested-\(index)", size: .init(width: 4, height: 1))
    }
    let nested = indexedLazyStack(
      "nested",
      axis: .vertical,
      children: nestedRows,
      realizationCounter: nestedCounter
    )
    let outerCounter = RealizationCounter()
    let outerElements =
      [nested]
      + (1..<40).map { index in
        leaf("outer-\(index)", size: .init(width: 4, height: 1))
      }
    let outer = indexedLazyStack(
      "outer",
      axis: .vertical,
      children: outerElements,
      realizationCounter: outerCounter
    )

    let passContext = LayoutPassContext(retainedLayout: nil)
    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .zero,
        viewportSize: .init(width: 8, height: 5)
      )
    )
    defer { passContext.popMeasureViewportHint() }
    let measured = engine.measure(
      outer,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )

    #expect(measured.containerAllocationSnapshot?.lazyStack?.measuredWindow != nil)
    // The nested stack fell back to exhaustive: every one of its 50 rows
    // realized (the exhaustive arm realizes the full source per
    // `stackChildren` derivation, so the count can exceed 50 — what matters
    // is that it is not a ~9-row window against the outer offset).
    #expect(nestedCounter.count >= 50)
  }

  @Test("heterogeneous band refines the stride past the element-0 probe")
  func heterogeneousBandRefinesStride() throws {
    // Element 0 is 1 row tall while the document body is 5 — the shape that
    // made an element-0-probe estimate under-length the content ~5× (and the
    // enclosing scroll clamps its offset against that length, truncating
    // scroll reach). The refined stride is the band's rounded mean extent.
    let engine = LayoutEngine()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: index == 0 ? 1 : 5))
    }
    let lazy = indexedLazyStack("lazy", axis: .vertical, children: rows)
    let passContext = LayoutPassContext(retainedLayout: nil)
    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .zero,
        viewportSize: .init(width: 8, height: 5)
      )
    )
    defer { passContext.popMeasureViewportHint() }

    let measured = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    let snapshot = try #require(measured.containerAllocationSnapshot?.lazyStack)

    // Probe stride 1 anchors the window at 0..<7; the band measures
    // extents [1, 5, 5, 5, 5, 5, 5] whose rounded mean is 4.
    #expect(snapshot.measuredWindow == 0..<7)
    #expect(snapshot.estimatedRowStride == 4)
    // In-window rows keep exact extents; the 93 out-of-window rows are
    // synthesized at the refined 4, not the probe's 1.
    #expect(snapshot.contentMainLength == 31 + 93 * 4)
    #expect(snapshot.windowHint?.contentOffset == .zero)
  }

  @Test("an indexed lazy stack reports its content extent as its own-axis maximum")
  func indexedLazyStackMaximumIsContentSized() {
    // Regression pin (org report 2026-08-03-003 finding 1): indexed-source
    // lazy stacks store no child measurements, so the composite maximums
    // walk zipped their realized children against an empty array and
    // derived a ZERO own-axis maximum. Under an enclosing stack's
    // allocation, a row containing such a stack was then capped at its
    // rigid sibling's extent — the one-display-line list-item clamp.
    let engine = LayoutEngine()
    let rows = (0..<3).map { index in
      leaf("max-row-\(index)", size: .init(width: 8, height: 3))
    }
    let lazy = indexedLazyStack("max-lazy", axis: .vertical, children: rows)
    let ideal = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: LayoutPassContext(retainedLayout: nil)
    )
    #expect(ideal.measuredSize.height == 9)
    let maximum = engine.derivedMaximumMainSize(
      for: lazy,
      idealMeasurement: ideal,
      axis: .vertical
    )
    #expect(maximum == 9, "derived maximum \(String(describing: maximum)), expected 9")
  }

  @Test("the previous windowed product's stride seeds the next window's anchor")
  func retainedStrideSeedsNextAnchor() throws {
    // Frame 1 windows at the top and stores its refined stride; frame 2's
    // anchor divides the new offset by that stride instead of re-probing
    // element 0 — no probe realization, and the window lands where rows of
    // the measured extent actually sit.
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 3))
    }
    let lazy = indexedLazyStack(
      "lazy", axis: .vertical, children: rows, realizationCounter: counter
    )

    let firstContext = LayoutPassContext(retainedLayout: nil)
    firstContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .zero,
        viewportSize: .init(width: 8, height: 6)
      )
    )
    let firstProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: firstContext
    )
    firstContext.popMeasureViewportHint()
    #expect(
      firstProduct.containerAllocationSnapshot?.lazyStack?.estimatedRowStride == 3
    )

    let placed = engine.place(
      lazy,
      measured: firstProduct,
      in: .init(origin: .zero, size: firstProduct.measuredSize),
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: lazy,
      measuredTree: firstProduct,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: lazy.identity,
        bounds: .init(origin: .zero, size: firstProduct.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let secondContext = LayoutPassContext(
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: .init(frame: previousFrame),
        invalidatedIdentities: [lazy.identity]
      )
    )
    secondContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 30),
        viewportSize: .init(width: 8, height: 6)
      )
    )
    defer { secondContext.popMeasureViewportHint() }
    let realizationsBefore = counter.count

    let secondProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: secondContext
    )
    let snapshot = try #require(secondProduct.containerAllocationSnapshot?.lazyStack)

    // Stride 3, offset 30 -> anchor 10, viewport 6 -> 2 rows -> 9..<14.
    // A probe-anchored stride of 1 would have anchored at 30 instead.
    #expect(snapshot.measuredWindow == 9..<14)
    // Band realizations only — element 0 was never probed.
    #expect(counter.count - realizationsBefore == 5)
  }

  @Test("rewindowing preserves the already-scrolled prefix allocation")
  func rewindowingPreservesAlreadyScrolledPrefixAllocation() throws {
    // The visible band's mean is allowed to refine the unseen tail so scroll
    // reach converges. It must not rewrite rows before the new window: doing
    // that changes the visible window's origin and makes content jump in the
    // opposite direction from the user's scroll input.
    let engine = LayoutEngine()
    let rows = (0..<40).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: index < 7 ? 1 : 5))
    }
    let lazy = indexedLazyStack(
      "lazy",
      axis: .vertical,
      children: rows,
      elementIdentities: rows.indices.map { testIdentity("derived-row-\($0)") }
    )

    let firstContext = LayoutPassContext(retainedLayout: nil)
    firstContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .zero,
        viewportSize: .init(width: 8, height: 5)
      )
    )
    let firstProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: firstContext
    )
    firstContext.popMeasureViewportHint()
    let firstSnapshot = try #require(firstProduct.containerAllocationSnapshot?.lazyStack)
    #expect(firstSnapshot.measuredWindow == 0..<7)
    #expect(firstSnapshot.estimatedRowStride == 1)

    let placed = engine.place(
      lazy,
      measured: firstProduct,
      in: .init(origin: .zero, size: firstProduct.measuredSize),
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: lazy,
      measuredTree: firstProduct,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: lazy.identity,
        bounds: .init(origin: .zero, size: firstProduct.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let secondContext = LayoutPassContext(
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: .init(frame: previousFrame),
        invalidatedIdentities: [lazy.identity]
      )
    )
    secondContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 12),
        viewportSize: .init(width: 8, height: 5)
      )
    )
    defer { secondContext.popMeasureViewportHint() }

    let secondProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: secondContext
    )
    let secondSnapshot = try #require(secondProduct.containerAllocationSnapshot?.lazyStack)
    let secondWindow = try #require(secondSnapshot.measuredWindow)

    #expect(secondWindow == 11..<19)
    #expect(secondSnapshot.estimatedRowStride == 5)
    #expect(
      Array(secondSnapshot.childMainLengths[..<secondWindow.lowerBound])
        == Array(firstSnapshot.childMainLengths[..<secondWindow.lowerBound])
    )
  }

  @Test("an exhaustive previous product seeds the stride from its exact mean")
  func exhaustivePreviousProductSeedsStride() throws {
    // The first windowed frame after an exhaustive one (the moment an
    // under-budget document first scrolls) anchors from the exhaustive
    // product's exact mean — (contentMainLength + spacing) / count — so its
    // content estimate starts right instead of at the element-0 guess.
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<20).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 2))
    }
    var lazy = indexedLazyStack(
      "lazy", axis: .vertical, children: rows, realizationCounter: counter
    )
    lazy.layoutBehavior = .lazyStack(
      axis: .vertical,
      spacing: 1,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )

    let exhaustive = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: LayoutPassContext(retainedLayout: nil)
    )
    #expect(exhaustive.containerAllocationSnapshot?.lazyStack?.measuredWindow == nil)
    // 20 rows × 2 + 19 × 1 spacing = 59.
    #expect(exhaustive.containerAllocationSnapshot?.lazyStack?.contentMainLength == 59)

    let placed = engine.place(
      lazy,
      measured: exhaustive,
      in: .init(origin: .zero, size: exhaustive.measuredSize),
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: lazy,
      measuredTree: exhaustive,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: lazy.identity,
        bounds: .init(origin: .zero, size: exhaustive.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let passContext = LayoutPassContext(
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: .init(frame: previousFrame),
        invalidatedIdentities: [lazy.identity]
      )
    )
    passContext.pushMeasureViewportHint(
      .init(
        axes: [.vertical],
        contentOffset: .init(x: 0, y: 12),
        viewportSize: .init(width: 8, height: 6)
      )
    )
    defer { passContext.popMeasureViewportHint() }
    let realizationsBefore = counter.count

    let windowed = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: passContext
    )
    let snapshot = try #require(windowed.containerAllocationSnapshot?.lazyStack)

    // Seed stride (59 + 1) / 20 = 3; offset 12 -> anchor 4, viewport 6 ->
    // 2 rows -> window 3..<8; no element-0 probe.
    #expect(snapshot.measuredWindow == 3..<8)
    #expect(counter.count - realizationsBefore == 5)
    #expect(snapshot.estimatedRowStride == 3)
  }

  @Test("re-measuring under any hint stays band-bounded and restamps the product's hint")
  func rewindowingStaysBandBoundedAndRestampsHint() throws {
    // Indexed-source nodes are `.viewportBarrier` edges: neither they nor
    // their ancestors ever reuse whole retained products (soundness — their
    // interiors are viewport-clipped subsets). The cost model is therefore
    // O(band) per re-measure, seeded by the previous product's stride, with
    // `windowHint` restamped to whatever hint the product was built under —
    // the field the (defense-in-depth) retained gate compares.
    let engine = LayoutEngine()
    let counter = RealizationCounter()
    let rows = (0..<100).map { index in
      leaf("row-\(index)", size: .init(width: 4, height: 1))
    }
    let lazy = indexedLazyStack(
      "lazy", axis: .vertical, children: rows, realizationCounter: counter
    )
    let hint = MeasureViewportHint(
      axes: [.vertical],
      contentOffset: .init(x: 0, y: 10),
      viewportSize: .init(width: 8, height: 5)
    )

    let firstContext = LayoutPassContext(retainedLayout: nil)
    firstContext.pushMeasureViewportHint(hint)
    let firstProduct = engine.measure(
      lazy,
      proposal: ProposedSize(width: .finite(8), height: .unspecified),
      passContext: firstContext
    )
    firstContext.popMeasureViewportHint()

    let placed = engine.place(
      lazy,
      measured: firstProduct,
      in: .init(origin: .zero, size: firstProduct.measuredSize),
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: lazy,
      measuredTree: firstProduct,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: lazy.identity,
        bounds: .init(origin: .zero, size: firstProduct.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )

    func remeasure(offset: Int) -> (MeasuredNode, Int) {
      let passContext = LayoutPassContext(
        retainedLayout: RetainedLayoutSession(
          previousFrameIndex: .init(frame: previousFrame),
          invalidatedIdentities: []
        )
      )
      passContext.pushMeasureViewportHint(
        .init(
          axes: [.vertical],
          contentOffset: .init(x: 0, y: offset),
          viewportSize: .init(width: 8, height: 5)
        )
      )
      defer { passContext.popMeasureViewportHint() }
      let before = counter.count
      let product = engine.measure(
        lazy,
        proposal: ProposedSize(width: .finite(8), height: .unspecified),
        passContext: passContext
      )
      return (product, counter.count - before)
    }

    // Identical hint: the re-measure is band-bounded (8 window rows, no
    // probe — the retained stride seeds the anchor), never O(dataset).
    let (samehint, samehintRealizations) = remeasure(offset: 10)
    #expect(samehintRealizations == 8)
    #expect(samehint.containerAllocationSnapshot?.lazyStack?.measuredWindow == 9..<17)

    // Offset moved: a fresh window is measured and the product's hint moves
    // with it.
    let (fresh, freshRealizations) = remeasure(offset: 11)
    #expect(freshRealizations > 0)
    #expect(freshRealizations <= 10)
    #expect(
      fresh.containerAllocationSnapshot?.lazyStack?.windowHint?.contentOffset
        == CellPoint(x: 0, y: 11)
    )
  }

  @Test("hint claims are identity-keyed and re-entrant for the claimer")
  func hintClaimsAreIdentityKeyedAndReentrant() {
    let passContext = LayoutPassContext(retainedLayout: nil)
    let hint = MeasureViewportHint(
      axes: [.vertical],
      contentOffset: .zero,
      viewportSize: .init(width: 8, height: 5)
    )

    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("a")) == nil)

    passContext.pushMeasureViewportHint(hint)
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("a")) == hint)
    // Re-claim by the same identity (an enclosing stack's flexibility
    // second round re-measuring the claimer) still windows.
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("a")) == hint)
    // A different container is refused.
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("b")) == nil)

    // A nested scroll's fresh hint is independently claimable...
    let inner = MeasureViewportHint(
      axes: [.vertical],
      contentOffset: .init(x: 0, y: 3),
      viewportSize: .init(width: 8, height: 2)
    )
    passContext.pushMeasureViewportHint(inner)
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("b")) == inner)
    passContext.popMeasureViewportHint()

    // ...and popping restores the outer entry with its claim intact.
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("b")) == nil)
    #expect(passContext.claimCurrentMeasureViewportHint(for: testIdentity("a")) == hint)
    passContext.popMeasureViewportHint()
  }

  @Test("flexible frame resolves unspecified finite and infinite proposals")
  func flexibleFrameResolvesProposalKinds() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("frame"),
      kind: .view("FlexibleFrame"),
      children: [leaf("content", size: .init(width: 4, height: 1))],
      layoutBehavior: .flexibleFrame(
        minWidth: 2,
        idealWidth: 6,
        maxWidth: 8,
        minHeight: nil,
        idealHeight: nil,
        maxHeight: nil,
        alignment: .topLeading
      )
    )

    let unspecified = engine.measure(resolved, proposal: .unspecified)
    let clampedFinite = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 1)
    )
    let minimumFinite = engine.measure(
      resolved,
      proposal: .init(width: 1, height: 1)
    )
    let infinite = engine.measure(
      resolved,
      proposal: .init(width: .infinity, height: 1)
    )

    #expect(unspecified.measuredSize == .init(width: 6, height: 1))
    #expect(clampedFinite.measuredSize == .init(width: 8, height: 1))
    #expect(minimumFinite.measuredSize == .init(width: 2, height: 1))
    #expect(infinite.measuredSize == .init(width: 8, height: 1))
  }

  @Test("overlay sizing uses the alignment-projected union of children")
  func overlaySizingUsesAlignmentProjectedUnion() {
    let engine = LayoutEngine()
    let centered = leaf("centered", size: .init(width: 2, height: 1))
    let leadingAligned = leaf(
      "leadingAligned",
      size: .init(width: 4, height: 1),
      layoutMetadata: LayoutMetadata().settingHorizontalAlignmentGuide(
        .center,
        debugName: HorizontalAlignment.center.debugName,
        computeValue: { _ in 0 }
      )
    )
    let resolved = ResolvedNode(
      identity: testIdentity("overlay"),
      kind: .view("Overlay"),
      children: [centered, leadingAligned],
      layoutBehavior: .overlay(alignment: .center)
    )

    let measured = engine.measure(resolved)
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.measuredSize == .init(width: 5, height: 1))
    #expect(placed.children.map(\.bounds.origin.x) == [0, 1])
  }

  @Test("ViewThatFits selects the first child that fits the proposal")
  func viewThatFitsSelectsFirstFittingChild() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("viewThatFits"),
      kind: .view("ViewThatFits"),
      children: [
        leaf("wide", size: .init(width: 7, height: 1)),
        leaf("fit", size: .init(width: 5, height: 1)),
        leaf("small", size: .init(width: 1, height: 1)),
      ],
      layoutBehavior: .viewThatFits(.horizontal)
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 5, height: 1)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.measuredSize == .init(width: 5, height: 1))
    #expect(measured.containerAllocationSnapshot?.selectedChildIndex == 1)
    #expect(placed.children.map(\.identity) == [testIdentity("fit")])
  }

  @Test("safe area inset measures adornment before base and stores source-facing order")
  func safeAreaInsetMeasuresAdornmentBeforeBaseAndStoresSourceFacingOrder() {
    let engine = LayoutEngine()
    let base = leaf("safe-area-base", size: .init(width: 10, height: 10))
    let adornment = leaf("safe-area-adornment", size: .init(width: 8, height: 2))
    let resolved = ResolvedNode(
      identity: testIdentity("safe-area-inset"),
      kind: .view("SafeAreaInset"),
      children: [base, adornment],
      layoutBehavior: .safeAreaInset(
        edge: .top,
        alignment: .center,
        spacing: 1,
        safeArea: .init()
      )
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 10)
    )

    #expect(measured.childMeasurements.map(\.identity) == [base.identity, adornment.identity])
    #expect(measured.childMeasurements[0].proposal == .init(width: 10, height: 7))
    #expect(
      measured.childMeasurements[1].proposal
        == .init(width: .finite(10), height: .unspecified)
    )
  }

  @Test("decoration falls back to source-order child measurement when primary is missing")
  func decorationFallsBackToSourceOrderChildMeasurementWhenPrimaryIsMissing() {
    let engine = LayoutEngine()
    let first = leaf("decoration-fallback-first", size: .init(width: 2, height: 1))
    let second = leaf("decoration-fallback-second", size: .init(width: 4, height: 1))
    let resolved = ResolvedNode(
      identity: testIdentity("decoration-fallback"),
      kind: .view("Decoration"),
      children: [first, second],
      layoutBehavior: .decoration(primaryIndex: 5, alignment: .center)
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 3)
    )

    #expect(measured.childMeasurements.map(\.identity) == [first.identity, second.identity])
    #expect(
      measured.childMeasurements.map(\.proposal)
        == [.init(width: 10, height: 3), .init(width: 10, height: 3)]
    )
    #expect(measured.measuredSize == .init(width: 4, height: 1))
  }

  @Test("padding reduces the child proposal and places the child at the inset origin")
  func paddingReducesProposalAndOffsetsPlacement() throws {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("padding"),
      kind: .view("Padding"),
      children: [leaf("content", size: .init(width: 20, height: 10))],
      layoutBehavior: .padding(.init(top: 1, leading: 2, bottom: 1, trailing: 2))
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 9, height: 5)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)
    let child = try #require(placed.children.first)

    #expect(measured.measuredSize == .init(width: 9, height: 5))
    #expect(measured.childMeasurements.first?.measuredSize == .init(width: 5, height: 3))
    #expect(child.bounds.origin == .init(x: 2, y: 1))
    #expect(child.bounds.size == .init(width: 5, height: 3))
  }

  @Test("offset preserves measured size while translating child placement")
  func offsetTranslatesChildPlacementWithoutChangingContentBounds() throws {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("offset"),
      kind: .view("Offset"),
      children: [leaf("content", size: .init(width: 4, height: 1))],
      layoutBehavior: .offset(x: 2, y: 1)
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 4, height: 1)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)
    let child = try #require(placed.children.first)

    #expect(measured.measuredSize == .init(width: 4, height: 1))
    #expect(child.bounds.origin == .init(x: 2, y: 1))
    #expect(child.bounds.size == .init(width: 4, height: 1))
    #expect(placed.contentBounds == .init(origin: .zero, size: .init(width: 4, height: 1)))
  }

  @Test("wide-character word wrapping measures by cell width instead of cluster count")
  func wideCharacterWordWrappingUsesCellWidth() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("text"),
      kind: .view("Text"),
      layoutMetadata: .init(textWrappingStrategy: .wordBoundary),
      drawPayload: .text("界界界界界")
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 8, height: .unspecified)
    )

    #expect(measured.measuredSize == .init(width: 7, height: 2))
  }

  @Test("zero and negative proposals clamp measured sizes to zero")
  func zeroAndNegativeProposalsClampToZero() {
    let engine = LayoutEngine()
    let resolved = leaf("leaf", size: .init(width: 4, height: 2))

    let zero = engine.measure(
      resolved,
      proposal: .init(width: 0, height: 0)
    )
    let negative = engine.measure(
      resolved,
      proposal: .init(width: -3, height: -1)
    )

    #expect(zero.measuredSize == .zero)
    #expect(negative.measuredSize == .zero)
  }

  @Test("retained reuse support updates when layout behavior or children change")
  func supportsRetainedReuseTracksResolvedMutations() {
    var parent = ResolvedNode(
      identity: testIdentity("parent"),
      kind: .view("Container"),
      children: [leaf("child", size: .init(width: 1, height: 1))]
    )

    #expect(parent.supportsRetainedReuse)

    parent.layoutBehavior = .viewThatFits(.horizontal)
    #expect(!parent.supportsRetainedReuse)

    parent.layoutBehavior = .intrinsic
    parent.children = [
      ResolvedNode(
        identity: testIdentity("custom"),
        kind: .view("Custom"),
        layoutBehavior: .custom(CustomLayoutHandle(NoOpCustomLayoutProxy()))
      )
    ]
    #expect(!parent.supportsRetainedReuse)

    parent.children = [
      ResolvedNode(
        identity: testIdentity("custom"),
        kind: .view("Custom"),
        layoutBehavior: .custom(
          CustomLayoutHandle(
            NoOpCustomLayoutProxy(),
            measurementReuseSignature: "custom.measure"
          ))
      )
    ]
    #expect(!parent.supportsRetainedReuse)

    parent.children = [
      ResolvedNode(
        identity: testIdentity("custom"),
        kind: .view("Custom"),
        layoutBehavior: .custom(
          CustomLayoutHandle(
            NoOpCustomLayoutProxy(),
            measurementReuseSignature: "custom.measure",
            placementReuseSignature: "custom.place"
          ))
      )
    ]
    #expect(parent.supportsRetainedReuse)
  }

  @Test("custom layout handles default to main actor execution")
  func customLayoutHandlesDefaultToMainActorExecution() {
    let handle = CustomLayoutHandle(NoOpCustomLayoutProxy())

    #expect(handle.executionCapability == .mainActorOnly)
    #expect(!handle.canRunOnWorker)
    #expect(handle.workerProxy == nil)
  }

  @Test("custom layout handles report worker execution capability")
  func customLayoutHandlesReportWorkerExecutionCapability() throws {
    let workerProxy = NoOpWorkerCustomLayoutProxy()
    let handle = CustomLayoutHandle(
      NoOpCustomLayoutProxy(),
      workerProxy: workerProxy
    )

    #expect(handle.executionCapability == .worker)
    #expect(handle.canRunOnWorker)
    #expect(try #require(handle.workerProxy).debugName == "NoOpWorkerCustomLayoutProxy")
  }

  @Test("retained placement translates eager scroll subtrees when only viewport origin changes")
  func retainedPlacementTranslatesEagerViewportShift() {
    let engine = LayoutEngine()
    let resolved = stack(
      "scroll-content",
      axis: .vertical,
      children: [
        leaf("row-0", size: .init(width: 2, height: 1)),
        leaf(
          "row-1",
          size: .init(width: 2, height: 1),
          semanticMetadata: .init(namedCoordinateSpace: .named("middle-row"))
        ),
        leaf("row-2", size: .init(width: 2, height: 1)),
      ]
    )

    let measured = engine.measure(resolved, proposal: .init(width: 8, height: 3))
    let initialBounds = CellRect(origin: .zero, size: measured.measuredSize)
    let initialPlaced = engine.place(
      resolved,
      measured: measured,
      in: initialBounds,
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: measured,
      placedTree: initialPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(identity: resolved.identity, bounds: initialBounds),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let retainedLayout = RetainedLayoutSession(
      previousFrameIndex: .init(frame: previousFrame),
      invalidatedIdentities: []
    )
    let passContext = LayoutPassContext(
      retainedLayout: retainedLayout,
      scrollViewportContext: .init(
        axes: [.vertical],
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 1)),
        contentOffset: .init(x: 0, y: 1)
      )
    )

    let shifted = engine.place(
      resolved,
      measured: measured,
      in: .init(origin: .init(x: 0, y: -1), size: measured.measuredSize),
      passContext: passContext
    )

    #expect(shifted.bounds.origin == .init(x: 0, y: -1))
    #expect(shifted.contentBounds.origin == .init(x: 0, y: -1))
    #expect(shifted.children.map(\.bounds.origin.y) == [-1, 0, 1])
    #expect(passContext.placedFrameTable == placedFrameTable(for: shifted))
    #expect(
      passContext.placedFrameTable.namedCoordinateSpaces[.named("middle-row")]
        == shifted.children[1].bounds
    )
    #expect(passContext.workMetrics.placedNodesComputed == 0)
    #expect(passContext.workMetrics.placedNodesReused == 4)
    #expect(passContext.workMetrics.placedFrameTableEntriesReused == 4)
  }

  @Test("retained placement carries identical placed frame table fragments")
  func retainedPlacementCarriesIdenticalPlacedFrameTableFragments() {
    let engine = LayoutEngine()
    let resolved = stack(
      "container",
      axis: .vertical,
      semanticMetadata: .init(namedCoordinateSpace: .named("shared")),
      children: [
        leaf(
          "row-0",
          size: .init(width: 3, height: 1),
          semanticMetadata: .init(namedCoordinateSpace: .named("shared"))
        ),
        leaf(
          "row-1",
          size: .init(width: 3, height: 1),
          semanticMetadata: .init(namedCoordinateSpace: .named("row-one"))
        ),
      ]
    )

    let measured = engine.measure(resolved, proposal: .init(width: 8, height: 2))
    let bounds = CellRect(origin: .zero, size: measured.measuredSize)
    let initialPlaced = engine.place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: measured,
      placedTree: initialPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(identity: resolved.identity, bounds: bounds),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let retainedLayout = RetainedLayoutSession(
      previousFrameIndex: .init(frame: previousFrame),
      invalidatedIdentities: []
    )
    let passContext = LayoutPassContext(retainedLayout: retainedLayout)

    let placed = engine.place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: passContext
    )

    #expect(passContext.placedFrameTable == placedFrameTable(for: placed))
    #expect(
      passContext.placedFrameTable.namedCoordinateSpaces[.named("shared")]
        == placed.children[0].bounds
    )
    #expect(
      passContext.placedFrameTable.namedCoordinateSpaces[.named("row-one")]
        == placed.children[1].bounds
    )
    #expect(passContext.workMetrics.placedNodesComputed == 0)
    #expect(passContext.workMetrics.placedNodesReused == 3)
    #expect(passContext.workMetrics.placedFrameTableEntriesReused == 3)
    #expect(
      passContext.workMetrics.geometryResolutionDiagnostics.duplicateNamedCoordinateSpaceCount
        == 1
    )
  }

  @Test("retained placement synchronizes geometry-stable resolved metadata")
  func retainedPlacementSynchronizesGeometryStableResolvedMetadata() {
    let engine = LayoutEngine()
    let environment = EnvironmentSnapshot(
      debugSignature: "retained-sync",
      values: ["scope": "current"]
    )
    let layoutMetadata = LayoutMetadata(lineLimit: 1)
    var initialDrawMetadata = DrawMetadata()
    initialDrawMetadata.baseStyle.foregroundStyle = .color(Color.red)
    var updatedDrawMetadata = DrawMetadata()
    updatedDrawMetadata.baseStyle.foregroundStyle = .color(Color.blue)
    let initialLayoutBehavior = LayoutBehavior.border(
      .rounded,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue]),
      blendPhase: 0.1,
      sides: .all
    )
    let updatedLayoutBehavior = LayoutBehavior.border(
      .rounded,
      placement: .outset,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue]),
      blendPhase: 0.8,
      sides: .all
    )

    let initial = leaf(
      "metadata",
      size: .init(width: 5, height: 1),
      environmentSnapshot: environment,
      layoutBehavior: initialLayoutBehavior,
      layoutMetadata: layoutMetadata,
      drawMetadata: initialDrawMetadata,
      semanticMetadata: .init(
        accessibilityLabel: "old",
        namedCoordinateSpace: .named("old-space")
      ),
      lifecycleMetadata: .init(appearHandlerIDs: ["old-appear"]),
      drawPayload: .text("Same")
    )
    var updated = leaf(
      "metadata",
      size: .init(width: 5, height: 1),
      environmentSnapshot: environment,
      layoutBehavior: updatedLayoutBehavior,
      layoutMetadata: layoutMetadata,
      drawMetadata: updatedDrawMetadata,
      semanticMetadata: .init(
        accessibilityLabel: "new",
        namedCoordinateSpace: .named("new-space")
      ),
      lifecycleMetadata: .init(appearHandlerIDs: ["new-appear"]),
      drawPayload: .text("Same")
    )
    updated.isTransient = true
    updated.matchedGeometry = MatchedGeometryConfig(
      key: MatchedGeometryKey(id: "hero"),
      isSource: false
    )

    let measured = engine.measure(initial, proposal: .init(width: 8, height: 1))
    let bounds = CellRect(origin: .zero, size: measured.measuredSize)
    let initialPlaced = engine.place(
      initial,
      measured: measured,
      in: bounds,
      passContext: nil
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: initial,
      measuredTree: measured,
      placedTree: initialPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(identity: initial.identity, bounds: bounds),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let retainedLayout = RetainedLayoutSession(
      previousFrameIndex: .init(frame: previousFrame),
      invalidatedIdentities: []
    )
    let passContext = LayoutPassContext(retainedLayout: retainedLayout)
    let updatedMeasured = engine.measure(updated, proposal: .init(width: 8, height: 1))

    let placed = engine.place(
      updated,
      measured: updatedMeasured,
      in: bounds,
      passContext: passContext
    )

    #expect(passContext.workMetrics.placedNodesComputed == 0)
    #expect(passContext.workMetrics.placedNodesReused == 1)
    #expect(passContext.workMetrics.placedFrameTableEntriesReused == 0)
    #expect(passContext.placedFrameTable.namedCoordinateSpaces[.named("old-space")] == nil)
    #expect(passContext.placedFrameTable.namedCoordinateSpaces[.named("new-space")] == bounds)
    #expect(placed.kind == updated.kind)
    #expect(placed.environmentSnapshot == environment)
    #expect(placed.layoutMetadata == layoutMetadata)
    #expect(placed.drawMetadata.baseStyle.foregroundStyle == .color(Color.blue))
    #expect(placed.semanticMetadata.accessibilityLabel == "new")
    #expect(placed.lifecycleMetadata.appearHandlerIDs == ["new-appear"])
    #expect(placed.drawPayload == .text("Same"))
    #expect(placed.layoutBehavior == updatedLayoutBehavior)
    #expect(placed.isTransient)
    #expect(placed.matchedGeometry == updated.matchedGeometry)
  }
}

private func leaf(
  _ name: String,
  size: CellSize,
  viewNodeID: ViewNodeID? = nil,
  kind: NodeKind = .view("Test"),
  environmentSnapshot: EnvironmentSnapshot = .init(),
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  lifecycleMetadata: LifecycleMetadata = .init(),
  drawPayload: DrawPayload = .none
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: viewNodeID ?? testViewNodeID(name),
    identity: testIdentity(name),
    kind: kind,
    environmentSnapshot: environmentSnapshot,
    layoutBehavior: layoutBehavior,
    layoutMetadata: layoutMetadata,
    drawMetadata: drawMetadata,
    semanticMetadata: semanticMetadata,
    lifecycleMetadata: lifecycleMetadata,
    drawPayload: drawPayload,
    intrinsicSize: size
  )
}

private func testViewNodeID(_ name: String) -> ViewNodeID {
  var hash: UInt64 = 14_695_981_039_346_656_037
  for byte in name.utf8 {
    hash ^= UInt64(byte)
    hash &*= 1_099_511_628_211
  }
  return ViewNodeID(rawValue: hash)
}

private func lazyStack(
  _ name: String,
  axis: Axis,
  children: [ResolvedNode],
  spacing: Int?,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "LazyHStack" : "LazyVStack"),
    children: children,
    layoutBehavior: .lazyStack(
      axis: axis,
      spacing: spacing,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )
  )
}

private func indexedLazyStack(
  _ name: String,
  axis: Axis,
  children: [ResolvedNode],
  realizationCounter: RealizationCounter? = nil,
  elementIdentities: [Identity]? = nil
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "LazyHStack" : "LazyVStack"),
    layoutBehavior: .lazyStack(
      axis: axis,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    ),
    indexedChildSource: TestIndexedChildSource(
      identityRoot: testIdentity(name),
      children: children,
      realizationCounter: realizationCounter,
      elementIdentities: elementIdentities
    )
  )
}

/// Counts `child(at:)` realizations on the test source, so windowed
/// measurement/placement tests can pin that out-of-window rows are never
/// materialized.
final class RealizationCounter: Sendable {
  private let storage = Mutex<Int>(0)

  var count: Int {
    storage.withLock { $0 }
  }

  func record() {
    storage.withLock { $0 += 1 }
  }
}

private func spacer(_ name: String) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Spacer"),
    intrinsicSize: .zero
  )
}

private func flexibleWidthFrame(
  _ name: String,
  maxWidth: ProposedDimension,
  child: ResolvedNode,
  layoutMetadata: LayoutMetadata = .init()
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("FlexibleFrame"),
    children: [child],
    layoutBehavior: .flexibleFrame(
      minWidth: nil,
      idealWidth: nil,
      maxWidth: maxWidth,
      minHeight: nil,
      idealHeight: nil,
      maxHeight: nil,
      alignment: .topLeading
    ),
    layoutMetadata: layoutMetadata
  )
}

private func stack(
  _ name: String,
  axis: Axis,
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "HStack" : "VStack"),
    children: children,
    layoutBehavior: .stack(
      axis: axis,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    ),
    semanticMetadata: semanticMetadata
  )
}

private func placedFrameTable(
  for node: PlacedNode
) -> PlacedFrameTable {
  var table = PlacedFrameTable()
  var work = [node]
  while let current = work.popLast() {
    table.record(
      viewNodeID: current.viewNodeID,
      identity: current.identity,
      bounds: current.bounds,
      namedCoordinateSpace: current.semanticMetadata.namedCoordinateSpace
    )
    work.append(contentsOf: current.children.reversed())
  }
  return table
}

private final class NoOpCustomLayoutProxy: CustomLayoutProxy {
  var debugName: String {
    "NoOpCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> CellSize {
    .zero
  }

  func placeSubviews(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    measured _: MeasuredNode,
    in _: CellRect
  ) -> [PlacedNode] {
    []
  }
}

private struct NoOpWorkerCustomLayoutProxy: WorkerCustomLayoutProxy {
  var debugName: String {
    "NoOpWorkerCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize,
    passContext _: LayoutPassContext?
  ) -> CellSize {
    .zero
  }

  func placeSubviews(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    measured _: MeasuredNode,
    in _: CellRect,
    passContext _: LayoutPassContext?
  ) -> [PlacedNode] {
    []
  }
}

private struct TestIndexedChildSource: IndexedChildSource {
  let identityRoot: Identity
  let measurementSignature: IndexedChildMeasurementSignature
  private let children: [ResolvedNode]
  private let realizationCounter: RealizationCounter?
  private let elementIdentities: [Identity]

  init(
    identityRoot: Identity,
    children: [ResolvedNode],
    realizationCounter: RealizationCounter? = nil,
    elementIdentities: [Identity]? = nil
  ) {
    self.identityRoot = identityRoot
    self.children = children
    self.realizationCounter = realizationCounter
    self.elementIdentities = elementIdentities ?? children.map(\.identity)
    measurementSignature = .init(elementPaths: children.map(\.identity.path))
  }

  var count: Int {
    children.count
  }

  func child(at index: Int) -> ResolvedNode {
    realizationCounter?.record()
    return children[index]
  }

  func elementIdentity(at index: Int) -> Identity {
    elementIdentities[index]
  }
}

/// F166: placement child/measurement mismatches must be reported, not
/// silently swallowed. A wrapper whose resolve produced a child but whose
/// measurement lost it (or vice versa) returned an empty placement — the
/// invisible-content class — with no diagnostic anywhere.
@MainActor
@Suite("Placement mismatch diagnostics (F166)")
struct PlacementMismatchDiagnosticsTests {
  @Test("a wrapper with a child but no measurement records a mismatch issue")
  func wrapperMismatchRecordsIssue() {
    let engine = LayoutEngine()
    let child = ResolvedNode(identity: testIdentity("Mismatch", "Child"), kind: .view("Child"))
    var wrapper = ResolvedNode(
      identity: testIdentity("Mismatch"),
      kind: .view("Padded"),
      children: [child]
    )
    wrapper.layoutBehavior = .padding(.init(top: 1, leading: 1, bottom: 1, trailing: 1))
    let measured = MeasuredNode(
      identity: wrapper.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 10, height: 4),
      childMeasurements: []
    )
    let passContext = LayoutPassContext()

    let requests = engine.placementRequests(
      for: wrapper,
      measured: measured,
      in: .init(origin: .zero, size: .init(width: 10, height: 4)),
      viewportContext: nil,
      passContext: passContext
    )

    #expect(requests.isEmpty)
    #expect(
      passContext.runtimeIssues.contains { issue in
        issue.code == "layout.placementChildMismatch"
      },
      "the divergence was swallowed silently; issues: \(passContext.runtimeIssues)"
    )
  }

  @Test("a childless wrapper records nothing")
  func childlessWrapperRecordsNothing() {
    let engine = LayoutEngine()
    var wrapper = ResolvedNode(identity: testIdentity("Childless"), kind: .view("Padded"))
    wrapper.layoutBehavior = .padding(.init(top: 1, leading: 1, bottom: 1, trailing: 1))
    let measured = MeasuredNode(
      identity: wrapper.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 4, height: 2)
    )
    let passContext = LayoutPassContext()

    _ = engine.placementRequests(
      for: wrapper,
      measured: measured,
      in: .init(origin: .zero, size: .init(width: 4, height: 2)),
      viewportContext: nil,
      passContext: passContext
    )

    #expect(passContext.runtimeIssues.isEmpty)
  }

  @Test("an intrinsic container with truncated measurements records a mismatch issue")
  func intrinsicTruncationRecordsIssue() {
    let engine = LayoutEngine()
    let childA = ResolvedNode(identity: testIdentity("Trunc", "A"), kind: .view("A"))
    let childB = ResolvedNode(identity: testIdentity("Trunc", "B"), kind: .view("B"))
    let container = ResolvedNode(
      identity: testIdentity("Trunc"),
      kind: .view("Container"),
      children: [childA, childB]
    )
    let measured = MeasuredNode(
      identity: container.identity,
      proposal: .unspecified,
      measuredSize: .init(width: 8, height: 2),
      childMeasurements: [
        MeasuredNode(
          identity: childA.identity,
          proposal: .unspecified,
          measuredSize: .init(width: 4, height: 1)
        )
      ]
    )
    let passContext = LayoutPassContext()

    let requests = engine.placementRequests(
      for: container,
      measured: measured,
      in: .init(origin: .zero, size: .init(width: 8, height: 2)),
      viewportContext: nil,
      passContext: passContext
    )

    #expect(requests.count == 1, "the truncated placement itself is unchanged")
    #expect(
      passContext.runtimeIssues.contains { issue in
        issue.code == "layout.placementChildMismatch"
      }
    )
  }
}

import Testing

@_spi(Testing) @testable import SwiftTUICore

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

  @Test("measurement cache keeps at most four proposal variants per identity")
  func measurementCacheCapsProposalVariantsPerIdentity() {
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

  @Test("measurement cache prunes dead identities")
  func measurementCachePrunesDeadIdentities() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let kept = leaf("kept", size: .init(width: 4, height: 1))
    let pruned = leaf("pruned", size: .init(width: 5, height: 1))

    _ = engine.measure(kept, proposal: .unspecified)
    _ = engine.measure(kept, proposal: .init(width: 2, height: nil))
    _ = engine.measure(pruned, proposal: .unspecified)
    let beforePrune = cache.metrics

    cache.prune(keeping: [kept.identity])
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

  @Test("stale cache eviction preserves other proposal variants for the same identity")
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
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("column-0"),
        testIdentity("column-1"),
        testIdentity("column-2"),
      ])
    #expect(placed.children.map(\.bounds.origin.x) == [0, 1, 2])
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
      in: .init(origin: .zero, size: .init(width: 8, height: 4)),
      passContext: passContext
    )

    #expect(
      placed.children.map(\.identity) == [
        testIdentity("row-1")
      ])
    #expect(placed.children.map(\.bounds.origin.y) == [1])
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
        leaf("row-1", size: .init(width: 2, height: 1)),
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
    #expect(passContext.workMetrics.placedNodesComputed == 0)
    #expect(passContext.workMetrics.placedNodesReused == 4)
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
      semanticMetadata: .init(accessibilityLabel: "old"),
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
      semanticMetadata: .init(accessibilityLabel: "new"),
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
  children: [ResolvedNode]
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
      children: children
    )
  )
}

private func spacer(_ name: String) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Spacer"),
    intrinsicSize: .zero
  )
}

private func stack(
  _ name: String,
  axis: Axis,
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
    )
  )
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
  let measurementSignature: String
  private let children: [ResolvedNode]

  init(
    identityRoot: Identity,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.children = children
    measurementSignature = children.map(\.identity.path).joined(separator: "|")
  }

  var count: Int {
    children.count
  }

  func child(at index: Int) -> ResolvedNode {
    children[index]
  }
}

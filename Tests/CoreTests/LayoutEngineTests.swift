import Testing

@testable import Core

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
  }
}

private func leaf(
  _ name: String,
  size: Size,
  layoutMetadata: LayoutMetadata = .init(),
  drawPayload: DrawPayload = .none
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Test"),
    layoutMetadata: layoutMetadata,
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

private final class NoOpCustomLayoutProxy: CustomLayoutProxy, @unchecked Sendable {
  var debugName: String {
    "NoOpCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> Size {
    .zero
  }

  func placeSubviews(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    measured _: MeasuredNode,
    in _: Rect
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

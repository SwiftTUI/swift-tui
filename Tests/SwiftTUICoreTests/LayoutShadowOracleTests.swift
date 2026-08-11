import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Owning tests for the `layout-shadow-divergence` oracle's comparison layer.
///
/// The red proofs inject doctored production trees against a genuine fresh
/// pass — the oracle must flag them. The green proofs run a real engine pass
/// twice and require silence. The recorder/trace plumbing is owned by
/// `SoundnessProbeConfigurationTests` and `SoundnessFailureChannelTests`.
@Suite
struct LayoutShadowOracleTests {
  @Test("a clean production pass compares silent against its shadow")
  func cleanPassComparesSilent() {
    let engine = LayoutEngine(cache: MeasurementCache())
    let resolved = stack(
      "root",
      axis: .vertical,
      children: [
        leaf("a", size: .init(width: 10, height: 2)),
        stack(
          "inner",
          axis: .horizontal,
          children: [
            leaf("b", size: .init(width: 4, height: 1)),
            leaf("c", size: .init(width: 6, height: 3)),
          ]
        ),
      ]
    )
    let proposal = ProposedSize(width: 40, height: 12)
    let passContext = LayoutPassContext()
    let measured = engine.measure(resolved, proposal: proposal, passContext: passContext)
    let placed = engine.place(resolved, measured: measured, passContext: passContext)

    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: resolved,
      proposal: proposal,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: passContext.scrollViewportContext,
      customLayoutCompatibilityDepthLimit: passContext.customLayoutCompatibilityDepthLimit
    )

    #expect(!summary.hasDivergence)
    #expect(summary.measureDivergenceCount == 0)
    #expect(summary.placeDivergenceCount == 0)
    #expect(summary.windowedExclusionCount == 0)
    #expect(summary.firstDivergenceDetail == nil)
  }

  @Test("an injected measured-size divergence is caught (red proof)")
  func injectedMeasureDivergenceIsCaught() {
    let engine = LayoutEngine()
    let resolved = stack(
      "root",
      axis: .vertical,
      children: [leaf("a", size: .init(width: 10, height: 2))]
    )
    let proposal = ProposedSize(width: 40, height: 12)
    let measured = engine.measure(resolved, proposal: proposal, passContext: nil)
    let placed = engine.place(resolved, measured: measured, passContext: nil)

    // Doctor the production measured tree the way a false-equal reuse would:
    // same structure, wrong geometry served as current.
    var doctored = measured
    doctored.childMeasurements[0].measuredSize.height += 1

    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: resolved,
      proposal: proposal,
      productionMeasured: doctored,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit
    )

    #expect(summary.hasDivergence)
    #expect(summary.measureDivergenceCount == 1)
    #expect(summary.firstDivergenceDetail?.contains("measure shadow divergence") == true)
  }

  @Test("an injected placed-bounds divergence is caught (red proof)")
  func injectedPlaceDivergenceIsCaught() {
    let engine = LayoutEngine()
    let resolved = stack(
      "root",
      axis: .vertical,
      children: [
        leaf("a", size: .init(width: 10, height: 2)),
        leaf("b", size: .init(width: 10, height: 2)),
      ]
    )
    let proposal = ProposedSize(width: 40, height: 12)
    let measured = engine.measure(resolved, proposal: proposal, passContext: nil)
    let placed = engine.place(resolved, measured: measured, passContext: nil)

    // A stale retained placement: the second child sits one row off from
    // where a fresh placement puts it.
    var doctored = placed
    doctored.children[1].bounds.origin.y += 1

    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: resolved,
      proposal: proposal,
      productionMeasured: measured,
      productionPlaced: doctored,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit
    )

    #expect(summary.hasDivergence)
    #expect(summary.measureDivergenceCount == 0)
    #expect(summary.placeDivergenceCount == 1)
    #expect(summary.firstDivergenceDetail?.contains("place shadow divergence") == true)
  }

  @Test("a diverged pair counts once and is not descended into")
  func divergedPairCountsOnce() {
    let identity = testIdentity("root")
    let production = MeasuredNode(
      identity: identity,
      proposal: .unspecified,
      measuredSize: .init(width: 10, height: 4),
      childMeasurements: [
        MeasuredNode(
          identity: testIdentity("root", "a"),
          proposal: .unspecified,
          measuredSize: .init(width: 10, height: 2)
        ),
        MeasuredNode(
          identity: testIdentity("root", "b"),
          proposal: .unspecified,
          measuredSize: .init(width: 10, height: 2)
        ),
      ]
    )
    var shadow = production
    shadow.measuredSize.height = 6
    shadow.childMeasurements[0].measuredSize.height = 3
    shadow.childMeasurements[1].measuredSize.height = 3

    let placed = PlacedNode(
      identity: identity, bounds: .init(origin: .zero, size: .init(width: 10, height: 4)))
    let summary = LayoutShadowOracle.compare(
      productionMeasured: production,
      productionPlaced: placed,
      shadowMeasured: shadow,
      shadowPlaced: placed
    )

    #expect(summary.measureDivergenceCount == 1)
  }

  @Test("windowed lazy subtrees are excluded and counted, not compared")
  func windowedSubtreeIsExcluded() {
    let rootIdentity = testIdentity("root")
    let listIdentity = testIdentity("root", "list")
    func tree(rowHeight: Int, window: Range<Int>?) -> MeasuredNode {
      MeasuredNode(
        identity: rootIdentity,
        proposal: .unspecified,
        measuredSize: .init(width: 20, height: 10),
        childMeasurements: [
          MeasuredNode(
            identity: listIdentity,
            proposal: .unspecified,
            // The windowed container's own extent is stride-derived; the
            // carve-out must ignore it along with everything beneath.
            measuredSize: .init(width: 20, height: 10 * rowHeight),
            childMeasurements: [
              MeasuredNode(
                identity: testIdentity("root", "list", "row-0"),
                proposal: .unspecified,
                measuredSize: .init(width: 20, height: rowHeight)
              )
            ],
            containerAllocationSnapshot: .init(
              lazyStack: LazyStackAllocationSnapshot(
                axis: .vertical,
                measuredWindow: window,
                estimatedRowStride: rowHeight
              )
            )
          )
        ]
      )
    }
    // Production refined its stride to 2; the cold shadow probed 3. Every
    // geometry difference is beneath (or at) the windowed carrier.
    let production = tree(rowHeight: 2, window: 0..<1)
    let shadow = tree(rowHeight: 3, window: 0..<2)

    let placedProduction = PlacedNode(
      identity: rootIdentity,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 10)),
      children: [
        PlacedNode(
          identity: listIdentity,
          bounds: .init(origin: .zero, size: .init(width: 20, height: 20))
        )
      ]
    )
    var placedShadow = placedProduction
    placedShadow.children[0].bounds = .init(origin: .zero, size: .init(width: 20, height: 30))

    let summary = LayoutShadowOracle.compare(
      productionMeasured: production,
      productionPlaced: placedProduction,
      shadowMeasured: shadow,
      shadowPlaced: placedShadow
    )

    #expect(!summary.hasDivergence)
    #expect(summary.windowedExclusionCount == 1)
  }

  // The first divergence class this oracle caught on a full gate run: the
  // measurement cache's equivalence gate is structural by design
  // (`StructuralEquivalenceLockTests` — a pure `.id` change stays
  // layout-reusable and keeps its `ViewNodeID`), so a hit served a product
  // stamped with the previous runtime identities. The serve must re-stamp
  // from the current resolved tree, the placed tier's
  // `synchronizeRetainedPhaseMetadata` contract.
  @Test("a cache hit across a pure .id change serves re-stamped identities")
  func cacheHitAcrossIdentityChangeRestampsIdentities() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let first = reidentifiedTree(id: "first")
    let second = reidentifiedTree(id: "second")

    _ = engine.measure(first, proposal: .unspecified, passContext: nil)
    let served = cache.lookup(resolved: second, proposal: .unspecified)

    #expect(served != nil)
    #expect(served?.identity == second.identity)
    #expect(served?.childMeasurements.first?.identity == second.children[0].identity)
    #expect(
      served?.containerAllocationSnapshot?.childSizes.first?.identity
        == second.children[0].identity
    )
  }

  // The second instance of the same class, through the other serve tier: an
  // ancestor re-resolve reidentifies a leaf (`ID[0]` → `ID[1]`) without
  // marking anything at or under the served node, so `retainedMeasurement`'s
  // structural equivalence walk passes and serves the previous frame's
  // stamped subtree. The retained serve must re-stamp exactly like the cache.
  @Test("a retained serve across a pure .id change serves re-stamped identities")
  func retainedServeAcrossIdentityChangeRestampsIdentities() {
    let engine = LayoutEngine()
    let first = reidentifiedTree(id: "first")
    let firstMeasured = engine.measure(first, proposal: .unspecified, passContext: nil)
    let firstPlaced = engine.place(first, measured: firstMeasured, passContext: nil)
    let previousFrame = FrameArtifacts(
      resolvedTree: first,
      measuredTree: firstMeasured,
      placedTree: firstPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: first.identity,
        bounds: .init(origin: .zero, size: firstMeasured.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let session = RetainedLayoutSession(
      previousFrameIndex: .init(frame: previousFrame),
      invalidatedIdentities: []
    )
    let second = reidentifiedTree(id: "second")
    let context = LayoutPassContext(retainedLayout: session)

    let measured = engine.measure(second, proposal: .unspecified, passContext: context)

    #expect(
      context.workMetrics.measuredNodesReused > 0,
      "the structural-reuse serve itself must still happen"
    )
    #expect(measured.childMeasurements.first?.identity == second.children[0].identity)

    let placed = engine.place(second, measured: measured, passContext: context)
    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: second,
      proposal: .unspecified,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit
    )
    #expect(!summary.hasDivergence)
  }

  @Test("the oracle stays silent when the cache serves across a pure .id change")
  func oracleSilentAcrossCacheServedIdentityChange() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let first = reidentifiedTree(id: "first")
    let second = reidentifiedTree(id: "second")

    _ = engine.measure(first, proposal: .unspecified, passContext: nil)
    let measured = engine.measure(second, proposal: .unspecified, passContext: nil)
    #expect(
      measured.childMeasurements.first?.identity == second.children[0].identity,
      "the integrated serve path must return re-stamped identities"
    )
    let placed = engine.place(second, measured: measured, passContext: nil)

    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: second,
      proposal: .unspecified,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit
    )

    #expect(!summary.hasDivergence)
  }

  @Test("summaries merge across reconciliation passes, first detail wins")
  func summariesMerge() {
    var first = LayoutShadowComparisonSummary()
    first.measureDivergenceCount = 1
    first.windowedExclusionCount = 2
    first.firstDivergenceDetail = "first"
    var second = LayoutShadowComparisonSummary()
    second.measureDivergenceCount = 1
    second.placeDivergenceCount = 3
    second.windowedExclusionCount = 1
    second.firstDivergenceDetail = "second"

    first.merge(second)

    #expect(first.measureDivergenceCount == 2)
    #expect(first.placeDivergenceCount == 3)
    #expect(first.windowedExclusionCount == 3)
    #expect(first.firstDivergenceDetail == "first")
  }
}

/// The graph keeps a node's structural path and `ViewNodeID` across a pure
/// `.id` change (the Stage-2 structural-reuse win); only the runtime identity
/// moves. Mirror exactly that shape.
private func reidentifiedTree(id: String) -> ResolvedNode {
  let child = ResolvedNode(
    viewNodeID: ViewNodeID(rawValue: 42),
    identity: testIdentity("Root", "ID[\(id)]"),
    structuralPath: StructuralPath(components: [
      .init(rawValue: "Root"), .init(rawValue: "Leaf"),
    ]),
    kind: .view("Test"),
    intrinsicSize: .init(width: 8, height: 2)
  )
  return ResolvedNode(
    viewNodeID: ViewNodeID(rawValue: 41),
    identity: testIdentity("Root"),
    structuralPath: StructuralPath(components: [.init(rawValue: "Root")]),
    kind: .view("VStack"),
    children: [child],
    layoutBehavior: .stack(
      axis: .vertical,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )
  )
}

private func leaf(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Test"),
    intrinsicSize: size
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

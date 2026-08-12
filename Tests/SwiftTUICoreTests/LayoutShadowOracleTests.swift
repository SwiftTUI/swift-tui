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

  // The 2026-08-11 mrkdwn `ScrollContent` false-alarm class: a lazy
  // container measured inside a custom scroll layout's subview walk keeps
  // never-placed children (`lazyChildScrollEstimates`), so its estimated
  // extent — and every wrapper bounds derived from it — is a cross-frame
  // refinement the cold shadow legitimately re-estimates. No `measuredWindow`
  // node is visible to the measured walk on this path.
  @Test("an estimated lazy extent difference is tolerated, realized rows still compared")
  func estimatedLazyExtentIsTolerated() {
    let rootIdentity = testIdentity("scroll-content")
    let listIdentity = testIdentity("scroll-content", "list")
    let measured = MeasuredNode(
      identity: rootIdentity,
      proposal: .unspecified,
      measuredSize: .init(width: 20, height: 4)
    )

    func placedTree(extent: Int) -> PlacedNode {
      var list = PlacedNode(
        identity: listIdentity,
        bounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 20, height: extent)),
        children: [
          PlacedNode(
            identity: testIdentity("scroll-content", "list", "row-0"),
            bounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 20, height: 2))
          )
        ]
      )
      list.lazyChildScrollEstimates = [
        LazyChildScrollEstimate(
          identity: testIdentity("scroll-content", "list", "row-9"),
          rect: .init(origin: .init(x: 0, y: extent - 2), size: .init(width: 20, height: 2))
        )
      ]
      return PlacedNode(
        identity: rootIdentity,
        bounds: .init(origin: .zero, size: .init(width: 20, height: extent)),
        children: [list]
      )
    }

    // Production refined the total extent to 50; the cold shadow estimates
    // 49. The wrapper's bounds absorbed the estimate, so its subtree is
    // skipped whole and counted, exactly like the measured-walk carve-out.
    let summary = LayoutShadowOracle.compare(
      productionMeasured: measured,
      productionPlaced: placedTree(extent: 50),
      shadowMeasured: measured,
      shadowPlaced: placedTree(extent: 49)
    )

    #expect(!summary.hasDivergence)
    #expect(summary.windowedExclusionCount == 1)

    // Control: the same extent difference WITHOUT estimates anywhere is a
    // real divergence.
    var bareProduction = placedTree(extent: 50)
    bareProduction.children[0].lazyChildScrollEstimates = nil
    var bareShadow = placedTree(extent: 49)
    bareShadow.children[0].lazyChildScrollEstimates = nil
    let bare = LayoutShadowOracle.compare(
      productionMeasured: measured,
      productionPlaced: bareProduction,
      shadowMeasured: measured,
      shadowPlaced: bareShadow
    )
    #expect(bare.placeDivergenceCount == 1)
  }

  @Test("an estimate-carrying lazy container is skipped whole even when extents agree")
  func estimateCarryingContainerIsSkippedWhole() {
    let rootIdentity = testIdentity("scroll-content")
    let listIdentity = testIdentity("scroll-content", "list")
    let measured = MeasuredNode(
      identity: rootIdentity,
      proposal: .unspecified,
      measuredSize: .init(width: 20, height: 4)
    )

    func placedTree(rowY: Int) -> PlacedNode {
      var list = PlacedNode(
        identity: listIdentity,
        bounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 20, height: 50)),
        children: [
          PlacedNode(
            identity: testIdentity("scroll-content", "list", "row-0"),
            bounds: .init(origin: .init(x: 0, y: rowY), size: .init(width: 20, height: 2))
          )
        ]
      )
      list.lazyChildScrollEstimates = [
        LazyChildScrollEstimate(
          identity: testIdentity("scroll-content", "list", "row-9"),
          rect: .init(origin: .init(x: 0, y: 48), size: .init(width: 20, height: 2))
        )
      ]
      return PlacedNode(
        identity: rootIdentity,
        bounds: .init(origin: .zero, size: .init(width: 20, height: 50)),
        children: [list]
      )
    }

    // Identical totals, but the realized row's offset embeds the estimated
    // heights of unrealized siblings — refined-exact in production, uniform
    // stride in the cold shadow. The container subtree is the estimate's
    // blast radius and is excluded whole (the D12 grain), counted so the
    // blind spot stays measured.
    let summary = LayoutShadowOracle.compare(
      productionMeasured: measured,
      productionPlaced: placedTree(rowY: 1),
      shadowMeasured: measured,
      shadowPlaced: placedTree(rowY: 0)
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

  @Test("a shadow that hits the depth budget is excluded whole, not diverged")
  func shadowDepthTruncationIsExcluded() {
    // The asymmetry class behind the 2026-08-11 mrkdwn examples-gate fatal:
    // production's serve tiers skip interior custom-layout descents, so a
    // depth-3 tree measures fine when served retained under a budget of 2 —
    // while the all-fresh shadow descends every level, hits the budget, and
    // truncates the innermost container to zero. Comparing would report
    // spurious divergences on geometry production legitimately computed.
    let tree = nestedCustomTree("depth-probe", customDepth: 3)
    let proposal = ProposedSize(width: 20, height: 10)

    // The previous frame measured under a generous budget (4), so its
    // products carry the real innermost geometry.
    let engine = LayoutEngine()
    let fullContext = LayoutPassContext(customLayoutCompatibilityDepthLimit: 4)
    let fullMeasured = engine.measure(tree, proposal: proposal, passContext: fullContext)
    let fullPlaced = engine.place(
      tree,
      measured: fullMeasured,
      in: .init(origin: .zero, size: fullMeasured.measuredSize),
      passContext: fullContext
    )
    #expect(fullContext.runtimeIssues.isEmpty)
    #expect(fullMeasured.measuredSize == CellSize(width: 8, height: 2))

    let previousFrame = FrameArtifacts(
      resolvedTree: tree,
      measuredTree: fullMeasured,
      placedTree: fullPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: tree.identity,
        bounds: .init(origin: .zero, size: fullMeasured.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    let session = RetainedLayoutSession(
      previousFrameIndex: .init(frame: previousFrame),
      invalidatedIdentities: []
    )

    // Production under the tight budget: the retained serve answers at the
    // root, so no custom boundary is ever entered — depth stays zero and
    // the real geometry rides through.
    let productionContext = LayoutPassContext(
      retainedLayout: session,
      customLayoutCompatibilityDepthLimit: 2
    )
    let productionMeasured = engine.measure(
      tree, proposal: proposal, passContext: productionContext)
    let productionPlaced = engine.place(
      tree,
      measured: productionMeasured,
      in: .init(origin: .zero, size: productionMeasured.measuredSize),
      passContext: productionContext
    )
    #expect(productionContext.runtimeIssues.isEmpty)
    #expect(productionMeasured.measuredSize == CellSize(width: 8, height: 2))

    // Pin the asymmetry mechanism itself: an all-fresh pass under the same
    // budget truncates and records the depth issue.
    let freshEngine = LayoutEngine(cache: nil)
    let freshContext = LayoutPassContext(customLayoutCompatibilityDepthLimit: 2)
    let freshMeasured = freshEngine.measure(tree, proposal: proposal, passContext: freshContext)
    #expect(
      freshContext.runtimeIssues.contains { issue in
        issue.code == "layout.customLayoutDepthLimitExceeded"
      }
    )
    #expect(freshMeasured.measuredSize != productionMeasured.measuredSize)

    // The oracle must therefore exclude the frame whole and count it,
    // instead of reporting the truncation as a divergence.
    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: tree,
      proposal: proposal,
      productionMeasured: productionMeasured,
      productionPlaced: productionPlaced,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit: 2
    )

    #expect(!summary.hasDivergence)
    #expect(summary.depthExclusionCount == 1)
    #expect(summary.measureDivergenceCount == 0)
    #expect(summary.placeDivergenceCount == 0)
  }

  @Test("a shadow within the depth budget still compares (no blanket exclusion)")
  func shadowWithinBudgetStillCompares() {
    let tree = nestedCustomTree("shallow-probe", customDepth: 2)
    let proposal = ProposedSize(width: 20, height: 10)
    let engine = LayoutEngine()
    let passContext = LayoutPassContext(customLayoutCompatibilityDepthLimit: 4)
    let measured = engine.measure(tree, proposal: proposal, passContext: passContext)
    let placed = engine.place(
      tree,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )

    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: tree,
      proposal: proposal,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit: 4
    )

    #expect(!summary.hasDivergence)
    #expect(summary.depthExclusionCount == 0)
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

/// A chain of `customDepth` nested custom layouts over one leaf, each
/// measuring and placing its single child through native engine re-entry —
/// the shape that consumes one unit of the compatibility depth budget per
/// level. Reuse signatures are constant so retained serves stay eligible.
private func nestedCustomTree(
  _ name: String,
  customDepth: Int
) -> ResolvedNode {
  var node = leaf("\(name)-leaf", size: .init(width: 8, height: 2))
  for level in (0..<customDepth).reversed() {
    node = customContainer("\(name)-c\(level)", child: node)
  }
  return node
}

private func customContainer(
  _ name: String,
  child: ResolvedNode
) -> ResolvedNode {
  let snapshot = WorkerCustomLayoutSnapshot(
    debugName: "ShadowDepthProbeLayout",
    measureContainer: { engine, node, proposal, passContext in
      guard let child = node.children.first else {
        return .zero
      }
      return engine.measure(child, proposal: proposal, passContext: passContext).measuredSize
    },
    placeSubviews: { engine, node, measured, bounds, passContext in
      guard let child = node.children.first else {
        return []
      }
      let childMeasured = engine.measure(
        child, proposal: measured.proposal, passContext: passContext)
      return [
        engine.place(child, measured: childMeasured, in: bounds, passContext: passContext)
      ]
    }
  )
  return ResolvedNode(
    identity: testIdentity(name),
    kind: .view("ShadowDepthProbe"),
    children: [child],
    layoutBehavior: .custom(
      CustomLayoutHandle(
        ShadowDepthProbeMainProxy(),
        measurementReuseSignature: "ShadowDepthProbeLayout",
        placementReuseSignature: "ShadowDepthProbeLayout",
        workerProxy: snapshot
      )
    )
  )
}

/// The handle requires a main-actor proxy even when the worker proxy answers
/// everything; this one is never consulted.
private final class ShadowDepthProbeMainProxy: CustomLayoutProxy {
  var debugName: String {
    "ShadowDepthProbeLayout"
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

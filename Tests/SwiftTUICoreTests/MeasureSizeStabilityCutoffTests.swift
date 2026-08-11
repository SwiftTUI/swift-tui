import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Owning tests for the size-stability cutoff's dark certificate pre-pass
/// (plan 2026-08-11-002 Stage 1): eligibility denials count by reason, a
/// size-stable dirty subtree certifies against its retained and cache-variant
/// baselines, and the read-only cache accessor disturbs nothing.
@Suite
struct MeasureSizeStabilityCutoffTests {
  private let proposal = ProposedSize(width: 20, height: 5)

  private func leafB(size: CellSize) -> ResolvedNode {
    ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: testIdentity("Root", "Inner", "B"),
      kind: .view("Test"),
      intrinsicSize: size
    )
  }

  private func tree(leafBSize: CellSize) -> ResolvedNode {
    ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: testIdentity("Root"),
      kind: .view("VStack"),
      children: [
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 4),
          identity: testIdentity("Root", "A"),
          kind: .view("Test"),
          intrinsicSize: .init(width: 5, height: 1)
        ),
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 2),
          identity: testIdentity("Root", "Inner"),
          kind: .view("VStack"),
          children: [leafB(size: leafBSize)],
          layoutBehavior: .stack(
            axis: .vertical,
            spacing: 0,
            horizontalAlignment: .leading,
            verticalAlignment: .top
          )
        ),
      ],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
  }

  private func session(
    for engine: LayoutEngine,
    previousTree: ResolvedNode,
    invalidated: Set<Identity>
  ) -> RetainedLayoutSession {
    let context = LayoutPassContext()
    let measured = engine.measure(previousTree, proposal: proposal, passContext: context)
    let placed = engine.place(previousTree, measured: measured, passContext: context)
    let artifacts = FrameArtifacts(
      resolvedTree: previousTree,
      measuredTree: measured,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: previousTree.identity,
        bounds: .init(origin: .zero, size: measured.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )
    return RetainedLayoutSession(
      previousFrameIndex: .init(frame: artifacts),
      invalidatedIdentities: invalidated
    )
  }

  @Test("a size-stable dirty leaf certifies against retained and cache baselines")
  func sizeStableDirtyLeafCertifies() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let current = tree(leafBSize: .init(width: 4, height: 1))
    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: current,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesAttempted == 1)
    #expect(result.metrics.certificatesCertified == 1)
    let certificate = try #require(result.certificates.first)
    #expect(certificate.rootIdentity == bIdentity)
    #expect(
      certificate.freshMeasuredAtRetainedProposal.measuredSize
        == retained.measuredNode(for: bIdentity)?.measuredSize
    )
    #expect(certificate.retainedProposal == retained.measuredNode(for: bIdentity)?.proposal)
  }

  @Test("a dirty leaf whose fresh size drifts is denied as size-mismatch")
  func driftedSizeDeniesAsSizeMismatch() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let current = tree(leafBSize: .init(width: 6, height: 2))
    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: current,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesAttempted == 1)
    #expect(result.metrics.certificatesCertified == 0)
    #expect(result.metrics.deniedSizeMismatch == 1)
    #expect(result.certificates.isEmpty)
  }

  @Test("a stack parent with no cached ideal-round baseline denies as no-baseline")
  func missingIdealRoundBaselineDenies() throws {
    // No measurement cache: the only baseline is the retained final
    // measurement, so the parent stack's reconstructed ideal-round proposal
    // is absent from the baseline set (D1's hard requirement).
    let engine = LayoutEngine()
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: tree(leafBSize: .init(width: 4, height: 1)),
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.deniedNoBaseline == 1)
    #expect(result.metrics.certificatesCertified == 0)
  }

  @Test("an animation-targeted dirty root is denied as animated")
  func animatedRootDenies() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: tree(leafBSize: .init(width: 4, height: 1)),
        passContext: context,
        animationExcludedIdentities: [bIdentity]
      )
    )

    #expect(result.metrics.deniedIneligibleAnimated == 1)
    #expect(result.metrics.certificatesCertified == 0)
  }

  @Test("a lazy container on the spine denies as ineligible-spine")
  func lazySpineDenies() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Lazy", "B")
    func lazyTree() -> ResolvedNode {
      ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 11),
        identity: testIdentity("Root"),
        kind: .view("VStack"),
        children: [
          ResolvedNode(
            viewNodeID: ViewNodeID(rawValue: 12),
            identity: testIdentity("Root", "Lazy"),
            kind: .view("LazyVStack"),
            children: [
              ResolvedNode(
                viewNodeID: ViewNodeID(rawValue: 13),
                identity: bIdentity,
                kind: .view("Test"),
                intrinsicSize: .init(width: 4, height: 1)
              )
            ],
            layoutBehavior: .lazyStack(
              axis: .vertical,
              spacing: 0,
              horizontalAlignment: .leading,
              verticalAlignment: .top
            )
          )
        ],
        layoutBehavior: .stack(
          axis: .vertical,
          spacing: 0,
          horizontalAlignment: .leading,
          verticalAlignment: .top
        )
      )
    }
    let retained = session(for: engine, previousTree: lazyTree(), invalidated: [bIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: lazyTree(),
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.deniedIneligibleSpine == 1)
    #expect(result.metrics.certificatesCertified == 0)
  }

  @Test("a dirty tree root aborts the pre-pass by cap")
  func dirtyTreeRootAbortsByCap() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let rootIdentity = testIdentity("Root")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [rootIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [rootIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: tree(leafBSize: .init(width: 4, height: 1)),
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesAttempted == 1)
    #expect(result.metrics.deniedAbortedByCap == 1)
  }

  private func fixedFrameTree(innerLeafWidth: Int) -> ResolvedNode {
    // Enough clean siblings that the certified frame subtree (2 nodes) stays
    // under the 25% subtree-share cap.
    let fillers = (0..<6).map { index in
      ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: UInt64(40 + index)),
        identity: testIdentity("Root", "Filler\(index)"),
        kind: .view("Test"),
        intrinsicSize: .init(width: 5, height: 1)
      )
    }
    return ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 31),
      identity: testIdentity("Root"),
      kind: .view("VStack"),
      children: fillers + [
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 33),
          identity: testIdentity("Root", "F"),
          kind: .view("Frame"),
          children: [
            ResolvedNode(
              viewNodeID: ViewNodeID(rawValue: 34),
              identity: testIdentity("Root", "F", "B"),
              kind: .view("Test"),
              intrinsicSize: .init(width: innerLeafWidth, height: 1)
            )
          ],
          layoutBehavior: .frame(width: 6, height: 1, alignment: .center)
        )
      ],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
  }

  @Test("a constant-family certificate serves the spine through a patched session")
  func constantFamilyCertificateServesSpine() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let frameIdentity = testIdentity("Root", "F")
    let previous = fixedFrameTree(innerLeafWidth: 4)
    let retained = session(for: engine, previousTree: previous, invalidated: [frameIdentity])

    // The frame's fixed extent pins its parent-visible size; the certified
    // win is exactly this shape — same size, different internal layout.
    let current = fixedFrameTree(innerLeafWidth: 3)
    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [frameIdentity]
    )
    let prePass = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: current,
        passContext: context,
        animationExcludedIdentities: []
      )
    )
    #expect(prePass.metrics.certificatesCertified == 1)
    let servable = prePass.certificates.filter(\.qualifiesForConstantFamilyServe)
    #expect(servable.count == 1)

    let patched = try #require(retained.patchingCertifiedSubtrees(servable))
    context.installPatchedMeasureSession(patched)

    let measured = engine.measure(current, proposal: proposal, passContext: context)

    // The spine served wholesale: the tree root's retained serve covers the
    // whole product, and the served tree carries the FRESH subtree.
    #expect(context.workMetrics.measuredNodesReused >= measured.subtreeNodeCount)
    let servedFrame = try #require(
      measured.childMeasurements.first(where: { $0.identity == frameIdentity })
    )
    #expect(servedFrame.measuredSize == .init(width: 6, height: 1))
    #expect(servedFrame.childMeasurements.first?.measuredSize == .init(width: 3, height: 1))

    // Placement keeps the ORIGINAL session (D5): fresh spine placement using
    // the served measured tree, fresh content in the certified subtree.
    let placed = engine.place(current, measured: measured, passContext: context)
    let placedFrame = try #require(
      placed.children.first(where: { $0.identity == frameIdentity })
    )
    #expect(placedFrame.bounds.size == .init(width: 6, height: 1))
    #expect(placedFrame.children.first?.bounds.size == .init(width: 3, height: 1))

    // The Stage 0 oracle polices the serve: a certified frame must compare
    // silent against an all-reuse-disabled fresh pass.
    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: current,
      proposal: proposal,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit,
      measurementSeedSession: retained
    )
    #expect(!summary.hasDivergence)
  }

  @Test("a non-constant certified root stays dark in Stage 2")
  func nonConstantCertifiedRootStaysDark() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let prePass = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: tree(leafBSize: .init(width: 4, height: 1)),
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(prePass.metrics.certificatesCertified == 1)
    #expect(prePass.certificates.filter(\.qualifiesForConstantFamilyServe).isEmpty)
  }

  @Test("the pre-pass never touches the main context's viewport hints")
  func prePassLeavesMainContextHintsUnclaimed() throws {
    let engine = LayoutEngine(cache: MeasurementCache())
    let bIdentity = testIdentity("Root", "Inner", "B")
    let previous = tree(leafBSize: .init(width: 4, height: 1))
    let retained = session(for: engine, previousTree: previous, invalidated: [bIdentity])

    let context = LayoutPassContext(
      retainedLayout: retained,
      invalidatedIdentities: [bIdentity]
    )
    let hint = MeasureViewportHint(
      axes: [.vertical],
      contentOffset: .zero,
      viewportSize: .init(width: 10, height: 4)
    )
    context.pushMeasureViewportHint(hint)
    defer { context.popMeasureViewportHint() }

    _ = engine.preMeasureCutoffPrePass(
      resolved: tree(leafBSize: .init(width: 4, height: 1)),
      passContext: context,
      animationExcludedIdentities: []
    )

    // The hint must still be present and unclaimed for the main pass.
    #expect(context.currentMeasureViewportHint == hint)
    #expect(context.claimCurrentMeasureViewportHint(for: bIdentity) == hint)
  }

  @Test("storedBaselineSizes reads variants without evicting or touching metrics")
  func storedBaselineSizesIsReadOnly() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let leaf = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 21),
      identity: testIdentity("Baseline"),
      kind: .view("Test"),
      intrinsicSize: .init(width: 9, height: 3)
    )
    _ = engine.measure(leaf, proposal: .unspecified, passContext: nil)
    _ = engine.measure(leaf, proposal: .init(width: 6, height: 2), passContext: nil)
    let lookupsBefore = cache.metrics.lookups

    let baselines = cache.storedBaselineSizes(for: ViewNodeID(rawValue: 21))

    #expect(baselines.count == 2)
    #expect(cache.metrics.lookups == lookupsBefore)
    #expect(cache.metrics.invalidations == 0)
    #expect(
      baselines.contains {
        $0.proposal == .unspecified && $0.measuredSize == .init(width: 9, height: 3)
      }
    )
  }
}

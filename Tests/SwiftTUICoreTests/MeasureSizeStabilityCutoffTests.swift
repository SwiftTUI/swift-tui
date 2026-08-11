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

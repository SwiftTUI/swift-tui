import SwiftTUICore
import Testing

@testable import SwiftTUIViews

/// Owning tests for the issued-proposal records (plan 2026-08-11-006
/// Stage 0): per-child, deduplicated, capped observations of the proposals
/// a container issued during one measure, assembled at finish sites plus
/// the author-probe recording seam — and the dark coverage counters the
/// cutoff computes for spine-denied roots.
@MainActor
@Suite("Issued-proposal records (plan 2026-08-11-006 Stage 0)")
struct IssuedProposalRecordTests {
  private static let proposal = ProposedSize(width: 40, height: 24)

  @Test("a finite/finite stack records ideal plus offer per child")
  func stackRecordsIdealAndOffer() throws {
    let engine = LayoutEngine()
    let resolved = stack(
      "record-stack",
      axis: .vertical,
      children: [
        leaf("a", size: .init(width: 10, height: 2)),
        leaf("b", size: .init(width: 8, height: 3)),
      ]
    )
    let measured = engine.measure(resolved, proposal: Self.proposal, passContext: nil)
    let records = try #require(measured.containerAllocationSnapshot?.childIssuedProposals)

    #expect(records.count == 2)
    let ideal = ProposedSize(width: .finite(40), height: .unspecified)
    for (record, child) in zip(records, measured.childMeasurements) {
      #expect(record.identity == child.identity)
      #expect(record.proposals.count == 2)
      #expect(record.proposals.contains(ideal))
      #expect(record.proposals.contains(child.proposal))
      #expect(!record.overflowed)
    }
  }

  @Test("cross reconciliation adds the re-measure proposal for replaced children")
  func reconciliationRecordsThirdProposal() throws {
    // Width unspecified: the flexible child is re-measured at the max cross
    // after allocation, so its record carries ideal + offer + reconciliation.
    let resolved = stack(
      "record-recon",
      axis: .vertical,
      children: [
        leaf("wide", size: .init(width: 10, height: 1)),
        flexibleWidthChild("flex", size: .init(width: 4, height: 1)),
      ]
    )
    let engine = LayoutEngine()
    let measured = engine.measure(
      resolved,
      proposal: ProposedSize(width: .unspecified, height: .finite(24)),
      passContext: nil
    )
    let records = try #require(measured.containerAllocationSnapshot?.childIssuedProposals)

    #expect(records[0].proposals.count == 2)
    #expect(records[1].proposals.count == 3)
  }

  @Test("ViewThatFits records the fit probe for the probed prefix only")
  func viewThatFitsRecordsProbePrefix() throws {
    let resolved = ResolvedNode(
      identity: testIdentity("record-vtf"),
      kind: .view("ViewThatFits"),
      children: [
        leaf("tall", size: .init(width: 10, height: 30)),
        leaf("medium", size: .init(width: 10, height: 20)),
        leaf("short", size: .init(width: 10, height: 5)),
      ],
      layoutBehavior: .viewThatFits(AxisSet.vertical)
    )
    let engine = LayoutEngine()
    let measured = engine.measure(resolved, proposal: Self.proposal, passContext: nil)
    let records = try #require(measured.containerAllocationSnapshot?.childIssuedProposals)

    // Child 1 is selected, so children 0 and 1 were probed at the relaxed
    // proposal; child 2 answered only the real one.
    #expect(records[0].proposals.count == 2)
    #expect(records[1].proposals.count == 2)
    #expect(records[2].proposals == [Self.proposal])
  }

  @Test("a custom layout's author probes join its pre-measure record")
  func customProbesJoinRecord() throws {
    let resolved = customNode(
      "record-custom",
      layout: FixedProbeLayout(probeProposals: [
        .init(width: .unspecified, height: .unspecified)
      ]),
      childCount: 2
    )
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let measured = engine.measure(resolved, proposal: Self.proposal, passContext: passContext)
    let records = try #require(measured.containerAllocationSnapshot?.childIssuedProposals)

    for record in records {
      #expect(record.proposals.count == 2)
      #expect(record.proposals.contains(Self.proposal))
      #expect(
        record.proposals.contains(.init(width: .unspecified, height: .unspecified))
      )
      #expect(!record.overflowed)
    }
  }

  @Test("more than eight distinct proposals overflow the record loudly")
  func overflowingProbesMarkTheRecord() throws {
    let probes = (1...9).map { width in
      ProposedSize(width: .finite(width), height: .finite(5))
    }
    let resolved = customNode(
      "record-overflow",
      layout: FixedProbeLayout(probeProposals: probes),
      childCount: 1
    )
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let measured = engine.measure(resolved, proposal: Self.proposal, passContext: passContext)
    let record = try #require(
      measured.containerAllocationSnapshot?.childIssuedProposals?.first
    )

    #expect(record.overflowed)
    #expect(record.proposals.count == ChildIssuedProposalRecord.maximumProposals)
  }

  @Test("a covered custom-spine root certifies and serves (Stage 1)")
  func coveredCustomSpineCertifiesAndServes() throws {
    let (resolved, leafIdentity) = customSpineTree("live-covered")
    // With a measurement cache, the leaf's ideal-round variant is a stored
    // baseline, so the recorded proposals are fully covered.
    let engine = LayoutEngine(cache: MeasurementCache())
    let session = retainedSession(
      for: engine, tree: resolved, invalidated: [leafIdentity])

    let context = LayoutPassContext(
      retainedLayout: session,
      invalidatedIdentities: [leafIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: resolved,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.deniedIneligibleSpine == 0)
    #expect(result.metrics.certificatesCertified == 1)
    #expect(result.metrics.deniedProposalCoverage == 0)

    // The serve rides the same patched-session path as every certificate,
    // and the shadow oracle stays the stage authority over the served
    // frame.
    let patched = try #require(session.patchingCertifiedSubtrees(result.certificates))
    context.installPatchedMeasureSession(patched)
    let measured = engine.measure(resolved, proposal: Self.proposal, passContext: context)
    #expect(context.workMetrics.measuredNodesReused >= measured.subtreeNodeCount)

    let placed = engine.place(resolved, measured: measured, passContext: context)
    let summary = LayoutShadowOracle.comparisonSummary(
      resolved: resolved,
      proposal: Self.proposal,
      productionMeasured: measured,
      productionPlaced: placed,
      scrollViewportContext: nil,
      customLayoutCompatibilityDepthLimit:
        LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit,
      measurementSeedSession: session
    )
    #expect(!summary.hasDivergence)
  }

  @Test("an uncovered recorded proposal denies as proposal-coverage (Stage 1)")
  func uncoveredProposalDeniesCoverage() throws {
    let (resolved, leafIdentity) = customSpineTree("live-uncovered")
    // No measurement cache: the only baseline is the retained final
    // proposal, so the ideal-round entry in the record is uncovered.
    let engine = LayoutEngine(cache: nil)
    let session = retainedSession(
      for: engine, tree: resolved, invalidated: [leafIdentity])

    let context = LayoutPassContext(
      retainedLayout: session,
      invalidatedIdentities: [leafIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: resolved,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesCertified == 0)
    #expect(result.metrics.deniedProposalCoverage == 1)
  }

  @Test("an overflowed parent record denies as record-overflow (Stage 1)")
  func overflowedRecordDeniesCoverage() throws {
    // The overflow-probing custom layout IS the immediate parent of the
    // dirty leaf, so its overflowed record gates the coverage certificate.
    let leafIdentity = testIdentity("live-overflow", "Inner", "Probe", "Leaf")
    let probes = (1...9).map { width in
      ProposedSize(width: .finite(width), height: .finite(5))
    }
    let custom = ResolvedNode(
      viewNodeID: fixtureViewNodeID("live-overflow-probe"),
      identity: testIdentity("live-overflow", "Inner", "Probe"),
      kind: .view("FixedProbe"),
      children: [
        ResolvedNode(
          viewNodeID: fixtureViewNodeID("live-overflow-leaf"),
          identity: leafIdentity,
          kind: .view("Test"),
          intrinsicSize: .init(width: 6, height: 2)
        )
      ],
      layoutBehavior: AnyLayout(FixedProbeLayout(probeProposals: probes)).resolvedBehavior
    )
    // The extra stack level keeps the dirty leaf under the 25% subtree
    // share cap (D10), which a three-node tree would trip.
    let inner = ResolvedNode(
      viewNodeID: fixtureViewNodeID("live-overflow-inner"),
      identity: testIdentity("live-overflow", "Inner"),
      kind: .view("VStack"),
      children: [custom],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
    let resolved = ResolvedNode(
      viewNodeID: fixtureViewNodeID("live-overflow-root"),
      identity: testIdentity("live-overflow"),
      kind: .view("VStack"),
      children: [inner],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
    let engine = LayoutEngine(cache: MeasurementCache())
    let session = retainedSession(
      for: engine, tree: resolved, invalidated: [leafIdentity])

    let context = LayoutPassContext(
      retainedLayout: session,
      invalidatedIdentities: [leafIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: resolved,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesCertified == 0)
    #expect(result.metrics.deniedRecordOverflow == 1)
  }

  @Test("a depth-truncated pre-pass measure denies instead of certifying (red proof)")
  func depthTruncatedPrePassDenies() throws {
    // A fixed-extent outermost layout MASKS interior truncation: the
    // pre-pass measure that hit the depth budget still reproduces the
    // retained root size, so without the depth guard this would certify a
    // product a fresh production pass could not compute.
    func maskedChainTree(leafWidth: Int) -> ResolvedNode {
      var chainNode = ResolvedNode(
        viewNodeID: fixtureViewNodeID("depth-mask-leaf"),
        identity: testIdentity("depth-mask", "C0", "C1", "C2", "C3", "C4", "Leaf"),
        kind: .view("Test"),
        intrinsicSize: .init(width: leafWidth, height: 2)
      )
      for level in (1...4).reversed() {
        chainNode = ResolvedNode(
          viewNodeID: fixtureViewNodeID("depth-mask-c\(level)"),
          identity: Identity(components: ["depth-mask"] + (0...level).map { "C\($0)" }),
          kind: .view("PassThrough"),
          children: [chainNode],
          layoutBehavior: AnyLayout(PassThroughLayout()).resolvedBehavior
        )
      }
      let chainRoot = ResolvedNode(
        viewNodeID: fixtureViewNodeID("depth-mask-c0"),
        identity: testIdentity("depth-mask", "C0"),
        kind: .view("FixedMask"),
        children: [chainNode],
        layoutBehavior: AnyLayout(FixedSizeIgnoringChildrenLayout()).resolvedBehavior
      )
      // Sibling padding keeps the dirty chain under the 25% subtree cap.
      let siblings = (0..<20).map { index in
        leaf("depth-mask-pad\(index)", size: .init(width: 4, height: 1))
      }
      return ResolvedNode(
        viewNodeID: fixtureViewNodeID("depth-mask-root"),
        identity: testIdentity("depth-mask"),
        kind: .view("VStack"),
        children: [chainRoot] + siblings,
        layoutBehavior: .stack(
          axis: .vertical,
          spacing: 0,
          horizontalAlignment: .leading,
          verticalAlignment: .top
        )
      )
    }
    let chainRootIdentity = testIdentity("depth-mask", "C0")

    // The retained frame measured under the main-actor budget, so its
    // products carry the real (untruncated) interior. The CURRENT tree
    // changes the leaf inside the mask, so the measurement cache's
    // equivalence check evicts and the certificate must measure fresh on
    // the tight scratch budget — the descent that truncates.
    let engine = LayoutEngine(cache: MeasurementCache())
    let session = retainedSession(
      for: engine,
      tree: maskedChainTree(leafWidth: 6),
      invalidated: [chainRootIdentity],
      depthLimit: LayoutPassContext.mainActorCustomLayoutCompatibilityDepthLimit
    )
    let resolved = maskedChainTree(leafWidth: 7)

    let context = LayoutPassContext(
      retainedLayout: session,
      invalidatedIdentities: [chainRootIdentity]
    )
    let result = try #require(
      engine.preMeasureCutoffPrePass(
        resolved: resolved,
        passContext: context,
        animationExcludedIdentities: []
      )
    )

    #expect(result.metrics.certificatesCertified == 0)
    #expect(result.metrics.deniedAbortedByCap == 1)
  }

  // MARK: - Fixtures

  /// Root VStack -> custom container (non-forwarding spine) -> inner VStack
  /// -> dirty leaf. The spine walk denies at the custom container; the dark
  /// evaluation reads the INNER stack's record for the leaf.
  private func customSpineTree(_ name: String) -> (ResolvedNode, Identity) {
    // Identities are hierarchical: the cutoff's spine walk descends by
    // identity ancestry.
    let leafIdentity = testIdentity(name, "Custom", "Inner", "Leaf")
    let inner = ResolvedNode(
      viewNodeID: fixtureViewNodeID("\(name)-inner"),
      identity: testIdentity(name, "Custom", "Inner"),
      kind: .view("VStack"),
      children: [
        ResolvedNode(
          viewNodeID: fixtureViewNodeID("\(name)-leaf"),
          identity: leafIdentity,
          kind: .view("Test"),
          intrinsicSize: .init(width: 6, height: 2)
        )
      ],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
    let custom = ResolvedNode(
      viewNodeID: fixtureViewNodeID("\(name)-custom"),
      identity: testIdentity(name, "Custom"),
      kind: .view("PassThrough"),
      children: [inner],
      layoutBehavior: AnyLayout(PassThroughLayout()).resolvedBehavior
    )
    let root = ResolvedNode(
      viewNodeID: fixtureViewNodeID("\(name)-root"),
      identity: testIdentity(name),
      kind: .view("VStack"),
      children: [custom],
      layoutBehavior: .stack(
        axis: .vertical,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
    return (root, leafIdentity)
  }

  private func retainedSession(
    for engine: LayoutEngine,
    tree: ResolvedNode,
    invalidated: Set<Identity>,
    depthLimit: Int = LayoutPassContext.defaultCustomLayoutCompatibilityDepthLimit
  ) -> RetainedLayoutSession {
    let context = LayoutPassContext(customLayoutCompatibilityDepthLimit: depthLimit)
    let measured = engine.measure(tree, proposal: Self.proposal, passContext: context)
    let placed = engine.place(tree, measured: measured, passContext: context)
    let artifacts = FrameArtifacts(
      resolvedTree: tree,
      measuredTree: measured,
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: tree.identity,
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

  private func customNode(
    _ name: String,
    layout: some Layout,
    childCount: Int
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("FixedProbe"),
      children: (0..<childCount).map { index in
        leaf("\(name)-c\(index)", size: .init(width: 6, height: 2))
      },
      layoutBehavior: AnyLayout(layout).resolvedBehavior
    )
  }
}

/// Probes every subview at each configured proposal during `sizeThatFits`.
private struct FixedProbeLayout: Layout {
  var probeProposals: [ProposedSize]

  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    var height = 0
    for subview in subviews {
      for probe in probeProposals {
        _ = subview.sizeThatFits(probe)
      }
      height += 2
    }
    return .init(width: 12, height: max(1, height))
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: .init(x: bounds.origin.x, y: bounds.origin.y + index * 2),
        proposal: .init(width: .finite(6), height: .finite(2))
      )
    }
  }
}

/// Returns a fixed size while still measuring its child — the shape whose
/// fixed extent masks interior depth truncation from the size test.
private struct FixedSizeIgnoringChildrenLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    _ = subviews.first?.sizeThatFits(proposal)
    return .init(width: 10, height: 4)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(at: bounds.origin, proposal: proposal)
  }
}

/// A non-forwarding spine occupant that forwards its single child unchanged.
private struct PassThroughLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    subviews.first?.place(at: bounds.origin, proposal: proposal)
  }
}

private func fixtureViewNodeID(_ name: String) -> ViewNodeID {
  var hash: UInt64 = 14_695_981_039_346_656_037
  for byte in name.utf8 {
    hash ^= UInt64(byte)
    hash &*= 1_099_511_628_211
  }
  return ViewNodeID(rawValue: hash)
}

private func leaf(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
    identity: testIdentity(name),
    kind: .view("Test"),
    intrinsicSize: size
  )
}

private func stack(
  _ name: String,
  axis: SwiftTUICore.Axis,
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
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

private func flexibleWidthChild(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
    identity: testIdentity(name),
    kind: .view("FlexibleFrame"),
    children: [leaf("\(name)-content", size: size)],
    layoutBehavior: .flexibleFrame(
      minWidth: nil,
      idealWidth: nil,
      maxWidth: .infinity,
      minHeight: nil,
      idealHeight: nil,
      maxHeight: nil,
      alignment: .topLeading
    )
  )
}

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

  @Test("a covered spine-denied root counts dark-coverage eligible")
  func darkCoverageEligibleCounts() throws {
    let (resolved, leafIdentity) = customSpineTree("dark-eligible")
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

    #expect(result.metrics.deniedIneligibleSpine == 1)
    #expect(result.metrics.darkCoverageEligible == 1)
    #expect(result.metrics.darkCoverageDeniedProposalCoverage == 0)
  }

  @Test("an uncovered recorded proposal counts dark-coverage denied")
  func darkCoverageUncoveredCounts() throws {
    let (resolved, leafIdentity) = customSpineTree("dark-uncovered")
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

    #expect(result.metrics.deniedIneligibleSpine == 1)
    #expect(result.metrics.darkCoverageEligible == 0)
    #expect(result.metrics.darkCoverageDeniedProposalCoverage == 1)
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
    invalidated: Set<Identity>
  ) -> RetainedLayoutSession {
    let context = LayoutPassContext()
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

import Testing

@testable import SwiftTUICore

struct FrameDropDroppabilityTests {
  @Test("Retained-baseline blockers are never inserted only to be subtracted")
  func noAddThenSubtract() {
    let tailBlockers = FrameDropEligibility.frameTailCommitBlockers(
      hasWorkerCustomLayoutCacheUpdates: true
    )
    let artifacts = makeFrameDropArtifacts(dropEligibilityBlockers: tailBlockers)
    let eligibility = FrameDropEligibility.classify(
      .init(
        artifacts: artifacts,
        hasCompleteBarrierSignals: true
      ))

    #expect(!eligibility.blockers.contains(.retainedLayoutBaseline))
    #expect(!eligibility.blockers.contains(.retainedRasterBaseline))
    #expect(eligibility.blockers == [.workerCustomLayoutCacheUpdate])
  }
}

private func makeFrameDropArtifacts(
  dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
) -> FrameArtifacts {
  let identity = Identity(components: ["FrameDropDroppabilityTests", "Root"])
  let resolved = ResolvedNode(identity: identity, kind: .root)
  let measured = MeasuredNode(
    identity: identity,
    proposal: .unspecified,
    measuredSize: .zero
  )
  let placed = PlacedNode(
    identity: identity,
    bounds: .init(origin: .zero, size: .zero)
  )
  let draw = DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero))

  return FrameArtifacts(
    resolvedTree: resolved,
    measuredTree: measured,
    placedTree: placed,
    semanticSnapshot: .init(),
    drawTree: draw,
    rasterSurface: .init(),
    presentationDamage: nil,
    commitPlan: .init(),
    diagnostics: .init(drop: .init(eligibilityBlockers: dropEligibilityBlockers))
  )
}

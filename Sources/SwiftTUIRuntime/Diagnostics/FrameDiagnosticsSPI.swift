import SwiftTUICore

/// SPI snapshot of the plan-2026-08-11-004 branching-factor counters for
/// external harnesses: TermUIPerf's cold benchmark lane (plan 2026-08-11-005)
/// reads its work census off the public one-shot `RenderSnapshot`, and these
/// counters are otherwise package-internal. A mirror rather than an exposure
/// of `LayoutBranchingMetrics`: the public work surface stays frozen and the
/// package type stays free to move.
@_spi(Runners) public struct LayoutBranchingCounterSnapshot: Equatable, Sendable {
  public let builtinContainerMeasures: Int
  public let builtinChildMeasureRequests: Int
  public let builtinChildMeasureRequestsProbe: Int
  public let customContainerMeasures: Int
  public let customChildMeasureRequests: Int
  public let customChildMeasureRequestsProbe: Int
  public let customPlacementChildMeasureRequests: Int
}

extension FrameDiagnosticWork {
  @_spi(Runners) public var layoutBranchingCounters: LayoutBranchingCounterSnapshot {
    LayoutBranchingCounterSnapshot(
      builtinContainerMeasures: layoutBranching.builtinContainerMeasureComputations,
      builtinChildMeasureRequests: layoutBranching.builtinChildMeasureRequests,
      builtinChildMeasureRequestsProbe: layoutBranching.builtinChildMeasureRequestsProbe,
      customContainerMeasures: layoutBranching.customContainerMeasureComputations,
      customChildMeasureRequests: layoutBranching.customChildMeasureRequests,
      customChildMeasureRequestsProbe: layoutBranching.customChildMeasureRequestsProbe,
      customPlacementChildMeasureRequests: layoutBranching.customPlacementChildMeasureRequests
    )
  }
}

/// SPI mirror of the committed-value anchor-projection walk tallies
/// (serve-path plan 2026-08-12-003 counters), same contract as
/// ``LayoutBranchingCounterSnapshot``: the cold bench lane reads its work
/// census off the one-shot `RenderSnapshot`, and the package type stays
/// free to move.
@_spi(Runners) public struct LifetimeAnchorCounterSnapshot: Equatable, Sendable {
  public let nodesWalked: Int
  public let replaceCalls: Int
  public let replaceNoops: Int
}

extension FrameDiagnosticWork {
  @_spi(Runners) public var lifetimeAnchorCounters: LifetimeAnchorCounterSnapshot {
    LifetimeAnchorCounterSnapshot(
      nodesWalked: lifetimeAnchorTallies.nodesWalked,
      replaceCalls: lifetimeAnchorTallies.replaceCalls,
      replaceNoops: lifetimeAnchorTallies.replaceNoops
    )
  }
}

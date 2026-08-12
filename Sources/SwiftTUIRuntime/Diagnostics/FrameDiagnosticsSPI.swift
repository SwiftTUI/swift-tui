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

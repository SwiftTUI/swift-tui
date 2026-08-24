public struct MeasurementCacheMetrics: Equatable, Sendable {
  public var generation: Int
  public var entries: Int
  public var lookups: Int
  public var hits: Int
  public var misses: Int
  /// Count of lookups that found a cached entry but evicted it because the
  /// cached `ResolvedNode` was no longer equivalent for measurement.  Kept
  /// distinct from `misses` so observability can tell a cold miss apart
  /// from a structural invalidation.
  public var invalidations: Int
  public var stores: Int

  public init(
    generation: Int = 0,
    entries: Int = 0,
    lookups: Int = 0,
    hits: Int = 0,
    misses: Int = 0,
    invalidations: Int = 0,
    stores: Int = 0
  ) {
    self.generation = generation
    self.entries = entries
    self.lookups = lookups
    self.hits = hits
    self.misses = misses
    self.invalidations = invalidations
    self.stores = stores
  }
}

package struct ResolveWorkMetrics: Equatable, Sendable {
  package var resolvedNodesComputed: Int
  package var resolvedNodesReused: Int
  /// Committed-value anchor-projection walk tallies for the frame, merged
  /// from the graph's per-frame diagnostics at the end of the head's last
  /// resolve pass (serve-path plan 2026-08-12-003 counters).
  package var lifetimeAnchorNodesWalked: Int
  package var lifetimeAnchorReplaceCalls: Int
  package var lifetimeAnchorReplaceNoops: Int

  package init(
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0,
    lifetimeAnchorNodesWalked: Int = 0,
    lifetimeAnchorReplaceCalls: Int = 0,
    lifetimeAnchorReplaceNoops: Int = 0
  ) {
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
    self.lifetimeAnchorNodesWalked = lifetimeAnchorNodesWalked
    self.lifetimeAnchorReplaceCalls = lifetimeAnchorReplaceCalls
    self.lifetimeAnchorReplaceNoops = lifetimeAnchorReplaceNoops
  }
}

/// Counters for the size-stability measure cutoff's pre-pass (plan
/// 2026-08-11-002 Stage 1, dark). One certificate attempt per eligible
/// outermost dirty root; denials are counted by their first failing rule so
/// the dark run's hit-rate report attributes every miss.
package struct PreMeasureCutoffMetrics: Equatable, Sendable {
  package var certificatesAttempted = 0
  package var certificatesCertified = 0
  /// Certified roots actually lifted through a derived session this pass
  /// (Stage 2+: the provably constant family; 0 on dark-only frames).
  package var certificatesServed = 0
  package var deniedIneligibleIndexed = 0
  package var deniedIneligibleWindowed = 0
  package var deniedIneligibleSpine = 0
  package var deniedIneligibleAnimated = 0
  package var deniedNoBaseline = 0
  package var deniedSizeMismatch = 0
  package var deniedAbortedByCap = 0
  /// Coverage-certificate denials (plan 2026-08-11-006 Stage 1): a
  /// non-forwarding spine no longer denies outright — the dirty root's
  /// certified baselines must cover every proposal its retained parent
  /// recorded issuing to it. An uncovered proposal or an overflowed
  /// record denies here; a missing record denies as no-baseline.
  package var deniedProposalCoverage = 0
  package var deniedRecordOverflow = 0
  /// Window-currency denial (plan 2026-08-11-006 Stage 2): the certificate
  /// measure of a windowed subtree did not reproduce the retained
  /// `measuredWindow` and `estimatedRowStride` exactly — size equality
  /// alone is too weak where out-of-window entries are synthesized from
  /// the stride.
  package var deniedWindowMismatch = 0

  package init() {}

  package mutating func merge(_ other: Self) {
    certificatesAttempted += other.certificatesAttempted
    certificatesCertified += other.certificatesCertified
    certificatesServed += other.certificatesServed
    deniedIneligibleIndexed += other.deniedIneligibleIndexed
    deniedIneligibleWindowed += other.deniedIneligibleWindowed
    deniedIneligibleSpine += other.deniedIneligibleSpine
    deniedIneligibleAnimated += other.deniedIneligibleAnimated
    deniedNoBaseline += other.deniedNoBaseline
    deniedSizeMismatch += other.deniedSizeMismatch
    deniedAbortedByCap += other.deniedAbortedByCap
    deniedProposalCoverage += other.deniedProposalCoverage
    deniedRecordOverflow += other.deniedRecordOverflow
    deniedWindowMismatch += other.deniedWindowMismatch
  }
}

/// Branching-factor counters for the layout branching oracle (plan
/// 2026-08-11-004 Stage 0): child measure requests issued by computing
/// containers, and the container computations that issued them, split
/// built-in vs custom. A request is any child measure a computing container
/// issues (work item or native re-entry) — retained and cache serves still
/// count as requests, because they change cost, not shape. Leaf-internal
/// work (text wrapping) is in neither numerator nor denominator.
package struct LayoutBranchingMetrics: Equatable, Sendable {
  package var builtinContainerMeasureComputations = 0
  package var builtinChildMeasureRequests = 0
  package var customContainerMeasureComputations = 0
  package var customChildMeasureRequests = 0
  package var customPlacementChildMeasureRequests = 0
  /// Probe-grade slices of the request counters (plan 2026-08-11-004
  /// Stage 1); commit-grade counts are the remainders. Placement
  /// re-measures have no probe slice: placement asserts commit grade.
  package var builtinChildMeasureRequestsProbe = 0
  package var customChildMeasureRequestsProbe = 0

  package init() {}

  /// Requests over computations for built-in containers, in milli-units
  /// (`2000` = two requests per container computation). `0` when the pass
  /// computed no built-in container.
  package var builtinBranchingFactorMilli: Int {
    guard builtinContainerMeasureComputations > 0 else {
      return 0
    }
    return builtinChildMeasureRequests * 1000 / builtinContainerMeasureComputations
  }

  /// Requests over computations for custom containers, in milli-units.
  /// Measure-time requests only; placement re-measures are reported
  /// separately because placement runs once where measurement can repeat.
  package var customBranchingFactorMilli: Int {
    guard customContainerMeasureComputations > 0 else {
      return 0
    }
    return customChildMeasureRequests * 1000 / customContainerMeasureComputations
  }

  package mutating func merge(_ other: Self) {
    builtinContainerMeasureComputations += other.builtinContainerMeasureComputations
    builtinChildMeasureRequests += other.builtinChildMeasureRequests
    customContainerMeasureComputations += other.customContainerMeasureComputations
    customChildMeasureRequests += other.customChildMeasureRequests
    customPlacementChildMeasureRequests += other.customPlacementChildMeasureRequests
    builtinChildMeasureRequestsProbe += other.builtinChildMeasureRequestsProbe
    customChildMeasureRequestsProbe += other.customChildMeasureRequestsProbe
  }
}

package struct LayoutWorkMetrics: Equatable, Sendable {
  package var measuredNodesComputed: Int
  package var measuredNodesReused: Int
  package var placedNodesComputed: Int
  package var placedNodesReused: Int
  package var placedFrameTableEntriesReused: Int
  package var measurementWorkStackSteps: Int
  package var placementWorkStackSteps: Int
  package var layoutDependentRealizations: Int
  package var layoutDependentRealizationCacheHits: Int
  package var layoutDependentMainActorFallbacks: Int
  package var preMeasureCutoff: PreMeasureCutoffMetrics
  package var branching: LayoutBranchingMetrics
  package var geometryResolutionDiagnostics: GeometryResolutionDiagnostics

  package init(
    measuredNodesComputed: Int = 0,
    measuredNodesReused: Int = 0,
    placedNodesComputed: Int = 0,
    placedNodesReused: Int = 0,
    placedFrameTableEntriesReused: Int = 0,
    measurementWorkStackSteps: Int = 0,
    placementWorkStackSteps: Int = 0,
    layoutDependentRealizations: Int = 0,
    layoutDependentRealizationCacheHits: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    preMeasureCutoff: PreMeasureCutoffMetrics = .init(),
    branching: LayoutBranchingMetrics = .init(),
    geometryResolutionDiagnostics: GeometryResolutionDiagnostics = .init()
  ) {
    self.measuredNodesComputed = measuredNodesComputed
    self.measuredNodesReused = measuredNodesReused
    self.placedNodesComputed = placedNodesComputed
    self.placedNodesReused = placedNodesReused
    self.placedFrameTableEntriesReused = placedFrameTableEntriesReused
    self.measurementWorkStackSteps = measurementWorkStackSteps
    self.placementWorkStackSteps = placementWorkStackSteps
    self.layoutDependentRealizations = layoutDependentRealizations
    self.layoutDependentRealizationCacheHits = layoutDependentRealizationCacheHits
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.preMeasureCutoff = preMeasureCutoff
    self.branching = branching
    self.geometryResolutionDiagnostics = geometryResolutionDiagnostics
  }

  package mutating func merge(_ other: Self) {
    measuredNodesComputed += other.measuredNodesComputed
    measuredNodesReused += other.measuredNodesReused
    placedNodesComputed += other.placedNodesComputed
    placedNodesReused += other.placedNodesReused
    placedFrameTableEntriesReused += other.placedFrameTableEntriesReused
    measurementWorkStackSteps += other.measurementWorkStackSteps
    placementWorkStackSteps += other.placementWorkStackSteps
    layoutDependentRealizations += other.layoutDependentRealizations
    layoutDependentRealizationCacheHits += other.layoutDependentRealizationCacheHits
    layoutDependentMainActorFallbacks += other.layoutDependentMainActorFallbacks
    preMeasureCutoff.merge(other.preMeasureCutoff)
    branching.merge(other.branching)
    geometryResolutionDiagnostics.merge(other.geometryResolutionDiagnostics)
  }
}

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

  package init(
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0
  ) {
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
  }
}

/// Counters for the size-stability measure cutoff's pre-pass (plan
/// 2026-08-11-002 Stage 1, dark). One certificate attempt per eligible
/// outermost dirty root; denials are counted by their first failing rule so
/// the dark run's hit-rate report attributes every miss.
package struct PreMeasureCutoffMetrics: Equatable, Sendable {
  package var certificatesAttempted = 0
  package var certificatesCertified = 0
  package var deniedIneligibleIndexed = 0
  package var deniedIneligibleWindowed = 0
  package var deniedIneligibleSpine = 0
  package var deniedIneligibleAnimated = 0
  package var deniedNoBaseline = 0
  package var deniedSizeMismatch = 0
  package var deniedAbortedByCap = 0

  package init() {}

  package mutating func merge(_ other: Self) {
    certificatesAttempted += other.certificatesAttempted
    certificatesCertified += other.certificatesCertified
    deniedIneligibleIndexed += other.deniedIneligibleIndexed
    deniedIneligibleWindowed += other.deniedIneligibleWindowed
    deniedIneligibleSpine += other.deniedIneligibleSpine
    deniedIneligibleAnimated += other.deniedIneligibleAnimated
    deniedNoBaseline += other.deniedNoBaseline
    deniedSizeMismatch += other.deniedSizeMismatch
    deniedAbortedByCap += other.deniedAbortedByCap
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
    geometryResolutionDiagnostics.merge(other.geometryResolutionDiagnostics)
  }
}

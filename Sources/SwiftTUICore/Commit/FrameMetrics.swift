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

package struct InvalidationSummary: Equatable, Sendable {
  package let directlyInvalidated: Set<Identity>
  package let identitiesWithInvalidatedDescendants: Set<Identity>

  package init(
    invalidatedIdentities: Set<Identity>
  ) {
    directlyInvalidated = invalidatedIdentities

    var identitiesWithInvalidatedDescendants: Set<Identity> = []
    for invalidatedIdentity in invalidatedIdentities {
      var ancestor = invalidatedIdentity.parent
      while let current = ancestor {
        identitiesWithInvalidatedDescendants.insert(current)
        ancestor = current.parent
      }
    }
    self.identitiesWithInvalidatedDescendants = identitiesWithInvalidatedDescendants
  }

  package var isEmpty: Bool {
    directlyInvalidated.isEmpty
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    directlyInvalidated.contains(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    identitiesWithInvalidatedDescendants.contains(identity)
  }

  package func hasInvalidatedAncestor(
    of identity: Identity
  ) -> Bool {
    var ancestor = identity.parent
    while let current = ancestor {
      if directlyInvalidated.contains(current) {
        return true
      }
      ancestor = current.parent
    }
    return false
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    isDirectlyInvalidated(identity)
      || containsInvalidatedDescendant(of: identity)
      || hasInvalidatedAncestor(of: identity)
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
    self.geometryResolutionDiagnostics = geometryResolutionDiagnostics
  }
}

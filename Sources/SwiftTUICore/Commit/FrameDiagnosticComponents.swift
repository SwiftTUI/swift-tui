// Component value types that make up `FrameDiagnostics`.
//
// `FrameDiagnostics` (in `FrameDiagnostics.swift`) aggregates one value of each
// of these structs per frame. They are split out here so the aggregate file
// stays focused on assembly and summary logic rather than field declarations.

public struct FrameDiagnosticInput: Equatable, Sendable {
  public var proposal: ProposedSize
  public var invalidatedIdentities: Set<Identity>

  public init(
    proposal: ProposedSize = .unspecified,
    invalidatedIdentities: Set<Identity> = []
  ) {
    self.proposal = proposal
    self.invalidatedIdentities = invalidatedIdentities
  }
}

public struct FrameDiagnosticCounts: Equatable, Sendable {
  public var resolvedNodes: Int
  public var measuredNodes: Int
  public var placedNodes: Int
  public var drawNodes: Int
  public var interactionRegions: Int
  public var focusRegions: Int
  public var scrollRoutes: Int
  public var selectionRoutes: Int

  public init(
    resolvedNodes: Int = 0,
    measuredNodes: Int = 0,
    placedNodes: Int = 0,
    drawNodes: Int = 0,
    interactionRegions: Int = 0,
    focusRegions: Int = 0,
    scrollRoutes: Int = 0,
    selectionRoutes: Int = 0
  ) {
    self.resolvedNodes = resolvedNodes
    self.measuredNodes = measuredNodes
    self.placedNodes = placedNodes
    self.drawNodes = drawNodes
    self.interactionRegions = interactionRegions
    self.focusRegions = focusRegions
    self.scrollRoutes = scrollRoutes
    self.selectionRoutes = selectionRoutes
  }
}

public struct FrameDiagnosticWork: Equatable, Sendable {
  public var resolvedNodesComputed: Int
  public var resolvedNodesReused: Int
  public var measuredNodesComputed: Int
  public var measuredNodesReused: Int
  public var placedNodesComputed: Int
  public var placedNodesReused: Int
  public var placedFrameTableEntriesReused: Int
  public var layoutDependentRealizations: Int
  public var layoutDependentRealizationCacheHits: Int
  public var layoutDependentMainActorFallbacks: Int
  public var measurementCache: MeasurementCacheMetrics?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: Identity?
  /// Branching-factor counters (plan 2026-08-11-004 Stage 0). `package`
  /// (set post-init, defaulting to zeroes) so the public work surface stays
  /// frozen.
  package var layoutBranching: LayoutBranchingMetrics = .init()
  package var retainedValidation: RetainedValidationWork?
  /// Committed-value anchor-projection walk tallies (serve-path plan
  /// 2026-08-12-003). Same post-init pattern as `layoutBranching`.
  package var lifetimeAnchorTallies: LifetimeAnchorProjectionTallies = .init()

  public init(
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0,
    measuredNodesComputed: Int = 0,
    measuredNodesReused: Int = 0,
    placedNodesComputed: Int = 0,
    placedNodesReused: Int = 0,
    placedFrameTableEntriesReused: Int = 0,
    layoutDependentRealizations: Int = 0,
    layoutDependentRealizationCacheHits: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    measurementCache: MeasurementCacheMetrics? = nil,
    customLayoutFallbackCount: Int = 0,
    firstCustomLayoutFallbackIdentity: Identity? = nil
  ) {
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
    self.measuredNodesComputed = measuredNodesComputed
    self.measuredNodesReused = measuredNodesReused
    self.placedNodesComputed = placedNodesComputed
    self.placedNodesReused = placedNodesReused
    self.placedFrameTableEntriesReused = placedFrameTableEntriesReused
    self.layoutDependentRealizations = layoutDependentRealizations
    self.layoutDependentRealizationCacheHits = layoutDependentRealizationCacheHits
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.measurementCache = measurementCache
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.firstCustomLayoutFallbackIdentity = firstCustomLayoutFallbackIdentity
  }
}

public struct FrameDiagnosticPresentation: Equatable, Sendable {
  public var damage: PresentationDamageDiagnostics?
  /// Which rasterizer path this frame took, and why raster-reuse damage
  /// production barriered when it did.
  public var rasterReuse: RasterReuseDiagnostics?

  public init(
    damage: PresentationDamageDiagnostics? = nil,
    rasterReuse: RasterReuseDiagnostics? = nil
  ) {
    self.damage = damage
    self.rasterReuse = rasterReuse
  }
}

/// Which of the rasterizer's two paths produced a surface.
public enum RasterPath: String, Sendable, Equatable {
  /// Painted from an empty surface.
  case fresh
  /// Reused the previous surface's clean rows and repainted only the damaged
  /// ones.
  case incremental
  /// The incremental path additionally served verified scroll-band rows by
  /// moving the previous surface's row buffers (R3.2b translation blit).
  case incrementalTranslated
  /// Took the incremental path, then the F13 verification oracle caught a
  /// divergence and repaired it with a fresh raster.
  case incrementalRepaired
}

/// A reason a frame could not reuse its previous raster.
public enum FrameTailRasterReuseBarrier: String, Hashable, Sendable, CaseIterable {
  case missingRetainedFrame = "missing_retained_frame"
  case rootInvalidated = "root_invalidated"
  case emptyInvalidation = "empty_invalidation"
  case surfaceTopologyChanged = "surface_topology_changed"
  /// The previous frame's placed tree was rooted at a different identity, so
  /// the two placed paths are not comparable.
  case placedRootChanged = "placed_root_changed"
  /// An identity on one of the placed paths resolved to more than one node, so
  /// the path may mix nodes from different duplicate siblings.
  case duplicateInvalidatedIdentity = "duplicate_invalidated_identity"
  /// The head's animation-injection stage rewrote resolved values after
  /// invalidation was computed, so `directlyInvalidated` is not the complete
  /// set of identities that repaint this frame.
  case animationInterpolationApplied = "animation_interpolation_applied"
  /// The current placed tree carries animation overlay decoration that the
  /// retained baseline placed tree does not.
  case animationOverlayDecorated = "animation_overlay_decorated"
}

/// Whether a committed frame reached the incremental rasterizer.
/// It also identifies the reason that stopped the frame.
///
/// The incremental tier was unreachable for its entire existence.
/// The codebase had no diagnostic for this state.
/// The performance lanes measured a constant zero, but they did not identify the cause.
/// Identification of the cause required a local change to the rasterizer.
/// This diagnostic lets tests and the performance harness identify the path directly.
public struct RasterReuseDiagnostics: Equatable, Sendable {
  /// `fresh`, `incremental`, or `incrementalRepaired`. The last means the
  /// incremental surface diverged from a fresh raster and was repaired.
  public var path: RasterPath
  /// Sorted, stable tokens naming why damage production returned no damage.
  /// Empty when damage was produced.
  public var barriers: [FrameTailRasterReuseBarrier]

  public init(
    path: RasterPath,
    barriers: [FrameTailRasterReuseBarrier] = []
  ) {
    self.path = path
    self.barriers = barriers
  }
}

public struct FrameDiagnosticTiming: Equatable, Sendable {
  public var phaseTimings: FramePhaseTimings?
  public var headTimings: FrameHeadTimings?
  public var renderGenerations: FrameRenderGenerations
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?

  public init(
    phaseTimings: FramePhaseTimings? = nil,
    headTimings: FrameHeadTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil
  ) {
    self.phaseTimings = phaseTimings
    self.headTimings = headTimings
    self.renderGenerations = renderGenerations
    self.workerTimings = workerTimings
    self.mainActorTimings = mainActorTimings
  }
}

public struct FrameDiagnosticRuntime: Equatable, Sendable {
  public var registrations: RuntimeRegistrationDiagnostics
  public var issues: [RuntimeIssue]

  public init(
    registrations: RuntimeRegistrationDiagnostics = .init(),
    issues: [RuntimeIssue] = []
  ) {
    self.registrations = registrations
    self.issues = issues
  }
}

public struct FrameDiagnosticDrop: Equatable, Sendable {
  public var eligibilityBlockers: Set<FrameDropBlocker>

  public init(
    eligibilityBlockers: Set<FrameDropBlocker> = []
  ) {
    self.eligibilityBlockers = eligibilityBlockers
  }
}

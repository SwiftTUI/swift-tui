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

  public init(damage: PresentationDamageDiagnostics? = nil) {
    self.damage = damage
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
  public var eligibilityBlockers: Set<FrameDropEligibility.Blocker>

  public init(
    eligibilityBlockers: Set<FrameDropEligibility.Blocker> = []
  ) {
    self.eligibilityBlockers = eligibilityBlockers
  }
}

import Synchronization

private struct FrameDiagnosticsSummaryDebugKey: Hashable, Sendable {
  var epoch: UInt64
  var id: UInt64
}

private enum FrameDiagnosticsSummaryComputationCounter {
  static let epoch = Atomic<UInt64>(0)
  static let nextID = Atomic<UInt64>(0)
  static let count = Atomic<Int>(0)
  static let seen = Mutex<Set<FrameDiagnosticsSummaryDebugKey>>([])
}

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
  public var renderGenerations: FrameRenderGenerations
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?

  public init(
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil
  ) {
    self.phaseTimings = phaseTimings
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

private struct FrameDiagnosticSummary: Equatable, Sendable {
  var counts: FrameDiagnosticCounts
  var work: FrameDiagnosticWork
}

public struct FrameDiagnostics: Sendable {
  public var input: FrameDiagnosticInput
  private var diagnosticSummary: FrameDiagnosticSummary
  private let debugSummaryID: UInt64
  public var counts: FrameDiagnosticCounts {
    get {
      Self.recordSummaryComputation(for: debugSummaryID)
      return diagnosticSummary.counts
    }
    set {
      diagnosticSummary.counts = newValue
    }
  }

  public var work: FrameDiagnosticWork {
    get {
      Self.recordSummaryComputation(for: debugSummaryID)
      return diagnosticSummary.work
    }
    set {
      diagnosticSummary.work = newValue
    }
  }

  public var presentation: FrameDiagnosticPresentation
  public var timing: FrameDiagnosticTiming
  public var runtime: FrameDiagnosticRuntime
  public var drop: FrameDiagnosticDrop
  package var geometryResolutionDiagnostics: GeometryResolutionDiagnostics = .init()

  public init(
    input: FrameDiagnosticInput = .init(),
    counts: FrameDiagnosticCounts = .init(),
    work: FrameDiagnosticWork = .init(),
    presentation: FrameDiagnosticPresentation = .init(),
    timing: FrameDiagnosticTiming = .init(),
    runtime: FrameDiagnosticRuntime = .init(),
    drop: FrameDiagnosticDrop = .init()
  ) {
    self.input = input
    self.diagnosticSummary = .init(
      counts: counts,
      work: work
    )
    self.debugSummaryID = Self.nextDebugSummaryID()
    self.presentation = presentation
    self.timing = timing
    self.runtime = runtime
    self.drop = drop
  }

  private init(
    input: FrameDiagnosticInput,
    diagnosticSummary: FrameDiagnosticSummary,
    presentation: FrameDiagnosticPresentation,
    timing: FrameDiagnosticTiming,
    runtime: FrameDiagnosticRuntime,
    drop: FrameDiagnosticDrop,
    geometryResolutionDiagnostics: GeometryResolutionDiagnostics
  ) {
    self.input = input
    self.diagnosticSummary = diagnosticSummary
    self.debugSummaryID = Self.nextDebugSummaryID()
    self.presentation = presentation
    self.timing = timing
    self.runtime = runtime
    self.drop = drop
    self.geometryResolutionDiagnostics = geometryResolutionDiagnostics
  }
}

extension FrameDiagnostics {
  private static func nextDebugSummaryID() -> UInt64 {
    FrameDiagnosticsSummaryComputationCounter.nextID.wrappingAdd(1, ordering: .relaxed).newValue
  }

  package static func debugResetSummaryComputationCount() {
    FrameDiagnosticsSummaryComputationCounter.count.store(0, ordering: .relaxed)
    FrameDiagnosticsSummaryComputationCounter.seen.withLock {
      $0.removeAll(keepingCapacity: true)
    }
    _ = FrameDiagnosticsSummaryComputationCounter.epoch.wrappingAdd(1, ordering: .relaxed)
  }

  package static func debugSummaryComputationCount() -> Int {
    FrameDiagnosticsSummaryComputationCounter.count.load(ordering: .relaxed)
  }

  private static func recordSummaryComputation(for id: UInt64) {
    let epoch = FrameDiagnosticsSummaryComputationCounter.epoch.load(ordering: .relaxed)
    guard epoch != 0 else {
      return
    }
    let key = FrameDiagnosticsSummaryDebugKey(epoch: epoch, id: id)
    let inserted = FrameDiagnosticsSummaryComputationCounter.seen.withLock {
      $0.insert(key).inserted
    }
    if inserted {
      FrameDiagnosticsSummaryComputationCounter.count.wrappingAdd(1, ordering: .relaxed)
    }
  }

  package static func fromCachedPhaseProducts(
    resolved: ResolvedNode,
    measured: MeasuredNode,
    placed: PlacedNode,
    semantics: SemanticSnapshot,
    draw: DrawNode,
    invalidatedIdentities: Set<Identity> = [],
    resolveWork: ResolveWorkMetrics? = nil,
    layoutWork: LayoutWorkMetrics? = nil,
    presentationDamage: PresentationDamage? = nil,
    presentationSurfaceWidth: Int = 0,
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil,
    runtimeIssues: [RuntimeIssue] = [],
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker> = []
  ) -> Self {
    let customLayoutFallback = resolved.customLayoutFallbackSummary
    return Self(
      input: .init(
        proposal: measured.proposal,
        invalidatedIdentities: invalidatedIdentities
      ),
      diagnosticSummary: .init(
        counts: .init(
          resolvedNodes: resolved.subtreeNodeCount,
          measuredNodes: measured.subtreeNodeCount,
          placedNodes: placed.subtreeNodeCount,
          drawNodes: draw.subtreeNodeCount,
          interactionRegions: semantics.interactionRegions.count,
          focusRegions: semantics.focusRegions.count,
          scrollRoutes: semantics.scrollRoutes.count,
          selectionRoutes: semantics.selectionRoutes.count
        ),
        work: .init(
          resolvedNodesComputed: resolveWork?.resolvedNodesComputed ?? 0,
          resolvedNodesReused: resolveWork?.resolvedNodesReused ?? 0,
          measuredNodesComputed: layoutWork?.measuredNodesComputed ?? 0,
          measuredNodesReused: layoutWork?.measuredNodesReused ?? 0,
          placedNodesComputed: layoutWork?.placedNodesComputed ?? 0,
          placedNodesReused: layoutWork?.placedNodesReused ?? 0,
          layoutDependentRealizations: layoutWork?.layoutDependentRealizations ?? 0,
          layoutDependentRealizationCacheHits:
            layoutWork?.layoutDependentRealizationCacheHits ?? 0,
          layoutDependentMainActorFallbacks:
            layoutWork?.layoutDependentMainActorFallbacks ?? 0,
          measurementCache: measurementCache,
          customLayoutFallbackCount: customLayoutFallback.count,
          firstCustomLayoutFallbackIdentity: customLayoutFallback.firstIdentity
        )),
      presentation: .init(
        damage: presentationDamage.map {
          .init(
            damage: $0,
            surfaceWidth: presentationSurfaceWidth
          )
        }
      ),
      timing: .init(
        phaseTimings: phaseTimings,
        renderGenerations: renderGenerations,
        workerTimings: workerTimings,
        mainActorTimings: mainActorTimings
      ),
      runtime: .init(issues: runtimeIssues),
      drop: .init(eligibilityBlockers: dropEligibilityBlockers),
      geometryResolutionDiagnostics:
        layoutWork?.geometryResolutionDiagnostics ?? .init()
    )
  }
}

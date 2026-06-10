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
    headTimings: FrameHeadTimings? = nil,
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
          placedFrameTableEntriesReused: layoutWork?.placedFrameTableEntriesReused ?? 0,
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
        headTimings: headTimings,
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

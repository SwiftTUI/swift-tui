import Synchronization

// Layout-pass context and its supporting value types.
//
// `LayoutPassContext` carries the mutable per-frame state the layout engine
// threads through a measure/place pass: scroll viewport context, work metrics,
// worker custom-layout cache updates, and the custom-layout compatibility
// boundary stack. `ScrollViewportContext`, `CustomLayoutCompatibilityPhase`,
// and `WorkerCustomLayoutCacheUpdate` are its companions.
//
// The read-only retained-frame query types this file was once named for now
// live in `RetainedFrameQueries.swift`.

package struct ScrollViewportContext: Equatable, Sendable {
  package var axes: AxisSet
  package var viewportRect: CellRect
  package var contentOffset: CellPoint

  package init(
    axes: AxisSet,
    viewportRect: CellRect,
    contentOffset: CellPoint
  ) {
    self.axes = axes
    self.viewportRect = viewportRect
    self.contentOffset = contentOffset
  }
}

/// The viewport a scroll layout declares for its content's MEASUREMENT
/// (proposal 2026-07-13-002 Stage 2.2). Measurement runs before placement,
/// so no absolute rect exists yet — the hint carries the scrollable axes,
/// the requested (unclamped) content offset, and the viewport's main-axis
/// length as known from the scroll layout's own proposal. Lazy containers
/// use it to bound realization/measurement to the visible band plus
/// overscan; the offset is unclamped by design (clamping needs the content
/// size, which is what measurement is computing) — the window math clamps
/// to the content range itself.
package struct MeasureViewportHint: Equatable, Sendable {
  package var axes: AxisSet
  package var contentOffset: CellPoint
  package var viewportSize: CellSize

  package init(
    axes: AxisSet,
    contentOffset: CellPoint,
    viewportSize: CellSize
  ) {
    self.axes = axes
    self.contentOffset = contentOffset
    self.viewportSize = viewportSize
  }
}

/// What a layout pass context exists FOR (plan 2026-08-11-004). The main
/// measure/place pass is the only purpose whose work metrics reach the frame
/// diagnostic record and the branching-factor ledger; scratch passes (the
/// size-stability pre-pass, the layout shadow oracle) keep their counters on
/// their own context and merge back only what they explicitly choose to.
package enum LayoutPassPurpose: Sendable {
  /// The production measure/place pass, including late-preference relayouts.
  case main
  /// The size-stability cutoff's certificate pre-pass (plan 2026-08-11-002).
  case sizeStabilityPrePass
  /// The layout shadow oracle's observe-only fresh pass.
  case shadowOracle
}

package final class LayoutPassContext: Sendable {
  /// One entry of the measure-viewport hint stack. `claimedBy` records the
  /// indexed container that anchored a window against this hint: the hint's
  /// `contentOffset` is meaningful only at the scroll content's origin, so the
  /// outermost indexed container on the hint's axis claims it and every deeper
  /// (or later-sibling) container measures exhaustively instead of anchoring
  /// `offset / ownStride` at its own origin — which parks a nested stack's
  /// window at its end once the outer offset exceeds `count × stride`. The
  /// claim is keyed by identity so a legitimate re-measure of the SAME
  /// container inside one hint scope (an enclosing stack's flexibility
  /// second round) windows again instead of degrading to exhaustive.
  private struct MeasureViewportHintEntry: Sendable {
    var hint: MeasureViewportHint
    var claimedBy: Identity?
  }

  private struct MutableState: Sendable {
    var scrollViewportContext: ScrollViewportContext?
    var measureViewportHints: [MeasureViewportHintEntry]
    /// One frame per in-flight custom-layout `measureContainer`, innermost
    /// last (plan 2026-08-11-006 Stage 0): author `sizeThatFits` probes
    /// record `(child, proposal)` into the top frame, and the `.custom`
    /// measure case drains it into the container's issued-proposal
    /// snapshot. Empty outside custom measurement, so placement-phase
    /// probes drop silently.
    var issuedProposalProbeFrames: [[Identity: [ProposedSize]]] = []
    /// Per-pass answers of the custom-layout container hooks
    /// (plan 2026-08-31-001): a container's declared outer spacing per
    /// identity, and its explicit alignment answers per identity, proposal,
    /// and guide. The stack engine asks for spacing from many sites per
    /// parent measure and a parent reads a guide once per placement, so the
    /// author hook runs once per question per pass. Living on the pass
    /// context rather than on the layout proxy makes the memo's lifetime
    /// exactly one pass — no stale answer can survive into a later frame.
    var customLayoutSpacingMemo: [Identity: Spacing] = [:]
    var customLayoutAlignmentMemo: [CustomLayoutAlignmentMemoKey: Int?] = [:]
    var workMetrics: LayoutWorkMetrics
    var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
    var layoutDependentRealizations: [LayoutDependentContentRealization]
    var deniedLayoutRealizationBoundaries: Set<Identity>
    var patchedMeasureSession: RetainedLayoutSession?
    var placedFrameTable: PlacedFrameTable
    var customLayoutCompatibilityDepth: Int
    var customLayoutCompatibilityDepthLimit: Int
    var runtimeIssues: [RuntimeIssue]
  }

  /// The conservative nesting budget for native layout-engine re-entry:
  /// custom-layout compatibility recursion and hosted-collection
  /// (`List`/`Table`) windowed row measurement share one counter, because
  /// they consume the same real stack. Each nesting level re-enters the
  /// engine on the native stack — measured at up to ~80 KiB per level in
  /// debug builds, with a ~54 KiB windowed-measurement frame at the tip — so
  /// this default is calibrated to the smallest stacks a pass can run on:
  /// the ~512 KiB frame-tail dispatch worker and cooperative-pool threads
  /// that call the engine directly.
  package static let defaultCustomLayoutCompatibilityDepthLimit = 4

  /// The nesting budget for passes guaranteed to run on the main thread
  /// (~8 MiB stack): the composed render pipeline's entry points are all
  /// main-actor, and trees nested deeper than the worker budget are
  /// disqualified from worker offload, so the pipeline's pass context can
  /// afford real-world nesting like one split-pane layout per split.
  /// 24 levels ≈ 2 MiB of worst-case debug stack against the main thread's
  /// ~8 MiB. WASI keeps the conservative default: it runs everything inline
  /// on one small wasm stack with no offload worker.
  package static let mainActorCustomLayoutCompatibilityDepthLimit: Int = {
    #if os(WASI)
      defaultCustomLayoutCompatibilityDepthLimit
    #else
      24
    #endif
  }()

  package let purpose: LayoutPassPurpose
  /// The renderer-owned persistent author-cache store (plan 2026-08-11-004
  /// Stage 2), or `nil` for scratch passes (the shadow oracle, the
  /// size-stability pre-pass) and when `SWIFTTUI_PERSISTENT_LAYOUT_CACHE=0`
  /// disables persistence: a nil store means custom layouts fall back to
  /// per-pass `makeCache`, the pre-Stage-2 behavior.
  package let customLayoutCacheStore: CustomLayoutCacheStore?
  package let retainedLayout: RetainedLayoutSession?
  package let invalidatedIdentities: Set<Identity>
  /// A previous-frame session consulted ONLY by the custom-layout
  /// hysteresis-seeding seam (`RetainedMeasurementSeedableLayout`) when
  /// `retainedLayout` is absent. The layout shadow oracle's scratch context
  /// carries the production session here so the fresh pass evaluates the same
  /// hysteresis inputs (for example `ScrollViewLayout`'s converged
  /// indicator-inset seed, which selects among bistable fixed points) while
  /// every product-reuse tier stays disabled. Seeds are, by the seam's
  /// contract, verified in-pass by fresh measurement, so this cannot hide an
  /// unsound product serve from the oracle.
  package let measurementSeedSession: RetainedLayoutSession?
  /// `false` for observe-only passes (the layout shadow oracle's scratch
  /// context): realizing layout-dependent content resolves authored closures
  /// against the live graph — reading AND writing it — so a shadow pass must
  /// consume the production pass's realizations instead of realizing anew.
  private let allowsLiveLayoutRealization: Bool
  private let state: Mutex<MutableState>

  package init(
    purpose: LayoutPassPurpose = .main,
    customLayoutCacheStore: CustomLayoutCacheStore? = nil,
    retainedLayout: RetainedLayoutSession? = nil,
    invalidatedIdentities: Set<Identity> = [],
    scrollViewportContext: ScrollViewportContext? = nil,
    customLayoutCompatibilityDepthLimit: Int = defaultCustomLayoutCompatibilityDepthLimit,
    measurementSeedSession: RetainedLayoutSession? = nil,
    seededLayoutRealizations: [LayoutDependentContentRealization]? = nil
  ) {
    self.purpose = purpose
    self.customLayoutCacheStore = customLayoutCacheStore
    self.retainedLayout = retainedLayout
    self.invalidatedIdentities = invalidatedIdentities
    self.measurementSeedSession = measurementSeedSession
    allowsLiveLayoutRealization = seededLayoutRealizations == nil
    let geometryDiagnosticsRecorder = GeometryResolutionDiagnosticsRecorder()
    state = .init(
      .init(
        scrollViewportContext: scrollViewportContext,
        measureViewportHints: [],
        workMetrics: .init(),
        workerCustomLayoutCacheUpdates: [],
        layoutDependentRealizations: seededLayoutRealizations ?? [],
        deniedLayoutRealizationBoundaries: [],
        patchedMeasureSession: nil,
        placedFrameTable: .init(diagnosticsRecorder: geometryDiagnosticsRecorder),
        customLayoutCompatibilityDepth: 0,
        customLayoutCompatibilityDepthLimit: customLayoutCompatibilityDepthLimit,
        runtimeIssues: []
      )
    )
  }

  package var scrollViewportContext: ScrollViewportContext? {
    state.withLock { $0.scrollViewportContext }
  }

  /// The custom-layout re-entry budget this context was constructed with. The
  /// layout shadow oracle reads it so a scratch shadow context inherits the
  /// production pass's budget rather than silently downgrading a main-actor
  /// pass to the worker limit.
  package var customLayoutCompatibilityDepthLimit: Int {
    state.withLock { $0.customLayoutCompatibilityDepthLimit }
  }

  /// The innermost measure-viewport hint, or `nil` outside any scroll
  /// layout's content measurement. Hints are scoped: a scroll layout pushes
  /// before measuring its content and pops after, so a nested scroll's hint
  /// shadows the outer one for exactly the inner content's measurement. A
  /// layout pass is sequential (one work stack, one thread at a time — the
  /// frame tail may run on a worker, but never concurrently with another
  /// pass on the same context), which is what makes a scoped stack sound
  /// here.
  package var currentMeasureViewportHint: MeasureViewportHint? {
    state.withLock { $0.measureViewportHints.last?.hint }
  }

  /// Atomically claims the innermost hint for the indexed container
  /// `identity`: returns the hint when the entry is unclaimed or already
  /// claimed by this same identity, or `nil` when a DIFFERENT container
  /// holds the claim (the caller must fall back to exhaustive measurement).
  /// Only the outermost indexed container on the hint's axis may window
  /// against a hint — its `contentOffset` is origin-relative and unadjusted
  /// for nesting depth — while same-identity re-claims keep an enclosing
  /// stack's flexibility re-measure of the claimer windowed.
  package func claimCurrentMeasureViewportHint(
    for identity: Identity
  ) -> MeasureViewportHint? {
    state.withLock {
      guard let last = $0.measureViewportHints.indices.last else {
        return nil
      }
      switch $0.measureViewportHints[last].claimedBy {
      case nil:
        $0.measureViewportHints[last].claimedBy = identity
        return $0.measureViewportHints[last].hint
      case identity:
        return $0.measureViewportHints[last].hint
      default:
        return nil
      }
    }
  }

  package func pushMeasureViewportHint(_ hint: MeasureViewportHint) {
    state.withLock {
      $0.measureViewportHints.append(.init(hint: hint, claimedBy: nil))
    }
  }

  package func popMeasureViewportHint() {
    state.withLock {
      precondition(
        !$0.measureViewportHints.isEmpty,
        "measure viewport hint stack underflow"
      )
      $0.measureViewportHints.removeLast()
    }
  }

  package func withMeasureViewportHint<Result>(
    _ hint: MeasureViewportHint?,
    _ body: () -> Result
  ) -> Result {
    guard let hint else {
      return body()
    }
    pushMeasureViewportHint(hint)
    defer { popMeasureViewportHint() }
    return body()
  }

  package var workMetrics: LayoutWorkMetrics {
    state.withLock {
      var metrics = $0.workMetrics
      metrics.geometryResolutionDiagnostics = $0.placedFrameTable.geometryResolutionDiagnostics
      return metrics
    }
  }

  package var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate] {
    state.withLock { $0.workerCustomLayoutCacheUpdates }
  }

  package var runtimeIssues: [RuntimeIssue] {
    state.withLock { $0.runtimeIssues }
  }

  /// The realizations this pass produced (or was seeded with), in record
  /// order. The layout shadow oracle seeds its scratch context with the
  /// production pass's records so the fresh pass places the same realized
  /// children without touching the live graph.
  package var layoutDependentRealizations: [LayoutDependentContentRealization] {
    state.withLock { $0.layoutDependentRealizations }
  }

  /// Boundaries an observe-only pass could not realize because its seeded
  /// memo did not cover them. Expected empty in practice; the oracle excludes
  /// these subtrees from comparison instead of reporting shape noise.
  package var deniedLayoutRealizationBoundaries: Set<Identity> {
    state.withLock { $0.deniedLayoutRealizationBoundaries }
  }

  /// Installs the measure cutoff's derived session (plan 2026-08-11-002 D4):
  /// the measure pass reads the patched copy through
  /// ``measureSessionForReuse`` while the place pass, the damage resolver,
  /// and diagnostics keep ``retainedLayout``. Installed once by the tail's
  /// pre-pass before the main measure; late-preference relayouts build fresh
  /// contexts, so the patched view never leaks across passes.
  package func installPatchedMeasureSession(_ session: RetainedLayoutSession) {
    state.withLock {
      precondition(
        $0.patchedMeasureSession == nil,
        "the patched measure session is installed at most once per pass"
      )
      $0.patchedMeasureSession = session
    }
  }

  /// The session the measure pass's reuse gates consult: the cutoff's
  /// patched derived session when installed, the frame's retained session
  /// otherwise.
  package var measureSessionForReuse: RetainedLayoutSession? {
    state.withLock { $0.patchedMeasureSession } ?? retainedLayout
  }

  package var layoutDependentRealizationsByIdentity: [Identity: [ResolvedNode]] {
    state.withLock { state in
      state.layoutDependentRealizations.reduce(into: [:]) { result, realization in
        result[realization.signature.boundaryIdentity] = realization.children
      }
    }
  }

  package var placedFrameTable: PlacedFrameTable {
    state.withLock { $0.placedFrameTable }
  }

  package func updateWorkMetrics(
    _ update: (inout LayoutWorkMetrics) -> Void
  ) {
    state.withLock { update(&$0.workMetrics) }
  }

  /// Branching-oracle issue-site counters (plan 2026-08-11-004 Stage 0) as
  /// plain methods rather than `updateWorkMetrics` closures: the author-probe
  /// and placement call sites sit on frames that stay live across
  /// custom-layout re-entry on the small frame-tail worker stack, and a
  /// closure context there is a per-nesting-level stack cost in -Onone.
  package func recordCustomChildMeasureRequest(
    grade: MeasurementGrade,
    childIdentity: Identity,
    proposal: ProposedSize
  ) {
    state.withLock {
      $0.workMetrics.branching.customChildMeasureRequests += 1
      if grade == .probe {
        $0.workMetrics.branching.customChildMeasureRequestsProbe += 1
      }
      if let top = $0.issuedProposalProbeFrames.indices.last {
        $0.issuedProposalProbeFrames[top][childIdentity, default: []].append(proposal)
      }
    }
  }

  package func pushIssuedProposalProbeFrame() {
    state.withLock { $0.issuedProposalProbeFrames.append([:]) }
  }

  /// The memoized container-spacing answer for `identity` in this pass, if
  /// the hook already ran (plan 2026-08-31-001).
  package func customLayoutSpacingMemo(for identity: Identity) -> Spacing? {
    state.withLock { $0.customLayoutSpacingMemo[identity] }
  }

  package func recordCustomLayoutSpacingMemo(_ spacing: Spacing, for identity: Identity) {
    state.withLock { $0.customLayoutSpacingMemo[identity] = spacing }
  }

  /// The memoized explicit-alignment answer for `key` in this pass. The
  /// outer optional is presence; the inner is the hook's answer (`nil` =
  /// "use the guide's default").
  package func customLayoutAlignmentMemo(for key: CustomLayoutAlignmentMemoKey) -> Int?? {
    state.withLock { $0.customLayoutAlignmentMemo[key] }
  }

  package func recordCustomLayoutAlignmentMemo(
    _ value: Int?,
    for key: CustomLayoutAlignmentMemoKey
  ) {
    state.withLock { $0.customLayoutAlignmentMemo[key] = value }
  }

  package func popIssuedProposalProbeFrame() {
    state.withLock {
      precondition(
        !$0.issuedProposalProbeFrames.isEmpty,
        "issued-proposal probe frame underflow"
      )
      $0.issuedProposalProbeFrames.removeLast()
    }
  }

  /// The innermost custom container's recorded author probes, or `nil`
  /// outside custom measurement.
  package func currentIssuedProposalProbes() -> [Identity: [ProposedSize]]? {
    state.withLock { $0.issuedProposalProbeFrames.last }
  }

  /// The fail-loud commit guard (plan 2026-08-11-004 Stage 1). A serve
  /// tier calls this when it answers a request with PROBE latitude — any
  /// service other than exact-key, exact-validity whose soundness rests on
  /// the product being discarded before commit. Reaching a commit-grade
  /// request is the violation: the caller must also assert on a `true`
  /// return (the DEBUG call-site assertion), and the recorded
  /// `layout.probeGradeCommit` issue rides the frame record in release.
  ///
  /// The size-stability cutoff's certified serves never call this: they
  /// serve fresh, certificate-validated products through the untouched
  /// exact-validity guards, so they are exempt by construction. No
  /// production serve tier has probe latitude at Stage 1; the first real
  /// caller is Stage 2's persistent custom-layout cache.
  @discardableResult
  package func recordProbeLatitudeServe(
    identity: Identity,
    source: String,
    requestGrade: MeasurementGrade
  ) -> Bool {
    guard requestGrade == .commit else {
      return false
    }
    state.withLock { state in
      let issue = RuntimeIssue(
        severity: .error,
        code: "layout.probeGradeCommit",
        message:
          "a probe-latitude serve from \(source) answered a commit-grade "
          + "measurement request; probe-grade output must never commit",
        identity: identity,
        source: source
      )
      if !state.runtimeIssues.contains(issue) {
        state.runtimeIssues.append(issue)
      }
    }
    return true
  }

  package func recordCustomPlacementChildMeasureRequests(_ count: Int) {
    state.withLock {
      $0.workMetrics.branching.customPlacementChildMeasureRequests += count
    }
  }

  package func recordWorkerCustomLayoutCacheUpdate(
    _ update: WorkerCustomLayoutCacheUpdate
  ) {
    state.withLock { $0.workerCustomLayoutCacheUpdates.append(update) }
  }

  /// Records a resolve-authored runtime issue into this frame's issue set —
  /// the merge channel for graph-buffered issues (`ViewGraph.
  /// frameRuntimeIssues`) that have no resolved node to ride a preference
  /// on. Deduplicated like the layout-authored issue sites.
  package func recordRuntimeIssue(_ issue: RuntimeIssue) {
    state.withLock { state in
      if !state.runtimeIssues.contains(issue) {
        state.runtimeIssues.append(issue)
      }
    }
  }

  package func recordPlacedFrame(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    bounds: CellRect,
    namedCoordinateSpaceName: String?
  ) {
    state.withLock {
      $0.placedFrameTable.record(
        viewNodeID: viewNodeID,
        identity: identity,
        bounds: bounds,
        namedCoordinateSpaceName: namedCoordinateSpaceName
      )
    }
  }

  package func recordPlacedFrames(
    in node: PlacedNode
  ) {
    state.withLock {
      var work = [node]
      while let current = work.popLast() {
        $0.placedFrameTable.record(
          viewNodeID: current.viewNodeID,
          identity: current.identity,
          bounds: current.bounds,
          namedCoordinateSpaceName: current.semanticMetadata.namedCoordinateSpaceName
        )
        work.append(contentsOf: current.children.reversed())
      }
    }
  }

  package func recordPlacedFrameFragment(
    _ fragment: PlacedFrameTableFragment
  ) {
    state.withLock {
      $0.workMetrics.placedFrameTableEntriesReused += $0.placedFrameTable.record(fragment)
    }
  }

  package func enterCustomLayoutCompatibilityBoundary(
    identity: Identity,
    debugName: String,
    phase: CustomLayoutCompatibilityPhase
  ) -> Bool {
    state.withLock { state in
      guard state.customLayoutCompatibilityDepth < state.customLayoutCompatibilityDepthLimit else {
        let issue = RuntimeIssue(
          severity: .error,
          code: "layout.customLayoutDepthLimitExceeded",
          message:
            "Layout engine re-entry (\(phase.rawValue)) exceeded the compatibility depth "
            + "limit of \(state.customLayoutCompatibilityDepthLimit).",
          identity: identity,
          source: debugName
        )
        if !state.runtimeIssues.contains(issue) {
          state.runtimeIssues.append(issue)
        }
        return false
      }

      state.customLayoutCompatibilityDepth += 1
      return true
    }
  }

  /// Records one placement child/measurement mismatch (F166): a placement
  /// request saw a different number of resolved children than measurements
  /// (or an allocation snapshot indexed a different child count), so part of
  /// the subtree is silently not placed — the invisible-content class.
  /// Observability-first like the lifecycle skip counters: a mismatch in a
  /// user app is better reported than crashed. Deduplicated per identity.
  package func recordPlacementChildMismatch(
    identity: Identity,
    behavior: String,
    childCount: Int,
    measurementCount: Int
  ) {
    state.withLock { state in
      let issue = RuntimeIssue(
        severity: .warning,
        code: "layout.placementChildMismatch",
        message:
          "placement for \(behavior) saw \(childCount) resolved children but "
          + "\(measurementCount) measurements; the surplus is not placed",
        identity: identity,
        source: "LayoutEngine"
      )
      if !state.runtimeIssues.contains(issue) {
        state.runtimeIssues.append(issue)
      }
    }
  }

  /// Records that a viewport-backed collection had to realize its whole
  /// dataset because nothing bounded it (D17): the height proposal was
  /// non-finite and no enclosing scroll layout declared a measure viewport.
  ///
  /// This is the deliberate fallback for `.fixedSize()`, ideal-height probes,
  /// and `ViewThatFits` alternatives, where the caller has asked for the true
  /// ideal size and estimating it from a probe would silently mis-size a
  /// heterogeneous-row collection. Reporting the cliff is better than hiding
  /// it behind a guess. Deduplicated per identity per pass.
  package func recordUnboundedCollectionRealization(
    identity: Identity,
    count: Int,
    source: String
  ) {
    state.withLock { state in
      let issue = RuntimeIssue(
        severity: .warning,
        code: "collection.unboundedRealization",
        message:
          "\(source) realized all \(count) rows: the height proposal is unbounded and no "
          + "enclosing scroll view declared a measure viewport to window against.",
        identity: identity,
        source: source
      )
      if !state.runtimeIssues.contains(issue) {
        state.runtimeIssues.append(issue)
      }
    }
  }

  package func exitCustomLayoutCompatibilityBoundary() {
    state.withLock { state in
      precondition(
        state.customLayoutCompatibilityDepth > 0,
        "custom layout compatibility depth underflow"
      )
      state.customLayoutCompatibilityDepth -= 1
    }
  }

  package func realizeLayoutDependentContent(
    in context: LayoutRealizationContext,
    using realize: () -> [ResolvedNode]
  ) -> [ResolvedNode] {
    let signature = LayoutDependentContentSignature(context)
    if let cached = state.withLock({
      $0.layoutDependentRealizations.first(where: { $0.signature == signature })
    }) {
      updateWorkMetrics {
        $0.layoutDependentRealizationCacheHits += 1
      }
      return cached.children
    }

    guard allowsLiveLayoutRealization else {
      state.withLock {
        _ = $0.deniedLayoutRealizationBoundaries.insert(signature.boundaryIdentity)
      }
      return []
    }

    let children = realize()
    state.withLock { state in
      state.layoutDependentRealizations.append(
        .init(
          signature: signature,
          children: children
        )
      )
      state.workMetrics.layoutDependentRealizations += 1
    }
    return children
  }
}

package enum CustomLayoutCompatibilityPhase: String, Sendable {
  case measurement
  case placement
}

/// Memo key for one custom container's explicit-alignment answer within a
/// pass (plan 2026-08-31-001): the container identity, the proposal it was
/// measured under (the answer may depend on it), the guide's axis, and the
/// guide's identity key.
package struct CustomLayoutAlignmentMemoKey: Hashable, Sendable {
  package var identity: Identity
  package var proposal: ProposedSize
  package var axis: Axis
  package var guide: ObjectIdentifier

  package init(identity: Identity, proposal: ProposedSize, axis: Axis, guide: ObjectIdentifier) {
    self.identity = identity
    self.proposal = proposal
    self.axis = axis
    self.guide = guide
  }
}

package struct WorkerCustomLayoutCacheUpdate: Sendable {
  package var identity: Identity
  private let applyHandler: @MainActor @Sendable () -> Void

  package init(
    identity: Identity,
    apply: @escaping @MainActor @Sendable () -> Void
  ) {
    self.identity = identity
    applyHandler = apply
  }

  @MainActor
  package func apply() {
    applyHandler()
  }
}

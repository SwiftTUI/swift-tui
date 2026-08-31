import SwiftTUICore
import Synchronization

// The custom-layout type-erasure engine.
//
// `AnyLayout` (in `CustomLayout.swift`) is backed by this machinery:
// `AnyLayoutBox` erases a concrete `Layout`'s associated `Cache` type;
// `ConcreteAnyLayoutBox` is the concrete eraser; `LayoutWorkerProxy` drives
// measurement/placement — on the frame-tail worker when the frame offloads,
// and inline on the main actor otherwise, with all pass-local cache state
// behind a `Mutex` either way; `LayoutContainer` is the `PrimitiveView` that
// lowers a layout into a resolved node.
//
// `Layout: Sendable` (with `Cache: Sendable`) makes this safe by
// construction: there is no main-actor-only custom-layout bridge anymore, and
// no unsynchronized cache for a mis-classified layout to race on. (The former
// `LayoutProxyBox` — a main-actor proxy over an unsynchronized `cachedStates`
// dictionary, release-guarded by `withCheckedMainActorAccess` as suspected
// SIGSEGV flake #1 surface — was deleted when `Layout` became `Sendable`.)
//
// Split out of `CustomLayout.swift` so that file stays the public custom-layout
// API surface. These declarations are widened from `private` to
// file-internal (`internal` — module-wide, the minimal level) so `AnyLayout`'s
// initializers and `callAsFunction` can construct them across files. They form
// one closed dependency graph; no file outside this pair references them.

protocol AnyLayoutBox: Sendable {
  var debugName: String { get }
  var builtinLayoutBehavior: LayoutBehavior? { get }
  var measurementReuseSignature: String? { get }
  var placementReuseSignature: String? { get }
  var layoutProperties: LayoutProperties { get }

  func spacing(
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> ViewSpacing

  func explicitAlignment(
    of guide: HorizontalAlignment,
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> Int?

  func explicitAlignment(
    of guide: VerticalAlignment,
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> Int?

  func makeCache(subviews: LayoutSubviews) -> any Sendable

  func updateCache(
    _ cache: inout any Sendable,
    subviews: LayoutSubviews
  )

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> LayoutSize

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  )
}

struct ConcreteAnyLayoutBox<L: Layout>: AnyLayoutBox {
  var layout: L

  var debugName: String {
    String(describing: L.self)
  }

  var builtinLayoutBehavior: LayoutBehavior? {
    (layout as? any BuiltinLayoutBehaviorProviding)?.builtinLayoutBehavior
  }

  var measurementReuseSignature: String? {
    layout.measurementReuseSignature
  }

  var placementReuseSignature: String? {
    layout.placementReuseSignature
  }

  var layoutProperties: LayoutProperties {
    L.layoutProperties
  }

  func spacing(
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> ViewSpacing {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    let spacing = layout.spacing(subviews: subviews, cache: &typedCache)
    cache = typedCache
    return spacing
  }

  func explicitAlignment(
    of guide: HorizontalAlignment,
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> Int? {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    let answer = layout.explicitAlignment(
      of: guide,
      in: bounds,
      proposal: proposal,
      subviews: subviews,
      cache: &typedCache
    )
    cache = typedCache
    return answer
  }

  func explicitAlignment(
    of guide: VerticalAlignment,
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> Int? {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    let answer = layout.explicitAlignment(
      of: guide,
      in: bounds,
      proposal: proposal,
      subviews: subviews,
      cache: &typedCache
    )
    cache = typedCache
    return answer
  }

  func makeCache(subviews: LayoutSubviews) -> any Sendable {
    layout.makeCache(subviews: subviews)
  }

  func updateCache(
    _ cache: inout any Sendable,
    subviews: LayoutSubviews
  ) {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    layout.updateCache(&typedCache, subviews: subviews)
    cache = typedCache
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) -> LayoutSize {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    let size = layout.sizeThatFits(
      proposal: proposal,
      subviews: subviews,
      cache: &typedCache
    )
    cache = typedCache
    return size
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout any Sendable
  ) {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    layout.placeSubviews(
      in: bounds,
      proposal: proposal,
      subviews: subviews,
      cache: &typedCache
    )
    cache = typedCache
  }
}

final class LayoutWorkerProxy<L: Layout>: WorkerCustomLayoutProxy,
  LayoutPassContextCustomLayoutProxy
{
  private struct CacheKey: Hashable, Sendable {
    var identity: Identity
    var proposal: ProposedSize
  }

  private struct State: Sendable {
    var cachedStates: [CacheKey: L.Cache] = [:]
  }

  let debugName: String
  private let layout: L
  private let state = Mutex(State())

  init(layout: L) {
    self.layout = layout
    debugName = String(describing: L.self)
  }

  // `CustomLayoutHandle` requires a `CustomLayoutProxy`; the worker proxy is
  // its own main-actor-capable proxy (the `Mutex`-backed cache is safe from
  // any executor), so the handle carries one object in both roles.
  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> CellSize {
    measureContainer(
      engine: engine,
      node: node,
      proposal: proposal,
      passContext: nil
    )
  }

  // Both proxy protocols default this member; conforming to both makes the
  // witness ambiguous, so it is implemented explicitly.
  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    // A viewport-declaring layout (a scroll) scopes its declared measure
    // viewport over this pre-measure of its children, so lazy containers in
    // the content window instead of realizing every element (Stage 2.2) —
    // this entry bypasses the layout's own `sizeThatFits`, which is where
    // the scroll otherwise declares the hint per subview measurement.
    let hint = (layout as? any MeasureViewportDeclaringLayout)?
      .declaredMeasureViewport(for: proposal)
    let measureAll = {
      node.children.map { child in
        engine.measure(child, proposal: proposal, passContext: passContext)
      }
    }
    guard let passContext, let hint else {
      return measureAll()
    }
    return passContext.withMeasureViewportHint(hint, measureAll)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    placeSubviews(
      engine: engine,
      node: node,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    let subviews = layoutSubviews(
      for: node,
      engine: engine,
      passContext: passContext
    )
    let prepared = preparedCache(
      for: node,
      proposal: proposal,
      subviews: subviews,
      passContext: passContext
    )
    var cache = prepared.cache
    let layout = seededLayout(for: node, proposal: proposal, passContext: passContext)
    let size = layout.sizeThatFits(
      proposal: proposal,
      subviews: subviews,
      cache: &cache
    )
    storeCache(cache, for: node, proposal: proposal)
    #if DEBUG
      // The plan-004 Stage 2 divergence check, size leg: a serve from the
      // persistent store must reproduce the fresh-cache size exactly. DEBUG
      // runs every serve (DEBUG sampling is every frame); record-only —
      // the runtime issue is the alarm, matching the layout shadow
      // oracle's current record-only posture — and any firing is the
      // plan's Stage-2 stop condition.
      if prepared.persisted {
        var freshCache = layout.makeCache(subviews: subviews)
        layout.updateCache(&freshCache, subviews: subviews)
        let freshSize = layout.sizeThatFits(
          proposal: proposal,
          subviews: subviews,
          cache: &freshCache
        )
        if freshSize != size {
          passContext?.recordRuntimeIssue(
            RuntimeIssue(
              severity: .error,
              code: "layout.persistedCacheDivergence",
              message:
                "a persisted Layout.Cache produced \(size.width)x\(size.height) where a "
                + "fresh makeCache pass produced \(freshSize.width)x\(freshSize.height); "
                + "the author cache carries pass-coupled state",
              identity: node.identity,
              source: debugName
            )
          )
        }
      }
    #endif
    return size
  }

  package func stackMinimumMainSize(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: SwiftTUICore.Axis,
    contentMinimum: Int,
    passContext _: LayoutPassContext?
  ) -> Int? {
    (layout as? any StackMinimumLayoutProviding)?
      .stackMinimumMainSize(
        axis: axis,
        idealSize: idealMeasurement.measuredSize,
        contentMinimum: contentMinimum
      )
  }

  // MARK: Container contract (plan 2026-08-31-001)

  /// The layout's declared outer spacing for `node`'s parent. Runs the
  /// author's `spacing(subviews:cache:)` against a fresh cache — the hook
  /// has no proposal to key a shared cache by, and the persistent store is
  /// proposal-keyed — under the same accounting as `sizeThatFits`. The
  /// handle memoizes the answer per pass, so this runs once per container
  /// per pass when a pass context is present.
  func preferredSpacing(
    engine: LayoutEngine,
    node: ResolvedNode,
    passContext: LayoutPassContext?
  ) -> Spacing {
    withContainerHookScope(
      engine: engine,
      node: node,
      passContext: passContext,
      refused: Spacing()
    ) { probeEngine in
      let subviews = layoutSubviews(
        for: node,
        engine: probeEngine,
        passContext: passContext
      )
      var cache = layout.makeCache(subviews: subviews)
      layout.updateCache(&cache, subviews: subviews)
      return layout.spacing(subviews: subviews, cache: &cache).coreSpacing
    }
  }

  /// The layout's answer for a horizontal `guide` in its zero-origin
  /// bounds, against the cache prepared for the proposal it was measured
  /// under. Mutations to that cache are discarded — the hook is a read.
  func explicitAlignment(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    horizontalGuide guide: HorizontalAlignment,
    passContext: LayoutPassContext?
  ) -> Int? {
    explicitAlignmentAnswer(
      engine: engine,
      node: node,
      measured: measured,
      passContext: passContext
    ) { layout, bounds, subviews, cache in
      layout.explicitAlignment(
        of: guide,
        in: bounds,
        proposal: measured.proposal,
        subviews: subviews,
        cache: &cache
      )
    }
  }

  /// The vertical counterpart of the horizontal `explicitAlignment`.
  func explicitAlignment(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    verticalGuide guide: VerticalAlignment,
    passContext: LayoutPassContext?
  ) -> Int? {
    explicitAlignmentAnswer(
      engine: engine,
      node: node,
      measured: measured,
      passContext: passContext
    ) { layout, bounds, subviews, cache in
      layout.explicitAlignment(
        of: guide,
        in: bounds,
        proposal: measured.proposal,
        subviews: subviews,
        cache: &cache
      )
    }
  }

  private func explicitAlignmentAnswer(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    passContext: LayoutPassContext?,
    _ ask: (L, CellRect, LayoutSubviews, inout L.Cache) -> Int?
  ) -> Int? {
    withContainerHookScope(
      engine: engine,
      node: node,
      passContext: passContext,
      refused: nil
    ) { probeEngine in
      let subviews = layoutSubviews(
        for: node,
        engine: probeEngine,
        passContext: passContext
      )
      let prepared = preparedCache(
        for: node,
        proposal: measured.proposal,
        subviews: subviews,
        passContext: passContext
      )
      var cache = prepared.cache
      let bounds = CellRect(origin: .zero, size: measured.measuredSize)
      let answer = ask(layout, bounds, subviews, &cache)
      #if DEBUG
        // Divergence check, alignment leg (plan 2026-08-31-001, after the
        // size and placement legs of plan 2026-08-11-004 Stage 2): a
        // guide answered from a persisted cache must match the answer a
        // fresh makeCache pass gives. Record-only, like the other legs.
        if prepared.persisted {
          var freshCache = layout.makeCache(subviews: subviews)
          layout.updateCache(&freshCache, subviews: subviews)
          let freshAnswer = ask(layout, bounds, subviews, &freshCache)
          if freshAnswer != answer {
            passContext?.recordRuntimeIssue(
              RuntimeIssue(
                severity: .error,
                code: "layout.persistedCacheDivergence",
                message:
                  "a persisted Layout.Cache answered an explicit alignment guide "
                  + "differently from a fresh makeCache pass; the author cache carries "
                  + "pass-coupled state",
                identity: node.identity,
                source: debugName
              )
            )
          }
        }
      #endif
      return answer
    }
  }

  /// Runs one container-contract hook under the accounting `sizeThatFits`
  /// gets: a probe-graded engine (subview measures inside the hook are
  /// author probes, not committed products), an isolated issued-proposal
  /// frame so those probes never land in an enclosing container's
  /// snapshot, and the compatibility depth boundary. A refused boundary
  /// returns `refused` without running author code, matching
  /// `measureContainer`'s truncation.
  private func withContainerHookScope<Answer>(
    engine: LayoutEngine,
    node: ResolvedNode,
    passContext: LayoutPassContext?,
    refused: Answer,
    _ body: (LayoutEngine) -> Answer
  ) -> Answer {
    guard
      passContext?.enterCustomLayoutCompatibilityBoundary(
        identity: node.identity,
        debugName: debugName,
        phase: .measurement
      ) ?? true
    else {
      return refused
    }
    defer {
      passContext?.exitCustomLayoutCompatibilityBoundary()
    }
    passContext?.pushIssuedProposalProbeFrame()
    defer {
      passContext?.popIssuedProposalProbeFrame()
    }
    return body(engine.withDefaultMeasurementGrade(.probe))
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    // Placement-time re-measures must be commit-grade (plan 2026-08-11-004
    // Stage 1): their products place directly.
    assert(
      engine.defaultMeasurementGrade == .commit,
      "custom-layout placement received a probe-graded engine"
    )
    let placementRecorder = LayoutSubviewPlacementRecorder()
    let subviews = layoutSubviews(
      for: node,
      engine: engine,
      placementRecorder: placementRecorder,
      passContext: passContext
    )
    let prepared = preparedCache(
      for: node,
      proposal: measured.proposal,
      subviews: subviews,
      passContext: passContext
    )
    var cache = prepared.cache
    let layout = seededLayout(
      for: node,
      proposal: measured.proposal,
      passContext: passContext
    )
    layout.placeSubviews(
      in: bounds,
      proposal: measured.proposal,
      subviews: subviews,
      cache: &cache
    )
    storeCache(cache, for: node, proposal: measured.proposal)
    #if DEBUG
      // Divergence check, placement leg (plan 2026-08-11-004 Stage 2): a
      // persisted cache served directly at placement (no in-pass measure
      // stored a bridge entry) must record the same subview placements a
      // fresh cache records. Record-only, like the size leg.
      if prepared.persisted {
        verifyPersistedCachePlacements(
          against: placementRecorder,
          layout: layout,
          node: node,
          measured: measured,
          in: bounds,
          engine: engine,
          passContext: passContext
        )
      }
    #endif
    // Persist the placement-final author cache (plan 2026-08-11-004
    // Stage 2): recorded through the worker update channel and applied on
    // the main actor only when the frame COMMITS, so abandoned candidates
    // and probe passes never mutate the store.
    if let passContext, let store = passContext.customLayoutCacheStore {
      let finalCache = cache
      let resolvedNode = node
      let storedProposal = measured.proposal
      let layoutDebugName = debugName
      passContext.recordWorkerCustomLayoutCacheUpdate(
        WorkerCustomLayoutCacheUpdate(identity: node.identity) {
          store.store(
            finalCache,
            resolved: resolvedNode,
            proposal: storedProposal,
            layoutDebugName: layoutDebugName
          )
        }
      )
    }
    // The in-pass map stays pass-local: retain measurement mutations
    // through placement, then drop every proposal entry for this container
    // identity. Cross-frame persistence is the store's job, above.
    discardPassLocalCacheStates(for: node.identity)

    // Branching oracle (plan 2026-08-11-004): custom placement re-measures
    // every child once at its recorded placement proposal. Reported apart
    // from measure-time requests because placement runs once per pass where
    // measurement can repeat per proposal.
    passContext?.recordCustomPlacementChildMeasureRequests(node.children.count)

    return node.children.map { child in
      let placement =
        placementRecorder.placement(for: child.identity)
        ?? defaultPlacement(in: bounds, proposal: measured.proposal)
      // A placement that carries a viewport context (a scroll layout placing
      // its content) re-declares it as a measure-viewport hint for this
      // placement-time re-measure, so windowed lazy containers in the
      // subtree stay windowed here too (Stage 2.2) — the sizeThatFits-side
      // hint is out of scope by now.
      let placementMeasureHint = placement.viewportContext.map { context in
        MeasureViewportHint(
          axes: context.axes,
          contentOffset: context.contentOffset,
          viewportSize: context.viewportRect.size
        )
      }
      let childMeasurement: MeasuredNode
      if let passContext, let placementMeasureHint {
        childMeasurement = passContext.withMeasureViewportHint(placementMeasureHint) {
          engine.measure(
            child,
            proposal: placement.proposal,
            passContext: passContext
          )
        }
      } else {
        childMeasurement = engine.measure(
          child,
          proposal: placement.proposal,
          passContext: passContext
        )
      }
      return engine.place(
        child,
        measured: childMeasurement,
        in: LayoutRect(
          origin: placedOrigin(
            for: placement.exactSize ?? childMeasurement.measuredSize,
            at: placement.position,
            anchor: placement.anchor
          ),
          size: placement.exactSize ?? childMeasurement.measuredSize
        ),
        viewportContext: placement.viewportContext,
        passContext: passContext
      )
    }
  }

  /// Seeds a seedable layout from the retained (previous-frame) measured
  /// product of this container, keyed by identity and gated on an identical
  /// proposal (scroll-latency R1.3). A wrong or stale retained product is
  /// safe by contract: the layout verifies whatever it derives from the seed
  /// against fresh measurement. Non-seedable layouts pass through untouched.
  ///
  /// The layout shadow oracle's scratch context has no retained session (no
  /// product may be served) but carries the production session as
  /// `measurementSeedSession`, so the fresh pass evaluates the same
  /// hysteresis inputs production did — a bistable layout (the scroll
  /// indicator gutter) must not re-decide its fixed point only in the shadow.
  private func seededLayout(
    for node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> L {
    let seedSession =
      passContext?.retainedLayout ?? passContext?.measurementSeedSession
    guard var seedable = layout as? any RetainedMeasurementSeedableLayout,
      let previousMeasured = seedSession?.measuredNode(for: node.identity),
      previousMeasured.proposal == proposal,
      previousMeasured.childMeasurements.count == 1
    else {
      return layout
    }
    seedable.applyRetainedMeasurementSeed(
      previousProposal: previousMeasured.proposal,
      previousChildSize: previousMeasured.childMeasurements[0].measuredSize
    )
    // The existential still boxes an `L` value; unboxing back cannot fail.
    return seedable as! L
  }

  private func layoutSubviews(
    for node: ResolvedNode,
    engine: LayoutEngine,
    placementRecorder: LayoutSubviewPlacementRecorder? = nil,
    passContext: LayoutPassContext?
  ) -> LayoutSubviews {
    node.children.map { child in
      LayoutSubview(
        child: child,
        engine: engine,
        placementRecorder: placementRecorder,
        passContext: passContext
      )
    }
  }

  /// Prepares the author cache for one measure or place, in tier order: the
  /// in-pass bridge map (measurement to placement inside the current pass),
  /// the cross-frame persistent store (plan 2026-08-11-004 Stage 2), then
  /// `makeCache`. `updateCache` runs on every tier, preserving the SwiftUI
  /// contract that caches refresh when subviews change. `persisted` reports
  /// a store serve so the DEBUG divergence checks know to verify it.
  private func preparedCache(
    for node: ResolvedNode,
    proposal: ProposedSize,
    subviews: LayoutSubviews,
    passContext: LayoutPassContext?
  ) -> (cache: L.Cache, persisted: Bool) {
    let key = CacheKey(identity: node.identity, proposal: proposal)
    if var cache = state.withLock({ $0.cachedStates[key] }) {
      layout.updateCache(&cache, subviews: subviews)
      return (cache, false)
    }
    if var persisted = persistedCache(for: node, proposal: proposal, passContext: passContext) {
      layout.updateCache(&persisted, subviews: subviews)
      return (persisted, true)
    }
    var cache = layout.makeCache(subviews: subviews)
    layout.updateCache(&cache, subviews: subviews)
    return (cache, false)
  }

  /// The persistent store's serve, behind the plan's validity guards: same
  /// layout type and an equivalent-for-measurement stored node (checked by
  /// the store itself), and nothing at or below this container invalidated
  /// this frame — a changed subtree must rebuild its cache from scratch
  /// through `makeCache`, not refresh a stale one.
  private func persistedCache(
    for node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> L.Cache? {
    guard let passContext,
      let store = passContext.customLayoutCacheStore,
      !isInvalidated(node, passContext: passContext),
      let value = store.lookup(
        resolved: node,
        proposal: proposal,
        layoutDebugName: debugName
      )
    else {
      return nil
    }
    return value as? L.Cache
  }

  /// The retainedMeasurement guard set, or the raw invalidation set when no
  /// session exists (a full re-render frame — exactly where persisted
  /// caches earn their keep).
  private func isInvalidated(
    _ node: ResolvedNode,
    passContext: LayoutPassContext
  ) -> Bool {
    if let session = passContext.retainedLayout {
      return session.isDirectlyInvalidated(node.identity)
        || session.hasSyntheticInvalidatedAncestor(node.identity)
        || session.containsInvalidatedDescendant(of: node.identity)
    }
    return passContext.invalidatedIdentities.contains { identity in
      identity == node.identity || identity.isDescendant(of: node.identity)
    }
  }

  #if DEBUG
    /// Divergence check, placement leg: re-place with a fresh cache into a
    /// second recorder and compare each child's recorded position, proposal,
    /// and exact size.
    private func verifyPersistedCachePlacements(
      against placementRecorder: LayoutSubviewPlacementRecorder,
      layout: L,
      node: ResolvedNode,
      measured: MeasuredNode,
      in bounds: CellRect,
      engine: LayoutEngine,
      passContext: LayoutPassContext?
    ) {
      let verifyRecorder = LayoutSubviewPlacementRecorder()
      let verifySubviews = layoutSubviews(
        for: node,
        engine: engine,
        placementRecorder: verifyRecorder,
        passContext: passContext
      )
      var freshCache = layout.makeCache(subviews: verifySubviews)
      layout.updateCache(&freshCache, subviews: verifySubviews)
      layout.placeSubviews(
        in: bounds,
        proposal: measured.proposal,
        subviews: verifySubviews,
        cache: &freshCache
      )
      for child in node.children {
        let served = placementRecorder.placement(for: child.identity)
        let fresh = verifyRecorder.placement(for: child.identity)
        let diverged =
          served?.position != fresh?.position
          || served?.proposal != fresh?.proposal
          || served?.exactSize != fresh?.exactSize
        if diverged {
          passContext?.recordRuntimeIssue(
            RuntimeIssue(
              severity: .error,
              code: "layout.persistedCacheDivergence",
              message:
                "a persisted Layout.Cache placed a subview differently from a fresh "
                + "makeCache pass; the author cache carries pass-coupled state",
              identity: child.identity,
              source: debugName
            )
          )
          return
        }
      }
    }
  #endif

  private func storeCache(
    _ cache: L.Cache,
    for node: ResolvedNode,
    proposal: ProposedSize
  ) {
    let key = CacheKey(identity: node.identity, proposal: proposal)
    state.withLock { state in
      state.cachedStates[key] = cache
    }
  }

  private func discardPassLocalCacheStates(
    for identity: Identity
  ) {
    state.withLock { state in
      state.cachedStates = state.cachedStates.filter { $0.key.identity != identity }
    }
  }
}

struct LayoutContainer<Content: View>: PrimitiveView, ResolvableView {
  var layout: AnyLayout
  var authoringScope: AuthoringContext?
  var content: Content

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // The container's declared orientation reaches its children the way a
    // built-in stack's does (plan 2026-08-31-001): `Spacer` and `Divider`
    // read `\.stackAxis` at resolve time. Installed unconditionally — a
    // layout that declares no orientation clears an axis inherited from an
    // enclosing stack, so a spacer inside a non-stack layout is flexible on
    // both axes rather than on whatever axis the parent happened to have.
    let childContext = context.settingEnvironment(
      \.stackAxis,
      to: layout.resolvedLayoutProperties.stackOrientation.map(coreAxis)
    )
    // AnyView policy: layout containers must flatten builder output at the
    // `resolveElements` layer, not after `normalizeResolvedElements`. If we
    // resolved each authored child as a single node, any direct child that
    // produces multiple elements (for example `ForEach`) would be collapsed
    // into an implicit `Group`, and the layout would see one overlapping
    // subview instead of distinct siblings.
    let resolvedChildren = withAuthoringContext(authoringScope) {
      resolveDeclaredChildren(
        content,
        in: childContext,
        kindName: "Layout"
      )
    }

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view(layout.debugName),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layout.resolvedBehavior
      )
    ]
  }
}

/// The core-layer axis for an authoring-layer `Axis`.
private func coreAxis(_ axis: Axis) -> SwiftTUICore.Axis {
  switch axis {
  case .horizontal:
    return .horizontal
  case .vertical:
    return .vertical
  }
}

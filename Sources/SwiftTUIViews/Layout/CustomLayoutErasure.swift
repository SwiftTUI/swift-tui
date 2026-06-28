import SwiftTUICore
import Synchronization

// The custom-layout type-erasure engine.
//
// `AnyLayout` (in `CustomLayout.swift`) is backed by this machinery:
// `AnyLayoutBox` erases a concrete `Layout`'s associated `Cache` type;
// `ConcreteAnyLayoutBox` is the concrete eraser; `LayoutProxyBox` and
// `SendableLayoutWorkerProxy` drive measurement/placement on the main actor
// and the frame-tail worker respectively; `LayoutContainer` is the
// `PrimitiveView` that lowers a layout into a resolved node.
//
// Split out of `CustomLayout.swift` so that file stays the public custom-layout
// API surface. These five declarations are widened from `private` to
// file-internal (`internal` — module-wide, the minimal level) so `AnyLayout`'s
// initializers and `callAsFunction` can construct them across files. They form
// one closed dependency graph; no file outside this pair references them.

protocol AnyLayoutBox {
  var debugName: String { get }
  var builtinLayoutBehavior: LayoutBehavior? { get }
  var measurementReuseSignature: String? { get }
  var placementReuseSignature: String? { get }

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
  ) -> Int?

  func makeCache(subviews: LayoutSubviews) -> Any

  func updateCache(
    _ cache: inout Any,
    subviews: LayoutSubviews
  )

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Any
  ) -> LayoutSize

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Any
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
    (layout as? any MeasurementLayoutReuseProviding)?.measurementLayoutReuseSignature
  }

  var placementReuseSignature: String? {
    (layout as? any PlacementLayoutReuseProviding)?.placementLayoutReuseSignature
  }

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
  ) -> Int? {
    (layout as? any StackMinimumLayoutProviding)?
      .stackMinimumMainSize(axis: axis, idealSize: idealSize)
  }

  func makeCache(subviews: LayoutSubviews) -> Any {
    layout.makeCache(subviews: subviews)
  }

  func updateCache(
    _ cache: inout Any,
    subviews: LayoutSubviews
  ) {
    var typedCache = (cache as? L.Cache) ?? layout.makeCache(subviews: subviews)
    layout.updateCache(&typedCache, subviews: subviews)
    cache = typedCache
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Any
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
    cache: inout Any
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

final class SendableLayoutWorkerProxy<L: SendableLayout>: WorkerCustomLayoutProxy {
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
    var cache = preparedCache(
      for: node,
      proposal: proposal,
      subviews: subviews
    )
    let size = layout.sizeThatFits(
      proposal: proposal,
      subviews: subviews,
      cache: &cache
    )
    storeCache(cache, for: node, proposal: proposal)
    return size
  }

  package func stackMinimumMainSize(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: SwiftTUICore.Axis,
    passContext _: LayoutPassContext?
  ) -> Int? {
    (layout as? any StackMinimumLayoutProviding)?
      .stackMinimumMainSize(axis: axis, idealSize: idealMeasurement.measuredSize)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    let placementRecorder = LayoutSubviewPlacementRecorder()
    let subviews = layoutSubviews(
      for: node,
      engine: engine,
      placementRecorder: placementRecorder,
      passContext: passContext
    )
    var cache = preparedCache(
      for: node,
      proposal: measured.proposal,
      subviews: subviews
    )
    layout.placeSubviews(
      in: bounds,
      proposal: measured.proposal,
      subviews: subviews,
      cache: &cache
    )
    storeCache(cache, for: node, proposal: measured.proposal)
    // `Layout.Cache` is pass-local: retain measurement mutations through
    // placement, then drop every proposal entry for this container identity.
    discardPassLocalCacheStates(for: node.identity)

    return node.children.map { child in
      let placement =
        placementRecorder.placement(for: child.identity)
        ?? defaultPlacement(in: bounds, proposal: measured.proposal)
      let childMeasurement = engine.measure(
        child,
        proposal: placement.proposal,
        passContext: passContext
      )
      return engine.place(
        child,
        measured: childMeasurement,
        in: LayoutRect(
          origin: placedOrigin(
            for: childMeasurement.measuredSize,
            at: placement.position,
            anchor: placement.anchor
          ),
          size: childMeasurement.measuredSize
        ),
        viewportContext: placement.viewportContext,
        passContext: passContext
      )
    }
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

  private func preparedCache(
    for node: ResolvedNode,
    proposal: ProposedSize,
    subviews: LayoutSubviews
  ) -> L.Cache {
    // This map only bridges measurement to placement inside the current pass.
    // Placement discards all entries for the identity, so arbitrary author cache
    // values do not persist across frames, proposals, or structural changes.
    let key = CacheKey(identity: node.identity, proposal: proposal)
    var cache = state.withLock { state in
      state.cachedStates[key] ?? layout.makeCache(subviews: subviews)
    }
    layout.updateCache(&cache, subviews: subviews)
    return cache
  }

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

@MainActor
final class LayoutProxyBox: LayoutPassContextCustomLayoutProxy {
  private struct CacheKey: Hashable {
    var identity: Identity
    var proposal: ProposedSize
  }

  private let box: any AnyLayoutBox
  private var cachedStates: [CacheKey: Any] = [:]

  init(box: any AnyLayoutBox) {
    self.box = box
  }

  // `LayoutProxyBox` drives *non-Sendable* custom layouts, whose caches must
  // stay main-actor-isolated, so it must never run on the frame-tail layout
  // worker. `FrameTailLayoutOffloadEligibility` is meant to guarantee that, but
  // it is a hand-maintained tree walk; if it ever mis-classifies one of these
  // layouts, a bare `assumeIsolated` could (under the runtime's legacy executor
  // mode) proceed off-main and race the unsynchronized `cachedStates` — the
  // suspected mechanism behind the sanitizer-invisible run-loop SIGSEGV flake
  // (#1). Every entry point therefore bridges through `withCheckedMainActorAccess`,
  // whose `preconditionIsolated` turns that into a loud, attributable crash — in
  // release builds too — instead of silent memory corruption misattributed to the
  // "known flake".
  nonisolated var debugName: String {
    withCheckedMainActorAccess("LayoutProxyBox.debugName") { box.debugName }
  }

  private func ensureCache(
    for node: ResolvedNode,
    proposal: ProposedSize,
    subviews: [LayoutSubview]
  ) -> Any {
    // This map only bridges measurement to placement inside the current pass.
    // Placement discards all entries for the identity, so arbitrary author cache
    // values do not persist across frames, proposals, or structural changes.
    let key = CacheKey(identity: node.identity, proposal: proposal)

    if var existing = cachedStates[key] {
      box.updateCache(&existing, subviews: subviews)
      cachedStates[key] = existing
      return existing
    }

    var fresh = box.makeCache(subviews: subviews)
    box.updateCache(&fresh, subviews: subviews)
    cachedStates[key] = fresh
    return fresh
  }

  private func discardPassLocalCacheStates(
    for identity: Identity
  ) {
    cachedStates = cachedStates.filter { $0.key.identity != identity }
  }

  nonisolated func measureContainer(
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

  nonisolated package func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    withCheckedMainActorAccess("LayoutProxyBox.measureContainer") {
      let subviews = node.children.map { child in
        LayoutSubview(
          child: child,
          engine: engine,
          passContext: passContext
        )
      }
      var cache = ensureCache(
        for: node,
        proposal: proposal,
        subviews: subviews
      )
      let result = box.sizeThatFits(
        proposal: proposal,
        subviews: subviews,
        cache: &cache
      )
      cachedStates[CacheKey(identity: node.identity, proposal: proposal)] = cache
      return result
    }
  }

  nonisolated package func stackMinimumMainSize(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: SwiftTUICore.Axis,
    passContext _: LayoutPassContext?
  ) -> Int? {
    withCheckedMainActorAccess("LayoutProxyBox.stackMinimumMainSize") {
      box.stackMinimumMainSize(axis: axis, idealSize: idealMeasurement.measuredSize)
    }
  }

  nonisolated func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    withCheckedMainActorAccess("LayoutProxyBox.placeSubviews") {
      placeSubviews(
        engine: engine,
        node: node,
        measured: measured,
        in: bounds,
        passContext: nil
      )
    }
  }

  nonisolated package func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    withCheckedMainActorAccess("LayoutProxyBox.placeSubviews") {
      let placementRecorder = LayoutSubviewPlacementRecorder()
      let subviews = node.children.map { child in
        LayoutSubview(
          child: child,
          engine: engine,
          placementRecorder: placementRecorder,
          passContext: passContext
        )
      }
      let cacheKey = CacheKey(identity: node.identity, proposal: measured.proposal)
      var cache = ensureCache(
        for: node,
        proposal: measured.proposal,
        subviews: subviews
      )
      box.placeSubviews(
        in: bounds,
        proposal: measured.proposal,
        subviews: subviews,
        cache: &cache
      )
      cachedStates[cacheKey] = cache
      // `Layout.Cache` is pass-local: retain measurement mutations through
      // placement, then drop every proposal entry for this container identity.
      discardPassLocalCacheStates(for: node.identity)

      return node.children.map { child in
        let placement =
          placementRecorder.placement(for: child.identity)
          ?? defaultPlacement(in: bounds, proposal: measured.proposal)
        let childMeasurement = engine.measure(
          child,
          proposal: placement.proposal,
          passContext: passContext
        )
        return engine.place(
          child,
          measured: childMeasurement,
          in: LayoutRect(
            origin: placedOrigin(
              for: childMeasurement.measuredSize,
              at: placement.position,
              anchor: placement.anchor
            ),
            size: childMeasurement.measuredSize
          ),
          viewportContext: placement.viewportContext,
          passContext: passContext
        )
      }
    }
  }
}

struct LayoutContainer<Content: View>: PrimitiveView, ResolvableView {
  var layout: AnyLayout
  var authoringScope: AuthoringContext?
  var content: Content

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // AnyView policy: layout containers must flatten builder output at the
    // `resolveElements` layer, not after `normalizeResolvedElements`. If we
    // resolved each authored child as a single node, any direct child that
    // produces multiple elements (for example `ForEach`) would be collapsed
    // into an implicit `Group`, and the layout would see one overlapping
    // subview instead of distinct siblings.
    let resolvedChildren = withAuthoringContext(authoringScope) {
      resolveDeclaredChildren(
        content,
        in: context,
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

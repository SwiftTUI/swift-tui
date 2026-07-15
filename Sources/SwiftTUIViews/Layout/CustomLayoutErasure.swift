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

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
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

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
  ) -> Int? {
    (layout as? any StackMinimumLayoutProviding)?
      .stackMinimumMainSize(axis: axis, idealSize: idealSize)
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

public import SwiftTUICore
import Synchronization

/// Declares a typed value exchanged between a parent layout and its subviews.
public protocol LayoutValueKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

// `LayoutSubviewPlacementRecord`, `LayoutSubviewPlacementRecorder`,
// `defaultPlacement`, and `placedOrigin` live in
// `CustomLayoutPlacementGeometry.swift`.

/// A layout-facing handle for a resolved child view.
public struct LayoutSubview {
  fileprivate let child: ResolvedNode
  fileprivate let engine: LayoutEngine
  fileprivate let placementRecorder: LayoutSubviewPlacementRecorder?
  fileprivate let passContext: LayoutPassContext?

  fileprivate init(
    child: ResolvedNode,
    engine: LayoutEngine,
    placementRecorder: LayoutSubviewPlacementRecorder? = nil,
    passContext: LayoutPassContext? = nil
  ) {
    self.child = child
    self.engine = engine
    self.placementRecorder = placementRecorder
    self.passContext = passContext
  }

  /// The child's declared layout priority.
  public var layoutPriority: Double {
    child.layoutMetadata.layoutPriority
  }

  /// Whether the child resists horizontal compression.
  public var fixedSizeHorizontal: Bool {
    child.layoutMetadata.fixedSizeHorizontal
  }

  /// Whether the child resists vertical compression.
  public var fixedSizeVertical: Bool {
    child.layoutMetadata.fixedSizeVertical
  }

  /// The child's preferred surrounding spacing.
  public var spacing: ViewSpacing {
    ViewSpacing(
      horizontal: child.layoutMetadata.spacing.horizontal,
      vertical: child.layoutMetadata.spacing.vertical
    )
  }

  public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
    child.layoutMetadata.layoutValue(
      for: ObjectIdentifier(K.self),
      as: K.Value.self
    ) ?? K.defaultValue
  }

  /// Measures the child under `proposal`.
  public func sizeThatFits(_ proposal: ProposedViewSize) -> LayoutSize {
    engine.measure(
      child,
      proposal: proposal,
      passContext: passContext
    ).measuredSize
  }

  /// Returns layout dimensions for the child under `proposal`.
  public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
    engine.dimensions(
      of: child,
      proposal: proposal,
      passContext: passContext
    )
  }

  /// Places the child at `position` using `anchor` and `proposal`.
  public func place(
    at position: LayoutPoint,
    anchor: Alignment = .topLeading,
    proposal: ProposedViewSize
  ) {
    place(
      at: position,
      anchor: anchor,
      proposal: proposal,
      viewportContext: nil
    )
  }

  package func place(
    at position: LayoutPoint,
    anchor: Alignment = .topLeading,
    proposal: ProposedViewSize,
    viewportContext: ScrollViewportContext?
  ) {
    placementRecorder?.record(
      identity: child.identity,
      placement: .init(
        position: position,
        anchor: anchor,
        proposal: proposal,
        viewportContext: viewportContext
      )
    )
  }
}

/// Convenience alias used by custom layout implementations.
public typealias LayoutSubviews = [LayoutSubview]
/// A custom layout algorithm.
public protocol Layout {
  associatedtype Cache = Void

  func makeCache(subviews: LayoutSubviews) -> Cache

  func updateCache(
    _ cache: inout Cache,
    subviews: LayoutSubviews
  )

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Cache
  ) -> LayoutSize

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Cache
  )
}

/// A custom layout whose value and cache can be evaluated on the frame-tail
/// worker.
///
/// Conforming to this protocol is an opt-in contract: the layout value, its
/// cache, and any state captured by its callbacks must be safe to use away from
/// the main actor. Layouts that conform to `Layout` but not `SendableLayout`
/// remain correct and continue to run through the main-actor custom-layout
/// bridge.
public protocol SendableLayout: Layout, Sendable where Cache: Sendable {
  /// A stable signature for measurement reuse across frames.
  ///
  /// Include every layout value field that can change measurement. Two layout
  /// instances with the same measurement signature may reuse retained
  /// measurement work.
  var measurementReuseSignature: String { get }

  /// A stable signature for placement reuse across frames.
  ///
  /// Include every layout value field that can change placement. Two layout
  /// instances with the same placement signature may reuse retained placement
  /// work.
  var placementReuseSignature: String { get }
}

extension Layout {
  public func updateCache(
    _ cache: inout Cache,
    subviews: LayoutSubviews
  ) {
    cache = makeCache(subviews: subviews)
  }

  @MainActor
  public func callAsFunction<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    return LayoutContainer(
      layout: AnyLayout(self),
      authoringScope: currentAuthoringContext(),
      content: content()
    )
  }
}

extension SendableLayout {
  @MainActor
  public func callAsFunction<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    return LayoutContainer(
      layout: AnyLayout(self),
      authoringScope: currentAuthoringContext(),
      content: content()
    )
  }
}

extension Layout where Cache == Void {
  public func makeCache(subviews _: LayoutSubviews) {}
}

protocol BuiltinLayoutBehaviorProviding {
  var builtinLayoutBehavior: LayoutBehavior { get }
}

package protocol StackMinimumLayoutProviding {
  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
  ) -> Int?
}

private protocol AnyLayoutBox {
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

package protocol MeasurementLayoutReuseProviding {
  var measurementLayoutReuseSignature: String { get }
}

package protocol PlacementLayoutReuseProviding {
  var placementLayoutReuseSignature: String { get }
}

private struct ConcreteAnyLayoutBox<L: Layout>: AnyLayoutBox {
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

private final class SendableLayoutWorkerProxy<L: SendableLayout>: WorkerCustomLayoutProxy {
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
    discardCachedStates(for: node.identity)

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

  private func discardCachedStates(
    for identity: Identity
  ) {
    state.withLock { state in
      state.cachedStates = state.cachedStates.filter { $0.key.identity != identity }
    }
  }
}

/// A type-erased custom layout.
public struct AnyLayout: Layout {
  /// The type-erased cache storage used by `AnyLayout`.
  public struct Cache {
    fileprivate var storage: Any
  }

  private let box: any AnyLayoutBox
  private let customLayoutHandle: CustomLayoutHandle?

  /// Reuses the underlying box from another `AnyLayout`.
  public init(_ layout: AnyLayout) {
    box = layout.box
    customLayoutHandle = layout.customLayoutHandle
  }

  /// Erases a concrete layout type.
  @MainActor
  public init<L: Layout>(_ layout: L) {
    let box = ConcreteAnyLayoutBox(layout: layout)
    self.box = box
    if box.builtinLayoutBehavior == nil {
      let proxyBox = LayoutProxyBox(box: box)
      customLayoutHandle = CustomLayoutHandle(
        proxyBox,
        measurementReuseSignature: box.measurementReuseSignature,
        placementReuseSignature: box.placementReuseSignature,
        placementHandler: { engine, node, measured, bounds, passContext in
          proxyBox.placeSubviews(
            engine: engine,
            node: node,
            measured: measured,
            in: bounds,
            passContext: passContext
          )
        },
        stackMinimumMainSizeHandler: { engine, node, idealMeasurement, axis, passContext in
          proxyBox.stackMinimumMainSize(
            engine: engine,
            node: node,
            idealMeasurement: idealMeasurement,
            axis: axis,
            passContext: passContext
          )
        }
      )
    } else {
      customLayoutHandle = nil
    }
  }

  /// Erases a worker-safe layout value.
  @MainActor
  public init<L: SendableLayout>(_ layout: L) {
    let box = ConcreteAnyLayoutBox(layout: layout)
    self.box = box
    if box.builtinLayoutBehavior == nil {
      let proxyBox = LayoutProxyBox(box: box)
      let workerProxy = SendableLayoutWorkerProxy(layout: layout)
      customLayoutHandle = CustomLayoutHandle(
        proxyBox,
        measurementReuseSignature: layout.measurementReuseSignature,
        placementReuseSignature: layout.placementReuseSignature,
        workerProxy: workerProxy,
        placementHandler: { engine, node, measured, bounds, passContext in
          proxyBox.placeSubviews(
            engine: engine,
            node: node,
            measured: measured,
            in: bounds,
            passContext: passContext
          )
        },
        stackMinimumMainSizeHandler: { engine, node, idealMeasurement, axis, passContext in
          workerProxy.stackMinimumMainSize(
            engine: engine,
            node: node,
            idealMeasurement: idealMeasurement,
            axis: axis,
            passContext: passContext
          )
        }
      )
    } else {
      customLayoutHandle = nil
    }
  }

  fileprivate var debugName: String {
    box.debugName
  }

  package var resolvedBehavior: LayoutBehavior {
    if let builtinLayoutBehavior = box.builtinLayoutBehavior {
      return builtinLayoutBehavior
    }
    return .custom(customLayoutHandle!)
  }

  public func makeCache(subviews: LayoutSubviews) -> Cache {
    Cache(storage: box.makeCache(subviews: subviews))
  }

  public func updateCache(
    _ cache: inout Cache,
    subviews: LayoutSubviews
  ) {
    box.updateCache(&cache.storage, subviews: subviews)
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Cache
  ) -> LayoutSize {
    box.sizeThatFits(
      proposal: proposal,
      subviews: subviews,
      cache: &cache.storage
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Cache
  ) {
    box.placeSubviews(
      in: bounds,
      proposal: proposal,
      subviews: subviews,
      cache: &cache.storage
    )
  }
}

extension AnyLayout {
  @MainActor
  public func callAsFunction<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    return LayoutContainer(
      layout: self,
      authoringScope: currentAuthoringContext(),
      content: content()
    )
  }
}

private struct LayoutContainer<Content: View>: PrimitiveView, ResolvableView {
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

@MainActor
private final class LayoutProxyBox: LayoutPassContextCustomLayoutProxy {
  private struct CacheKey: Hashable {
    var identity: Identity
    var proposal: ProposedSize
  }

  private let box: any AnyLayoutBox
  private var cachedStates: [CacheKey: Any] = [:]

  init(box: any AnyLayoutBox) {
    self.box = box
  }

  nonisolated var debugName: String {
    MainActor.assumeIsolated { box.debugName }
  }

  private func ensureCache(
    for node: ResolvedNode,
    proposal: ProposedSize,
    subviews: [LayoutSubview]
  ) -> Any {
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

  private func discardCachedStates(
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
    MainActor.assumeIsolated {
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
    MainActor.assumeIsolated {
      box.stackMinimumMainSize(axis: axis, idealSize: idealMeasurement.measuredSize)
    }
  }

  nonisolated func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    MainActor.assumeIsolated {
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
    MainActor.assumeIsolated {
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
      discardCachedStates(for: node.identity)

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

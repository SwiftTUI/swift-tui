public import Core

/// Declares a typed value exchanged between a parent layout and its subviews.
public protocol LayoutValueKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

private struct LayoutSubviewPlacementRecord {
  var position: LayoutPoint
  var anchor: UnitPoint
  var proposal: ProposedViewSize
  var viewportContext: ScrollViewportContext?
}

private final class LayoutSubviewPlacementRecorder {
  private var placements: [Identity: LayoutSubviewPlacementRecord] = [:]

  func record(identity: Identity, placement: LayoutSubviewPlacementRecord) {
    placements[identity] = placement
  }

  func placement(for identity: Identity) -> LayoutSubviewPlacementRecord? {
    placements[identity]
  }
}

/// A layout-facing handle for a resolved child view.
public struct LayoutSubview {
  fileprivate let child: ResolvedNode
  fileprivate let engine: LayoutEngine
  fileprivate let placementRecorder: LayoutSubviewPlacementRecorder?

  fileprivate init(
    child: ResolvedNode,
    engine: LayoutEngine,
    placementRecorder: LayoutSubviewPlacementRecorder? = nil
  ) {
    self.child = child
    self.engine = engine
    self.placementRecorder = placementRecorder
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
    engine.measure(child, proposal: proposal).measuredSize
  }

  /// Returns layout dimensions for the child under `proposal`.
  public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
    engine.dimensions(of: child, proposal: proposal)
  }

  /// Places the child at `position` using `anchor` and `proposal`.
  public func place(
    at position: LayoutPoint,
    anchor: UnitPoint = .topLeading,
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
    anchor: UnitPoint = .topLeading,
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
    LayoutContainer(
      layout: AnyLayout(self),
      content: content()
    )
  }
}

extension Layout where Cache == Void {
  public func makeCache(subviews _: LayoutSubviews) {}
}

private protocol BuiltinLayoutBehaviorProviding {
  var builtinLayoutBehavior: LayoutBehavior { get }
}

private protocol AnyLayoutBox {
  var debugName: String { get }
  var builtinLayoutBehavior: LayoutBehavior? { get }
  var measurementReuseSignature: String? { get }

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
        placementHandler: { engine, node, measured, bounds, passContext in
          proxyBox.placeSubviews(
            engine: engine,
            node: node,
            measured: measured,
            in: bounds,
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
    LayoutContainer(
      layout: self,
      content: content()
    )
  }
}

/// The layout algorithm underlying `HStack`.
public struct HStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: VerticalAlignment
  public var spacing: Int?

  /// Creates a horizontal stack layout.
  public init(
    alignment: VerticalAlignment = .center,
    spacing: Int? = nil
  ) {
    self.alignment = alignment
    self.spacing = spacing
  }

  fileprivate var builtinLayoutBehavior: LayoutBehavior {
    .stack(
      axis: .horizontal,
      spacing: spacing,
      horizontalAlignment: .center,
      verticalAlignment: alignment
    )
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    simpleStackSize(
      axis: .horizontal,
      horizontalAlignment: .center,
      verticalAlignment: alignment,
      spacing: spacing,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeSimpleStack(
      axis: .horizontal,
      horizontalAlignment: .center,
      verticalAlignment: alignment,
      spacing: spacing,
      in: bounds,
      subviews: subviews
    )
  }
}

/// The layout algorithm underlying `VStack`.
public struct VStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: HorizontalAlignment
  public var spacing: Int?

  /// Creates a vertical stack layout.
  public init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil
  ) {
    self.alignment = alignment
    self.spacing = spacing
  }

  fileprivate var builtinLayoutBehavior: LayoutBehavior {
    .stack(
      axis: .vertical,
      spacing: spacing,
      horizontalAlignment: alignment,
      verticalAlignment: .center
    )
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    simpleStackSize(
      axis: .vertical,
      horizontalAlignment: alignment,
      verticalAlignment: .center,
      spacing: spacing,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeSimpleStack(
      axis: .vertical,
      horizontalAlignment: alignment,
      verticalAlignment: .center,
      spacing: spacing,
      in: bounds,
      subviews: subviews
    )
  }
}

/// The layout algorithm underlying `ZStack`.
public struct ZStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: Alignment

  /// Creates a z-axis stack layout.
  public init(alignment: Alignment = .center) {
    self.alignment = alignment
  }

  fileprivate var builtinLayoutBehavior: LayoutBehavior {
    .overlay(alignment: alignment)
  }

  public func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let dimensions = subviews.map { $0.dimensions(in: .unspecified) }
    let alignmentMetrics = overlayAlignmentMetrics(
      dimensions: dimensions,
      alignment: alignment
    )
    return LayoutSize(
      width: alignmentMetrics.leading + alignmentMetrics.trailing,
      height: alignmentMetrics.top + alignmentMetrics.bottom
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeOverlaySubviews(
      alignment: alignment,
      in: bounds,
      subviews: subviews
    )
  }
}

private struct LayoutContainer<Content: View>: View, ResolvableView {
  var layout: AnyLayout
  var content: Content

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "Layout"
    )

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

package struct LayoutValueModifier<Key: LayoutValueKey, Content: View>: View, ResolvableView {
  var content: Content
  var value: Key.Value

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingLayoutValue(
      value,
      for: ObjectIdentifier(Key.self),
      debugName: String(reflecting: Key.self),
      debugValue: String(describing: value)
    )
    return [node]
  }
}

package struct HorizontalAlignmentGuideModifier<Content: View>: View, ResolvableView {
  var content: Content
  var alignment: HorizontalAlignment
  var computeValue: @Sendable (ViewDimensions) -> Int

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingHorizontalAlignmentGuide(
      alignment,
      debugName: alignment.debugName,
      computeValue: computeValue
    )
    return [node]
  }
}

package struct VerticalAlignmentGuideModifier<Content: View>: View, ResolvableView {
  var content: Content
  var alignment: VerticalAlignment
  var computeValue: @Sendable (ViewDimensions) -> Int

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingVerticalAlignmentGuide(
      alignment,
      debugName: alignment.debugName,
      computeValue: computeValue
    )
    return [node]
  }
}

@MainActor
private final class LayoutProxyBox: CustomLayoutProxy {
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
  ) -> Size {
    MainActor.assumeIsolated {
      let subviews = node.children.map { child in
        LayoutSubview(child: child, engine: engine)
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

  nonisolated func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect
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
    in bounds: Rect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    MainActor.assumeIsolated {
      let placementRecorder = LayoutSubviewPlacementRecorder()
      let subviews = node.children.map { child in
        LayoutSubview(
          child: child,
          engine: engine,
          placementRecorder: placementRecorder
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

private func simpleStackSize(
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment,
  spacing: Int?,
  proposal: ProposedViewSize,
  subviews: LayoutSubviews
) -> LayoutSize {
  let idealProposal: ProposedViewSize =
    switch axis {
    case .horizontal:
      .init(width: .unspecified, height: proposal.height)
    case .vertical:
      .init(width: proposal.width, height: .unspecified)
    }

  let dimensions = subviews.map { $0.dimensions(in: idealProposal) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let stackSpacings = resolvedStackSpacings(
    for: subviews,
    axis: axis,
    spacingOverride: spacing
  )
  let totalSpacing = stackSpacings.reduce(0, +)
  let crossMetrics = stackCrossMetrics(
    dimensions: dimensions,
    axis: axis,
    horizontalAlignment: horizontalAlignment,
    verticalAlignment: verticalAlignment
  )

  switch axis {
  case .horizontal:
    return LayoutSize(
      width: sizes.reduce(0) { $0 + $1.width } + totalSpacing,
      height: crossMetrics.leading + crossMetrics.trailing
    )
  case .vertical:
    return LayoutSize(
      width: crossMetrics.leading + crossMetrics.trailing,
      height: sizes.reduce(0) { $0 + $1.height } + totalSpacing
    )
  }
}

private func placeSimpleStack(
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment,
  spacing: Int?,
  in bounds: LayoutRect,
  subviews: LayoutSubviews
) {
  let idealProposal: ProposedViewSize =
    switch axis {
    case .horizontal:
      .init(width: .unspecified, height: .finite(bounds.size.height))
    case .vertical:
      .init(width: .finite(bounds.size.width), height: .unspecified)
    }

  let dimensions = subviews.map { $0.dimensions(in: idealProposal) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let stackSpacings = resolvedStackSpacings(
    for: subviews,
    axis: axis,
    spacingOverride: spacing
  )
  let crossMetrics = stackCrossMetrics(
    dimensions: dimensions,
    axis: axis,
    horizontalAlignment: horizontalAlignment,
    verticalAlignment: verticalAlignment
  )

  var cursor = axis == .horizontal ? bounds.origin.x : bounds.origin.y
  for (index, subview) in subviews.enumerated() {
    let size = sizes[index]
    let origin =
      switch axis {
      case .horizontal:
        LayoutPoint(
          x: cursor,
          y: bounds.origin.y + crossMetrics.leading - dimensions[index][verticalAlignment]
        )
      case .vertical:
        LayoutPoint(
          x: bounds.origin.x + crossMetrics.leading - dimensions[index][horizontalAlignment],
          y: cursor
        )
      }
    subview.place(
      at: origin,
      anchor: .topLeading,
      proposal: .init(width: size.width, height: size.height)
    )
    cursor += axis == .horizontal ? size.width : size.height
    if index < stackSpacings.count {
      cursor += stackSpacings[index]
    }
  }
}

private func resolvedStackSpacings(
  for subviews: LayoutSubviews,
  axis: Axis,
  spacingOverride: Int?
) -> [Int] {
  guard subviews.count > 1 else {
    return []
  }

  if let spacingOverride {
    return Array(repeating: spacingOverride, count: subviews.count - 1)
  }

  return subviews.indices.dropLast().map { index in
    subviews[index].spacing.distance(
      to: subviews[index + 1].spacing,
      along: axis == .horizontal ? .horizontal : .vertical
    )
  }
}

private func stackCrossMetrics(
  dimensions: [ViewDimensions],
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment
) -> (leading: Int, trailing: Int) {
  switch axis {
  case .horizontal:
    let leading = dimensions.map { max(0, $0[verticalAlignment]) }.max() ?? 0
    let trailing = dimensions.map { max(0, $0.height - $0[verticalAlignment]) }.max() ?? 0
    return (leading, trailing)
  case .vertical:
    let leading = dimensions.map { max(0, $0[horizontalAlignment]) }.max() ?? 0
    let trailing = dimensions.map { max(0, $0.width - $0[horizontalAlignment]) }.max() ?? 0
    return (leading, trailing)
  }
}

private func overlayAlignmentMetrics(
  dimensions: [ViewDimensions],
  alignment: Alignment
) -> (leading: Int, trailing: Int, top: Int, bottom: Int) {
  let leading = dimensions.map { max(0, $0[alignment.horizontal]) }.max() ?? 0
  let trailing = dimensions.map { max(0, $0.width - $0[alignment.horizontal]) }.max() ?? 0
  let top = dimensions.map { max(0, $0[alignment.vertical]) }.max() ?? 0
  let bottom = dimensions.map { max(0, $0.height - $0[alignment.vertical]) }.max() ?? 0

  return (leading, trailing, top, bottom)
}

private func placeOverlaySubviews(
  alignment: Alignment,
  in bounds: LayoutRect,
  subviews: LayoutSubviews
) {
  let dimensions = subviews.map { $0.dimensions(in: .unspecified) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let alignmentMetrics = overlayAlignmentMetrics(
    dimensions: dimensions,
    alignment: alignment
  )

  for (index, subview) in subviews.enumerated() {
    subview.place(
      at: LayoutPoint(
        x: bounds.origin.x + alignmentMetrics.leading - dimensions[index][alignment.horizontal],
        y: bounds.origin.y + alignmentMetrics.top - dimensions[index][alignment.vertical]
      ),
      anchor: .topLeading,
      proposal: .init(width: sizes[index].width, height: sizes[index].height)
    )
  }
}

private func defaultPlacement(
  in bounds: LayoutRect,
  proposal: ProposedViewSize
) -> LayoutSubviewPlacementRecord {
  LayoutSubviewPlacementRecord(
    position: LayoutPoint(
      x: bounds.origin.x + (bounds.size.width / 2),
      y: bounds.origin.y + (bounds.size.height / 2)
    ),
    anchor: .center,
    proposal: proposal
  )
}

private func placedOrigin(
  for childSize: LayoutSize,
  at position: LayoutPoint,
  anchor: UnitPoint
) -> LayoutPoint {
  let dimensions = ViewDimensions(width: childSize.width, height: childSize.height)
  let xOffset =
    if anchor.horizontal == .center {
      (childSize.width + 1) / 2
    } else {
      dimensions[anchor.horizontal]
    }
  let yOffset =
    if anchor.vertical == .center {
      (childSize.height + 1) / 2
    } else {
      dimensions[anchor.vertical]
    }

  return LayoutPoint(
    x: position.x - xOffset,
    y: position.y - yOffset
  )
}

public import SwiftTUICore

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

  // Widened from `fileprivate` to file-internal so the layout proxies in
  // `CustomLayoutErasure.swift` can construct `LayoutSubview` values.
  init(
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
  /// Scratch state for one measure/place layout pass.
  ///
  /// SwiftTUI shares this cache between ``sizeThatFits(proposal:subviews:cache:)``
  /// and ``placeSubviews(in:proposal:subviews:cache:)`` for the same container
  /// identity and proposal in a single pass. The cache is discarded after
  /// placement, so custom layouts must not rely on it persisting across frames,
  /// proposals, structural changes, or binding-driven invalidations. SwiftTUI
  /// intentionally does not expose a cross-frame cache reuse hook; store durable
  /// layout state outside `Cache`.
  associatedtype Cache = Void

  /// Creates the pass-local scratch cache for this layout.
  func makeCache(subviews: LayoutSubviews) -> Cache

  /// Refreshes a pass-local cache before measurement or placement.
  func updateCache(
    _ cache: inout Cache,
    subviews: LayoutSubviews
  )

  /// Returns this layout's measured size and may write data needed later in
  /// ``placeSubviews(in:proposal:subviews:cache:)`` to `cache`.
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Cache
  ) -> LayoutSize

  /// Places this layout's subviews using the same pass-local cache produced for
  /// measurement when measurement and placement happen in the same pass.
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

// `AnyLayoutBox` and the type-erasure engine live in
// `CustomLayoutErasure.swift`.

package protocol MeasurementLayoutReuseProviding {
  var measurementLayoutReuseSignature: String { get }
}

package protocol PlacementLayoutReuseProviding {
  var placementLayoutReuseSignature: String { get }
}

// `ConcreteAnyLayoutBox` and `SendableLayoutWorkerProxy` live in
// `CustomLayoutErasure.swift`.

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

  // Widened from `fileprivate` to file-internal so `LayoutContainer` (in
  // `CustomLayoutErasure.swift`) can read the layout's debug name.
  var debugName: String {
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

// `LayoutContainer` and `LayoutProxyBox` live in `CustomLayoutErasure.swift`.

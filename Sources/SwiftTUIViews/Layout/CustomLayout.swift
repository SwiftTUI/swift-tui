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

  /// Like ``sizeThatFits(_:)``, but declares the measure-time viewport the
  /// calling scroll layout will show this content through, so lazy
  /// containers in the subtree can bound realization and measurement to the
  /// visible band (proposal 2026-07-13-002 Stage 2.2). The hint is scoped to
  /// exactly this measurement.
  package func sizeThatFits(
    _ proposal: ProposedViewSize,
    measureViewport hint: MeasureViewportHint?
  ) -> LayoutSize {
    guard let passContext, let hint else {
      return sizeThatFits(proposal)
    }
    return passContext.withMeasureViewportHint(hint) {
      engine.measure(
        child,
        proposal: proposal,
        passContext: passContext
      ).measuredSize
    }
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
        exactSize: nil,
        viewportContext: viewportContext
      )
    )
  }

  func place(
    at position: LayoutPoint,
    proposal: ProposedViewSize,
    exactSize: LayoutSize
  ) {
    placementRecorder?.record(
      identity: child.identity,
      placement: .init(
        position: position,
        anchor: .topLeading,
        proposal: proposal,
        exactSize: exactSize,
        viewportContext: nil
      )
    )
  }
}

func builtinLayoutSize(
  behavior: LayoutBehavior,
  proposal: ProposedViewSize,
  subviews: LayoutSubviews
) -> LayoutSize {
  guard let first = subviews.first else {
    return .zero
  }
  return first.engine.measureBuiltinLayout(
    behavior: behavior,
    children: subviews.map(\.child),
    proposal: proposal,
    passContext: first.passContext
  ).measuredSize
}

func placeBuiltinLayoutSubviews(
  behavior: LayoutBehavior,
  in bounds: LayoutRect,
  proposal: ProposedViewSize,
  subviews: LayoutSubviews
) {
  guard let first = subviews.first else {
    return
  }
  let placements = first.engine.placeBuiltinLayout(
    behavior: behavior,
    children: subviews.map(\.child),
    proposal: proposal,
    in: bounds,
    passContext: first.passContext
  )
  precondition(
    placements.count == subviews.count,
    "builtin Layout delegation produced a mismatched child placement count"
  )
  for (subview, placement) in zip(subviews, placements) {
    subview.place(
      at: placement.bounds.origin,
      proposal: placement.proposal,
      exactSize: placement.bounds.size
    )
  }
}

/// A layout that declares the measure-time viewport it shows its content
/// through (a scroll layout), so lazy containers below it can window
/// realization and measurement (proposal 2026-07-13-002 Stage 2.2). The
/// custom-layout machinery consults this at engine measure entries that
/// bypass the layout's own `sizeThatFits` (the child pre-measure).
protocol MeasureViewportDeclaringLayout {
  func declaredMeasureViewport(for proposal: ProposedViewSize) -> MeasureViewportHint?
}

/// Convenience alias used by custom layout implementations.
public typealias LayoutSubviews = [LayoutSubview]
/// A custom layout algorithm.
///
/// A layout is a `Sendable` value: SwiftTUI may evaluate
/// ``sizeThatFits(proposal:subviews:cache:)`` and
/// ``placeSubviews(in:proposal:subviews:cache:)`` on the frame-tail layout
/// worker, away from the main actor. Store only value-semantic,
/// concurrency-safe state in a layout; read mutable app state before
/// constructing the layout and pass the resolved values in.
public protocol Layout: Sendable {
  /// Scratch state for one measure/place layout pass.
  ///
  /// SwiftTUI shares this cache between ``sizeThatFits(proposal:subviews:cache:)``
  /// and ``placeSubviews(in:proposal:subviews:cache:)`` for the same container
  /// identity and proposal in a single pass. The cache is discarded after
  /// placement, so custom layouts must not rely on it persisting across frames,
  /// proposals, structural changes, or binding-driven invalidations. SwiftTUI
  /// intentionally does not expose a cross-frame cache reuse hook; store durable
  /// layout state outside `Cache`. The cache must be `Sendable` because layout
  /// passes can run on the frame-tail worker.
  associatedtype Cache: Sendable = Void

  /// A stable signature for measurement reuse across frames, or `nil` to opt
  /// out of cross-frame measurement reuse.
  ///
  /// Include every layout value field that can change measurement. Two layout
  /// instances with the same measurement signature may reuse retained
  /// measurement work.
  var measurementReuseSignature: String? { get }

  /// A stable signature for placement reuse across frames, or `nil` to opt
  /// out of cross-frame placement reuse.
  ///
  /// Include every layout value field that can change placement. Two layout
  /// instances with the same placement signature may reuse retained placement
  /// work.
  var placementReuseSignature: String? { get }

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

extension Layout {
  /// Layouts opt out of cross-frame measurement reuse by default.
  public var measurementReuseSignature: String? { nil }

  /// Layouts opt out of cross-frame placement reuse by default.
  public var placementReuseSignature: String? { nil }

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

// `AnyLayoutBox`, `ConcreteAnyLayoutBox`, and `LayoutWorkerProxy` live in
// `CustomLayoutErasure.swift`.

/// A type-erased custom layout.
public struct AnyLayout: Layout {
  /// The type-erased cache storage used by `AnyLayout`.
  public struct Cache: Sendable {
    fileprivate var storage: any Sendable
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
      let workerProxy = LayoutWorkerProxy(layout: layout)
      customLayoutHandle = CustomLayoutHandle(
        workerProxy,
        measurementReuseSignature: layout.measurementReuseSignature,
        placementReuseSignature: layout.placementReuseSignature,
        workerProxy: workerProxy,
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

  /// Forwards the erased layout's measurement reuse signature.
  public var measurementReuseSignature: String? {
    box.measurementReuseSignature
  }

  /// Forwards the erased layout's placement reuse signature.
  public var placementReuseSignature: String? {
    box.placementReuseSignature
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

// `LayoutContainer` lives in `CustomLayoutErasure.swift`.

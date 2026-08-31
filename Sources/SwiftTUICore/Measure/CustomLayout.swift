package protocol CustomLayoutProxy: AnyObject, Sendable {
  var debugName: String { get }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> CellSize

  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> [MeasuredNode]

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode]
}

extension CustomLayoutProxy {
  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> [MeasuredNode] {
    node.children.map { child in
      engine.measure(child, proposal: proposal)
    }
  }
}

package protocol LayoutPassContextCustomLayoutProxy: CustomLayoutProxy {
  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize

  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode]

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode]
}

extension LayoutPassContextCustomLayoutProxy {
  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    node.children.map { child in
      engine.measure(child, proposal: proposal, passContext: passContext)
    }
  }
}

/// Interface implemented by custom layouts that can execute on the frame-tail
/// worker without crossing a main-actor-isolated proxy.
package protocol WorkerCustomLayoutProxy: Sendable {
  var debugName: String { get }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize

  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode]

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode]
}

extension WorkerCustomLayoutProxy {
  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    node.children.map { child in
      engine.measure(child, proposal: proposal, passContext: passContext)
    }
  }
}

/// Sendable closure-backed snapshot for custom layouts that can execute on the
/// frame-tail worker.
package struct WorkerCustomLayoutSnapshot: WorkerCustomLayoutProxy {
  package typealias MeasureContainerHandler =
    @Sendable (LayoutEngine, ResolvedNode, ProposedSize, LayoutPassContext?) -> CellSize
  package typealias MeasureChildrenHandler =
    @Sendable (LayoutEngine, ResolvedNode, ProposedSize, LayoutPassContext?) -> [MeasuredNode]
  package typealias PlaceSubviewsHandler =
    @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
    [PlacedNode]

  package var debugName: String
  private let measureContainerHandler: MeasureContainerHandler
  private let measureChildrenHandler: MeasureChildrenHandler?
  private let placeSubviewsHandler: PlaceSubviewsHandler

  package init(
    debugName: String,
    measureChildren: MeasureChildrenHandler? = nil,
    measureContainer: @escaping MeasureContainerHandler,
    placeSubviews: @escaping PlaceSubviewsHandler
  ) {
    self.debugName = debugName
    measureChildrenHandler = measureChildren
    measureContainerHandler = measureContainer
    placeSubviewsHandler = placeSubviews
  }

  package func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    measureContainerHandler(engine, node, proposal, passContext)
  }

  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    if let measureChildrenHandler {
      return measureChildrenHandler(engine, node, proposal, passContext)
    }
    return node.children.map { child in
      engine.measure(child, proposal: proposal, passContext: passContext)
    }
  }

  package func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    placeSubviewsHandler(engine, node, measured, bounds, passContext)
  }
}

/// Reference wrapper used to carry a custom layout through the pipeline.
package final class CustomLayoutHandle: CustomLayoutToken {
  /// The container-contract hooks (plan 2026-08-31-001). Each answers one
  /// question a *parent* asks about the container: its preferred outer
  /// spacing, and its own value for a horizontal or vertical alignment
  /// guide. The engine memoizes the answers on the pass context, so the
  /// author hook behind a handler runs once per question per pass.
  package typealias PreferredSpacingHandler =
    @Sendable (LayoutEngine, ResolvedNode, LayoutPassContext?) -> Spacing
  package typealias ExplicitHorizontalAlignmentHandler =
    @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, HorizontalAlignment, LayoutPassContext?)
    -> Int?
  package typealias ExplicitVerticalAlignmentHandler =
    @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, VerticalAlignment, LayoutPassContext?)
    -> Int?

  package let proxy: any CustomLayoutProxy
  package let workerProxy: (any WorkerCustomLayoutProxy)?
  package let measurementReuseSignature: String?
  package let placementReuseSignature: String?
  package let placementHandler:
    (
      @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
        [PlacedNode]
    )?
  package let stackMinimumMainSizeHandler:
    (
      @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, Axis, Int, LayoutPassContext?) -> Int?
    )?
  package let preferredSpacingHandler: PreferredSpacingHandler?
  package let explicitHorizontalAlignmentHandler: ExplicitHorizontalAlignmentHandler?
  package let explicitVerticalAlignmentHandler: ExplicitVerticalAlignmentHandler?

  package init(
    _ proxy: some CustomLayoutProxy,
    measurementReuseSignature: String? = nil,
    placementReuseSignature: String? = nil
  ) {
    self.proxy = proxy
    workerProxy = nil
    self.measurementReuseSignature = measurementReuseSignature
    self.placementReuseSignature = placementReuseSignature
    placementHandler = nil
    stackMinimumMainSizeHandler = nil
    preferredSpacingHandler = nil
    explicitHorizontalAlignmentHandler = nil
    explicitVerticalAlignmentHandler = nil
  }

  package init(
    _ proxy: some CustomLayoutProxy,
    measurementReuseSignature: String? = nil,
    placementReuseSignature: String? = nil,
    workerProxy: (any WorkerCustomLayoutProxy)? = nil,
    placementHandler:
      (
        @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
          [PlacedNode]
      )? = nil,
    stackMinimumMainSizeHandler:
      (
        @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, Axis, Int, LayoutPassContext?) -> Int?
      )? = nil,
    preferredSpacingHandler: PreferredSpacingHandler? = nil,
    explicitHorizontalAlignmentHandler: ExplicitHorizontalAlignmentHandler? = nil,
    explicitVerticalAlignmentHandler: ExplicitVerticalAlignmentHandler? = nil
  ) {
    self.proxy = proxy
    self.measurementReuseSignature = measurementReuseSignature
    self.placementReuseSignature = placementReuseSignature
    self.workerProxy = workerProxy
    self.placementHandler = placementHandler
    self.stackMinimumMainSizeHandler = stackMinimumMainSizeHandler
    self.preferredSpacingHandler = preferredSpacingHandler
    self.explicitHorizontalAlignmentHandler = explicitHorizontalAlignmentHandler
    self.explicitVerticalAlignmentHandler = explicitVerticalAlignmentHandler
  }

  package var debugName: String {
    if let workerProxy {
      return workerProxy.debugName
    }
    return proxy.debugName
  }

  package var executionCapability: CustomLayoutExecutionCapability {
    workerProxy == nil ? .mainActorOnly : .worker
  }

  package var canRunOnWorker: Bool {
    workerProxy != nil
  }

  package func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    if let workerProxy {
      return workerProxy.measureContainer(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    if let proxy = proxy as? any LayoutPassContextCustomLayoutProxy {
      return proxy.measureContainer(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    return proxy.measureContainer(
      engine: engine,
      node: node,
      proposal: proposal
    )
  }

  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    if let workerProxy {
      return workerProxy.measureChildren(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    if let proxy = proxy as? any LayoutPassContextCustomLayoutProxy {
      return proxy.measureChildren(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    if passContext != nil {
      return node.children.map { child in
        engine.measure(child, proposal: proposal, passContext: passContext)
      }
    }
    return proxy.measureChildren(
      engine: engine,
      node: node,
      proposal: proposal
    )
  }

  package func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    if let workerProxy {
      return workerProxy.placeSubviews(
        engine: engine,
        node: node,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }
    if let proxy = proxy as? any LayoutPassContextCustomLayoutProxy {
      return proxy.placeSubviews(
        engine: engine,
        node: node,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }
    if let placementHandler {
      return placementHandler(engine, node, measured, bounds, passContext)
    }
    return proxy.placeSubviews(
      engine: engine,
      node: node,
      measured: measured,
      in: bounds
    )
  }

  package func stackMinimumMainSize(
    engine: LayoutEngine,
    node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis,
    contentMinimum: Int,
    passContext: LayoutPassContext?
  ) -> Int? {
    stackMinimumMainSizeHandler?(engine, node, idealMeasurement, axis, contentMinimum, passContext)
  }

  // MARK: Container contract (plan 2026-08-31-001)

  /// The layout's declared outer spacing, or `nil` when this handle carries
  /// no spacing hook (a main-actor-only proxy built without one). Memoized
  /// per identity on the pass context; without a pass context the hook runs
  /// for every question (direct engine callers, the structural min/max
  /// traversals).
  package func preferredSpacing(
    engine: LayoutEngine,
    node: ResolvedNode,
    passContext: LayoutPassContext?
  ) -> Spacing? {
    guard let preferredSpacingHandler else {
      return nil
    }
    if let memo = passContext?.customLayoutSpacingMemo(for: node.identity) {
      return memo
    }
    let spacing = preferredSpacingHandler(engine, node, passContext)
    passContext?.recordCustomLayoutSpacingMemo(spacing, for: node.identity)
    return spacing
  }

  /// Whether this handle can answer explicit alignment guides at all. A
  /// `false` lets the alignment fast paths skip the hook without asking.
  package var answersExplicitAlignment: Bool {
    explicitHorizontalAlignmentHandler != nil || explicitVerticalAlignmentHandler != nil
  }

  /// The container's own value for `guide` in its zero-origin bounds, or
  /// `nil` for the guide's default. Memoized per identity, proposal, and
  /// guide on the pass context.
  package func explicitAlignment(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    horizontalGuide guide: HorizontalAlignment,
    passContext: LayoutPassContext?
  ) -> Int? {
    guard let explicitHorizontalAlignmentHandler else {
      return nil
    }
    let key = CustomLayoutAlignmentMemoKey(
      identity: node.identity,
      proposal: measured.proposal,
      axis: .horizontal,
      guide: guide.key
    )
    if let memo = passContext?.customLayoutAlignmentMemo(for: key) {
      return memo
    }
    let answer = explicitHorizontalAlignmentHandler(engine, node, measured, guide, passContext)
    passContext?.recordCustomLayoutAlignmentMemo(answer, for: key)
    return answer
  }

  package func explicitAlignment(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    verticalGuide guide: VerticalAlignment,
    passContext: LayoutPassContext?
  ) -> Int? {
    guard let explicitVerticalAlignmentHandler else {
      return nil
    }
    let key = CustomLayoutAlignmentMemoKey(
      identity: node.identity,
      proposal: measured.proposal,
      axis: .vertical,
      guide: guide.key
    )
    if let memo = passContext?.customLayoutAlignmentMemo(for: key) {
      return memo
    }
    let answer = explicitVerticalAlignmentHandler(engine, node, measured, guide, passContext)
    passContext?.recordCustomLayoutAlignmentMemo(answer, for: key)
    return answer
  }
}

extension CustomLayoutHandle: Equatable {
  package static func == (lhs: CustomLayoutHandle, rhs: CustomLayoutHandle) -> Bool {
    lhs === rhs
  }
}

public import SwiftTUICore

/// A terminal-native geometry proxy.
public struct GeometryProxy: Equatable, Sendable {
  /// The terminal-cell extent assigned to the current geometry scope.
  public var size: CellSize
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics
  public var pointerInputCapabilities: PointerInputCapabilities
  package var bounds: CellRect
  package var placedFrameTable: PlacedFrameTable

  public init(
    size: CellSize,
    safeAreaInsets: EdgeInsets = .zero,
    cellPixelMetrics: CellPixelMetrics = .estimated,
    pointerInputCapabilities: PointerInputCapabilities = .cellOnly
  ) {
    self.size = size
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
    self.pointerInputCapabilities = pointerInputCapabilities
    bounds = CellRect(origin: .zero, size: size)
    placedFrameTable = .init()
  }

  package init(
    bounds: CellRect,
    safeAreaInsets: EdgeInsets = .zero,
    cellPixelMetrics: CellPixelMetrics = .estimated,
    pointerInputCapabilities: PointerInputCapabilities = .cellOnly,
    placedFrameTable: PlacedFrameTable = .init()
  ) {
    size = bounds.size
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
    self.pointerInputCapabilities = pointerInputCapabilities
    self.bounds = bounds
    self.placedFrameTable = placedFrameTable
  }

  /// Returns this geometry scope's frame in the supplied coordinate space.
  public func frame(
    in coordinateSpace: CoordinateSpace
  ) -> Rect {
    coordinateSpace.resolve(
      terminalRect: bounds.continuous,
      targetRect: bounds,
      namedCoordinateSpaces: placedFrameTable.namedCoordinateSpaces,
      diagnosticsRecorder: placedFrameTable.diagnosticsRecorder
    )
  }

  /// Resolves a bounds anchor in this proxy's local coordinate space.
  public subscript(anchor: Anchor<Rect>) -> Rect {
    guard let sourceFrame = placedFrameTable.frame(for: anchor.payload.identity) else {
      return .zero
    }

    switch anchor.payload.kind {
    case .bounds:
      return localRect(sourceFrame.continuous)
    case .point:
      return .zero
    }
  }

  /// Resolves a point anchor in this proxy's local coordinate space.
  public subscript(anchor: Anchor<Point>) -> Point {
    guard let sourceFrame = placedFrameTable.frame(for: anchor.payload.identity) else {
      return .zero
    }

    switch anchor.payload.kind {
    case .bounds:
      return .zero
    case .point(let unitPoint):
      return localPoint(
        Point(
          x: Double(sourceFrame.origin.x) + Double(sourceFrame.size.width) * unitPoint.x,
          y: Double(sourceFrame.origin.y) + Double(sourceFrame.size.height) * unitPoint.y
        )
      )
    }
  }

  private func localRect(
    _ rect: Rect
  ) -> Rect {
    Rect(
      origin: localPoint(rect.origin),
      size: rect.size
    )
  }

  private func localPoint(
    _ point: Point
  ) -> Point {
    Point(
      x: point.x - Double(bounds.origin.x),
      y: point.y - Double(bounds.origin.y)
    )
  }
}

/// Reads the current proposed geometry and maps it into authored content.
public struct GeometryReader<Content: View>: View, ResolvableView {
  private let content: (GeometryProxy) -> Content

  public init(
    @ViewBuilder content: @escaping (GeometryProxy) -> Content
  ) {
    self.content = content
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let authoringContext = makeDeferredAuthoringContext()
    let realizer = GeometryReaderLayoutDependentContent(
      content: content,
      context: context,
      authoringContext: authoringContext
    )
    let boundary = LayoutDependentContentBoundary(
      identity: context.identity,
      sizingPolicy: .fillsProposal(
        unspecifiedIdeal: CellSize(width: 10, height: 10)
      ),
      safeAreaInsets: context.environmentValues.safeAreaInsets,
      cellPixelMetrics: context.environmentValues.cellPixelMetrics,
      pointerInputCapabilities: context.environmentValues.pointerInputCapabilities,
      debugName: "GeometryReader",
      handle: LayoutDependentContentHandle(realizer)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("GeometryReader"),
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutDependentContent: boundary
      )
    ]
  }
}

@MainActor
private final class GeometryReaderLayoutDependentContent<Content: View>:
  LayoutDependentContentRealizer
{
  let debugName = "GeometryReader"
  private let content: (GeometryProxy) -> Content
  private let context: ResolveContext
  private let authoringContext: AuthoringContext?

  init(
    content: @escaping (GeometryProxy) -> Content,
    context: ResolveContext,
    authoringContext: AuthoringContext?
  ) {
    self.content = content
    self.context = context
    self.authoringContext = authoringContext
  }

  func realize(
    in realizationContext: LayoutRealizationContext
  ) -> [ResolvedNode] {
    let proxy = GeometryProxy(
      bounds: realizationContext.bounds,
      safeAreaInsets: realizationContext.safeAreaInsets,
      cellPixelMetrics: realizationContext.cellPixelMetrics,
      pointerInputCapabilities: realizationContext.pointerInputCapabilities,
      placedFrameTable: realizationContext.placedFrameTable
    )
    let view = withAuthoringContext(authoringContext) {
      ViewNodeContext.withCurrentValue(authoringContext?.viewNode) {
        context.trackingObservableAccess {
          content(proxy)
        }
      }
    }
    let contentContext =
      context
      .child(component: .named("content"))
      .settingEnvironment(\.safeAreaInsets, to: realizationContext.safeAreaInsets)
    let resolved = resolveView(
      view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
      in: contentContext
    )
    context.viewGraph?.installLayoutDependentChildren(
      for: realizationContext.boundaryIdentity,
      children: [resolved]
    )
    return [resolved]
  }
}

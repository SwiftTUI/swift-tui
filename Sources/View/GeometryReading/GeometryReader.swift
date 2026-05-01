public import Core

/// A terminal-native geometry proxy.
public struct GeometryProxy: Equatable, Sendable {
  /// The terminal-cell extent assigned to the current geometry scope.
  public var size: CellSize
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics
  public var pointerInputCapabilities: PointerInputCapabilities

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
      size: realizationContext.bounds.size,
      safeAreaInsets: realizationContext.safeAreaInsets,
      cellPixelMetrics: realizationContext.cellPixelMetrics,
      pointerInputCapabilities: realizationContext.pointerInputCapabilities
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

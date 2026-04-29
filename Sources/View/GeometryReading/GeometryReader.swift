public import Core

/// A terminal-native geometry proxy.
///
/// The proxy reports the size proposed by the nearest resolved container when
/// that container can tighten the geometry environment.
public struct GeometryProxy: Equatable, Sendable {
  /// The proposed terminal-cell extent for the current geometry scope.
  public var size: CellSize
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics

  public init(
    size: CellSize,
    safeAreaInsets: EdgeInsets = .zero,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.size = size
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
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
    let proxy = context.trackingObservableAccess {
      GeometryProxy(
        size: context.environmentValues.terminalSize,
        safeAreaInsets: context.environmentValues.safeAreaInsets,
        cellPixelMetrics: context.environmentValues.cellPixelMetrics
      )
    }
    let view = context.trackingObservableAccess {
      content(proxy)
    }
    return
      view
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .resolveElements(in: context)
  }
}

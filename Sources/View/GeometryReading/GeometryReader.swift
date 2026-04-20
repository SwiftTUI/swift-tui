public import Core

/// A terminal-native geometry proxy.
///
/// For now, the proxy reports the current terminal surface size from the
/// environment rather than a per-container local coordinate space.
public struct GeometryProxy: Equatable, Sendable {
  public var size: Size
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics

  public init(
    size: Size,
    safeAreaInsets: EdgeInsets = .zero,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.size = size
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
  }
}

/// Reads the current terminal geometry and maps it into authored content.
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
    return view.resolveElements(in: context)
  }
}

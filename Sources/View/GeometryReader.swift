public import Core

/// A terminal-native geometry proxy.
///
/// For now, the proxy reports the current terminal surface size from the
/// environment rather than a per-container local coordinate space.
public struct GeometryProxy: Equatable, Sendable {
  public var size: Size

  public init(size: Size) {
    self.size = size
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
      GeometryProxy(size: context.environmentValues.terminalSize)
    }
    return content(proxy).resolveElements(in: context)
  }
}

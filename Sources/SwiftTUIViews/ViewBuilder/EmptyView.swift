package import SwiftTUICore

/// A view with no rendered content.
public struct EmptyView: PrimitiveView, ResolvableView {
  public init() {}

  package func resolveElements(in _: ResolveContext) -> [ResolvedNode] {
    []
  }
}

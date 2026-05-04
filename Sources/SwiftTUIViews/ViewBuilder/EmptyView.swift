package import SwiftTUICore

/// A view with no rendered content.
public struct EmptyView: View, ResolvableView {
  public init() {}

  package func resolveElements(in _: ResolveContext) -> [ResolvedNode] {
    []
  }
}

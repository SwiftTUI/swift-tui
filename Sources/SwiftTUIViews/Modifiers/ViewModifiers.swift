package import SwiftTUICore

extension View {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveViewElements(self, in: context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }

  /// Erases `self` for local branch unification or interoperability.
  ///
  /// Prefer typed `@ViewBuilder` composition and generic storage when possible.
  /// If authored content will be stored for later evaluation, prefer
  /// `scopedAnyView(...)` over storing this result directly.
  public var erasedToAnyView: AnyView {
    AnyView(self)
  }
}

package import Core

/// A transparent structural container that groups child views.
public struct Group<Content: View>: View, ResolvableView {
  package var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      content,
      in: context,
      kindName: "Group"
    )
  }
}

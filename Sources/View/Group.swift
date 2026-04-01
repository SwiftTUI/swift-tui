package import Core

/// A transparent structural container that groups child views.
public struct Group<Content: View>: View, ResolvableView {
  package var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
  }

  package init(children: [AnyView]) where Content == VariadicView<AnyView> {
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      content,
      in: context,
      kindName: "Group"
    )
  }
}

@MainActor
func composedView(from children: [AnyView]) -> AnyView {
  switch children.count {
  case 0:
    return AnyView(EmptyView())
  case 1:
    return children[0]
  default:
    return AnyView(Group(children: children))
  }
}

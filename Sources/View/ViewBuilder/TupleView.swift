package import Core
/// The builder artifact produced when a ``ViewBuilder`` contains multiple child
/// expressions in sequence.
public struct TupleView<each Content: View>: View, ResolvableView, BuilderCompositeView,
  DeclaredChildrenView
{
  package let value: (repeat each Content)

  package init(
    _ value: (repeat each Content)
  ) {
    self.value = value
  }

  public var body: Never {
    fatalError("TupleView is a builder composition artifact.")
  }

  package var builderChildren: [AnyView] {
    var children: [AnyView] = []
    for child in repeat each value {
      appendDeclaredBuilderChildren(
        from: child,
        into: &children
      )
    }
    return children
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      self,
      in: context,
      kindName: "Group"
    )
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    for child in repeat each value {
      appendDeclaredChildNodes(
        child,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    }
  }
}

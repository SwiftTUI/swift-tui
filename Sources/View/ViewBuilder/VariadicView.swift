package import Core

/// The builder artifact produced by array-like view composition such as
/// `ForEach` expansion or `buildArray` support.
public struct VariadicView<Content: View>: View, ResolvableView, BuilderCompositeView,
  DeclaredChildrenView
{
  package let content: [Content]

  package init(
    _ content: [Content]
  ) {
    self.content = content
  }

  public var body: Never {
    fatalError("VariadicView is a builder composition artifact.")
  }

  package var builderChildren: [AnyView] {
    content.flatMap { declaredBuilderChildren(from: $0) }
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
    for element in content {
      appendDeclaredChildNodes(
        element,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    }
  }
}

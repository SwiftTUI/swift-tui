package import Core

/// The builder artifact produced by array-like view composition such as
/// `ForEach` expansion or `buildArray` support.
public struct VariadicView<Content: View>: View, ResolvableView, DeclaredChildrenView {
  package let content: [Content]

  package init(
    _ content: [Content]
  ) {
    self.content = content
  }

  public var body: Never {
    fatalError("VariadicView is a builder composition artifact.")
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

  package func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  ) {
    for element in content {
      appendErasedDeclaredBuilderChildren(
        from: element,
        into: &children
      )
    }
  }
}

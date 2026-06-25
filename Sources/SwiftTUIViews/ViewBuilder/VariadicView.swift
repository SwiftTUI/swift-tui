package import SwiftTUICore

/// The builder artifact produced by array-like view composition such as
/// `ForEach` expansion or `buildArray` support.
public struct VariadicView<Content: View>: PrimitiveView, ResolvableView, DeclaredChildrenView {
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

  package func appendScopedDeclaredChildren(
    into children: inout [ScopedContentPayload]
  ) {
    for element in content {
      appendScopedDeclaredBuilderChildren(
        from: element,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalAttachmentContentPayload]
  ) {
    for element in content {
      appendPortalDeclaredBuilderChildren(
        from: element,
        into: &children
      )
    }
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    visitor: (
      _ child: Any,
      _ childContext: ResolveContext,
      _ resolveOne: @escaping @MainActor () -> ResolvedNode
    ) -> Void
  ) {
    for element in content {
      enumerateDeclaredChildViews(
        element,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        visitor: visitor
      )
    }
  }
}

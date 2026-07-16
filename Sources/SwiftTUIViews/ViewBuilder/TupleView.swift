package import SwiftTUICore

/// The builder artifact produced when a ``ViewBuilder`` contains multiple child
/// expressions in sequence.
public struct TupleView<each Content: View>: PrimitiveView, ResolvableView, DeclaredChildrenView {
  package let value: (repeat each Content)

  package init(
    _ value: (repeat each Content)
  ) {
    self.value = value
  }

  public var body: Never {
    fatalError("TupleView is a builder composition artifact.")
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

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    for child in repeat each value {
      appendScopedDeclaredBuilderChildren(
        from: child,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    for child in repeat each value {
      appendPortalDeclaredBuilderChildren(
        from: child,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
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
    for child in repeat each value {
      enumerateDeclaredChildViews(
        child,
        in: context,
        kindName: kindName,
        nextIndex: &nextIndex,
        visitor: visitor
      )
    }
  }
}

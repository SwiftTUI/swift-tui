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
    var resolved: [ResolvedNode] = []
    var elementIndex = 0
    for element in content {
      appendDeclaredChildNodes(
        element,
        in: context,
        kindName: "Group",
        nextIndex: &elementIndex,
        into: &resolved
      )
    }
    assignEntityIdentityOccurrences(to: &resolved)
    return resolved
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    var elementIndex = 0

    for element in content {
      appendDeclaredChildNodes(
        element,
        in: slotContext,
        kindName: kindName,
        nextIndex: &elementIndex,
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
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    var elementIndex = 0
    for element in content {
      appendScopedDeclaredBuilderChildren(
        from: element,
        in: slotContext,
        kindName: kindName,
        nextIndex: &elementIndex,
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
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    var elementIndex = 0
    for element in content {
      appendPortalDeclaredBuilderChildren(
        from: element,
        in: slotContext,
        kindName: kindName,
        nextIndex: &elementIndex,
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
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    var elementIndex = 0

    for element in content {
      enumerateDeclaredChildViews(
        element,
        in: slotContext,
        kindName: kindName,
        nextIndex: &elementIndex,
        visitor: visitor
      )
    }
  }
}

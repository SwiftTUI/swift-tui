package import Core

/// A transparent structural container that groups child views.
public struct Group<Content: View>: View, ResolvableView, DeclaredChildrenView {
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

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    resolved.append(
      contentsOf: resolveDeclaredChildren(
        content,
        in: groupContext,
        kindName: "Group"
      )
    )
  }

  package func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  ) {
    appendErasedDeclaredBuilderChildren(
      from: content,
      into: &children
    )
  }

  package func appendDeferredDeclaredChildren(
    into children: inout [DeferredViewPayload]
  ) {
    appendDeferredDeclaredBuilderChildren(
      from: content,
      into: &children
    )
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalContentPayload]
  ) {
    appendPortalDeclaredBuilderChildren(
      from: content,
      into: &children
    )
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
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    var groupIndex = 0
    enumerateDeclaredChildViews(
      content,
      in: groupContext,
      kindName: "Group",
      nextIndex: &groupIndex,
      visitor: visitor
    )
  }
}

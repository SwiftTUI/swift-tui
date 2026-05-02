package import Core

/// The builder artifact produced by conditional branches inside a
/// ``ViewBuilder``.
public struct ConditionalContent<TrueContent: View, FalseContent: View>: View,
  ResolvableView, DeclaredChildrenView
{
  /// The currently active conditional branch.
  public enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }

  package let storage: Storage
  package let collapsesImplicitEmptyFalseBranch: Bool

  package init(
    storage: Storage,
    collapsesImplicitEmptyFalseBranch: Bool
  ) {
    self.storage = storage
    self.collapsesImplicitEmptyFalseBranch = collapsesImplicitEmptyFalseBranch
  }

  public var body: Never {
    fatalError("ConditionalContent is a builder composition artifact.")
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    switch storage {
    case .trueContent(let content):
      let branchContext = context.child(component: .init(rawValue: "true"))
      appendDeclaredChildNodes(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      let branchContext = context.child(component: .init(rawValue: "false"))
      appendDeclaredChildNodes(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &nextIndex,
        into: &resolved
      )
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .trueContent(let content):
      let branchContext = context.child(component: .init(rawValue: "true"))
      return resolveViewElements(content, in: branchContext)
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return []
      }
      let branchContext = context.child(component: .init(rawValue: "false"))
      return resolveViewElements(content, in: branchContext)
    }
  }

  package func appendErasedDeclaredChildren(
    into children: inout [AnyView]
  ) {
    switch storage {
    case .trueContent(let content):
      appendErasedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendErasedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    }
  }

  package func appendDeferredDeclaredChildren(
    into children: inout [DeferredViewPayload]
  ) {
    switch storage {
    case .trueContent(let content):
      appendDeferredDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendDeferredDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalContentPayload]
  ) {
    switch storage {
    case .trueContent(let content):
      appendPortalDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendPortalDeclaredBuilderChildren(
        from: content,
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
    switch storage {
    case .trueContent(let content):
      let branchContext = context.child(component: .init(rawValue: "true"))
      enumerateDeclaredChildViews(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &nextIndex,
        visitor: visitor
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      let branchContext = context.child(component: .init(rawValue: "false"))
      enumerateDeclaredChildViews(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &nextIndex,
        visitor: visitor
      )
    }
  }
}

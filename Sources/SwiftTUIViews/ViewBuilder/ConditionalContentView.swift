package import SwiftTUICore

/// The builder artifact produced by conditional branches inside a
/// ``ViewBuilder``.
public struct ConditionalContent<TrueContent: View, FalseContent: View>: PrimitiveView,
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

  package func appendScopedDeclaredChildren(
    into children: inout [ScopedContentPayload]
  ) {
    switch storage {
    case .trueContent(let content):
      appendScopedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      appendScopedDeclaredBuilderChildren(
        from: content,
        into: &children
      )
    }
  }

  package func appendPortalDeclaredChildren(
    into children: inout [PortalAttachmentContentPayload]
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

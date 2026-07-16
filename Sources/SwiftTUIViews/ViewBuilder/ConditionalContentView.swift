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
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1

    switch storage {
    case .trueContent(let content):
      let branchContext = slotContext.child(component: .init(rawValue: "true"))
      var branchIndex = 0
      appendDeclaredChildNodes(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
        into: &resolved
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        // The slot was consumed above. No node is minted for the implicit
        // empty branch, but trailing siblings keep their authored indices.
        return
      }
      let branchContext = slotContext.child(component: .init(rawValue: "false"))
      var branchIndex = 0
      appendDeclaredChildNodes(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
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
    let slotContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1

    switch storage {
    case .trueContent(let content):
      let branchContext = slotContext.child(component: .init(rawValue: "true"))
      var branchIndex = 0
      enumerateDeclaredChildViews(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
        visitor: visitor
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        // Mirror appendDeclaredChildren: the slot was already consumed and
        // the implicit empty branch produces no visitor call.
        return
      }
      let branchContext = slotContext.child(component: .init(rawValue: "false"))
      var branchIndex = 0
      enumerateDeclaredChildViews(
        content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
        visitor: visitor
      )
    }
  }
}

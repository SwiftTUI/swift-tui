import SwiftTUICore

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
      return resolveBranchElements(content, in: context, component: "true")
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return []
      }
      return resolveBranchElements(content, in: context, component: "false")
    }
  }

  /// Resolves one branch's content at the branch-extended identity.
  ///
  /// A bare composite child (a user struct with a body — the only view class
  /// that reaches `resolveBody` node-less on this path) resolves through
  /// `resolveView` so it mints its own view node AT the branch identity, the
  /// same identity the value-only resolution used. Without the mint its
  /// `@State` slots landed on the ambient authoring owner — a node that
  /// never departs when the branch flips — so a removed-and-reinserted
  /// branch resurrected its prior state instead of starting a fresh
  /// lifetime. This mirrors `ModifierContentInputs.resolve`, which already
  /// node-backs composite modifier bases through the same door.
  ///
  /// Every `ResolvableView` keeps the value-only path: structural children
  /// (`TupleView`, `ForEach`, nested conditionals) mint per-child nodes in
  /// their own traversal; `AnyView`, modifier chains, and control chrome
  /// resolve their own interior nodes and anchor them to the enclosing
  /// evaluated parent — interposing a mint on that post-processing edge gets
  /// the mint absorbed and barrier-reclaimed, and the reclaim cascade tears
  /// down the live interiors (gesture routes die with them).
  @MainActor
  private func resolveBranchElements<Content: View>(
    _ content: Content,
    in context: ResolveContext,
    component: String
  ) -> [ResolvedNode] {
    let branchContext = context.child(component: .init(rawValue: component))
    let erased: Any = content
    guard !(erased is any ResolvableView), context.viewGraph != nil else {
      return resolveViewElements(content, in: branchContext)
    }
    let resolved = resolveView(content, in: branchContext)
    return consumeDeclaredChild(
      resolved,
      resolvedUnder: branchContext.identity,
      in: context.viewGraph,
      policy: .declaredBuilder
    )
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
    switch storage {
    case .trueContent(let content):
      let branchContext = slotContext.child(component: .init(rawValue: "true"))
      var branchIndex = 0
      appendScopedDeclaredBuilderChildren(
        from: content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      let branchContext = slotContext.child(component: .init(rawValue: "false"))
      var branchIndex = 0
      appendScopedDeclaredBuilderChildren(
        from: content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
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
    switch storage {
    case .trueContent(let content):
      let branchContext = slotContext.child(component: .init(rawValue: "true"))
      var branchIndex = 0
      appendPortalDeclaredBuilderChildren(
        from: content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
        into: &children
      )
    case .falseContent(let content):
      if collapsesImplicitEmptyFalseBranch, content is EmptyView {
        return
      }
      let branchContext = slotContext.child(component: .init(rawValue: "false"))
      var branchIndex = 0
      appendPortalDeclaredBuilderChildren(
        from: content,
        in: branchContext,
        kindName: kindName,
        nextIndex: &branchIndex,
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

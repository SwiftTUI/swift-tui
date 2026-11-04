import SwiftTUICore

/// A transparent structural container that groups child views.
public struct Group<Content: View>: PrimitiveView, IterativeResolvableView, DeclaredChildrenView,
  DeclaredChildStructure
{
  package var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    resolveDeclaredChildrenWork(
      content,
      in: context,
      kindName: .group
    )
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: ViewKind,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    var accumulator = DeclaredChildAccumulator(indexed: false)
    appendDeclaredStructure(
      in: context, kindName: kindName, nextIndex: &nextIndex, into: &accumulator
    )
    resolved.append(contentsOf: accumulator.nodes)
  }

  package func appendDeclaredStructure(
    in context: ResolveContext,
    kindName: ViewKind,
    nextIndex: inout Int,
    into resolved: inout DeclaredChildAccumulator
  ) {
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName.name),
      index: nextIndex
    )
    nextIndex += 1
    var children = DeclaredChildAccumulator(indexed: resolved.indexed)
    var groupIndex = 0
    appendDeclaredContent(
      content, in: groupContext, kindName: .group,
      nextIndex: &groupIndex, into: &children
    )
    children.normalizeOccurrences()
    resolved.append(children)
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: ViewKind,
    nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName.name),
      index: nextIndex
    )
    nextIndex += 1
    var groupIndex = 0
    appendScopedDeclaredBuilderChildren(
      from: content,
      in: groupContext,
      kindName: .group,
      nextIndex: &groupIndex,
      into: &children
    )
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: ViewKind,
    nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName.name),
      index: nextIndex
    )
    nextIndex += 1
    var groupIndex = 0
    appendPortalDeclaredBuilderChildren(
      from: content,
      in: groupContext,
      kindName: .group,
      nextIndex: &groupIndex,
      into: &children
    )
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext,
    kindName: ViewKind,
    nextIndex: inout Int,
    visitor: (
      _ child: Any,
      _ childContext: ResolveContext,
      _ resolveOne: @escaping @MainActor () -> ResolvedNode
    ) -> Void
  ) {
    let groupContext = context.indexedChild(
      kind: .init(rawValue: kindName.name),
      index: nextIndex
    )
    nextIndex += 1
    var groupIndex = 0
    enumerateDeclaredChildViews(
      content,
      in: groupContext,
      kindName: .group,
      nextIndex: &groupIndex,
      visitor: visitor
    )
  }
}

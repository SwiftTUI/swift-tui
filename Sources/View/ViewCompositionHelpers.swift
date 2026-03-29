package import Core

@MainActor
package func combinedView(
  from views: [AnyView],
  kindName: String
) -> AnyView {
  switch views.count {
  case 0:
    return AnyView(EmptyView())
  case 1:
    return views[0]
  default:
    return AnyView(
      NamedGroupView(
        kindName: kindName,
        children: views
      )
    )
  }
}

@MainActor
private func parallelResolveGroup(
  kindName: String = "Group",
  children: [AnyView],
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = .init(),
  semanticMetadata: SemanticMetadata = .init(),
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  let resolvedChildren = children.enumerated().map { index, child in
    child.resolve(in: context.indexedChild(kind: kindName, index: index))
  }

  return ResolvedNode(
    identity: context.identity,
    kind: .view(kindName),
    children: resolvedChildren,
    environmentSnapshot: context.environment,
    transactionSnapshot: context.transaction,
    layoutBehavior: layoutBehavior,
    layoutMetadata: layoutMetadata,
    drawMetadata: drawMetadata,
    semanticMetadata: semanticMetadata
  )
}

@MainActor
private struct NamedGroupView: View, ResolvableView {
  var kindName: String
  var children: [AnyView]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      parallelResolveGroup(
        kindName: kindName,
        children: children,
        in: context
      )
    ]
  }
}

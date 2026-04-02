import Core

// AnyView policy: retain typed builder plumbing here while composition
// helpers normalize heterogeneous authored children.
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
private func resolveGroupElements(
  kindName: String = "Group",
  children: [AnyView],
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  in context: ResolveContext
) -> ResolvedNode {
  context.recordResolvedComputation()
  let resolvedChildren = children.enumerated().map { index, child in
    child.resolve(in: context.indexedChild(kind: .init(rawValue: kindName), index: index))
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
      resolveGroupElements(
        kindName: kindName,
        children: children,
        in: context
      )
    ]
  }
}

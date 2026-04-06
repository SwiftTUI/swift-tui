package import Core

/// A deferred authored child payload that preserves authoring scope without
/// exposing `AnyView` as the transport type.
@MainActor
package struct DeferredViewPayload: Sendable {
  private let resolveElementsClosure: @MainActor @Sendable (ResolveContext) -> [ResolvedNode]

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    let builder = ScopedBuilder(
      authoringContext: authoringContext,
      content: content
    )
    resolveElementsClosure = { context in
      builder.resolveElements(in: context)
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveElementsClosure(context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    normalizeResolvedElements(
      resolveElements(in: context),
      in: context
    )
  }
}

@MainActor
package struct DeferredPayloadView: View, ResolvableView {
  package var payload: DeferredViewPayload

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context)
  }
}

@MainActor
package struct DeferredPayloadGroupView: View, ResolvableView {
  package var kindName: String
  package var payloads: [DeferredViewPayload]

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return payloads[0].resolveElements(in: context)
    default:
      return [
        resolveDeferredGroupElements(
          kindName: kindName,
          payloads: payloads,
          in: context
        )
      ]
    }
  }
}

@MainActor
private func resolveDeferredGroupElements(
  kindName: String = "Group",
  payloads: [DeferredViewPayload],
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  in context: ResolveContext
) -> ResolvedNode {
  context.recordResolvedComputation()
  let resolvedChildren = payloads.enumerated().map { index, payload in
    payload.resolve(
      in: context.indexedChild(
        kind: .init(rawValue: kindName),
        index: index
      )
    )
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

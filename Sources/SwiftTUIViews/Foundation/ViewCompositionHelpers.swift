package import SwiftTUICore

/// A deferred authored child payload that preserves authoring scope without
/// exposing `AnyView` as the transport type.
@MainActor
package struct DeferredViewPayload: Sendable {
  private let resolveElementsClosure: @MainActor @Sendable (ResolveContext) -> [ResolvedNode]

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    // Deferred payloads are resolved in a different part of the tree (e.g.
    // a presentation overlay). Preserve the original owner identity and
    // ViewNode, but isolate future first-time ordinal claims from the
    // capture-site tracker.
    let authoringContext = makeDeferredAuthoringContext(from: authoringContext)
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
package struct DeferredPayloadView: PrimitiveView, ResolvableView {
  package var payload: DeferredViewPayload

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context)
  }
}

@MainActor
package struct DeferredPayloadGroupView: PrimitiveView, ResolvableView {
  package var kindName: String
  package var payloads: [DeferredViewPayload]

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return [
        resolveView(
          DeferredPayloadView(payload: payloads[0]),
          in: context
        )
      ]
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
    resolveView(
      DeferredPayloadView(payload: payload),
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

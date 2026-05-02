package import Core

/// Destination-owned content payload for portal-hosted UI.
@MainActor
package struct PortalContentPayload: Sendable {
  private let resolveNodeClosure: @MainActor @Sendable (ResolveContext) -> ResolvedNode

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    // Build the view value at the declaration site so captured bindings
    // keep pointing at their original owner. Resolve it later at the
    // portal destination so dynamic properties inside the hosted content
    // bind to destination graph nodes.
    let output = withAuthoringContext(authoringContext) {
      content()
    }
    resolveNodeClosure = { context in
      resolveView(output, in: context)
    }
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveNodeClosure(context)
  }
}

@MainActor
package struct PortalPayloadView: View, ResolvableView {
  package var payload: PortalContentPayload

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [payload.resolve(in: context)]
  }
}

@MainActor
package func appendPortalDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [PortalContentPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendPortalDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(
    PortalContentPayload {
      view
    }
  )
}

@MainActor
package func portalDeclaredBuilderChildren<V: View>(
  from view: V
) -> [PortalContentPayload] {
  var children: [PortalContentPayload] = []
  appendPortalDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package struct PortalPayloadGroupView: View, ResolvableView {
  package var kindName: String
  package var payloads: [PortalContentPayload]

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return [
        resolveView(
          PortalPayloadView(payload: payloads[0]),
          in: context
        )
      ]
    default:
      return [
        resolvePortalGroupElements(
          kindName: kindName,
          payloads: payloads,
          in: context
        )
      ]
    }
  }
}

@MainActor
private func resolvePortalGroupElements(
  kindName: String = "Group",
  payloads: [PortalContentPayload],
  in context: ResolveContext
) -> ResolvedNode {
  context.recordResolvedComputation()
  let resolvedChildren = payloads.enumerated().map { index, payload in
    resolveView(
      PortalPayloadView(payload: payload),
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
    transactionSnapshot: context.transaction
  )
}

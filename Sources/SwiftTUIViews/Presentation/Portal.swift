package import SwiftTUICore

/// Destination-owned content payload for portal-hosted UI.
@MainActor
package struct PortalAttachmentContentPayload: Sendable {
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

package struct PortalAttachmentEdge: Sendable, Equatable {
  package var portalEntryID: PortalEntryID
  package var modalPolicy: PortalModalPolicy?
  package var lifecycleActiveWhileHidden: Bool

  package init(
    portalEntryID: PortalEntryID,
    modalPolicy: PortalModalPolicy? = nil,
    lifecycleActiveWhileHidden: Bool = true
  ) {
    self.portalEntryID = portalEntryID
    self.modalPolicy = modalPolicy
    self.lifecycleActiveWhileHidden = lifecycleActiveWhileHidden
  }
}

@MainActor
package struct PortalAttachmentPayload: Sendable {
  package var edge: PortalAttachmentEdge?
  private var payload: PortalAttachmentContentPayload

  package init(
    _ payload: PortalAttachmentContentPayload,
    edge: PortalAttachmentEdge? = nil
  ) {
    self.edge = edge
    self.payload = payload
  }

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    edge: PortalAttachmentEdge? = nil,
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    self.edge = edge
    payload = PortalAttachmentContentPayload(
      authoringContext: authoringContext,
      content: content
    )
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    payload.resolve(in: context)
  }

  package func attachingEdgeIfMissing(
    _ edge: PortalAttachmentEdge
  ) -> PortalAttachmentPayload {
    guard self.edge == nil else {
      return self
    }
    var copy = self
    copy.edge = edge
    return copy
  }
}

@MainActor
package struct PortalAttachmentView: PrimitiveView, ResolvableView {
  package var payload: PortalAttachmentPayload

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [payload.resolve(in: context)]
  }
}

@MainActor
package func appendPortalDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [PortalAttachmentContentPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendPortalDeclaredChildren(
      into: &children
    )
    return
  }
  children.append(
    PortalAttachmentContentPayload {
      view
    }
  )
}

@MainActor
package func portalDeclaredBuilderChildren<V: View>(
  from view: V
) -> [PortalAttachmentContentPayload] {
  var children: [PortalAttachmentContentPayload] = []
  appendPortalDeclaredBuilderChildren(
    from: view,
    into: &children
  )
  return children
}

@MainActor
package func appendPortalAttachmentDeclaredBuilderChildren<V: View>(
  from view: V,
  edge: PortalAttachmentEdge?,
  into children: inout [PortalAttachmentPayload]
) {
  var contentPayloads: [PortalAttachmentContentPayload] = []
  appendPortalDeclaredBuilderChildren(
    from: view,
    into: &contentPayloads
  )
  children.append(
    contentsOf: contentPayloads.map {
      PortalAttachmentPayload($0, edge: edge)
    }
  )
}

@MainActor
package func portalAttachmentDeclaredBuilderChildren<V: View>(
  from view: V,
  edge: PortalAttachmentEdge?
) -> [PortalAttachmentPayload] {
  var children: [PortalAttachmentPayload] = []
  appendPortalAttachmentDeclaredBuilderChildren(
    from: view,
    edge: edge,
    into: &children
  )
  return children
}

@MainActor
package func portalAttachmentDeclaredBuilderChildren<V: View>(
  from view: V,
  portalEntryID: PortalEntryID,
  modalPolicy: PortalModalPolicy? = nil,
  lifecycleActiveWhileHidden: Bool = true
) -> [PortalAttachmentPayload] {
  portalAttachmentDeclaredBuilderChildren(
    from: view,
    edge: PortalAttachmentEdge(
      portalEntryID: portalEntryID,
      modalPolicy: modalPolicy,
      lifecycleActiveWhileHidden: lifecycleActiveWhileHidden
    )
  )
}

@MainActor
package struct PortalAttachmentGroupView: PrimitiveView, ResolvableView {
  package var kindName: String
  package var payloads: [PortalAttachmentPayload]

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return [
        resolveView(
          PortalAttachmentView(payload: payloads[0]),
          in: context
        )
      ]
    default:
      return [
        resolvePortalAttachmentGroupElements(
          kindName: kindName,
          payloads: payloads,
          in: context
        )
      ]
    }
  }
}

@MainActor
private func resolvePortalAttachmentGroupElements(
  kindName: String = "Group",
  payloads: [PortalAttachmentPayload],
  in context: ResolveContext
) -> ResolvedNode {
  context.recordResolvedComputation()
  let resolvedChildren = payloads.enumerated().map { index, payload in
    resolveView(
      PortalAttachmentView(payload: payload),
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

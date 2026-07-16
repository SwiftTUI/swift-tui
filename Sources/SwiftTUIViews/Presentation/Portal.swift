package import SwiftTUICore

/// Destination-owned content payload for portal-hosted UI.
@MainActor
package struct PortalAttachmentContentPayload: Sendable {
  private let resolveElementsClosure:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]

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
    resolveElementsClosure = { context, _ in
      [resolveView(output, in: context)]
    }
  }

  package init(
    resolveElements:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  ) {
    resolveElementsClosure = resolveElements
  }

  package func resolveElements(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    resolveElementsClosure(context, placementRoot ?? context)
  }

  package func resolve(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> ResolvedNode {
    normalizeResolvedElements(
      resolveElements(in: context, placementRoot: placementRoot),
      in: context
    )
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

  package func resolve(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> ResolvedNode {
    payload.resolve(in: context, placementRoot: placementRoot)
  }

  package func resolveElements(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    payload.resolveElements(in: context, placementRoot: placementRoot)
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
  package var placementRoot: ResolveContext? = nil

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context, placementRoot: placementRoot)
  }
}

/// A transparent destination-side expansion of already-authored portal
/// payloads. Unlike an implementation-only `ForEach` over payload indices, the
/// sequence adds no competing entity route; every deferred payload resolves
/// relative to the stable sequence slot and keeps its declaration-side ID.
@MainActor
package struct PortalAttachmentSequenceView: PrimitiveView, ResolvableView,
  DeclaredChildrenView
{
  package var payloads: [PortalAttachmentPayload]
  package var fixedSizeChildren = false

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if fixedSizeChildren {
      return payloads.enumerated().map { index, payload in
        resolveView(
          PortalAttachmentView(
            payload: payload,
            placementRoot: context
          )
          .fixedSize(),
          in: payloadContext(index: index, root: context)
        )
      }
    }
    return payloads.enumerated().flatMap { index, payload in
      payload.resolveElements(
        in: payloadContext(index: index, root: context),
        placementRoot: context
      )
    }
  }

  package func appendDeclaredChildren(
    in context: ResolveContext,
    kindName: String,
    nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let sequenceContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    resolved.append(contentsOf: resolveElements(in: sequenceContext))
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    let sequenceContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    children.append(
      ScopedContentPayload(resolveElements: { _, placementRoot in
        resolveElements(in: sequenceContext.applying(to: placementRoot))
      })
    )
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext,
    kindName: String,
    nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    let sequenceContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    children.append(
      PortalAttachmentContentPayload(resolveElements: { _, placementRoot in
        resolveElements(in: sequenceContext.applying(to: placementRoot))
      })
    )
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
    let sequenceContext = context.indexedChild(
      kind: .init(rawValue: kindName),
      index: nextIndex
    )
    nextIndex += 1
    visitor(self, sequenceContext) {
      resolveView(self, in: sequenceContext)
    }
  }

  private func payloadContext(
    index: Int,
    root: ResolveContext
  ) -> ResolveContext {
    root.indexedChild(
      kind: .init(rawValue: "PortalAttachment"),
      index: index
    )
  }
}

@MainActor
package func appendPortalDeclaredBuilderChildren<V: View>(
  from view: V,
  into children: inout [PortalAttachmentContentPayload]
) {
  var nextIndex = 0
  appendPortalDeclaredBuilderChildren(
    from: view,
    in: .root,
    kindName: "Group",
    nextIndex: &nextIndex,
    into: &children
  )
}

@MainActor
package func appendPortalDeclaredBuilderChildren<V: View>(
  from view: V,
  in context: DeclaredPayloadTraversalContext,
  kindName: String,
  nextIndex: inout Int,
  into children: inout [PortalAttachmentContentPayload]
) {
  let erased: Any = view
  if let structural = erased as? any DeclaredChildrenView {
    structural.appendPortalDeclaredChildren(
      in: context,
      kindName: kindName,
      nextIndex: &nextIndex,
      into: &children
    )
    return
  }
  nextIndex += 1
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
      return payloads[0].resolveElements(
        in: context,
        placementRoot: context
      )
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
  let resolvedChildren = payloads.enumerated().flatMap { index, payload in
    payload.resolveElements(
      in: context.indexedChild(
        kind: .init(rawValue: kindName),
        index: index
      ),
      placementRoot: context
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

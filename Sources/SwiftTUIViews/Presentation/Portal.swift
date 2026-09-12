import SwiftTUICore

/// Destination-owned content, scheduled at its placement context.
@MainActor
package struct PortalAttachmentContentPayload: Sendable {
  package let hasDeclaredContent: Bool
  private let elements:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    let output = withAuthoringContext(authoringContext) { content() }
    hasDeclaredContent = !(output is EmptyView)
    elements = { context, _ in resolveViewWork(output, in: context).map { [$0] } }
  }

  package init(
    hasDeclaredContent: Bool = true,
    resolveElements:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  ) {
    self.init(
      hasDeclaredContent: hasDeclaredContent,
      resolveElementsWork: { context, root in
        .deferred { .value(resolveElements(context, root)) }
      })
  }

  package init(
    hasDeclaredContent: Bool = true,
    resolveElementsWork:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>
  ) {
    self.hasDeclaredContent = hasDeclaredContent
    elements = resolveElementsWork
  }

  package func resolveElements(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> [ResolvedNode]
  {
    resolveElementsWork(in: context, placementRoot: placementRoot).run()
  }

  package func resolveElementsWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<[ResolvedNode]>
  {
    elements(context, placementRoot ?? context)
  }

  package func resolve(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolvedNode
  {
    resolveWork(in: context, placementRoot: placementRoot).run()
  }

  package func resolveWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<ResolvedNode>
  {
    resolveElementsWork(in: context, placementRoot: placementRoot).map {
      normalizeResolvedElements($0, in: context)
    }
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

  package var hasDeclaredContent: Bool { payload.hasDeclaredContent }

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

  package func resolveElementsWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<[ResolvedNode]>
  {
    payload.resolveElementsWork(in: context, placementRoot: placementRoot)
  }

  package func resolveWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<ResolvedNode>
  {
    payload.resolveWork(in: context, placementRoot: placementRoot)
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
package struct PortalAttachmentView: PrimitiveView, IterativeResolvableView {
  package var payload: PortalAttachmentPayload
  package var placementRoot: ResolveContext? = nil

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    payload.resolveElementsWork(in: context, placementRoot: placementRoot)
  }
}

/// A transparent destination-side expansion of already-authored portal
/// payloads. Unlike an implementation-only `ForEach` over payload indices, the
/// sequence adds no competing entity route; every deferred payload resolves
/// relative to the stable sequence slot and keeps its declaration-side ID.
@MainActor
package struct PortalAttachmentSequenceView: PrimitiveView, IterativeResolvableView,
  DeclaredChildrenView
{
  package var payloads: [PortalAttachmentPayload]
  package var fixedSizeChildren = false

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let result = DeclaredChildrenWorkState()
    return resolveSequentially(Array(payloads.enumerated())) { index, payload in
      let childContext = payloadContext(index: index, root: context)
      if fixedSizeChildren {
        return resolveViewWork(
          PortalAttachmentView(payload: payload, placementRoot: context).fixedSize(),
          in: childContext
        ).map {
          result.nodes.append($0)
        }
      }
      return payload.resolveElementsWork(in: childContext, placementRoot: context).map {
        result.nodes.append(contentsOf: $0)
      }
    }.map { result.nodes }
  }

  package func appendDeclaredChildrenWork(
    in context: ResolveContext, kindName: String, into state: DeclaredChildrenWorkState
  ) -> ResolveWork<Void> {
    .deferred {
      let childContext = context.indexedChild(
        kind: .init(rawValue: kindName), index: state.nextIndex)
      state.nextIndex += 1
      return makeResolveWork(in: childContext).map { state.nodes.append(contentsOf: $0) }
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
      ScopedContentPayload(resolveElementsWork: { _, placementRoot in
        makeResolveWork(in: sequenceContext.applying(to: placementRoot))
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
      PortalAttachmentContentPayload(
        hasDeclaredContent: payloads.contains { $0.hasDeclaredContent },
        resolveElementsWork: { _, placementRoot in
          makeResolveWork(in: sequenceContext.applying(to: placementRoot))
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
package struct PortalAttachmentGroupView: PrimitiveView, IterativeResolvableView {
  package var kindName: String
  package var payloads: [PortalAttachmentPayload]

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    switch payloads.count {
    case 0: return .value([])
    case 1: return payloads[0].resolveElementsWork(in: context, placementRoot: context)
    default:
      context.recordResolvedComputation()
      let result = DeclaredChildrenWorkState()
      return resolveSequentially(Array(payloads.enumerated())) { index, payload in
        payload.resolveElementsWork(
          in: context.indexedChild(kind: .init(rawValue: kindName), index: index),
          placementRoot: context
        ).map {
          result.nodes.append(contentsOf: $0)
        }
      }.map {
        [
          ResolvedNode(
            identity: context.identity, kind: .view(kindName),
            typeDiscriminator: kindName == "Group"
              ? ObjectIdentifier(SynthesizedGroupWrapperMarker.self) : nil,
            children: result.nodes, environmentSnapshot: context.environment,
            transactionSnapshot: context.transaction)
        ]
      }
    }
  }
}

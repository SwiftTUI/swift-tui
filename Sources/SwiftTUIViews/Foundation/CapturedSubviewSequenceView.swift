import SwiftTUICore

/// Expands captured authoring slots as distinct layout children at either an
/// inline or a deferred host. A body-only wrapper would normalize the slots
/// into one overlaying group before the destination stack can lay them out.
@MainActor
package struct CapturedSubviewSequenceView: PrimitiveView, IterativeResolvableView,
  DeclaredChildrenView
{
  package var payloads: [ScopedContentPayload]
  package var retention: CapturedSubviewRetention? = nil

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    if let retention { return retention.resolveWork(payloads: payloads, in: context) }
    let result = DeclaredChildrenWorkState()
    return resolveSequentially(Array(payloads.enumerated())) { index, payload in
      payload.resolveDeclaredElementsWork(
        in: payloadContext(index: index, root: context), placementRoot: context
      ).map {
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
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    into resolved: inout [ResolvedNode]
  ) {
    let sequenceContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    nextIndex += 1
    resolved.append(contentsOf: resolveElements(in: sequenceContext))
  }

  package func appendScopedDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [ScopedContentPayload]
  ) {
    let sequenceContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    nextIndex += 1
    children.append(
      ScopedContentPayload(resolveElementsWork: { _, placementRoot in
        makeResolveWork(in: sequenceContext.applying(to: placementRoot))
      }))
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    let sequenceContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    nextIndex += 1
    children.append(
      PortalAttachmentContentPayload(resolveElementsWork: { _, placementRoot in
        makeResolveWork(in: sequenceContext.applying(to: placementRoot))
      }))
  }

  package func enumerateDeclaredChildren(
    in context: ResolveContext, kindName: String, nextIndex: inout Int,
    visitor: (Any, ResolveContext, @escaping @MainActor () -> ResolvedNode) -> Void
  ) {
    let sequenceContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    nextIndex += 1
    // The captured slot is an opaque declaration, as with portal sequences.
    // Resolving it must pass through the same ownership seam as bulk layout.
    visitor(self, sequenceContext) {
      resolveView(self, in: sequenceContext)
    }
  }

  private func payloadContext(index: Int, root: ResolveContext) -> ResolveContext {
    root.indexedChild(kind: .named("CapturedSubview"), index: index)
  }
}

import SwiftTUICore

/// Expands captured authoring slots as distinct layout children at either an
/// inline or a deferred host. A body-only wrapper would normalize the slots
/// into one overlaying group before the destination stack can lay them out.
@MainActor
package struct CapturedSubviewSequenceView: PrimitiveView, ResolvableView, DeclaredChildrenView {
  package var payloads: [ScopedContentPayload]
  package var retention: CapturedSubviewRetention? = nil

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let retention { return retention.resolve(payloads: payloads, in: context) }
    return payloads.enumerated().flatMap { index, payload in
      let childContext = payloadContext(index: index, root: context)
      // Deferred ForEach payloads derive their collection scope from the
      // shared declaration root, not their current flattened array offset.
      return payload.resolveDeclaredElements(in: childContext, placementRoot: context)
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
      ScopedContentPayload(resolveElements: { _, placementRoot in
        resolveElements(in: sequenceContext.applying(to: placementRoot))
      }))
  }

  package func appendPortalDeclaredChildren(
    in context: DeclaredPayloadTraversalContext, kindName: String, nextIndex: inout Int,
    into children: inout [PortalAttachmentContentPayload]
  ) {
    let sequenceContext = context.indexedChild(kind: .init(rawValue: kindName), index: nextIndex)
    nextIndex += 1
    children.append(
      PortalAttachmentContentPayload(resolveElements: { _, placementRoot in
        resolveElements(in: sequenceContext.applying(to: placementRoot))
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

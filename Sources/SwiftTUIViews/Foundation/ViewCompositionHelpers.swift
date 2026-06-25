package import SwiftTUICore

/// A scoped authored child payload that preserves authoring scope without
/// exposing `AnyView` as the transport type.
@MainActor
package struct ScopedContentPayload: Sendable {
  private let resolveElementsClosure: @MainActor @Sendable (ResolveContext) -> [ResolvedNode]

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    // Scoped payloads may resolve in a different part of the tree. Preserve
    // the original owner identity and ViewNode, but isolate future first-time
    // ordinal claims from the capture-site tracker.
    let authoringContext = makeCapturedAuthoringContext(from: authoringContext)
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
package struct CapturedSubviewPayload: Sendable {
  fileprivate var payload: ScopedContentPayload

  package init(_ payload: ScopedContentPayload) {
    self.payload = payload
  }

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    payload = ScopedContentPayload(
      authoringContext: authoringContext,
      content: content
    )
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    payload.resolve(in: context)
  }
}

@MainActor
package struct CapturedSubviewView: PrimitiveView, ResolvableView {
  package var payload: CapturedSubviewPayload

  package init(payload: CapturedSubviewPayload) {
    self.payload = payload
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context)
  }
}

@MainActor
package struct CapturedSubviewGroupView: PrimitiveView, ResolvableView {
  package var kindName: String
  package var payloads: [CapturedSubviewPayload]

  package init(
    kindName: String,
    payloads: [CapturedSubviewPayload]
  ) {
    self.kindName = kindName
    self.payloads = payloads
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return [
        resolveView(
          CapturedSubviewView(payload: payloads[0]),
          in: context
        )
      ]
    default:
      let scopedPayloads = payloads.map(\.payload)
      return [
        resolveScopedContentGroupElements(
          kindName: kindName,
          payloads: scopedPayloads,
          in: context
        )
      ]
    }
  }
}

package enum LazySubviewPayloadOrigin: Sendable, Equatable {
  case tabBody
  case navigationDestination
}

package enum LazySubviewLifecyclePolicy: Sendable, Equatable {
  case activeOnly
}

@MainActor
package enum LazySubviewPayloadStorage: Sendable {
  case scopedContent(ScopedContentPayload)
  case portal(PortalAttachmentContentPayload)
}

@MainActor
package struct LazySubviewPayload: Sendable {
  package var debugName: String
  package var origin: LazySubviewPayloadOrigin
  package var declarationIdentity: Identity?
  package var declarationStructuralPath: StructuralPath?
  package var lifecyclePolicy: LazySubviewLifecyclePolicy
  private var storage: LazySubviewPayloadStorage

  package init(
    debugName: String,
    origin: LazySubviewPayloadOrigin,
    declarationIdentity: Identity? = nil,
    declarationStructuralPath: StructuralPath? = nil,
    lifecyclePolicy: LazySubviewLifecyclePolicy = .activeOnly,
    storage: LazySubviewPayloadStorage
  ) {
    self.debugName = debugName
    self.origin = origin
    self.declarationIdentity = declarationIdentity
    self.declarationStructuralPath = declarationStructuralPath
    self.lifecyclePolicy = lifecyclePolicy
    self.storage = storage
  }

  package init(
    tabBody payload: ScopedContentPayload,
    debugName: String = "TabBody",
    declarationIdentity: Identity? = nil,
    declarationStructuralPath: StructuralPath? = nil
  ) {
    self.init(
      debugName: debugName,
      origin: .tabBody,
      declarationIdentity: declarationIdentity,
      declarationStructuralPath: declarationStructuralPath,
      storage: .scopedContent(payload)
    )
  }

  package init(
    navigationDestination payload: PortalAttachmentContentPayload,
    debugName: String = "NavigationDestination",
    declarationIdentity: Identity? = nil,
    declarationStructuralPath: StructuralPath? = nil
  ) {
    self.init(
      debugName: debugName,
      origin: .navigationDestination,
      declarationIdentity: declarationIdentity,
      declarationStructuralPath: declarationStructuralPath,
      storage: .portal(payload)
    )
  }

  package init<V: View>(
    navigationDestinationAuthoringContext authoringContext: AuthoringContext?,
    debugName: String = "NavigationDestination",
    declarationIdentity: Identity? = nil,
    declarationStructuralPath: StructuralPath? = nil,
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    self.init(
      navigationDestination: PortalAttachmentContentPayload(
        authoringContext: authoringContext,
        content: content
      ),
      debugName: debugName,
      declarationIdentity: declarationIdentity,
      declarationStructuralPath: declarationStructuralPath
    )
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolve(in: context)
    case .portal(let payload):
      return payload.resolve(in: context)
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveElements(in: context)
    case .portal(let payload):
      return [payload.resolve(in: context)]
    }
  }
}

package typealias NavigationDestinationPayload = LazySubviewPayload

@MainActor
package struct ScopedContentPayloadView: PrimitiveView, ResolvableView {
  package var payload: ScopedContentPayload

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context)
  }
}

@MainActor
package struct ScopedContentPayloadGroupView: PrimitiveView, ResolvableView {
  package var kindName: String
  package var payloads: [ScopedContentPayload]

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch payloads.count {
    case 0:
      return []
    case 1:
      return [
        resolveView(
          ScopedContentPayloadView(payload: payloads[0]),
          in: context
        )
      ]
    default:
      return [
        resolveScopedContentGroupElements(
          kindName: kindName,
          payloads: payloads,
          in: context
        )
      ]
    }
  }
}

@MainActor
private func resolveScopedContentGroupElements(
  kindName: String = "Group",
  payloads: [ScopedContentPayload],
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  in context: ResolveContext
) -> ResolvedNode {
  context.recordResolvedComputation()
  let resolvedChildren = payloads.enumerated().map { index, payload in
    resolveView(
      ScopedContentPayloadView(payload: payload),
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

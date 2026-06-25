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
package struct CapturedSubviewPayload: Sendable {
  fileprivate var payload: DeferredViewPayload

  package init(_ payload: DeferredViewPayload) {
    self.payload = payload
  }

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    payload = DeferredViewPayload(
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
      let deferredPayloads = payloads.map(\.payload)
      return [
        resolveDeferredGroupElements(
          kindName: kindName,
          payloads: deferredPayloads,
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
  case deferred(DeferredViewPayload)
  case portal(PortalContentPayload)
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
    tabBody payload: DeferredViewPayload,
    debugName: String = "TabBody",
    declarationIdentity: Identity? = nil,
    declarationStructuralPath: StructuralPath? = nil
  ) {
    self.init(
      debugName: debugName,
      origin: .tabBody,
      declarationIdentity: declarationIdentity,
      declarationStructuralPath: declarationStructuralPath,
      storage: .deferred(payload)
    )
  }

  package init(
    navigationDestination payload: PortalContentPayload,
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

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    switch storage {
    case .deferred(let payload):
      return payload.resolve(in: context)
    case .portal(let payload):
      return payload.resolve(in: context)
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    switch storage {
    case .deferred(let payload):
      return payload.resolveElements(in: context)
    case .portal(let payload):
      return [payload.resolve(in: context)]
    }
  }
}

package typealias NavigationDestinationPayload = LazySubviewPayload

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

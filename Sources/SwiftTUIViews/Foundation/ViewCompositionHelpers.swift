import SwiftTUICore

/// A scoped authored child payload that preserves authoring scope without
/// exposing `AnyView` as the transport type.
@MainActor
package struct ScopedContentPayload: Sendable {
  private let resolveElementsClosure:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  private let resolveEntityRoutedElementsClosure:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  private let resolveDeclaredElementsClosure:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]

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
    resolveElementsClosure = { context, _ in
      builder.resolveElements(in: context)
    }
    resolveEntityRoutedElementsClosure = { context, _ in
      [resolveView(builder, in: context)]
    }
    resolveDeclaredElementsClosure = { context, _ in
      withAuthoringContext(authoringContext) {
        [resolveView(builder.build(), in: context)]
      }
    }
  }

  package init(
    resolveElements:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  ) {
    resolveElementsClosure = resolveElements
    resolveEntityRoutedElementsClosure = resolveElements
    resolveDeclaredElementsClosure = resolveElements
  }

  /// Resolves a declared child through its own central seam, including its
  /// authored entity route before dynamic properties are prepared. Unlike a
  /// capture-slot wrapper, the declaration itself owns this graph position.
  package func resolveDeclaredElements(
    in context: ResolveContext, placementRoot: ResolveContext
  ) -> [ResolvedNode] {
    resolveDeclaredElementsClosure(context, placementRoot)
  }

  package func resolveElements(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    // Captured content resolves through whatever node hosts this payload — a
    // non-transparent hosting boundary. Host-escaping entity routes must not
    // be claimed at that node (see `ResolveContext.entityHosting`).
    resolveElementsClosure(
      context.asEntityHost(),
      (placementRoot ?? context).asEntityHost()
    )
  }

  /// Resolves the captured builder through the central graph seam below a
  /// caller-owned entity host.
  ///
  /// Ordinary scoped payloads lower transparently. Dormant entity hosts need a
  /// real central resolve at their qualified structural child so dynamic
  /// properties prepare against the same node whose authored metadata commits.
  package func resolveElementsInEntityRoutedHost(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    resolveEntityRoutedElementsClosure(
      context,
      (placementRoot ?? context).asEntityHost()
    )
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

  package func resolveInEntityRoutedHost(
    in context: ResolveContext,
    entityIdentity: EntityIdentity,
    structuralIdentity: TabDormantPayloadStructuralIdentity?
  ) -> ResolvedNode {
    let route = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath
    )
    return withResolveEntityRoute(route) {
      resolveView(
        EntityRoutedScopedContentHost(
          payload: self,
          entityIdentity: entityIdentity,
          structuralIdentity: structuralIdentity
        ),
        in: context
      )
    }
  }
}

/// Gives a caller-supplied entity route a concrete graph owner at the lazy
/// payload position. Authored content resolves unchanged at a fully qualified,
/// unowned structural child, so its own IDs and metadata cannot displace or
/// overwrite the dormant entity host.
@MainActor
private struct EntityRoutedScopedContentHost: PrimitiveView, ResolvableView {
  var payload: ScopedContentPayload
  var entityIdentity: EntityIdentity
  var structuralIdentity: TabDormantPayloadStructuralIdentity?

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentContext = context.child(
      component: tabContentValueComponent(structuralIdentity)
    )
    // Keep the stable dormant entity visible as ancestry for a nested TabView,
    // but leave the qualified authored child unowned: the route is bound to the
    // outer host's path and therefore cannot claim `contentContext`. A public
    // `.id` can still own the child without displacing the tab lifetime.
    let ancestryRoute = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath
    )
    let content = withResolveEntityRoute(ancestryRoute) {
      normalizeResolvedElements(
        payload.resolveElementsInEntityRoutedHost(
          in: contentContext,
          placementRoot: context
        ),
        in: contentContext
      )
    }
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("TabContentEntityHost"),
        children: [content],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

private func tabContentValueComponent(
  _ identity: TabDormantPayloadStructuralIdentity?
) -> IdentityComponent {
  guard let identity else {
    return .named("TabContentValue")
  }
  let tag = identity.typedTagComponent.reduce(into: "") { result, character in
    switch character {
    case "%": result.append("%25")
    case "/": result.append("%2F")
    case "]": result.append("%5D")
    case ";": result.append("%3B")
    case "=": result.append("%3D")
    default: result.append(character)
    }
  }
  return IdentityComponent(
    rawValue:
      "TabContentValue[tag=\(tag);optional=\(identity.includeOptional);occurrence=\(identity.occurrence);generation=\(identity.generation)]"
  )
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
  /// Resolve only while active, but preserve explicitly certified value-state
  /// slots in the declaring lazy container's bounded dormant archive.
  case dormantStatePreserving
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

  package func resolve(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> ResolvedNode {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolve(in: context, placementRoot: placementRoot)
    case .portal(let payload):
      return payload.resolve(in: context, placementRoot: placementRoot)
    }
  }

  package func resolveInEntityRoutedHost(
    in context: ResolveContext,
    entityIdentity: EntityIdentity,
    structuralIdentity: TabDormantPayloadStructuralIdentity?
  ) -> ResolvedNode {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveInEntityRoutedHost(
        in: context,
        entityIdentity: entityIdentity,
        structuralIdentity: structuralIdentity
      )
    case .portal(let payload):
      return payload.resolve(in: context, placementRoot: context)
    }
  }

  package func resolveElements(
    in context: ResolveContext,
    placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveElements(in: context, placementRoot: placementRoot)
    case .portal(let payload):
      return payload.resolveElements(in: context, placementRoot: placementRoot)
    }
  }
}

package typealias NavigationDestinationPayload = LazySubviewPayload

@MainActor
package struct ScopedContentPayloadView: PrimitiveView, ResolvableView {
  package var payload: ScopedContentPayload
  package var placementRoot: ResolveContext? = nil

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    payload.resolveElements(in: context, placementRoot: placementRoot)
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
      return payloads[0].resolveElements(
        in: context,
        placementRoot: context
      )
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
    transactionSnapshot: context.transaction,
    layoutBehavior: layoutBehavior,
    layoutMetadata: layoutMetadata,
    drawMetadata: drawMetadata,
    semanticMetadata: semanticMetadata
  )
}

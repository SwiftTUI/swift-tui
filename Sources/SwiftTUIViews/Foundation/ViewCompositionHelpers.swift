import SwiftTUICore

/// Authored content with a typed continuation and captured state-owner scope.
@MainActor
package struct ScopedContentPayload: Sendable {
  private let elements:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>
  private let entityElements:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>
  private let declaredElements:
    @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>

  package init<V: View>(
    authoringContext: AuthoringContext? = currentAuthoringContext(),
    @ViewBuilder content: @escaping @MainActor () -> V
  ) {
    let authoringContext = makeCapturedAuthoringContext(from: authoringContext)
    let builder = ScopedBuilder(authoringContext: authoringContext, content: content)
    elements = { context, _ in builder.makeResolveWork(in: context) }
    entityElements = { context, _ in resolveViewWork(builder, in: context).map { [$0] } }
    declaredElements = { context, _ in
      withAuthoringContext(authoringContext) {
        resolveViewWork(builder.build(), in: context).map { [$0] }
      }
    }
  }

  package init(
    resolveElements:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> [ResolvedNode]
  ) {
    self.init(resolveElementsWork: { context, root in
      .deferred { .value(resolveElements(context, root)) }
    })
  }

  package init(
    resolveElementsWork:
      @escaping @MainActor @Sendable (ResolveContext, ResolveContext) -> ResolveWork<[ResolvedNode]>
  ) {
    elements = resolveElementsWork
    entityElements = resolveElementsWork
    declaredElements = resolveElementsWork
  }

  package func resolveDeclaredElements(in context: ResolveContext, placementRoot: ResolveContext)
    -> [ResolvedNode]
  {
    resolveDeclaredElementsWork(in: context, placementRoot: placementRoot).run()
  }

  package func resolveDeclaredElementsWork(
    in context: ResolveContext, placementRoot: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    declaredElements(context, placementRoot)
  }

  package func resolveElements(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> [ResolvedNode]
  {
    resolveElementsWork(in: context, placementRoot: placementRoot).run()
  }

  package func resolveElementsWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<[ResolvedNode]>
  {
    elements(context.asEntityHost(), (placementRoot ?? context).asEntityHost())
  }

  package func resolveElementsInEntityRoutedHost(
    in context: ResolveContext, placementRoot: ResolveContext? = nil
  ) -> [ResolvedNode] {
    resolveElementsInEntityRoutedHostWork(in: context, placementRoot: placementRoot).run()
  }

  package func resolveElementsInEntityRoutedHostWork(
    in context: ResolveContext, placementRoot: ResolveContext? = nil
  ) -> ResolveWork<[ResolvedNode]> {
    entityElements(context, (placementRoot ?? context).asEntityHost())
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

  package func resolveInEntityRoutedHost(
    in context: ResolveContext, entityIdentity: EntityIdentity,
    structuralIdentity: TabDormantPayloadStructuralIdentity?
  ) -> ResolvedNode {
    resolveInEntityRoutedHostWork(
      in: context, entityIdentity: entityIdentity, structuralIdentity: structuralIdentity
    ).run()
  }

  package func resolveInEntityRoutedHostWork(
    in context: ResolveContext, entityIdentity: EntityIdentity,
    structuralIdentity: TabDormantPayloadStructuralIdentity?
  ) -> ResolveWork<ResolvedNode> {
    let route = ResolveEntityRoute(identity: entityIdentity, structuralPath: context.structuralPath)
    return withResolveEntityRoute(route) {
      resolveViewWork(
        EntityRoutedScopedContentHost(
          payload: self, entityIdentity: entityIdentity,
          structuralIdentity: structuralIdentity), in: context)
    }
  }
}

/// Gives a caller-supplied entity route a concrete graph owner at the lazy
/// payload position. Authored content resolves unchanged at a fully qualified,
/// unowned structural child, so its own IDs and metadata cannot displace or
/// overwrite the dormant entity host.
@MainActor
private struct EntityRoutedScopedContentHost: PrimitiveView, IterativeResolvableView {
  var payload: ScopedContentPayload
  var entityIdentity: EntityIdentity
  var structuralIdentity: TabDormantPayloadStructuralIdentity?

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
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
    return withResolveEntityRoute(ancestryRoute) {
      payload.resolveElementsInEntityRoutedHostWork(in: contentContext, placementRoot: context).map
      {
        normalizeResolvedElements($0, in: contentContext)
      }
    }.map { content in
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
package struct CapturedSubviewView: PrimitiveView, IterativeResolvableView {
  package var payload: CapturedSubviewPayload

  package init(payload: CapturedSubviewPayload) {
    self.payload = payload
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    payload.resolveElementsWork(in: context)
  }
}

@MainActor
package struct CapturedSubviewGroupView: PrimitiveView, IterativeResolvableView {
  package var kindName: String
  package var payloads: [CapturedSubviewPayload]

  package init(
    kindName: String,
    payloads: [CapturedSubviewPayload]
  ) {
    self.kindName = kindName
    self.payloads = payloads
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    switch payloads.count {
    case 0: return .value([])
    case 1:
      return resolveViewWork(CapturedSubviewView(payload: payloads[0]), in: context).map { [$0] }
    default:
      return resolveScopedContentGroupElementsWork(
        kindName: kindName, payloads: payloads.map(\.payload), in: context
      ).map { [$0] }
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
package struct ScopedContentPayloadView: PrimitiveView, IterativeResolvableView {
  package var payload: ScopedContentPayload
  package var placementRoot: ResolveContext? = nil

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    payload.resolveElementsWork(in: context, placementRoot: placementRoot)
  }
}

@MainActor
package struct ScopedContentPayloadGroupView: PrimitiveView, IterativeResolvableView {
  package var kindName: String
  package var payloads: [ScopedContentPayload]

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    switch payloads.count {
    case 0: return .value([])
    case 1: return payloads[0].resolveElementsWork(in: context, placementRoot: context)
    default:
      return resolveScopedContentGroupElementsWork(
        kindName: kindName, payloads: payloads, in: context
      ).map { [$0] }
    }
  }
}

@MainActor
private func resolveScopedContentGroupElementsWork(
  kindName: String = "Group",
  payloads: [ScopedContentPayload],
  layoutBehavior: LayoutBehavior = .intrinsic,
  layoutMetadata: LayoutMetadata = .init(),
  drawMetadata: DrawMetadata = DrawMetadata(),
  semanticMetadata: SemanticMetadata = SemanticMetadata(),
  in context: ResolveContext
) -> ResolveWork<ResolvedNode> {
  context.recordResolvedComputation()
  let result = DeclaredChildrenWorkState()
  return resolveSequentially(Array(payloads.enumerated())) { index, payload in
    payload.resolveElementsWork(
      in: context.indexedChild(kind: .init(rawValue: kindName), index: index),
      placementRoot: context
    ).map { result.nodes.append(contentsOf: $0) }
  }.map {
    let resolvedChildren = result.nodes

    return ResolvedNode(
      identity: context.identity,
      kind: .view(kindName),
      typeDiscriminator: kindName == "Group"
        ? ObjectIdentifier(SynthesizedGroupWrapperMarker.self) : nil,
      children: resolvedChildren,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutBehavior: layoutBehavior,
      layoutMetadata: layoutMetadata,
      drawMetadata: drawMetadata,
      semanticMetadata: semanticMetadata
    )
  }
}

extension CapturedSubviewPayload {
  package func resolveElementsWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    payload.resolveElementsWork(in: context)
  }
  package func resolveWork(in context: ResolveContext) -> ResolveWork<ResolvedNode> {
    payload.resolveWork(in: context)
  }
}

extension LazySubviewPayload {
  package func resolveWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<ResolvedNode>
  {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveWork(in: context, placementRoot: placementRoot)
    case .portal(let payload): return payload.resolveWork(in: context, placementRoot: placementRoot)
    }
  }
  package func resolveElementsWork(in context: ResolveContext, placementRoot: ResolveContext? = nil)
    -> ResolveWork<[ResolvedNode]>
  {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveElementsWork(in: context, placementRoot: placementRoot)
    case .portal(let payload):
      return payload.resolveElementsWork(in: context, placementRoot: placementRoot)
    }
  }
  package func resolveInEntityRoutedHostWork(
    in context: ResolveContext, entityIdentity: EntityIdentity,
    structuralIdentity: TabDormantPayloadStructuralIdentity?
  ) -> ResolveWork<ResolvedNode> {
    switch storage {
    case .scopedContent(let payload):
      return payload.resolveInEntityRoutedHostWork(
        in: context, entityIdentity: entityIdentity, structuralIdentity: structuralIdentity)
    case .portal(let payload): return payload.resolveWork(in: context, placementRoot: context)
    }
  }
}

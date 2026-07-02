package import SwiftTUICore

package struct ResolveEntityRoute: Sendable {
  package var identity: EntityIdentity
  package var structuralPath: StructuralPath
  /// True when the providing modifier re-roots its content to an identity that
  /// escapes the enclosing host's identity subtree (``ExactIdentityModifier``'s
  /// wholesale replacement). Escaping routes are suppressed at entity-hosting
  /// boundaries (``ResolveContext/entityHosting``): the host node must stay a
  /// positional node and never claim, or be adopted for, an entity that
  /// belongs to re-rooted content inside it.
  package var escapesHostingBoundary: Bool

  package init(
    identity: EntityIdentity,
    structuralPath: StructuralPath,
    escapesHostingBoundary: Bool = false
  ) {
    self.identity = identity
    self.structuralPath = structuralPath
    self.escapesHostingBoundary = escapesHostingBoundary
  }
}

package enum ResolveEntityRouteStorage {
  @TaskLocal package static var current: ResolveEntityRoute?
}

@MainActor
package protocol EntityRouteProvidingView {
  func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity?
  var providesHostEscapingEntityRoute: Bool { get }
}

extension EntityRouteProvidingView {
  package var providesHostEscapingEntityRoute: Bool { false }
}

@MainActor
package protocol EntityRouteProvidingModifier {
  func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity
  var providesHostEscapingEntityRoute: Bool { get }
}

extension EntityRouteProvidingModifier {
  package var providesHostEscapingEntityRoute: Bool { false }
}

@MainActor
package func withResolveEntityRoute<Result>(
  _ route: ResolveEntityRoute?,
  _ body: () -> Result
) -> Result {
  ResolveEntityRouteStorage.$current.withValue(route) {
    body()
  }
}

@MainActor
package func currentEntityRouteIdentity(
  in context: ResolveContext
) -> EntityIdentity? {
  guard let route = ResolveEntityRouteStorage.current,
    route.structuralPath == context.structuralPath,
    !(route.escapesHostingBoundary && context.entityHosting)
  else {
    return nil
  }
  return route.identity
}

@MainActor
package func entityRouteIdentity<V: View>(
  for view: V,
  in context: ResolveContext
) -> EntityIdentity? {
  if let routed = currentEntityRouteIdentity(in: context) {
    return routed
  }

  let erased: Any = view
  guard let provider = erased as? any EntityRouteProvidingView else {
    return nil
  }
  if context.entityHosting, provider.providesHostEscapingEntityRoute {
    return nil
  }
  guard let entity = provider.resolveEntityRouteIdentity(in: context) else {
    return nil
  }
  // A forwarded claim may re-fire at every wrapper-derived interior
  // `resolveView` of the same chain (a `.frame` content wrapper re-resolves
  // the chain one level down and the conformance forwards again). For a
  // host-escaping route the interior re-claim must not cross-identity adopt
  // the mid-evaluation enclosing node: the escaping re-root gives the interior
  // subtree its own stable identities, and pulling the enclosing node across
  // aliases the parent's committed child pairing (the stamp-coherence trap).
  // Host-descending routes (`IDModifier`) keep the re-entrant adoption — it is
  // the transparent-chain collapse spanning a host boundary, and the entity's
  // state legitimately folds into the enclosing node (a wrapper toggle hands
  // the prior node to the arriving host-content position through it).
  if provider.providesHostEscapingEntityRoute,
    context.viewGraph?.entityRouteTargetsMidEvaluationNode(
      entity,
      claimedAt: context.identity
    ) == true
  {
    return nil
  }
  return entity
}

package import SwiftTUICore

package struct ResolveEntityRoute: Sendable {
  package var identity: EntityIdentity
  package var structuralPath: StructuralPath

  package init(
    identity: EntityIdentity,
    structuralPath: StructuralPath
  ) {
    self.identity = identity
    self.structuralPath = structuralPath
  }
}

package enum ResolveEntityRouteStorage {
  @TaskLocal package static var current: ResolveEntityRoute?
}

@MainActor
package protocol EntityRouteProvidingView {
  func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity?
}

@MainActor
package protocol EntityRouteProvidingModifier {
  func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity
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
    route.structuralPath == context.structuralPath
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
  return (erased as? any EntityRouteProvidingView)?
    .resolveEntityRouteIdentity(in: context)
}

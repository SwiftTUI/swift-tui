import SwiftTUICore

/// A destination-relative builder-slot path for deferred scoped/portal
/// payloads. Unlike a concrete `ResolveContext`, this can be derived while the
/// content is authored and applied later at whichever host resolves it.
package struct DeclaredPayloadTraversalContext: Sendable {
  private var components: [IdentityComponent]

  package static let root = Self(components: [])

  package func child(component: IdentityComponent) -> Self {
    Self(components: components + [component])
  }

  package func indexedChild(
    kind: IdentityComponent,
    index: Int
  ) -> Self {
    child(
      component: .init(rawValue: "\(kind.rawValue)[\(index)]")
    )
  }

  package func applying(
    to placementRoot: ResolveContext
  ) -> ResolveContext {
    components.reduce(placementRoot) { context, component in
      context.child(component: component)
    }
  }
}

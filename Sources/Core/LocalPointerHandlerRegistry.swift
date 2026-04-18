package enum LocalPointerButton: Equatable, Sendable {
  case primary
  case middle
  case secondary
}

package struct LocalPointerScrollContext: Equatable, Sendable {
  package var viewportRect: Rect
  package var contentBounds: Rect

  package init(
    viewportRect: Rect,
    contentBounds: Rect
  ) {
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
  }
}

package struct LocalPointerEvent: Equatable, Sendable {
  package enum Kind: Equatable, Sendable {
    case down(LocalPointerButton)
    case up(LocalPointerButton)
    case moved
    case dragged(LocalPointerButton)
    case scrolled(deltaX: Int, deltaY: Int)
  }

  package var kind: Kind
  package var location: Point
  package var targetRect: Rect
  package var scrollContext: LocalPointerScrollContext?
  package var timestamp: MonotonicInstant

  package init(
    kind: Kind,
    location: Point,
    targetRect: Rect,
    scrollContext: LocalPointerScrollContext? = nil,
    timestamp: MonotonicInstant = .now()
  ) {
    self.kind = kind
    self.location = location
    self.targetRect = targetRect
    self.scrollContext = scrollContext
    self.timestamp = timestamp
  }
}

@MainActor
package final class LocalPointerHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (LocalPointerEvent) -> Bool

  private var handlers: [RouteID: Handler] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalPointerHandlerRegistry, rhs: LocalPointerHandlerRegistry
  )
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    routeID: RouteID,
    handler: @escaping Handler
  ) {
    handlers[routeID] = handler
    ViewNodeContext.current?.recordPointerHandlerRegistration(
      routeID: routeID,
      handler: handler
    )
  }

  package func hasHandler(
    routeID: RouteID
  ) -> Bool {
    handlers[routeID] != nil
  }

  @discardableResult
  package func dispatch(
    routeID: RouteID,
    event: LocalPointerEvent
  ) -> Bool {
    handlers[routeID]?(event) ?? false
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for routeID in handlers.keys.filter({
      identityMatchesAnySubtreeRoot($0.identity, roots: roots)
    }) {
      handlers.removeValue(forKey: routeID)
    }
  }

  package func snapshot() -> [RouteID: Handler] {
    handlers
  }

  package func restore(_ snapshot: [RouteID: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (routeID, handler) in snapshot {
      handlers[routeID] = handler
    }
  }
}

private func identityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}

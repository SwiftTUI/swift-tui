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

  package init(
    kind: Kind,
    location: Point,
    targetRect: Rect,
    scrollContext: LocalPointerScrollContext? = nil
  ) {
    self.kind = kind
    self.location = location
    self.targetRect = targetRect
    self.scrollContext = scrollContext
  }
}

// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// Contains non-Sendable closures (Handler = (LocalPointerEvent) -> Bool).
// All mutable state protected by OSAllocatedUnfairLock.
package final class LocalPointerHandlerRegistry: @unchecked Sendable, Equatable {
  package typealias Handler = (LocalPointerEvent) -> Bool

  private struct Storage {
    var handlers: [RouteID: Handler] = [:]
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (lhs: LocalPointerHandlerRegistry, rhs: LocalPointerHandlerRegistry)
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    routeID: RouteID,
    handler: @escaping Handler
  ) {
    storage.withLockUnchecked { storage in
      storage.handlers[routeID] = handler
    }
  }

  package func hasHandler(
    routeID: RouteID
  ) -> Bool {
    storage.withLockUnchecked { storage in
      storage.handlers[routeID] != nil
    }
  }

  @discardableResult
  package func dispatch(
    routeID: RouteID,
    event: LocalPointerEvent
  ) -> Bool {
    let handler = storage.withLockUnchecked { storage in
      storage.handlers[routeID]
    }
    return handler?(event) ?? false
  }

  package func reset() {
    storage.withLockUnchecked { storage in
      storage.handlers.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> [RouteID: Handler] {
    storage.withLockUnchecked { storage in
      storage.handlers
    }
  }

  package func restore(_ snapshot: [RouteID: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    storage.withLockUnchecked { storage in
      for (routeID, handler) in snapshot {
        storage.handlers[routeID] = handler
      }
    }
  }
}

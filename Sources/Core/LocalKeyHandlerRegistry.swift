package enum LocalKeyEvent: Equatable, Sendable {
  case character(Character)
  case enter
  case space
  case tab
  case shiftTab
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case backspace
  case escape
  case ctrlC
}

@MainActor
package final class LocalKeyHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (LocalKeyEvent) -> Bool

  private var handlers: [Identity: Handler] = [:]

  package init() {}

  nonisolated package static func == (lhs: LocalKeyHandlerRegistry, rhs: LocalKeyHandlerRegistry)
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    handlers[identity] = handler
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    event: LocalKeyEvent
  ) -> Bool {
    handlers[identity]?(event) ?? false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    handlers[identity] != nil
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: Handler] {
    handlers
  }

  package func restore(_ snapshot: [Identity: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlers[identity] = handler
    }
  }
}

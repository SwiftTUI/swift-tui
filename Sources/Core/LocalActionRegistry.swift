// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// Contains non-Sendable closures (Handler = () -> Bool).
// All mutable state protected by OSAllocatedUnfairLock.
package final class LocalActionRegistry: @unchecked Sendable, Equatable {
  package typealias Handler = () -> Bool

  private struct Storage {
    var handlers: [Identity: Handler] = [:]
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (lhs: LocalActionRegistry, rhs: LocalActionRegistry) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    storage.withLockUnchecked { storage in
      storage.handlers[identity] = handler
    }
  }

  @discardableResult
  package func dispatch(identity: Identity) -> Bool {
    let handler = storage.withLockUnchecked { storage in
      storage.handlers[identity]
    }
    return handler?() ?? false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    storage.withLockUnchecked { storage in
      storage.handlers[identity] != nil
    }
  }

  package func reset() {
    storage.withLockUnchecked { storage in
      storage.handlers.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> [Identity: Handler] {
    storage.withLockUnchecked { storage in
      storage.handlers
    }
  }

  package func restore(_ snapshot: [Identity: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    storage.withLockUnchecked { storage in
      for (identity, handler) in snapshot {
        storage.handlers[identity] = handler
      }
    }
  }
}

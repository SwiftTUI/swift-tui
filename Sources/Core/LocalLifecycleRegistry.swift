// SAFETY: Contains non-Sendable closures (@MainActor Handler). Only transferred between
// the registry and RetainedResolveFrame, both of which are exclusively accessed on @MainActor.
package struct LifecycleHandlerSnapshot: @unchecked Sendable {
  package var appearHandlers: [String: LocalLifecycleRegistry.Handler]
  package var disappearHandlers: [String: LocalLifecycleRegistry.Handler]

  package init(
    appearHandlers: [String: LocalLifecycleRegistry.Handler] = [:],
    disappearHandlers: [String: LocalLifecycleRegistry.Handler] = [:]
  ) {
    self.appearHandlers = appearHandlers
    self.disappearHandlers = disappearHandlers
  }
}

// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// Contains non-Sendable closures (@MainActor Handler). All mutable state protected by OSAllocatedUnfairLock.
package final class LocalLifecycleRegistry: @unchecked Sendable, Equatable {
  package typealias Handler = @MainActor () -> Void

  private struct Storage {
    var appearHandlers: [String: Handler] = [:]
    var disappearHandlers: [String: Handler] = [:]
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (
    lhs: LocalLifecycleRegistry,
    rhs: LocalLifecycleRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func registerAppear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    storage.withLockUnchecked { storage in
      storage.appearHandlers[handlerID] = handler
    }
  }

  package func registerDisappear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    storage.withLockUnchecked { storage in
      storage.disappearHandlers[handlerID] = handler
    }
  }

  package func appearHandler(
    for handlerID: String
  ) -> Handler? {
    storage.withLockUnchecked { storage in
      storage.appearHandlers[handlerID]
    }
  }

  package func disappearHandler(
    for handlerID: String
  ) -> Handler? {
    storage.withLockUnchecked { storage in
      storage.disappearHandlers[handlerID]
    }
  }

  package func reset() {
    storage.withLockUnchecked { storage in
      storage.appearHandlers.removeAll(keepingCapacity: true)
      storage.disappearHandlers.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> LifecycleHandlerSnapshot {
    storage.withLockUnchecked { storage in
      .init(
        appearHandlers: storage.appearHandlers,
        disappearHandlers: storage.disappearHandlers
      )
    }
  }

  package func restore(
    _ snapshot: LifecycleHandlerSnapshot
  ) {
    guard !snapshot.appearHandlers.isEmpty || !snapshot.disappearHandlers.isEmpty else {
      return
    }

    storage.withLockUnchecked { storage in
      for (handlerID, handler) in snapshot.appearHandlers {
        storage.appearHandlers[handlerID] = handler
      }
      for (handlerID, handler) in snapshot.disappearHandlers {
        storage.disappearHandlers[handlerID] = handler
      }
    }
  }
}

// SAFETY: Contains non-Sendable closures (@MainActor Handler). Access is
// confined to @MainActor.
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

@MainActor
package final class LocalLifecycleRegistry: Equatable {
  package typealias Handler = @MainActor () -> Void

  private var appearHandlers: [String: Handler] = [:]
  private var disappearHandlers: [String: Handler] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalLifecycleRegistry,
    rhs: LocalLifecycleRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func registerAppear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    appearHandlers[handlerID] = handler
  }

  package func registerDisappear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    disappearHandlers[handlerID] = handler
  }

  package func appearHandler(
    for handlerID: String
  ) -> Handler? {
    appearHandlers[handlerID]
  }

  package func disappearHandler(
    for handlerID: String
  ) -> Handler? {
    disappearHandlers[handlerID]
  }

  package func reset() {
    appearHandlers.removeAll(keepingCapacity: true)
    disappearHandlers.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> LifecycleHandlerSnapshot {
    .init(
      appearHandlers: appearHandlers,
      disappearHandlers: disappearHandlers
    )
  }

  package func restore(
    _ snapshot: LifecycleHandlerSnapshot
  ) {
    guard !snapshot.appearHandlers.isEmpty || !snapshot.disappearHandlers.isEmpty else {
      return
    }

    for (handlerID, handler) in snapshot.appearHandlers {
      appearHandlers[handlerID] = handler
    }
    for (handlerID, handler) in snapshot.disappearHandlers {
      disappearHandlers[handlerID] = handler
    }
  }
}

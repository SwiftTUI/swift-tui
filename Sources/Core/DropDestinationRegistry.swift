/// A registered file-drop handler. Returning `true` marks the drop
/// consumed; returning `false` bubbles to the next outer scope on the
/// focus chain. The final outer scope that returns `false` yields
/// overall consumption=false, and the runtime falls back to re-emitting
/// the paste as ordinary characters.
package typealias DropDestinationHandler =
  @MainActor @Sendable ([DroppedPath]) -> Bool

/// Stores file-drop destinations keyed by scope `Identity` and
/// dispatches a single drop event leafmost-first along the current
/// focus chain. Mirrors `CommandRegistry` in lifetime and lifecycle;
/// the direction reversal is intentional — drop dispatch favors the
/// innermost attention target, the inverse of broad-shortcut routing.
@MainActor
package final class DropDestinationRegistry: Equatable {
  private var handlersByScope: [Identity: DropDestinationHandler] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: DropDestinationRegistry,
    rhs: DropDestinationRegistry
  ) -> Bool {
    lhs === rhs
  }

  /// Registers (or replaces) the drop handler at `scope`. A second
  /// registration at the same identity is undefined at the public API
  /// level — the `.dropDestination` modifier is only valid on
  /// `ActionScope` conformers, so two registrations at one scope
  /// identity imply two `.dropDestination` modifiers on the same scope,
  /// which is a programming error; last-write-wins here.
  package func register(
    at scope: Identity,
    handler: @escaping DropDestinationHandler
  ) {
    handlersByScope[scope] = handler
    ViewNodeContext.current?.recordDropDestinationRegistration(
      scope: scope,
      handler: handler
    )
  }

  /// Returns the registered handler at `scope`, if any.
  package func handler(at scope: Identity) -> DropDestinationHandler? {
    handlersByScope[scope]
  }

  /// Walks `scopePath` from leaf to root, invoking the first registered
  /// handler. If the handler returns `true`, dispatch stops. If it
  /// returns `false`, dispatch continues outward looking for another
  /// handler. Returns `true` if any handler consumed; `false` if every
  /// handler (or none) declined.
  ///
  /// `scopePath` is provided shallowest-first by the runtime, matching
  /// `CommandRegistry.dispatch(key:along:)`. This method reverses it
  /// internally so callers don't need to know the registry's direction.
  @discardableResult
  package func dispatch(
    paths: [DroppedPath],
    along scopePath: [Identity]
  ) -> Bool {
    for scope in scopePath.reversed() {
      guard let handler = handlersByScope[scope] else { continue }
      if handler(paths) {
        return true
      }
    }
    return false
  }

  /// Clears every registration.
  package func reset() {
    handlersByScope.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: DropDestinationHandler] {
    handlersByScope
  }

  package func restore(
    _ snapshot: [Identity: DropDestinationHandler]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlersByScope[identity] = handler
    }
  }

  /// Removes every registration whose identity sits under any of
  /// `roots`. Called by `RuntimeRegistrationSet.removeSubtrees` during
  /// partial re-resolves so stale handlers don't linger.
  package func removeSubtrees(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else { return }
    for identity in handlersByScope.keys
    where dropDestinationIdentityMatchesAnySubtreeRoot(identity, roots: roots) {
      handlersByScope.removeValue(forKey: identity)
    }
  }
}

private func dropDestinationIdentityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}

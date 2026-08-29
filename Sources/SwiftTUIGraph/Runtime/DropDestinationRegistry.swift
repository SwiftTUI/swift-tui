/// A registered file-drop handler.
/// A return value of `true` marks the drop as consumed.
/// A return value of `false` sends the drop to the next outer scope on the focus chain.
/// If the final outer scope returns `false`, the overall consumption value is `false`.
/// Then the runtime emits the paste as ordinary characters.
public struct DropContext: Equatable, Sendable {
  public var location: Point?
  public var pointer: PointerLocation?
  public var modifiers: EventModifiers

  public init(
    location: Point? = nil,
    pointer: PointerLocation? = nil,
    modifiers: EventModifiers = []
  ) {
    self.location = location
    self.pointer = pointer
    self.modifiers = modifiers
  }
}

package typealias DropDestinationHandler =
  @MainActor @Sendable ([DroppedPath], DropContext) -> Bool

package struct DropDestinationRegistrySnapshot: Sendable {
  package var handlersByScope: [Identity: DropDestinationHandler]
  package var ownersByScope: [Identity: RuntimeRegistrationOwnerKey]

  package init(
    handlersByScope: [Identity: DropDestinationHandler] = [:],
    ownersByScope: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    self.handlersByScope = handlersByScope
    self.ownersByScope = ownersByScope
  }

  package var isEmpty: Bool {
    handlersByScope.isEmpty
  }
}

/// Stores file-drop destinations keyed by scope `Identity` and
/// dispatches a single drop event leafmost-first along the current
/// focus chain. Mirrors `CommandRegistry` in lifetime and lifecycle;
/// the direction reversal is intentional — drop dispatch favors the
/// innermost attention target, the inverse of broad-shortcut routing.
@MainActor
package final class DropDestinationRegistry: Equatable {
  private var store = IdentityKeyedRegistryStorage<DropDestinationHandler>()

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
    let owner = RuntimeRegistrationOwnerKey.current(identity: scope)
    store.set(handler, for: scope, owner: owner)
    ViewNodeContext.current?.recordDropDestinationRegistration(
      DropDestinationRegistrySnapshot(
        handlersByScope: [scope: handler],
        ownersByScope: [scope: owner]
      )
    )
  }

  package func register(
    at scope: Identity,
    handler: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) {
    register(at: scope) { paths, _ in
      handler(paths)
    }
  }

  /// Returns the registered handler at `scope`, if any.
  package func handler(at scope: Identity) -> DropDestinationHandler? {
    store[scope]
  }

  package func hasHandler(at scope: Identity) -> Bool {
    store[scope] != nil
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
    context: DropContext = .init(),
    along scopePath: [Identity]
  ) -> Bool {
    for scope in scopePath.reversed() {
      guard let handler = store[scope] else { continue }
      if handler(paths, context) {
        return true
      }
    }
    return false
  }

  /// Clears every registration.
  package func reset() {
    store.reset()
  }

  package func snapshot() -> DropDestinationRegistrySnapshot {
    DropDestinationRegistrySnapshot(
      handlersByScope: store.values,
      ownersByScope: store.ownersByIdentity
    )
  }

  package func restore(_ snapshot: DropDestinationRegistrySnapshot) {
    store.restore(snapshot.handlersByScope, ownersByIdentity: snapshot.ownersByScope)
  }

  /// Removes every registration whose identity sits under any of
  /// `roots`. Called by `RuntimeRegistrationSet.removeSubtrees` during
  /// partial re-resolves so stale handlers don't linger.
  package func removeSubtrees(rootedAt roots: [Identity]) {
    store.removeSubtrees(rootedAt: roots)
  }

  /// The node axis of teardown — see
  /// ``RuntimeRegistry/removeUnjustifiedRegistrations(_:)``.
  package func removeUnjustifiedRegistrations(
    _ record: (ViewNodeID) -> NodeHandlers?
  ) {
    store.removeUnjustified { identity, owner in
      // An entry restored without an owner carries no node claim to check.
      guard let viewNodeID = owner.viewNodeID else {
        return true
      }
      return record(viewNodeID)?.dropDestination.handlersByScope[identity] != nil
    }
  }
}

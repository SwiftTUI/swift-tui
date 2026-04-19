/// Type-erased handle the recognizer uses to write into and reset a
/// `@GestureState` storage cell. Mirrors the shape of
/// `FocusStateLocation` in the focus subsystem.
@MainActor
public final class AnyGestureStateBinding {
  private let _setValue: (Any) -> Void
  private let _reset: () -> Void
  public let valueType: Any.Type

  public init<T>(
    valueType: T.Type,
    setValue: @escaping (T) -> Void,
    reset: @escaping () -> Void
  ) {
    self.valueType = valueType
    self._setValue = { if let t = $0 as? T { setValue(t) } }
    self._reset = reset
  }

  /// Writes `value` if it matches this binding's `valueType`; silently
  /// ignores type mismatches (defensive -- updater/recognizer type
  /// agreement is enforced at the `.updating` call site).
  public func setValueErased(_ value: Any) {
    _setValue(value)
  }

  public func resetToSeed() {
    _reset()
  }
}

/// Holds `@GestureState` bindings attached to the view tree. One
/// identity can register multiple bindings (a gesture tree with
/// several `.updating($state)` nodes).
@MainActor
package final class LocalGestureStateRegistry: Equatable {
  private var bindingsByIdentity: [Identity: [AnyGestureStateBinding]] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalGestureStateRegistry,
    rhs: LocalGestureStateRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    bindingsByIdentity[identity, default: []].append(binding)
    ViewNodeContext.current?.recordGestureStateBinding(
      identity: identity,
      binding: binding
    )
  }

  package func bindings(for identity: Identity) -> [AnyGestureStateBinding] {
    bindingsByIdentity[identity] ?? []
  }

  /// Drops all bindings for `identity` without firing their reset
  /// closures. `.gesture(_:)` calls this before registering a fresh
  /// recognizer tree so the per-resolve `register` calls don't
  /// accumulate stale bindings pointing to discarded
  /// `GestureStateBox` instances from prior body evaluations.
  ///
  /// Does NOT call `resetToSeed` on the dropped bindings — those
  /// bindings point to boxes from previous body runs that are already
  /// detached from the view's live state slot; resetting them would
  /// either no-op or (worse) trample the current gesture's in-flight
  /// state.
  package func clearBindings(for identity: Identity) {
    bindingsByIdentity.removeValue(forKey: identity)
  }

  package func resetAll(for identity: Identity) {
    for binding in bindings(for: identity) {
      binding.resetToSeed()
    }
  }

  package func reset() {
    // Full-frame rebuilds call this; do NOT fire `resetToSeed` on
    // registered bindings — a gesture in progress would have its
    // `@GestureState` value silently wiped between frames. Subtree
    // teardown (`removeSubtrees`) is the correct place to reset
    // values because that genuinely corresponds to the view
    // disappearing.
    bindingsByIdentity.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    preserving preservedIdentities: Set<Identity> = []
  ) {
    guard !roots.isEmpty else { return }
    for identity in bindingsByIdentity.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
        && !preservedIdentities.contains($0)
    }) {
      if let bindings = bindingsByIdentity.removeValue(forKey: identity) {
        for binding in bindings { binding.resetToSeed() }
      }
    }
  }

  package func prune(
    keeping liveIdentities: Set<Identity>
  ) {
    for identity in bindingsByIdentity.keys.filter({ !liveIdentities.contains($0) }) {
      if let bindings = bindingsByIdentity.removeValue(forKey: identity) {
        for binding in bindings { binding.resetToSeed() }
      }
    }
  }

  /// Re-populates the registry from a snapshot captured by `NodeHandlers`.
  /// Used during cache-hit frames where resolve doesn't run but
  /// registrations must still be live.
  package func restore(_ snapshot: [Identity: [AnyGestureStateBinding]]) {
    guard !snapshot.isEmpty else { return }
    for (identity, bindings) in snapshot {
      bindingsByIdentity[identity] = bindings
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

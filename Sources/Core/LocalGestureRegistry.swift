/// Holds gesture recognizers attached to the view tree. Mirrors the
/// structure of `LocalPointerHandlerRegistry` and `LocalActionRegistry`:
/// keyed by the attaching `Identity`, drained on subtree teardown.
@MainActor
package final class LocalGestureRegistry: Equatable {
  private var recognizers: [Identity: AnyGestureRecognizer] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalGestureRegistry,
    rhs: LocalGestureRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    if let existing = recognizers[identity] {
      // If the existing recognizer is mid-interaction (e.g. a
      // DragGesture has captured `.down` but hasn't seen a `.dragged`
      // yet), keep it and discard the incoming replacement. Without
      // this, any view re-resolve between `.down` and the first
      // `.dragged` — triggered by `setPressedIdentity`, a parent
      // state change, or any other invalidation — tears down the
      // active recognizer and destroys the state it just captured;
      // subsequent pointer events see a fresh recognizer with no
      // `startLocation` and are silently ignored.
      if existing.isActive {
        if existing !== recognizer {
          recognizer.tearDown()
        }
        return
      }
      if existing !== recognizer {
        existing.tearDown()
      }
    }
    recognizers[identity] = recognizer
    ViewNodeContext.current?.recordGestureRegistration(
      identity: identity,
      recognizer: recognizer
    )
  }

  package func recognizer(for identity: Identity) -> AnyGestureRecognizer? {
    recognizers[identity]
  }

  package func reset() {
    // `RuntimeRegistrationSet.resetAll()` fires on every full-resolve
    // frame (TerminalUI.swift:188). Without an in-flight guard, a
    // `.down` event that lands between two full-resolve frames would
    // register its captured state on a recognizer that is then
    // silently torn down — the next `.dragged` arrives at a fresh
    // recognizer with no `startLocation` and is ignored forever.
    //
    // Preserve active recognizers across reset; tear down the rest.
    // Subtree teardown (`removeSubtrees`) remains aggressive: if the
    // owning view genuinely disappears, its recognizer should die.
    var preserved: [Identity: AnyGestureRecognizer] = [:]
    for (identity, recognizer) in recognizers {
      if recognizer.isActive {
        preserved[identity] = recognizer
      } else {
        recognizer.tearDown()
      }
    }
    recognizers = preserved
  }

  package func activeIdentities(
    rootedAt roots: [Identity]
  ) -> Set<Identity> {
    guard !roots.isEmpty else { return [] }
    return Set(
      recognizers.compactMap { identity, recognizer in
        guard recognizer.isActive,
          identityMatchesAnySubtreeRoot(identity, roots: roots)
        else {
          return nil
        }
        return identity
      }
    )
  }

  package func activeIdentitySnapshot() -> Set<Identity> {
    Set(
      recognizers.compactMap { identity, recognizer in
        recognizer.isActive ? identity : nil
      }
    )
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    preserving preservedIdentities: Set<Identity> = []
  ) {
    guard !roots.isEmpty else { return }
    for identity in recognizers.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
        && !preservedIdentities.contains($0)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
    }
  }

  package func prune(
    keeping liveIdentities: Set<Identity>
  ) {
    for identity in recognizers.keys.filter({ !liveIdentities.contains($0) }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
    }
  }

  /// Re-populates the registry from a snapshot captured by `NodeHandlers`.
  /// Used during cache-hit frames where resolve doesn't run but
  /// registrations must still be live.
  package func snapshot() -> [Identity: AnyGestureRecognizer] {
    recognizers
  }

  package func restore(_ snapshot: [Identity: AnyGestureRecognizer]) {
    guard !snapshot.isEmpty else { return }
    for (identity, recognizer) in snapshot {
      if let existing = recognizers[identity] {
        if existing.isActive {
          if existing !== recognizer {
            recognizer.tearDown()
          }
          continue
        }
        if existing !== recognizer {
          existing.tearDown()
        }
      }
      recognizers[identity] = recognizer
    }
  }

  /// Iterates all active recognizers. Called from the RunLoop to drain
  /// deadlines when the scheduler fires `.deadline`.
  package func activeRecognizers() -> [(Identity, AnyGestureRecognizer)] {
    recognizers.map { ($0.key, $0.value) }
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

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
    if let existing = recognizers[identity], existing !== recognizer {
      existing.tearDown()
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
    for recognizer in recognizers.values {
      recognizer.tearDown()
    }
    recognizers.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else { return }
    for identity in recognizers.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
    }
  }

  /// Re-populates the registry from a snapshot captured by `NodeHandlers`.
  /// Used during cache-hit frames where resolve doesn't run but
  /// registrations must still be live.
  package func restore(_ snapshot: [Identity: AnyGestureRecognizer]) {
    guard !snapshot.isEmpty else { return }
    for (identity, recognizer) in snapshot {
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

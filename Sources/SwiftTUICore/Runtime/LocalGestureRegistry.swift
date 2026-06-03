/// Holds gesture recognizers attached to the view tree. Mirrors the
/// structure of `LocalPointerHandlerRegistry` and `LocalActionRegistry`:
/// keyed by the attaching `Identity`, drained on subtree teardown.
@MainActor
package final class LocalGestureRegistry: Equatable {
  private var recognizers: [Identity: AnyGestureRecognizer] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]

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
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordGestureRegistration(
      identity: identity,
      recognizer: recognizer
    )
  }

  package func registerStacked(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    guard let currentPassRecognizer = ViewNodeContext.current?.gestureRegistration(
      for: identity
    ) else {
      register(identity: identity, recognizer: recognizer)
      return
    }

    guard !currentPassRecognizer.isActive else {
      if currentPassRecognizer !== recognizer {
        recognizer.tearDown()
      }
      return
    }

    let stacked = AnyGestureRecognizer(
      StackedGestureRecognizer(
        recognizers: [
          currentPassRecognizer,
          recognizer,
        ]
      )
    )
    recognizers[identity] = stacked
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordGestureRegistration(
      identity: identity,
      recognizer: stacked
    )
  }

  package func recognizer(for identity: Identity) -> AnyGestureRecognizer? {
    recognizers[identity]
  }

  package func hasCurrentPassRecognizer(for identity: Identity) -> Bool {
    ViewNodeContext.current?.gestureRegistration(for: identity) != nil
  }

  package func reset() {
    // `RuntimeRegistrationSet.resetAll()` fires on every full-resolve
    // frame (SwiftTUI.swift:188). Without an in-flight guard, a
    // `.down` event that lands between two full-resolve frames would
    // register its captured state on a recognizer that is then
    // silently torn down — the next `.dragged` arrives at a fresh
    // recognizer with no `startLocation` and is ignored forever.
    //
    // Preserve active recognizers across reset; tear down the rest.
    // Subtree teardown (`removeSubtrees`) remains aggressive: if the
    // owning view genuinely disappears, its recognizer should die.
    var preserved: [Identity: AnyGestureRecognizer] = [:]
    var preservedOwners: [Identity: RuntimeRegistrationOwnerKey] = [:]
    for (identity, recognizer) in recognizers {
      if recognizer.isActive {
        preserved[identity] = recognizer
        preservedOwners[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
      } else {
        recognizer.tearDown()
      }
    }
    recognizers = preserved
    ownersByIdentity = preservedOwners
  }

  package func activeIdentities(
    rootedAt roots: [Identity]
  ) -> Set<Identity> {
    guard !roots.isEmpty else { return [] }
    return Set(
      recognizers.compactMap { identity, recognizer in
        guard recognizer.isActive,
          (ownersByIdentity[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots)
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
      (ownersByIdentity[$0] ?? .init(identity: $0)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
      ownersByIdentity.removeValue(forKey: identity)
    }
  }

  package func prune(
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    for identity in recognizers.keys.filter({
      guard let viewNodeID = ownersByIdentity[$0]?.viewNodeID else {
        return true
      }
      return !liveNodeIDs.contains(viewNodeID)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
      ownersByIdentity.removeValue(forKey: identity)
    }
  }

  /// Re-populates the registry from a snapshot captured by `NodeHandlers`.
  /// Used during cache-hit frames where resolve doesn't run but
  /// registrations must still be live.
  package func snapshot() -> [Identity: AnyGestureRecognizer] {
    recognizers
  }

  package func restore(
    _ snapshot: [Identity: AnyGestureRecognizer],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else { return }
    for (identity, recognizer) in snapshot {
      if let existing = recognizers[identity] {
        if existing.isActive {
          if existing !== recognizer {
            recognizer.tearDown()
          }
          self.ownersByIdentity[identity] =
            ownersByIdentity[identity] ?? self.ownersByIdentity[identity] ?? .init(identity: identity)
          continue
        }
        if existing !== recognizer {
          existing.tearDown()
        }
      }
      recognizers[identity] = recognizer
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  /// Iterates all active recognizers. Called from the RunLoop to drain
  /// deadlines when the scheduler fires `.deadline`.
  package func activeRecognizers() -> [(Identity, AnyGestureRecognizer)] {
    recognizers.map { ($0.key, $0.value) }
  }
}

@MainActor
private final class StackedGestureRecognizer: GestureRecognizer {
  typealias Value = Never

  private let recognizers: [AnyGestureRecognizer]

  init(recognizers: [AnyGestureRecognizer]) {
    self.recognizers = recognizers
  }

  var phase: GestureRecognizerPhase {
    if recognizers.contains(where: { $0.phase == .changed }) {
      return .changed
    }
    if recognizers.contains(where: { $0.phase == .began }) {
      return .began
    }
    if recognizers.contains(where: { !$0.phase.isTerminal }) {
      return .possible
    }
    if recognizers.contains(where: { $0.phase == .ended }) {
      return .ended
    }
    if recognizers.contains(where: { $0.phase == .failed }) {
      return .failed
    }
    return .cancelled
  }

  var isActive: Bool {
    recognizers.contains { $0.isActive }
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    var sawHandled = false
    var sawFailed = false

    for recognizer in recognizers {
      switch recognizer.handle(event: event) {
      case .handled:
        sawHandled = true
      case .failed:
        sawFailed = true
      case .ignored:
        break
      }
    }

    if sawHandled {
      return .handled
    }
    return sawFailed ? .failed : .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    var didTerminate = false
    for recognizer in recognizers {
      if recognizer.handleDeadline(at: instant) {
        didTerminate = true
      }
    }
    return didTerminate
  }

  func currentValue() -> Never? {
    nil
  }

  func tearDown() {
    for recognizer in recognizers {
      recognizer.tearDown()
    }
  }
}

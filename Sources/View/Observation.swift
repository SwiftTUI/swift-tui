import Core
import Observation
import Synchronization

// SAFETY: Stores a weak reference to `any Invalidating` (non-Sendable existential).
// Only accessed on @MainActor during resolve/invalidation phases. The weak reference
// is set once during attachment and read during observation callbacks on the same actor.
private final class ObservationInvalidatorBox: @unchecked Sendable {
  weak var invalidator: (any Invalidating)?
}

package final class ObservationBridge: Sendable, Equatable {
  private let generations = Mutex<[Identity: UInt64]>([:])
  private let invalidatorBox = ObservationInvalidatorBox()

  package init() {}

  package static func == (
    lhs: ObservationBridge,
    rhs: ObservationBridge
  ) -> Bool {
    lhs === rhs
  }

  package func attachInvalidator(
    _ invalidator: (any Invalidating)?
  ) {
    invalidatorBox.invalidator = invalidator
  }

  package func track<T>(
    identity: Identity,
    _ apply: () -> T
  ) -> T {
    let generation = generations.withLock { generations in
      let nextGeneration = (generations[identity] ?? 0) &+ 1
      generations[identity] = nextGeneration
      return nextGeneration
    }

    return withObservationTracking {
      apply()
    } onChange: {
      self.recordChange(identity: identity, generation: generation)
    }
  }

  package func prune(keeping identities: Set<Identity>) {
    generations.withLock { generations in
      guard !generations.isEmpty else {
        return
      }

      let staleIdentities = generations.keys.filter { !identities.contains($0) }
      for identity in staleIdentities {
        generations.removeValue(forKey: identity)
      }
    }
  }

  package func prune(
    keeping index: ResolvedTreeIndex
  ) {
    generations.withLock { generations in
      guard !generations.isEmpty else {
        return
      }

      let staleIdentities = generations.keys.filter { !index.contains($0) }
      for identity in staleIdentities {
        generations.removeValue(forKey: identity)
      }
    }
  }

  private func recordChange(
    identity: Identity,
    generation: UInt64
  ) {
    let isCurrent = generations.withLock { generations in
      generations[identity] == generation
    }
    guard isCurrent else {
      return
    }
    invalidatorBox.invalidator?.requestInvalidation(of: [identity])
  }
}

package import Core
import Observation

@MainActor
package final class ObservationBridge: Equatable {
  private var generations: [Identity: UInt64] = [:]
  private weak var invalidator: (any Invalidating)?

  package init() {}

  nonisolated package static func == (
    lhs: ObservationBridge,
    rhs: ObservationBridge
  ) -> Bool {
    lhs === rhs
  }

  package func attachInvalidator(
    _ invalidator: (any Invalidating)?
  ) {
    self.invalidator = invalidator
  }

  package func track<T>(
    identity: Identity,
    _ apply: () -> T
  ) -> T {
    let generation = (generations[identity] ?? 0) &+ 1
    generations[identity] = generation

    return withObservationTracking {
      apply()
    } onChange: {
      MainActor.assumeIsolated {
        self.recordChange(identity: identity, generation: generation)
      }
    }
  }

  package func prune(keeping identities: Set<Identity>) {
    guard !generations.isEmpty else {
      return
    }

    let staleIdentities = generations.keys.filter { !identities.contains($0) }
    for identity in staleIdentities {
      generations.removeValue(forKey: identity)
    }
  }

  package func prune(
    keeping index: ResolvedTreeIndex
  ) {
    guard !generations.isEmpty else {
      return
    }

    let staleIdentities = generations.keys.filter { !index.contains($0) }
    for identity in staleIdentities {
      generations.removeValue(forKey: identity)
    }
  }

  private func recordChange(
    identity: Identity,
    generation: UInt64
  ) {
    guard generations[identity] == generation else {
      return
    }
    invalidator?.requestInvalidation(of: [identity])
  }
}

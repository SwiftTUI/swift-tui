package import Core
import Observation

@MainActor
package final class ObservationBridge: Equatable {
  private var currentPass: UInt64 = 0
  private var observedPasses: [Identity: UInt64] = [:]
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

  package func beginTrackingPass() {
    currentPass &+= 1
  }

  package func track<T>(
    identity: Identity,
    _ apply: () -> T
  ) -> T {
    let pass = currentPass
    observedPasses[identity] = pass

    return withObservationTracking {
      apply()
    } onChange: {
      MainActor.assumeIsolated {
        self.recordChange(identity: identity, pass: pass)
      }
    }
  }

  package func prune(keeping identities: Set<Identity>) {
    guard !observedPasses.isEmpty else {
      return
    }

    let staleIdentities = observedPasses.keys.filter { !identities.contains($0) }
    for identity in staleIdentities {
      observedPasses.removeValue(forKey: identity)
    }
  }

  private func recordChange(
    identity: Identity,
    pass: UInt64
  ) {
    guard observedPasses[identity] == pass else {
      return
    }
    invalidator?.requestInvalidation(of: [identity])
  }
}

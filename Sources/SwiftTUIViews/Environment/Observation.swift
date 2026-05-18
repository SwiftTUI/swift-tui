import Observation
package import SwiftTUICore

@MainActor
package final class ObservationBridge: Equatable {
  private var currentPass: UInt64 = 0
  private var observedPasses: [Identity: UInt64] = [:]
  private weak var invalidator: (any Invalidating)?
  private weak var viewGraph: ViewGraph?
  private weak var activeDraft: ObservationBridgeDraft?

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

  package func attachViewGraph(
    _ viewGraph: ViewGraph?
  ) {
    self.viewGraph = viewGraph
  }

  package func beginTrackingPass() {
    currentPass &+= 1
  }

  package func makeDraft(
    attaching viewGraph: ViewGraph?
  ) -> ObservationBridgeDraft {
    precondition(activeDraft == nil)
    let draft = ObservationBridgeDraft(
      bridge: self,
      viewGraph: viewGraph,
      pass: currentPass &+ 1
    )
    activeDraft = draft
    return draft
  }

  package func track<T>(
    identity: Identity,
    _ apply: () -> T
  ) -> T {
    let pass: UInt64
    if let activeDraft {
      pass = activeDraft.recordObserved(identity)
    } else {
      pass = currentPass
      observedPasses[identity] = pass
    }

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
    viewGraph?.queueDirtyForObservationChange(observedBy: identity)
    invalidator?.requestInvalidation(of: [identity])
  }

  fileprivate func finishRecording(
    _ draft: ObservationBridgeDraft
  ) {
    if activeDraft === draft {
      activeDraft = nil
    }
  }

  fileprivate func resumeRecording(
    _ draft: ObservationBridgeDraft
  ) {
    precondition(activeDraft == nil || activeDraft === draft)
    activeDraft = draft
  }

  fileprivate func publish(
    _ draft: ObservationBridgeDraft
  ) {
    finishRecording(draft)
    currentPass = draft.pass
    for (identity, pass) in draft.observedPasses {
      observedPasses[identity] = pass
    }
    viewGraph = draft.viewGraph
  }
}

@MainActor
package final class ObservationBridgeDraft {
  private let bridge: ObservationBridge
  fileprivate weak var viewGraph: ViewGraph?
  fileprivate let pass: UInt64
  fileprivate var observedPasses: [Identity: UInt64] = [:]
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(
    bridge: ObservationBridge,
    viewGraph: ViewGraph?,
    pass: UInt64
  ) {
    self.bridge = bridge
    self.viewGraph = viewGraph
    self.pass = pass
  }

  fileprivate func recordObserved(
    _ identity: Identity
  ) -> UInt64 {
    precondition(!didCommit && !didDiscard)
    observedPasses[identity] = pass
    return pass
  }

  package func commit() {
    precondition(!didCommit && !didDiscard)
    bridge.publish(self)
    didCommit = true
  }

  package func suspendRecording() {
    precondition(!didCommit && !didDiscard)
    bridge.finishRecording(self)
  }

  package func resumeRecording() {
    precondition(!didCommit && !didDiscard)
    bridge.resumeRecording(self)
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    bridge.finishRecording(self)
    didDiscard = true
  }
}

extension ObservationBridge {
  package struct Checkpoint {
    package var currentPass: UInt64
    package var observedPasses: [Identity: UInt64]
    package var invalidator: (any Invalidating)?
    package var viewGraph: ViewGraph?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      currentPass: currentPass,
      observedPasses: observedPasses,
      invalidator: invalidator,
      viewGraph: viewGraph
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    currentPass = checkpoint.currentPass
    observedPasses = checkpoint.observedPasses
    invalidator = checkpoint.invalidator
    viewGraph = checkpoint.viewGraph
  }
}
